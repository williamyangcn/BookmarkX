#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
echo "Generated BookmarkX.xcodeproj"
