#!/usr/bin/env python3
"""Build an isolated Golden Gate source proof on CI/an Android build machine.

This does not change the app's backend and does not use an installed Fitbit APK.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

UPSTREAM = "https://github.com/Google-Health-API/golden-gate.git"
REVISION = "b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa"


def run(*args, cwd=None, env=None):
    print("+ " + " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def output(*args):
    return subprocess.check_output(list(map(str, args)), text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", required=True, type=Path)
    parser.add_argument("--abi", choices=["arm64-v8a", "x86_64"], default="arm64-v8a")
    parser.add_argument("--work", type=Path, default=Path("build/native-source-proof"))
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    ndk = args.ndk.resolve()
    toolchain = ndk / "build/cmake/android.toolchain.cmake"
    if not toolchain.is_file():
        parser.error("--ndk must point to an installed Android NDK")
    source = work / "upstream"
    if not source.exists():
        run("git", "clone", "--filter=blob:none", "--no-checkout", UPSTREAM, source)
    run("git", "checkout", "--detach", REVISION, cwd=source)
    run("git", "submodule", "update", "--init", "--depth", "1",
        "external/lwip", "external/mbedtls", cwd=source)
    if output("git", "-C", source, "rev-parse", "HEAD").strip() != REVISION:
        raise RuntimeError("Unexpected upstream revision")
    env = dict(os.environ)
    env["SOURCE_DATE_EPOCH"] = output("git", "-C", source, "show", "-s", "--format=%ct", "HEAD").strip()
    common = [
        "-G", "Ninja",
        f"-DCMAKE_TOOLCHAIN_FILE={toolchain}",
        f"-DANDROID_ABI={args.abi}", "-DANDROID_PLATFORM=android-24",
        "-DANDROID_STL=c++_static", "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
        "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
        "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,--no-undefined",
        f"-DCMAKE_MAKE_PROGRAM={shutil.which('ninja')}",
    ]
    core_build = source / "xp/build/cmake/android" / args.abi
    run("cmake", "-S", source / "xp", "-B", core_build,
        "-C", source / f"xp/config/profiles/android/{args.abi}.cmake",
        *common, "-DGG_ENABLE_APPS=OFF", "-DGG_ENABLE_EXAMPLES=OFF",
        "-DGG_ENABLE_UNIT_TESTS=OFF", env=env)
    run("cmake", "--build", core_build, "--target", "gg", "--parallel", "1", env=env)
    jni_build = work / f"jni-{args.abi}"
    run("cmake", "-S", source / "platform/android/goldengate/GoldenGateBindings",
        "-B", jni_build, *common, "-DGG_ENABLE_UNIT_TESTS=OFF", env=env)
    run("cmake", "--build", jni_build, "--target", "xp", "--parallel", "1", env=env)
    artifact = work / "artifact" / args.abi
    artifact.mkdir(parents=True, exist_ok=True)
    tools = ndk / "toolchains/llvm/prebuilt/linux-x86_64/bin"
    manifest = {
        "upstream": UPSTREAM, "revision": REVISION, "abi": args.abi,
        "ndk": (ndk / "source.properties").read_text(),
        "submodules": output("git", "-C", source, "submodule", "status", "external/lwip", "external/mbedtls").splitlines(),
        "files": {},
        "scope": "Native compilation and ELF checks only. Not a drop-in app backend, legal clearance, or hardware proof.",
    }
    for library in [core_build / "bundle/libgg.so", jni_build / "libxp.so"]:
        target = artifact / library.name
        shutil.copy2(library, target)
        headers = output(tools / "llvm-readelf", "--program-headers", "--wide", target)
        loads = [line for line in headers.splitlines() if line.strip().startswith("LOAD ")]
        if not loads or any(int(line.split()[-1], 16) < 16384 for line in loads):
            raise RuntimeError(f"{library.name} has insufficient ELF LOAD alignment")
        (artifact / f"{library.name}.elf.txt").write_text(headers + output(tools / "llvm-readelf", "--dynamic", target))
        (artifact / f"{library.name}.symbols.txt").write_text(output(tools / "llvm-nm", "--dynamic", "--defined-only", target))
        manifest["files"][library.name] = hashlib.sha256(target.read_bytes()).hexdigest()
    symbols = (artifact / "libxp.so.symbols.txt").read_text()
    for expected in ["GoldenGate_initModulesJNI", "RunLoop", "Stack_create", "CoapEndpoint"]:
        if expected not in symbols:
            raise RuntimeError(f"Missing JNI family: {expected}")
    licenses = artifact / "licenses"
    licenses.mkdir(exist_ok=True)
    for src, name in [
        (source / "LICENSE", "golden-gate-LICENSE"),
        (source / "NOTICE", "golden-gate-NOTICE"),
        (source / "external/mbedtls/LICENSE", "mbedtls-LICENSE"),
        (source / "external/lwip/COPYING", "lwip-COPYING"),
    ]:
        shutil.copy2(src, licenses / name)
    (artifact / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Native proof artifacts: {artifact}")


if __name__ == "__main__":
    main()
