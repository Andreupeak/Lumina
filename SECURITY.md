# Security

Security fixes are targeted at the current source on `main` and the latest maintained release.
There is no guaranteed response time or long-term support policy.

## Report a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/Andreupeak/Lumina/security/advisories/new)
if enabled for this repository. Include the affected revision, macOS version, impact, and minimal
reproduction steps, with credentials and personal data removed. Do not attach real coordinates,
IP addresses, provisioning profiles, or signing material.

If private reporting is not available, open an ordinary issue asking the maintainer to enable a private
reporting channel, without disclosing exploit details or sensitive data. No private mailbox is assumed.

## Security boundaries

- **Private API:** CoreBrightness is unsupported by Apple as a public API. Selector and calling-convention checks reduce
  compatibility failures but cannot prove that a private ABI remains unchanged. A future OS update
  can still break or crash hardware control. Test each supported OS/hardware combination.
- **No App Sandbox:** the app runs with the normal permissions of your user. Hardened runtime is
  enabled in the project; the free beta has an identity-free ad-hoc signature, without Apple notarization. A downloaded
  copy normally needs an explicit per-app first-open decision; this is not Apple verification.
  There is no privileged helper, root requirement, downloaded executable code, or shell-command execution in the app.
- **Local location data:** rounded coordinates and schedules are unencrypted preferences, not secrets
  protected against other software running as your user. Rounding limits precision; it is not anonymization.
- **Optional external service:** confirmed IP lookup exposes your public IP to `ipapi.co`. TLS uses system
  certificate validation; redirects, cookies, cache, and stored credentials are disabled. Payload size,
  HTTP status, service error flags, and coordinate ranges are validated.
- **Input:** idle detection reads only an elapsed-time counter. Lumina does not request Accessibility
  or Input Monitoring permissions or record event contents.
- **Hardware changes:** brightness and ambient state captured at launch are restored on normal quit.
  Forced termination, a crash, or a private framework failure cannot guarantee restoration; macOS's
  keyboard brightness controls remain the recovery path.

## Repository and CI

The repository contains no signing certificates or private keys. Signing team selection is local.
Build products, local environment files, signing material, and Xcode user state are ignored. The initial
commit contains an Apple signing team identifier; that identifier is public metadata, not a signing credential.
The author alias and repository URL are intentionally public.

CI runs untrusted pull requests using `pull_request`, with read-only repository permissions and no
signing secrets. The checkout action is pinned to a full commit SHA and does not persist credentials.
There is no automatic publishing job. CI skips execution if the repository becomes private and stores no Actions artifacts or caches. Dependabot proposes GitHub Actions updates.

`scripts/check_repository.py` checks repository hygiene, known credential patterns, forbidden personal
paths, project privacy settings, and privacy-manifest syntax. `--history` scans all locally available
Git commits for the same credential patterns. This is a lightweight check, not a full secret scanner,
penetration test, or guarantee that all sensitive data is absent. Review new files and history before publication;
GitHub secret scanning and push protection provide additional coverage when enabled.

See [privacy](PRIVACY.md), [release instructions](docs/RELEASING.md), and [validation scope](docs/TESTING.md).
