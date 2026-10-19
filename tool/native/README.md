# Bundled native transport

The plugin ships Golden Gate's core (`libgg.so`) and JNI bridge (`libxp.so`)
for `arm64-v8a`, `armeabi-v7a`, `x86_64` and `x86` under
`android/src/main/jniLibs/`. They are built from pinned public source:

- Golden Gate `b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa` (Apache-2.0)
- its mbedTLS (Apache-2.0) and lwIP (BSD-3-Clause) submodule pins
- Android NDK 28.2.13676358, minimum API 24, 16 KB page alignment

Rebuild and replace the committed libraries (also rewrites `manifest.json`):

```sh
python3 tool/native/build.py --ndk "$ANDROID_HOME/ndk/28.2.13676358"
```

Check that the committed libraries match a fresh build:

```sh
python3 tool/native/build.py --ndk "$ANDROID_HOME/ndk/28.2.13676358" --check
```

Source paths are normalized and the libraries are stripped, so the output does
not depend on the machine or checkout location. The **Native transport**
workflow runs the check for every ABI when these files change and uploads the
built libraries.

The Kotlin bindings in `android/src/main/kotlin/com/fitbit/goldengate/bindings/`
must match this upstream JNI ABI; `NativeBindingSignaturesTest` guards it.
