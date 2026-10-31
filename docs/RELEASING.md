# Releasing Lumina

Source and downloads are published to the public GitHub repository. The default distribution
route is a free, identity-free public beta; Developer ID signing/notarization is an optional future route.

## Publish source

1. Run `./scripts/check.sh` and inspect `git diff --check` and `git status --short`.
2. Review all files and Git history for credentials and personal data. The lightweight scan includes
   known credential patterns; it is not exhaustive. The historical signing team identifier and
   public Git author alias are metadata, not credentials. Do not publish local signing material.
3. Confirm the rights to the code and app icon under the MIT license. Keep the copyright notice.
4. Review README, PRIVACY, SECURITY, and the testing record for accuracy and a working reporting route.
5. Enable GitHub private vulnerability reporting, secret scanning/push protection where available,
   and branch protection requiring the build/test workflow. These are repository-owner settings;
   no credentials or privileged workflow is needed for the existing CI.
6. Commit the reviewed changes, push them, and verify CI on GitHub before tagging a release.

## Free public beta

After committing reviewed source, run:

```sh
python3 scripts/package_release.py 1.0.0-beta.1
```

The command builds a universal Release app in a temporary workspace outside the user's home,
remaps compiler source paths, strips local debug symbols, embeds the license/privacy policy,
and completes an ad-hoc signature with hardened runtime and only the required Location resource-access entitlement. It verifies the bundle and rejects
personal home/temporary paths, signing material, personal certificates, and debug-injection binaries.
It creates a DMG, ZIP, release metadata, and SHA-256 checksums under `dist/<version>/`.
It does not contact Apple, enroll in a paid program, or upload anything.

`--allow-dirty` is for local validation only. Never publish its output. A public package must
record a clean source revision that matches its GitHub tag. Publish only the DMG, ZIP,
`release-metadata.json`, and `SHA256SUMS.txt`. Never upload `build.log`, DerivedData, or dSYMs.
Test read-only DMG mounting, a clean-folder copy, ZIP extraction, signature checks, and launching
before publication. Keep the unnotarized warning prominent in the download and installation text.

GitHub standard runners are free for public repositories. CI skips if the repository becomes
private, uses no larger runners, and uploads no billable Actions artifacts or caches. Release
files use GitHub Releases instead. Do not introduce paid resources or add billing credentials.

## Optional Developer ID release

`./scripts/build.sh Release` creates an ad-hoc-signed universal app at
`build/DerivedData/Build/Products/Release/Lumina.app` with `arm64` and `x86_64` slices.
It is a local verification artifact. The ad-hoc signature verifies bundle integrity; it is not
a Developer ID identity or Apple notarization. Use the packaging command for downloads.

Check the marketing version and build number in Xcode; the UI reads its version from the bundle.
Use your own Developer ID Application identity and team when archiving/exporting for distribution
with Xcode. The project enables hardened runtime and intentionally disables App Sandbox because
of the private hardware integration. Never commit your team selection, certificate private key,
provisioning material, App Store Connect key, or notarization credentials.

Use Apple's [Developer ID distribution workflow](https://developer.apple.com/developer-id/) and
[notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Keep notarization credentials in Keychain or your private release environment. The public CI does
not receive signing secrets, sign binaries, upload artifacts, or publish releases.

After signing, verify the actual exported app:

```sh
codesign --verify --deep --strict --verbose=2 /path/to/exported/Lumina.app
spctl --assess --type execute --verbose=2 /path/to/exported/Lumina.app
xcrun stapler validate /path/to/exported/Lumina.app
lipo -archs /path/to/exported/Lumina.app/Contents/MacOS/Lumina
```

Notarize and staple the distributable app/package, then run the real-device checklist in
[TESTING.md](TESTING.md) on that artifact. Publish checksums with any final downloads and include
the MIT license. Do not advise users to disable Gatekeeper or remove quarantine attributes. For the free beta,
link Apple’s documented per-app approval process rather than weakening system-wide protections.

## Release notes

Move the relevant `CHANGELOG.md` entries into the tagged version. State tested Mac/macOS versions,
private API limitations, current known issues, and whether the download is signed/notarized.
Do not claim App Store compatibility, universal hardware support, or a security audit beyond the
checks actually performed. Keep the source tag and distributed binary version aligned.
