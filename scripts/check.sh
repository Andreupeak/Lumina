#!/bin/bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"
python3 scripts/check_repository.py --history
swift test --scratch-path build/SwiftPackage
./scripts/build.sh Debug
./scripts/build.sh Release
