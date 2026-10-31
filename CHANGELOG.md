# Changelog

## 1.0.0-beta.1 — 2026-10-31

- Replace hover-expanded timer wheels and custom input capture with native click-to-open menus.
- Add a bounded scrolling settings panel with a persistent header and footer.
- Use native brightness sliders and switches, accessible control labels, and semantic text colors.
- Correct solar calculations, respect local time zones and DST, and handle polar day/night explicitly.
- Reject invalid, zero-length, overlapping, duplicate, and excessive saved time slots.
- Clarify that zero slot timeouts inherit the global inactivity setting.
- Reduce idle polling from ten to two checks per second and coalesce brightness previews.
- Refresh schedules after sleep/wake and clock/time-zone changes; restore captured hardware state on normal quit.
- Preserve the selected location source and remove silent IP-based fallbacks and startup IP requests.
- Confirm IP lookup, validate/bound responses, reject redirects, cancel stale work, and disable cookies/cache/credentials.
- Round saved coordinates to 0.1° and add Forget Saved Location.
- Add core regression tests, unsigned build scripts, public CI, MIT licensing, and contributor/privacy/security documentation.
- Remove the hardcoded signing team, declare menu-bar-only behavior, and include a privacy manifest.
- Set a macOS 14 deployment target; hardware compatibility still requires device testing.

- Add the required macOS location purpose string, Location resource-access entitlement, foreground authorization request, and bounded permission wait.
- Validate CoreBrightness method signatures before dispatching calls.
- Make setup edit the remembered System brightness; avoid an unrelated startup brightness flash.
- Complete local app signatures without developer certificates and remove debug-injection dylibs.
- Add privacy-checked DMG/ZIP packaging, checksums, source-revision metadata, and free-install instructions.
- Restrict CI to free public-repository execution and document distribution costs and limits.
