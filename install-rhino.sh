#!/usr/bin/env bash
#
# install-rhino.sh — set up Rhinoceros (8 or 9 WIP) in its own Wine prefix.
#
# As of Wine 11.14 no patched Wine is needed: the uxtheme immersive-color
# exports that Rhino's dark-mode probe depends on are upstream, so stock Wine
# runs Rhino out of the box. This script just wraps the boring parts:
#   1. checks your Wine is new enough (>= 11.14),
#   2. creates a fresh, isolated prefix,
#   3. runs the Rhino installer,
#   4. drops a launcher + an application-menu entry.
#
# Usage:
#   ./install-rhino.sh /path/to/rhino_installer.exe [prefix_dir]
#
# Examples:
#   ./install-rhino.sh ~/Downloads/rhino_en-us_8.31.26126.13431.exe
#   ./install-rhino.sh ~/Downloads/rhino_9.0.26160.12305.exe \
#       ~/.local/share/wineprefixes/rhino9wip
#
# Environment overrides:
#   WINE       wine binary to use (default: wine)
#   WINEARCH   prefix architecture (default: win64)

set -euo pipefail

MIN_MAJOR=11
MIN_MINOR=14

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WINE="${WINE:-wine}"
WINEARCH="${WINEARCH:-win64}"

die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 1. arguments
# ---------------------------------------------------------------------------
INSTALLER="${1:-}"
[ -n "$INSTALLER" ] || die "usage: $0 /path/to/rhino_installer.exe [prefix_dir]"
[ -f "$INSTALLER" ] || die "installer not found: $INSTALLER"

WINEPREFIX="${2:-$HOME/.local/share/wineprefixes/rhino8}"

# ---------------------------------------------------------------------------
# 2. check Wine version (>= 11.14 — that's where Rhino's dark-mode fix landed)
# ---------------------------------------------------------------------------
command -v "$WINE" >/dev/null 2>&1 || die \
  "'$WINE' not found. Install the WineHQ devel or staging branch (>= 11.14).
   NOTE: winehq-stable is 11.0 and will NOT work — it lacks the fix."

RAW_VER="$("$WINE" --version 2>/dev/null || true)"
VER="$(printf '%s' "$RAW_VER" | sed -n 's/^wine-\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
[ -n "$VER" ] || die "could not parse Wine version from: '$RAW_VER'"

MAJOR="${VER%%.*}"
MINOR="${VER#*.}"
if [ "$MAJOR" -lt "$MIN_MAJOR" ] || { [ "$MAJOR" -eq "$MIN_MAJOR" ] && [ "$MINOR" -lt "$MIN_MINOR" ]; }; then
  if [ -n "${ALLOW_OLD_WINE:-}" ]; then
    warn "Wine $VER is older than ${MIN_MAJOR}.${MIN_MINOR}; continuing because ALLOW_OLD_WINE is set."
    warn "(Only safe with the legacy patched build — see legacy/README.md.)"
  else
    die "Wine $VER is too old — Rhino needs >= ${MIN_MAJOR}.${MIN_MINOR}.
   winehq-stable (11.0) does NOT have the fix; install winehq-devel or
   winehq-staging (>= 11.14), or set WINE=/path/to/newer/wine.
   (Using the legacy patched Wine build? Re-run with ALLOW_OLD_WINE=1.)"
  fi
else
  info "Using $RAW_VER  (>= ${MIN_MAJOR}.${MIN_MINOR}, good)"
fi

# ---------------------------------------------------------------------------
# 3. create the prefix and run the installer
# ---------------------------------------------------------------------------
export WINEPREFIX WINEARCH
info "Prefix: $WINEPREFIX"
if [ -e "$WINEPREFIX" ]; then
  warn "prefix already exists — reusing it (delete it first for a clean slate)."
fi

info "Initializing the Wine prefix..."
WINEDEBUG=-all "$WINE" wineboot -u

info "Launching the Rhino installer (a window will open; follow the prompts)..."
info "The installer bundles its prerequisites (VC runtimes, WebView2, .NET 8, ASP.NET Core)."
WINEDEBUG=-all "$WINE" "$INSTALLER"

# ---------------------------------------------------------------------------
# 4. locate the installed Rhino.exe and wire up launchers
# ---------------------------------------------------------------------------
info "Looking for the installed Rhino..."
RHINO_EXE="$(find "$WINEPREFIX/drive_c/Program Files" -maxdepth 3 \
  -path '*/System/Rhino.exe' 2>/dev/null | sort | head -n1 || true)"

if [ -z "$RHINO_EXE" ]; then
  warn "couldn't find Rhino.exe under the prefix — did the install finish?"
  warn "You can still launch manually once installed:"
  warn "  WINEPREFIX=$WINEPREFIX $SCRIPT_DIR/run-rhino.sh"
  exit 0
fi
info "Found: $RHINO_EXE"

# Product folder, e.g. "Rhino 8" or "Rhino 9 WIP" -> tag "rhino8" / "rhino9wip"
PRODUCT_DIR="$(basename "$(dirname "$(dirname "$RHINO_EXE")")")"   # ".../Rhino 8/System/Rhino.exe" -> "Rhino 8"
TAG="$(printf '%s' "$PRODUCT_DIR" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"

# best-effort icon
ICON="$(find "$(dirname "$RHINO_EXE")/.." -maxdepth 2 -iname '*.ico' 2>/dev/null | head -n1 || true)"
[ -n "$ICON" ] || ICON="applications-graphics"

APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
DESKTOP="$APPS_DIR/${TAG:-rhino}.desktop"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=$PRODUCT_DIR (Wine)
Comment=Rhinoceros 3D running under Wine
Exec=env WINEPREFIX="$WINEPREFIX" RHINO="$RHINO_EXE" "$SCRIPT_DIR/run-rhino.sh"
Icon=$ICON
Terminal=false
Categories=Graphics;3DGraphics;Engineering;
EOF
info "Created application-menu entry: $DESKTOP"

cat <<EOF

$(info "Done — $PRODUCT_DIR is installed.")

Launch it any of these ways:
  • From your application menu: "$PRODUCT_DIR (Wine)"
  • From a terminal:
      WINEPREFIX="$WINEPREFIX" "$SCRIPT_DIR/run-rhino.sh"

First launch will ask you to sign in (Rhino Account / Cloud Zoo). If the
browser redirects to http://127.0.0.1:1717/ and says "can't connect", run the
launcher once with --fresh to restart the licensing server:
      WINEPREFIX="$WINEPREFIX" "$SCRIPT_DIR/run-rhino.sh" --fresh
EOF
