#!/usr/bin/env bash
# Test the Wine-side dark-mode fix (uxtheme immersive-color exports) by running
# Rhino with an UNPATCHED rhcommon_c.dll. If the fix works, Rhino launches
# without the dark-mode mutual-recursion stack overflow described in
# WINE_PORTING_NOTES.md Problem 2 — without binary-patching Rhino's DLL.
#
# This installs the locally-built uxtheme.dll over the wine builtin, restores
# the original rhcommon_c.dll, then (optionally) launches Rhino.
#
# Usage:
#   ./test-uxtheme-fix.sh            # install dll + restore rhcommon, then print next step
#   ./test-uxtheme-fix.sh --run      # ...and launch Rhino, tailing the log
#   ./test-uxtheme-fix.sh --revert   # undo: restore wine's builtin uxtheme.dll
#
# Override locations with env vars if your layout differs:
#   WINE_INSTALL=/opt/wine-rhino8
#   WINEPREFIX=$HOME/.local/share/wineprefixes/rhino8

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
WINE_INSTALL="${WINE_INSTALL:-/opt/wine-rhino8}"
WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/rhino8}"
BUILT_X64="$REPO/src/build/dlls/uxtheme/x86_64-windows/uxtheme.dll"
BUILT_X86="$REPO/src/build/dlls/uxtheme/i386-windows/uxtheme.dll"
RHCOMMON_ORIG="$REPO/rhino8-rhcommon_c.dll.orig"

log() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2; }

# --- locate the wine builtin uxtheme.dll(s) ---------------------------------
mapfile -t BUILTINS < <(find "$WINE_INSTALL" -name uxtheme.dll 2>/dev/null)
if [[ ${#BUILTINS[@]} -eq 0 ]]; then
    err "no uxtheme.dll found under $WINE_INSTALL (set WINE_INSTALL=...)"
    exit 1
fi

# /opt/wine-rhino8 is root-owned (installed by makepkg/pacman), so writes there
# need sudo. Detect once; everything else (prefix, launch) stays non-root.
SUDO=""
if [[ ! -w "$WINE_INSTALL" ]]; then
    SUDO="sudo"
    log "$WINE_INSTALL is not writable; using sudo for DLL install (you'll be prompted)"
fi

revert() {
    local n=0
    for b in "${BUILTINS[@]}"; do
        if [[ -f "$b.builtin-bak" ]]; then
            $SUDO cp "$b.builtin-bak" "$b"; log "restored builtin: $b"; n=$((n+1))
        fi
    done
    [[ $n -eq 0 ]] && err "no .builtin-bak backups found to restore"
    exit 0
}
[[ "${1:-}" == "--revert" ]] && revert

[[ -f "$BUILT_X64" ]] || { err "built dll missing: $BUILT_X64 (run: make -C src/build dlls/uxtheme/x86_64-windows/uxtheme.dll)"; exit 1; }

# --- install our built uxtheme.dll over each builtin (matching arch) --------
for b in "${BUILTINS[@]}"; do
    case "$b" in
        *x86_64-windows*|*lib64*|*/system32/*) src="$BUILT_X64" ;;
        *i386-windows*|*/syswow64/*)           src="$BUILT_X86" ;;
        *)                                     src="$BUILT_X64" ;;
    esac
    [[ -f "$src" ]] || { err "no built dll for $b (skipping)"; continue; }
    [[ -f "$b.builtin-bak" ]] || $SUDO cp "$b" "$b.builtin-bak"   # one-time backup of pristine builtin
    $SUDO cp "$src" "$b"
    log "installed $(basename "$(dirname "$src")") uxtheme.dll -> $b"
done

# --- ensure rhcommon_c.dll is UNPATCHED (the whole point of the test) -------
RHCOMMON="$(find "$WINEPREFIX/drive_c" -ipath '*Rhino*/System/rhcommon_c.dll' 2>/dev/null | head -1 || true)"
if [[ -z "$RHCOMMON" ]]; then
    err "rhcommon_c.dll not found under $WINEPREFIX (is Rhino installed? set WINEPREFIX=...)"
    exit 1
fi
if [[ -f "$RHCOMMON_ORIG" ]]; then
    if ! cmp -s "$RHCOMMON_ORIG" "$RHCOMMON"; then
        cp "$RHCOMMON" "$RHCOMMON.patched-bak" 2>/dev/null || true
        cp "$RHCOMMON_ORIG" "$RHCOMMON"
        log "restored ORIGINAL (unpatched) rhcommon_c.dll  (saved prior copy as .patched-bak)"
    else
        log "rhcommon_c.dll already matches the unpatched original — good"
    fi
else
    err "no $RHCOMMON_ORIG to restore from; verify rhcommon_c.dll is unpatched manually:"
    err "  ./find-darkmode-patch.sh \"$RHCOMMON\""
fi

log "Setup complete. uxtheme fix installed, rhcommon_c.dll unpatched."

if [[ "${1:-}" == "--run" ]]; then
    log "Launching Rhino (log: /tmp/rhino.log). Watching for recursion crash + uxtheme stubs..."
    "$REPO/run-rhino.sh" --fresh &
    RHPID=$!
    sleep 8
    echo "----- uxtheme stub hits (proves real detection path runs) -----"
    grep -i "GetImmersive" /tmp/rhino.log | head || echo "  (none yet)"
    echo "----- stack overflow signature (should be ABSENT) -----"
    grep -i "stack overflow\|get_DarkMode\|virtual_setup_exception" /tmp/rhino.log | head || echo "  none — good"
    wait $RHPID 2>/dev/null || true
else
    echo
    log "Next: run Rhino and watch the log:"
    echo "    ./run-rhino.sh --fresh    # then, in another shell:"
    echo "    grep -iE 'GetImmersive|stack overflow|get_DarkMode' /tmp/rhino.log"
    echo
    log "Expect: 'GetImmersive...' FIXME lines present (real path runs),"
    log "        NO 'stack overflow' / 'get_DarkMode' recursion trace."
    log "Undo with: ./test-uxtheme-fix.sh --revert"
fi
