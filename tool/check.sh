#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"

cd "$package_dir"
flutter pub get
flutter analyze
flutter test

cd "$package_dir/example"
flutter build apk --debug

cd "$package_dir"
dart pub publish --dry-run
