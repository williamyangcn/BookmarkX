#!/usr/bin/env bash
# Replace /Applications/BookmarkX.app with a freshly built Release app.
#
# DATA SAFETY:
# - Touches ONLY the .app bundle and Desktop alias.
# - Never reads/writes/deletes:
#     ~/Library/Containers/com.williamyang.BookmarkX/   (sandboxed live data)
#     ~/Library/Application Support/BookmarkX/            (legacy data)
# - Never runs sqlite, never clears credentials, never prunes folders.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-${ROOT}/.derivedData/Build/Products/Release/BookmarkX.app}"
DEST="/Applications/BookmarkX.app"
DESKTOP_ALIAS="${HOME}/Desktop/BookmarkX"

if [[ ! -d "${SRC}" ]]; then
  echo "Missing app bundle: ${SRC}" >&2
  echo "Build Release first (e.g. ./Scripts/package-dmg.sh) or pass an .app path." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${SRC}/Contents/Info.plist" 2>/dev/null || echo unknown)"
echo "==> Installing BookmarkX ${VERSION} → ${DEST}"
echo "    App bundle only. Data paths left untouched:"
echo "      • ~/Library/Containers/com.williamyang.BookmarkX/"
echo "      • ~/Library/Application Support/BookmarkX/"

# Quit if running so the bundle can be replaced cleanly.
if pgrep -x BookmarkX >/dev/null 2>&1; then
  echo "==> Quitting running BookmarkX"
  osascript -e 'tell application "BookmarkX" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -x BookmarkX >/dev/null 2>&1 || break
    sleep 0.25
  done
  if pgrep -x BookmarkX >/dev/null 2>&1; then
    echo "BookmarkX is still running; quit it and retry." >&2
    exit 1
  fi
fi

TMP="$(mktemp -d /tmp/BookmarkX-install.XXXXXX)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

ditto "${SRC}" "${TMP}/BookmarkX.app"
rm -rf "${DEST}"
ditto "${TMP}/BookmarkX.app" "${DEST}"

# Keep / refresh Desktop alias → /Applications/BookmarkX.app
rm -f "${DESKTOP_ALIAS}" "${HOME}/Desktop/BookmarkX alias" 2>/dev/null || true
osascript <<EOF
set destPOSIX to "${DEST}"
set desktopPOSIX to (POSIX path of (path to desktop folder))
tell application "Finder"
  set destFile to (POSIX file destPOSIX) as alias
  set desktopFolder to (POSIX file desktopPOSIX) as alias
  make alias file to destFile at desktopFolder with properties {name:"BookmarkX"}
end tell
EOF

INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${DEST}/Contents/Info.plist" 2>/dev/null || echo unknown)"
echo ""
echo "Installed: ${DEST} (${INSTALLED})"
echo "Desktop alias refreshed → ${DEST}"
echo "User data was not modified."
