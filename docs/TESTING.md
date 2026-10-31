# Testing and validation

## Automated checks

```sh
swift test --scratch-path build/SwiftPackage
./scripts/check.sh
```

The full check runs repository/history checks, the core XCTest suite, and Debug plus universal
Release builds with Swift warnings treated as errors. Local app bundles are fully ad-hoc signed
without a developer certificate, and their signatures are verified. Test suites use isolated preference domains;
HTTP transport tests use URLProtocol fixtures and never contact a real service. Tests do not invoke
CoreBrightness, change the keyboard, or request location permission.

Coverage includes:

- Inclusive starts, exclusive ends, adjacent slots, overlap rejection, and midnight crossings.
- Corrupt/overflowing time fields, invalid brightness, duplicate IDs, slot limits, persistence, and legacy migration.
- System/Sun Cycle/Time Slots behavior; timeout precedence; zero durations; idle restoration and startup grace.
- Solar reference times in both hemispheres; polar conditions; leap day; DST; date-line and cross-zone cases.
- Coordinate bounds/rounding/deletion, location startup choices, HTTP status, bounded streamed responses,
  malformed JSON, generic request metadata, and denied redirect responses.

The repository scan reports only file names and pattern categories, never matching secret values.
It is deliberately limited and does not replace a dedicated secret scanner or a manual review.

## Isolated UI window

Build a Debug-only test copy with a separate bundle identifier:

```sh
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/UITesting \
  PRODUCT_BUNDLE_IDENTIFIER=org.lumina.UITesting \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG LUMINA_UI_TESTING' \
  CODE_SIGNING_ALLOWED=NO build
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements Lumina/Lumina.entitlements build/UITesting/Build/Products/Debug/Lumina.app
open build/UITesting/Build/Products/Debug/Lumina.app
```

This displays the real settings views in a regular window. It uses only `Lumina.UITesting`
preferences, resets them on launch, and deletes them on normal quit. Hardware and location are
simulated by default; the IP lookup confirmation still appears, but a confirmed lookup returns sample data.
The Debug-only `--test-mac-location` argument allows an explicitly consented real Mac Location test,
still using isolated preferences. `--light` selects light appearance. No coordinates should be logged.
The installed app and its preferences are not modified. Do not use this build for hardware validation.

Check setup navigation, each mode, all menus, adding/editing/deleting slots, invalid and overlapping
ranges, scrolling to the bottom, keyboard navigation, and light/dark appearance. Verify that closed
timer menus keep their values when the surrounding panel scrolls; open menus scroll normally.

## Real-device checklist before binary distribution

- Confirm brightness and ambient auto-brightness on each advertised Mac/macOS combination.
- Verify a short idle timeout and prompt restoration after input, including after a slot ends.
- Verify global and slot-specific timeouts, previews, sleep/wake, time-zone changes, and normal-quit restoration.
- Exercise the actual menu-bar popover on small displays and multiple monitors, with mouse and trackpad.
- Check macOS permission denial, permission changes, a location timeout, offline IP failure,
  cancelling a lookup, switching sources mid-request, and forgetting location during a request.
- Use a network inspector to confirm no IP lookup occurs on startup or Mac location failure.
- Confirm zero Accessibility/Input Monitoring prompts and no administrator requirement.
- Validate the signed/notarized build on a clean user account.

## Validation record

Validation dates: 2026-10-23 and 2026-10-31. Toolchain: Xcode 27, Swift 6.4, macOS 27, Apple silicon.
The core suite has 60 passing XCTest cases. Local Debug and universal Release builds pass with
Swift warnings treated as errors. The working files and available Git history were checked for
known credential patterns; none were found. This is not an exhaustive security audit.

On the real Mac keyboard, read/write checks passed for fixed brightness, off, ambient enable/disable,
invalid brightness rejection, and restoration of the original state. The installed app was briefly
paused during this check and resumed afterward. No hardware IDs, actual location, or original
brightness values were published in the validation record.

The public package candidate was built in a non-personal temporary workspace and checked for home
directory paths, personal temporary paths, signing keys/certificates, unexpected binaries, bundle
signature validity, required permission strings, the privacy manifest, and both CPU slices. The DMG
mounted read-only and its app copied successfully into a clean temporary Applications directory.
The ZIP extracted successfully and its executable matched the DMG copy. The package has an ad-hoc
signature with hardened runtime, no personal certificate, and no Apple notarization.

The isolated settings window was previously inspected in dark appearance. Checks covered setup,
native timer choices, global timeouts, stable scrolling with a persistent header/footer, IP consent
and cancellation, manual coordinate validation/rounding, schedule menus, and equal-time rejection.
A stale validation warning was fixed. The latest light-appearance setup, System Control, Time Slots, and actual schedule Save action
passed native UI checks. A real Mac Location request succeeded after the permission/signature fixes;
only one-decimal coordinates were stored, no IP lookup was used, and test preferences were removed afterward.
The Location resource-access entitlement is included in the project and in final bundle verification.

Not certified: other Mac models, an Intel device, macOS 14 hardware, a multi-monitor/small-display
matrix, room-light sensor behavior under all lighting conditions, or every sleep/wake configuration.
A universal binary is not a guarantee that every private CoreBrightness implementation is compatible.
Downloaded app approval is controlled by Gatekeeper; no security protection was disabled in testing.
