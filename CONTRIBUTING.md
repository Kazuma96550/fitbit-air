# Contributing

Issues and focused pull requests are welcome. Please keep observed behavior,
decompiled-code conclusions, and hypotheses clearly separated.

Before opening a pull request, run:

```bash
flutter analyze
flutter test
cd example
flutter build apk --debug
```

Device-facing changes should include the Android version, Air firmware version,
whether Google Health remained functional afterward, and sanitized logs. Never
commit account tokens, Bluetooth addresses, device identifiers, pairing keys,
APK-extracted libraries, or private app data.
