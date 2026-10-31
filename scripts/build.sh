#!/bin/bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
configuration="${1:-Debug}"
case "$configuration" in
    Debug|Release) ;;
    *) echo "Usage: $0 [Debug|Release]" >&2; exit 2 ;;
esac

build_options=("ONLY_ACTIVE_ARCH=YES")
if [[ "$configuration" == Release ]]; then
    build_options=("ARCHS=arm64 x86_64" "ONLY_ACTIVE_ARCH=NO")
fi

xcodebuild \
    -project "$repo_dir/Lumina.xcodeproj" \
    -scheme Lumina \
    -configuration "$configuration" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$repo_dir/build/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    "${build_options[@]}" \
    build

# Complete the bundle signature without a certificate or developer account.
# A linker-only signature is insufficient for protected services such as location.
app_path="$repo_dir/build/DerivedData/Build/Products/$configuration/Lumina.app"
codesign --force --sign - --options runtime --timestamp=none \
    --entitlements "$repo_dir/Lumina/Lumina.entitlements" "$app_path"
codesign --verify --deep --strict "$app_path"
