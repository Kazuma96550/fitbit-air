# Source-built native proof

This experiment builds the pinned, public Apache-licensed Golden Gate core and
Android JNI wrapper with a pinned Android NDK. It does not extract libraries
from another app, change the Flutter plugin, or enable a new runtime backend.

Run the **Native source feasibility** workflow, or on an Android build machine:

```sh
python3 tool/native-proof/build.py --ndk /path/to/android-ndk
```

The build uses one compiler job. The artifact contains the two source-built
libraries, ELF headers, exported symbols, pinned revision metadata and license
notices. ELF LOAD alignment is checked against 16 KB. A successful build proves
compilation and those ELF checks only, not APK/AAB packaging, Kotlin/JNI
compatibility, successful device communication, or Play acceptance.

The existing app's Kotlin bindings were adapted to Google Health's different
JNI ABI. Do not replace its libraries with these artifacts without porting the
bindings and testing on hardware. See [the audit](../../doc/play-store-feasibility.md).
