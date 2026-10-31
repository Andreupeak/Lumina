# Contributing

Bug reports, focused improvements, and compatibility reports are welcome.
Please keep discussion respectful and describe concrete behavior and reproduction steps.

## Development

Use macOS with Xcode 16 or later. Open `Lumina.xcodeproj` and select the Lumina scheme.
The app has no external runtime package dependencies. Choose your own signing team locally
if needed; do not commit that selection, provisioning material, or Xcode user state.

Run `./scripts/check.sh` before submitting a pull request. It checks repository hygiene,
tests core behavior, and builds Debug and universal Release configurations. See
[testing](docs/TESTING.md) for the isolated UI test window and hardware checklist.

Keep changes focused and explain the user-visible behavior. Test meaningful policy changes,
especially overnight boundaries, timeout precedence, preference migrations, solar edge cases,
and location privacy. UI changes need keyboard, mouse, trackpad, small-screen, and light/dark checks.
Avoid adding event taps, permissions, dependencies, or network requests without a clear need and
matching updates to the privacy/security documentation.

Preserve existing preference keys and migrations. Never silently substitute an external
location provider for Apple's location service. Keep hardware calls behind
`KeyboardBacklightManager`; private API changes require a real-device compatibility check.
Update the changelog and relevant documentation when behavior changes.

## Reports and pull requests

Include the macOS version, app version or commit, Mac model (no serial number), reproduction
steps, and expected versus actual behavior. State which checks passed and which could not
be performed. Remove personal information from screenshots and logs.

Use [SECURITY.md](SECURITY.md) for vulnerabilities. Do not submit credentials, IP addresses,
actual location coordinates, signing certificates, or provisioning profiles.

By submitting a contribution, you agree to provide it under the project's [MIT license](LICENSE).
Only contribute code and assets you have the right to license.
