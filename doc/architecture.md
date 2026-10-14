# Architecture

The public Dart surface deliberately hides the native transport:

```text
FitbitAir.isAirPaired() / FitbitAir.vibrate()
                    │ MethodChannel
                    ▼
             FitbitAirPlugin.kt
                    │ Android GATT
                    ▼
       Golden Gate JNI (runtime-loaded libxp.so)
                    │
       CoAP → DTLS → Gattlink → tracker BLE channel
                    │
                    ▼
                 Fitbit Air
```

`FitbitAirPlugin` owns one short-lived operation at a time. It locates a bonded
device whose Android name contains `Fitbit Air`, connects to the tracker service,
subscribes to its receive characteristic, bridges BLE packets into Golden Gate,
and waits for a DTLS session. It then performs the bounded `/settings` sequence
and tears down GATT in every success, error, or timeout path.

`GoogleHealthNativeLoader` verifies the signing certificate of the installed
`com.fitbit.FitbitMobile` package, locates `libxp.so` for a supported device ABI
inside its public base/split APKs, and copies it to a versioned private code-cache
directory before loading it. Neither the package nor the resulting app APK
contains that binary. The JNI-compatible Kotlin binding source is compiled into
the app.

The plugin intentionally does not expose CoAP, DTLS, Gattlink, Bluetooth handles,
or protocol payloads to Dart. Additional verified operations should be modeled as
small typed Dart methods and implemented behind this boundary.

## Haptic sequence

1. Read haptic intensity using `PUT /settings` and payload `0a0101`.
2. Accept only the known low/high responses (`...0802` or `...0803`).
3. Write the alternate intensity using `POST /settings`.
4. Wait 800 ms, producing the user-visible haptic effect.
5. Restore the original intensity and read it back.
6. Close the Golden Gate stack and Android GATT connection.

An operation error after the read triggers another best-effort restore. The API
returns success only after a follow-up read matches the original value.

`pulse()` omits steps 4–5: it reads the current strength, writes the opposite
strength once, verifies it, and intentionally leaves it active. This is the
one-pulse primitive. `setHapticIntensity()` follows the same write/verify path
for an explicitly requested strength and performs no write when already set.
Google Health remains the pairing owner and may independently reconcile its
stored setting after this short-lived connection closes.

## Deliberate limitations

- Android arm64 on Pixel 7 Pro is the verified target. Other Android ABIs are
  attempted when the installed Google Health APK provides `libxp.so`, but are
  currently untested.
- Pairing remains owned by Google Health. The plugin does not provision or copy
  the normal device-specific mobile-data PSK or read private app data.
- The haptic operation works through the bootstrap session observed on the Air.
- The JNI ABI is private and version-sensitive. A Google Health update may
  require updated Kotlin bindings.
- Incoming wrist taps and live heart-rate data have not been semantically decoded
  and are not represented in the public API.
