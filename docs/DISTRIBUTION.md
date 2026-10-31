# Free distribution, privacy, and limitations

Lumina is published as a free community project on the public
[Andreupeak/Lumina repository](https://github.com/Andreupeak/Lumina), with downloads in GitHub Releases.
There is no subscription, server, custom domain, payment service, or automatic update service.

## Costs

GitHub documents that [standard Actions runners in public repositories are free](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
This workflow uses a standard runner, skips if the repository becomes private, and does not
store billable Actions artifacts/caches. Release downloads use
[GitHub Releases](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github#distributing-large-binaries).
No billing credentials or paid account features are needed for this setup.

Apple's usual Developer ID and notarization route is separate. The
[Apple Developer Program](https://developer.apple.com/programs/enroll/) normally costs USD 99 per year,
with regional prices and limited fee waivers. No enrollment or purchase is part of this release.
Free source builds and the downloadable beta use an ad-hoc signature without a personal certificate.
It protects bundle integrity but does not establish a trusted publisher or certify absence of malware.
Read [Apple's explanation of first-open security decisions](https://support.apple.com/en-us/102445).
Users on managed Macs may be unable to approve an unnotarized app.

## Public information

The repository, code, public GitHub alias, project history, and release notes are public by design.
Commits use the existing public alias and GitHub no-reply email. Release packaging avoids personal
certificates, remaps build paths, excludes debug logs and signing material, and checks the final app
for personal home-directory paths. It does not conceal information already public on a GitHub profile
or make a publisher anonymous. The initial public commit contains a signing team ID, which is
metadata rather than a private key; history is not silently rewritten.

App-user privacy is described in [PRIVACY.md](../PRIVACY.md). Preferences and rounded region
coordinates stay on the Mac. The optional IP estimate sends the public IP to its external provider
only after confirmation. Location testing and public validation records must never publish actual coordinates.

## CoreBrightness and licensing

CoreBrightness is an internal Apple interface. It is not maintained as a public compatibility
contract, so an OS update can break support. Lumina checks its method signatures and refuses
unknown calling conventions rather than calling them unsafely. That reduces compatibility risk;
it cannot remove the dependency or guarantee every Mac will work.

Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#software-requirements)
require public APIs for App Store apps. Lumina's release route is independent macOS distribution,
without an App Store submission or a claim of Apple endorsement. Apple's applicable software and
developer agreements still matter; an MIT license is not permission to redistribute Apple's frameworks.
Lumina loads the system-installed framework and does not include it in the download.

The repository uses the [MIT license](../LICENSE), including its warranty disclaimer. There are no
third-party runtime packages, bundled Apple frameworks, paid fonts, analytics SDKs, or copied SDK headers.
The release notes state the tests actually completed. This document records engineering precautions,
not a guarantee against every legal claim or a formal legal clearance.
