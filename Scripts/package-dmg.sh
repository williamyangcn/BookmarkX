#!/usr/bin/env bash
# Build a notarization-ready unsigned (ad-hoc) DMG for local / GitHub Release distribution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/BookmarkX/Resources/Info.plist 2>/dev/null || echo '0.1.0')}"
DERIVED="${ROOT}/.derivedData"
PRODUCT="${DERIVED}/Build/Products/Release/BookmarkX.app"
DIST="${ROOT}/dist"
STAGE="${DIST}/dmg-stage"
DMG_NAME="BookmarkX-${VERSION}.dmg"
DMG_PATH="${DIST}/${DMG_NAME}"

echo "==> Generating Xcode project"
./Scripts/generate.sh

echo "==> Building Release"
xcodebuild \
  -scheme BookmarkX \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES

if [[ ! -d "${PRODUCT}" ]]; then
  echo "Build product missing: ${PRODUCT}" >&2
  exit 1
fi

echo "==> Staging DMG contents"
rm -rf "${STAGE}"
mkdir -p "${STAGE}" "${DIST}"
ditto "${PRODUCT}" "${STAGE}/BookmarkX.app"
ln -sf /Applications "${STAGE}/Applications"

echo "==> Creating ${DMG_PATH}"
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "BookmarkX ${VERSION}" \
  -srcfolder "${STAGE}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

rm -rf "${STAGE}"

echo ""
echo "DMG ready:"
echo "  ${DMG_PATH}"
ls -lh "${DMG_PATH}"
