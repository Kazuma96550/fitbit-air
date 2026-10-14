# Third-party notices

No binary from the Google Health or Fitbit Android applications is included in
this repository, package archive, or built example APK.

## Golden Gate

- Source: https://github.com/Google-Health-API/golden-gate
- Commit: `b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa`
- Copyright 2017–2020 Fitbit, Inc.
- License: Apache License 2.0

The full license text is included in [`LICENSE-APACHE-2.0`](LICENSE-APACHE-2.0).

The Kotlin sources under
`android/src/main/kotlin/com/fitbit/goldengate/bindings/` are derived from the
upstream Android bindings and retain their SPDX headers. They include limited
adaptations for the JNI ABI exposed by the currently tested Google Health
version, error propagation, and Gattlink configuration.

## Runtime Google Health dependency

At runtime, the plugin verifies the installed `com.fitbit.FitbitMobile` signing
certificate and loads a compatible `libxp.so` copied from that app's publicly
installed APK split into the caller app's private code cache. That binary is not
redistributed by this project and remains subject to its owner's terms. No file
from Google Health's private application-data directory is read.
