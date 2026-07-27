#!/usr/bin/env bash
#
# run-rhino.sh — launch Rhinoceros (8 or 9 WIP) under stock Wine (>= 11.14).
#
# No patched Wine needed as of Wine 11.14 — the dark-mode fix is upstream.
#
# Usage:
#   ./run-rhino.sh                 launch Rhino
#   ./run-rhino.sh --fresh         restart the wineserver first
#                                  (fixes port 1717 / OAuth licensing failures)
#
# Environment overrides:
#   WINE         wine binary          (default: wine — your system Wine)
#   WINESERVER   wineserver binary    (default: wineserver)
#   WINEPREFIX   prefix to launch     (default: ~/.local/share/wineprefixes/rhino8)
#   RHINO        path to Rhino.exe    (default: auto-detected in the prefix)

set -euo pipefail

WINE="${WINE:-wine}"
WINESERVER="${WINESERVER:-wineserver}"
WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/rhino8}"
export WINEPREFIX

if ! command -v "$WINE" >/dev/null 2>&1; then
  echo "ERROR: '$WINE' not found. Install WineHQ devel or staging (>= 11.14)." >&2
  echo "       (winehq-stable is 11.0 and lacks Rhino's dark-mode fix.)" >&2
  exit 1
fi

# Locate Rhino.exe unless RHINO was provided (covers "Rhino 8", "Rhino 9 WIP", ...)
RHINO="${RHINO:-}"
if [ -z "$RHINO" ]; then
  RHINO="$(find "$WINEPREFIX/drive_c/Program Files" -maxdepth 3 \
    -path '*/System/Rhino.exe' 2>/dev/null | sort | head -n1 || true)"
fi

if [ -z "$RHINO" ] || [ ! -f "$RHINO" ]; then
  echo "ERROR: Rhino.exe not found in prefix: $WINEPREFIX" >&2
  echo "       Install it first:  ./install-rhino.sh /path/to/rhino_installer.exe" >&2
  echo "       Or point RHINO at the executable, or set WINEPREFIX." >&2
  exit 1
fi

if [ "${1:-}" = "--fresh" ]; then
  echo "Restarting wineserver for clean http.sys state..."
  "$WINESERVER" -k 2>/dev/null || true
  sleep 2
fi

echo "Launching: $RHINO"
DISPLAY="${DISPLAY:-:0}" \
WINEDEBUG="${WINEDEBUG:--all}" \
  "$WINE" "$RHINO" 2>/tmp/rhino.log
