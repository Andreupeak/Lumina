#!/usr/bin/env python3
"""Small, dependency-free repository checks; not a comprehensive secret scanner."""

import argparse
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "private key": rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----",
    "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b",
    "AWS access key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "Slack token": rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b",
    "API secret": rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,}\b",
    "credential assignment": rb"(?im)^\s*(?:api[_-]?key|secret|password|access[_-]?token)\s*[:=]\s*[\"']?[A-Za-z0-9/+_=.-]{16,}",
}
SECRET_SUFFIXES = {".pem", ".key", ".p8", ".p12", ".pfx", ".mobileprovision", ".provisionprofile"}


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=ROOT)


def scan(data: bytes, label: str, problems: list[str]) -> None:
    for name, pattern in PATTERNS.items():
        match = re.search(pattern, data)
        if match:
            line = data[:match.start()].count(b"\n") + 1
            # Never print matched values into CI logs.
            problems.append(f"{label}:{line}: possible {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true", help="scan all locally available Git commits")
    args = parser.parse_args()
    problems: list[str] = []
    files = sorted(set(git("ls-files", "--cached", "--others", "--exclude-standard", "-z").decode().split("\0")) - {""})
    for name in files:
        path = ROOT / name
        if path.is_symlink():
            problems.append(f"{name}: review symbolic link before publication")
            continue
        if not path.is_file():
            continue
        if path.suffix.lower() in SECRET_SUFFIXES or (path.name.startswith(".env") and path.name != ".env.example"):
            problems.append(f"{name}: local secret or environment file must not be published")
        if any(part in {"xcuserdata", "DerivedData", ".build"} for part in path.parts) or path.name == ".DS_Store":
            problems.append(f"{name}: generated or user-specific file must not be published")
        data = path.read_bytes()
        scan(data, name, problems)
        if re.search(rb"/(?:Users|home)/[A-Za-z0-9._-]+/", data):
            problems.append(f"{name}: personal absolute filesystem path")
        if path.suffix == ".png" and b"eXIf" in data:
            problems.append(f"{name}: review/remove embedded EXIF metadata")

    for name in ["README.md", "LICENSE", "PRIVACY.md", "SECURITY.md", "CONTRIBUTING.md", "docs/TESTING.md", "docs/RELEASING.md"]:
        if not (ROOT / name).is_file():
            problems.append(f"{name}: required public-project documentation is missing")

    project = (ROOT / "Lumina.xcodeproj/project.pbxproj").read_text()
    if re.search(r"DEVELOPMENT_TEAM\s*=\s*\w", project):
        problems.append("project: do not commit a developer's signing team")
    if project.count("ENABLE_HARDENED_RUNTIME = YES;") != 2:
        problems.append("project: enable hardened runtime for Debug and Release")
    if project.count("INFOPLIST_KEY_LSUIElement = YES;") != 2:
        problems.append("project: declare the menu-bar app's LSUIElement flag")
    if "NSAllowsArbitraryLoads" in project:
        problems.append("project: do not relax App Transport Security")
    if project.count("INFOPLIST_KEY_NSLocationUsageDescription =") != 2:
        problems.append("project: include the macOS location purpose string in both configurations")
    try:
        entitlements = plistlib.loads((ROOT / "Lumina/Lumina.entitlements").read_bytes())
        if entitlements != {"com.apple.security.personal-information.location": True}:
            problems.append("entitlements: allow only user-authorized location access")
    except (OSError, plistlib.InvalidFileException):
        problems.append("entitlements: missing or invalid resource-access declaration")

    manifest_path = ROOT / "Lumina/PrivacyInfo.xcprivacy"
    try:
        manifest = plistlib.loads(manifest_path.read_bytes())
        required = {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}
        if manifest.get("NSPrivacyTracking") is not False or required not in manifest.get("NSPrivacyAccessedAPITypes", []):
            problems.append("privacy manifest: declare no tracking and local UserDefaults access")
        location_disclosure = {
            "NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeCoarseLocation",
            "NSPrivacyCollectedDataTypeLinked": True,
            "NSPrivacyCollectedDataTypeTracking": False,
            "NSPrivacyCollectedDataTypePurposes": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
        }
        if location_disclosure not in manifest.get("NSPrivacyCollectedDataTypes", []):
            problems.append("privacy manifest: disclose the optional IP location service")
    except (OSError, plistlib.InvalidFileException):
        problems.append("privacy manifest: missing or invalid plist")

    for path in (ROOT / ".github/workflows").glob("*.yml"):
        workflow = path.read_text()
        if "pull_request_target:" in workflow:
            problems.append(f"{path.name}: untrusted PR code must not run with target privileges")
        if "contents: read" not in workflow:
            problems.append(f"{path.name}: declare read-only repository permission")
        for action, revision in re.findall(r"uses:\s*([^@\s]+)@([^\s#]+)", workflow):
            if not re.fullmatch(r"[0-9a-f]{40}", revision):
                problems.append(f"{path.name}: pin {action} to a full commit SHA")

    revisions = git("rev-list", "--all").decode().splitlines() if args.history else []
    seen_blobs: set[str] = set()
    for revision in revisions:
        for entry in git("ls-tree", "-rz", revision).split(b"\0"):
            if not entry:
                continue
            metadata, name = entry.split(b"\t", 1)
            _, kind, blob = metadata.decode().split()
            if kind != "blob" or blob in seen_blobs:
                continue
            seen_blobs.add(blob)
            scan(git("cat-file", "blob", blob), f"history {revision[:8]}:{name.decode()}", problems)

    if problems:
        print("Repository checks failed (matched values are redacted):")
        for problem in problems:
            print(f"- {problem}")
        return 1
    print(f"Repository checks passed: {len(files)} files, {len(revisions)} historical commits. No known credential patterns found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
