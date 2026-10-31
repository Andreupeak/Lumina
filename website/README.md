# Lumina public showcase

Published at **https://andreupeak.github.io/Lumina/**.
This is a buildless static site: HTML, CSS, JavaScript, and local images. It has no
account system, analytics, cookies, browser storage, backend, external fonts, or
runtime service requests. GitHub receives ordinary hosting requests under its own
privacy policy. Download and documentation links lead to the project's GitHub repository.

## Preview and check

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory website
python3 scripts/check_website.py
node --check website/script.js
```

Visit http://127.0.0.1:8765/ in your browser. Check both wide and narrow layouts,
keyboard navigation, the three demo states, all four screenshot tabs, the image
dialog (including Escape), and the installation links. Check with reduced motion
enabled. Important explanations and screenshots remain available without JavaScript;
the interactive demonstration and tour tabs require it.

The dependency-free checker validates local assets, anchor destinations, image sizes,
HTTPS links, a restrictive Content Security Policy, metadata, and the absence of
unexpected network or storage APIs. It does not replace a real browser or accessibility audit.

## Publishing and cost

`.github/workflows/pages.yml` publishes only this folder on changes to main.
GitHub Pages must be configured for GitHub Actions. It uses a standard Ubuntu runner,
fixed official action revisions, short-lived deployment identity, and a Pages artifact
retained for one day. There are no paid services, domain purchases, signing keys,
long-lived deployment secrets, or caches. The workflow skips private repositories.

GitHub Pages and standard Actions runners are free for this public repository.
See [GitHub's Pages availability](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site).
Recheck the hosting terms if the repository's visibility, runner type, or plan changes.

## Updating the release

Keep the visible version, DMG/ZIP URLs, minimum macOS version, signing disclosure,
and actual release artifacts consistent when a new app version is published.
Website-only changes do not replace the tested beta binaries or move their tag.
See [asset provenance and generation prompt](ASSETS.md) for screenshots and illustrations.
