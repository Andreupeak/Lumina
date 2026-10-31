#!/usr/bin/env python3
"""Build a privacy-checked, identity-free public beta. No uploads or paid services."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args: str, cwd: Path | None = None, log=None) -> None:
    subprocess.run(args, cwd=cwd, stdout=log, stderr=subprocess.STDOUT if log else None, check=True)


def capture(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(args, cwd=cwd, stderr=subprocess.STDOUT, text=True).strip()


def copy_file(source: str, destination: str) -> str:
    # Preserve executable bits, never copy Finder tags, quarantine, or other xattrs.
    shutil.copyfile(source, destination)
    os.chmod(destination, stat.S_IMODE(os.stat(source).st_mode))
    return destination


def verify_app(app: Path) -> dict:
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    assert info.get("LSUIElement") is True, "Missing menu-bar declaration"
    assert info.get("NSLocationUsageDescription"), "Missing macOS location purpose"
    assert info.get("NSLocationWhenInUseUsageDescription"), "Missing authorization purpose"
    assert info.get("CFBundleIdentifier") == "Andreupeak.Lumina", "Unexpected app identity"
    binary = contents / "MacOS/Lumina"
    assert {path.name for path in binary.parent.iterdir()} == {"Lumina"}, "Debug-injection binaries must not ship"
    arches = capture("lipo", "-archs", str(binary)).split()
    assert set(arches) == {"arm64", "x86_64"}, "Not a universal app"
    run("codesign", "--verify", "--deep", "--strict", str(app))
    signature = capture("codesign", "--display", "--verbose=2", str(app))
    assert "Signature=adhoc" in signature, "Expected an identity-free signature"
    assert "Authority=" not in signature, "Must not include a personal certificate"
    assert "runtime" in signature, "Hardened runtime is not enabled"
    entitlement_data = subprocess.run(
        ["codesign", "--display", "--entitlements", "-", "--xml", str(app)],
        capture_output=True, check=True).stdout
    entitlements = plistlib.loads(entitlement_data)
    assert entitlements == {"com.apple.security.personal-information.location": True}, "Unexpected or missing resource access entitlement"
    manifest = plistlib.loads((contents / "Resources/PrivacyInfo.xcprivacy").read_bytes())
    assert manifest["NSPrivacyTracking"] is False
    for path in app.rglob("*"):
        if path.is_symlink():
            assert path.resolve().is_relative_to(app.resolve()), "External app symlink"
            continue
        if not path.is_file():
            continue
        assert path.suffix.lower() not in {".p12", ".p8", ".pem", ".key", ".mobileprovision"}, "Signing material in bundle"
        data = path.read_bytes()
        assert not re.search(rb"/(?:Users|home)/[A-Za-z0-9._-]+/", data), "Personal home path in bundle"
        assert b"/private/var/folders/" not in data, "Personal temporary path in bundle"
        private_key_header = b"-----BEGIN " + b"PRIVATE KEY-----"
        assert private_key_header not in data, "Private key in bundle"
    return {"architectures": sorted(arches), "minimum_macos": info["LSMinimumSystemVersion"],
            "signing": "ad-hoc (no developer identity)", "notarized": False}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="e.g. 1.0.0-beta.1")
    parser.add_argument("--allow-dirty", action="store_true", help="local validation only; do not publish these artifacts")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[a-z]+\.\d+)?", args.version):
        parser.error("Use a version such as 1.0.0-beta.1")
    dirty = bool(capture("git", "status", "--porcelain", cwd=ROOT))
    if dirty and not args.allow_dirty:
        parser.error("Commit reviewed source before packaging, or use --allow-dirty for local checks")
    run("python3", str(ROOT / "scripts/check_repository.py"), "--history", cwd=ROOT)
    revision = capture("git", "rev-parse", "HEAD", cwd=ROOT)
    output = ROOT / "dist" / args.version
    output.mkdir(parents=True, exist_ok=True)
    stem = "Lumina-" + args.version
    for suffix in [".dmg", ".zip"]:
        if (output / (stem + suffix)).exists():
            parser.error("Output already exists; choose a new version or move the previous local output")

    # Compile away from the user's home so paths cannot leak through compiler metadata.
    with tempfile.TemporaryDirectory(prefix="lumina-release-", dir="/private/tmp") as temporary:
        work = Path(temporary)
        source = work / "source"
        source.mkdir()
        for name in ["Lumina", "Lumina.xcodeproj"]:
            shutil.copytree(ROOT / name, source / name, copy_function=copy_file,
                            ignore=shutil.ignore_patterns("xcuserdata", "*.xcuserstate", ".DS_Store"))
        with (output / "build.log").open("w") as log:
            run("xcodebuild", "-project", str(source / "Lumina.xcodeproj"), "-scheme", "Lumina",
                "-configuration", "Release", "-destination", "generic/platform=macOS",
                "-derivedDataPath", str(work / "DerivedData"), "CODE_SIGNING_ALLOWED=NO",
                "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
                "SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO",
                "MARKETING_VERSION=" + args.version.split("-")[0],
                "OTHER_SWIFT_FLAGS=$(inherited) -file-prefix-map " + str(source) + "=/Lumina -debug-prefix-map " + str(source) + "=/Lumina",
                "build", cwd=source, log=log)
        payload = work / "payload"
        payload.mkdir()
        app = payload / "Lumina.app"
        shutil.copytree(work / "DerivedData/Build/Products/Release/Lumina.app", app, copy_function=copy_file)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["LuminaReleaseVersion"] = args.version
        info["LuminaSourceRevision"] = revision
        info_path.write_bytes(plistlib.dumps(info))
        resources = app / "Contents/Resources"
        copy_file(str(ROOT / "LICENSE"), str(resources / "LICENSE.txt"))
        copy_file(str(ROOT / "PRIVACY.md"), str(resources / "PRIVACY.md"))
        run("xcrun", "strip", "-S", "-x", str(app / "Contents/MacOS/Lumina"))
        run("codesign", "--force", "--sign", "-", "--options", "runtime", "--timestamp=none",
            "--entitlements", str(ROOT / "Lumina/Lumina.entitlements"), str(app))
        metadata = verify_app(app)
        metadata.update(version=args.version, source_revision=revision, source_dirty=dirty)
        (output / "release-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
        copy_file(str(ROOT / "LICENSE"), str(payload / "LICENSE.txt"))
        copy_file(str(ROOT / "docs/INSTALL.md"), str(payload / "INSTALL.md"))
        (payload / "Applications").symlink_to("/Applications")
        run("ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", str(app), str(output / (stem + ".zip")))
        run("hdiutil", "create", "-volname", "Lumina", "-srcfolder", str(payload), "-format", "UDZO",
            "-fs", "HFS+", str(output / (stem + ".dmg")))
        run("hdiutil", "verify", str(output / (stem + ".dmg")))
    checksums = []
    for name in [stem + ".dmg", stem + ".zip", "release-metadata.json"]:
        checksums.append(hashlib.sha256((output / name).read_bytes()).hexdigest() + "  " + name)
    (output / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n")
    print("Prepared " + str(output) + (" (LOCAL DIRTY VALIDATION ONLY)" if dirty else ""))
    print("Only publish the DMG, ZIP, release-metadata.json, and SHA256SUMS.txt; never build.log.")


if __name__ == "__main__":
    main()
