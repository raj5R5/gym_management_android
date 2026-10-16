#!/bin/bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
developer_dir="$(xcode-select -p)"
platform_dir="$developer_dir/Platforms/MacOSX.platform/Developer"
output_dir="$(mktemp -d "${TMPDIR:-/private/tmp}/gym-onboarding-keychain.XXXXXX")"
trap 'rm -rf -- "$output_dir"' EXIT
source_dir="$test_dir/../darwin/flutter_secure_storage_darwin/Sources/flutter_secure_storage_darwin"
swiftc -module-cache-path "$output_dir/modules" \
  -I "$platform_dir/usr/lib" -L "$platform_dir/usr/lib" \
  -F "$platform_dir/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform_dir/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform_dir/Library/PrivateFrameworks" \
  -Xlinker -rpath -Xlinker "$platform_dir/usr/lib" \
  "$source_dir/FlutterSecureStorage.swift" "$source_dir/OnboardingKeychain.swift" \
  "$test_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests"
