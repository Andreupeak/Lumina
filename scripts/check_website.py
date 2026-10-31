#!/usr/bin/env python3
"""Dependency-free public-site checks for broken links and accidental data exposure."""

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "website"


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.references = []
        self.problems = []
        self.images = []
        self.csp = None

    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if "id" in attrs:
            if attrs["id"] in self.ids:
                self.problems.append(f"Duplicate HTML ID: {attrs['id']}")
            self.ids.add(attrs["id"])
        for name, value in pairs:
            if name.startswith("on") or name == "style":
                self.problems.append("Inline scripts/styles conflict with the site's security policy")
            if name in {"src", "href"}:
                self.references.append((tag, name, value))
        if tag == "img":
            if "alt" not in attrs:
                self.problems.append("Image has no alternative text")
            self.images.append(attrs)
        if tag == "meta" and attrs.get("http-equiv", "").lower() == "content-security-policy":
            self.csp = attrs.get("content", "")


def main():
    page = Page()
    page.feed((SITE / "index.html").read_text())
    problems = page.problems
    for tag, attr, value in page.references:
        url = urlsplit(value)
        if url.scheme or url.netloc:
            if url.scheme != "https":
                problems.append("External link must use HTTPS")
            if attr == "src" or tag == "link" and not (url.netloc == "andreupeak.github.io" and url.path == "/Lumina/"):
                problems.append("Runtime assets must be self-hosted")
            continue
        if url.path:
            path = (SITE / unquote(url.path)).resolve()
            if not path.is_relative_to(SITE) or not path.is_file():
                problems.append(f"Missing or unsafe local resource: {url.path}")
        elif url.fragment and unquote(url.fragment) not in page.ids:
            problems.append(f"Broken page anchor: {url.fragment}")
    for attrs in page.images:
        path = SITE / attrs.get("src", "")
        if path.suffix == ".png" and path.is_file():
            data = path.read_bytes()
            if data[:8] != b"\x89PNG\r\n\x1a\n":
                problems.append(f"Invalid PNG: {path.name}")
                continue
            width, height = struct.unpack(">II", data[16:24])
            if (str(width), str(height)) != (attrs.get("width"), attrs.get("height")) and attrs.get("id") != "dialog-image":
                # Icons intentionally use smaller, square intrinsic display dimensions.
                if path.name != "app-icon.png":
                    problems.append(f"Incorrect intrinsic image dimensions: {path.name}")
    if not page.csp or any(directive not in page.csp for directive in ["default-src 'none'", "connect-src 'none'", "script-src 'self'", "base-uri 'none'", "object-src 'none'"]):
        problems.append("Missing restrictive browser security policy")
    js = (SITE / "script.js").read_text()
    if re.search(r"\b(?:fetch|XMLHttpRequest|WebSocket|localStorage|sessionStorage|sendBeacon|eval)\b|document\.cookie", js):
        problems.append("Review unexpected network, storage, or dynamic-code feature")
    for name in re.findall(r'image: "([^"]+)"', js):
        if not (SITE / "assets" / name).is_file():
            problems.append(f"Missing interactive tour image: {name}")
    for path in SITE.rglob("*"):
        if path.is_symlink():
            problems.append("Website must not include symbolic links")
        if path.is_file():
            data = path.read_bytes()
            if re.search(rb"/(?:Users|home)/[A-Za-z0-9._-]+/", data):
                problems.append(f"Personal local path in {path.name}")
            if path.suffix == ".png" and b"eXIf" in data:
                problems.append(f"Embedded EXIF metadata in {path.name}")
    if not (SITE / "assets/lumina-social.png").is_file():
        problems.append("Missing social sharing image")
    if problems:
        print("Website checks failed:\n" + "\n".join(f"- {item}" for item in problems))
        return 1
    total = sum(path.stat().st_size for path in SITE.rglob("*") if path.is_file())
    print(f"Website checks passed: {len(page.references)} resources/links, {len(page.images)} images, {total / 1024 / 1024:.2f} MiB total. No external runtime assets or browser storage.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
