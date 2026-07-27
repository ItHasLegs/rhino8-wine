#!/usr/bin/env bash
# Locate (and optionally apply) the RHC_RhOSInDarkMode binary patch in
# rhcommon_c.dll that breaks the Wine dark-mode mutual-recursion crash
# (see WINE_PORTING_NOTES.md, Problem 2).
#
# RHC_RhOSInDarkMode is a JMP-thunk export:
#   48 ff 25 ?? ?? ?? ?? cc      ; jmp [rip+disp]; int3
# Patching it to:
#   31 c0 c3 90 90 90 90 cc      ; xor eax,eax; ret; nop*4; int3
# makes it always report "light mode", breaking the recursion.
#
# The file offset of this export shifts between Rhino builds/versions
# (0xdff50 for Rhino 8.31.26126.13431, 0x136040 for Rhino 9.0.26160.12305
# WIP), so this script re-derives it from the DLL's own export table and
# section headers rather than hardcoding it.
#
# Usage:
#   find-darkmode-patch.sh <path-to-rhcommon_c.dll> [--apply]
#
# Without --apply: reports the offset and whether it matches the patchable
# JMP-thunk pattern.
# With --apply: backs up the DLL to <dll>.bak (if not already present) and
# writes the patch in place.

set -euo pipefail

DLL="${1:?Usage: $0 <path-to-rhcommon_c.dll> [--apply]}"
APPLY=0
[[ "${2:-}" == "--apply" ]] && APPLY=1

if [[ ! -f "$DLL" ]]; then
    echo "error: '$DLL' not found" >&2
    exit 1
fi

WINEDUMP="${WINEDUMP:-$(command -v winedump || true)}"
if [[ -z "$WINEDUMP" ]]; then
    for candidate in /opt/wine-rhino8/bin/winedump; do
        [[ -x "$candidate" ]] && WINEDUMP="$candidate" && break
    done
fi
if [[ -z "$WINEDUMP" ]]; then
    echo "error: winedump not found (set WINEDUMP=/path/to/winedump)" >&2
    exit 1
fi

if ! command -v objdump >/dev/null; then
    echo "error: objdump not found (install binutils)" >&2
    exit 1
fi

# --- Find the export's RVA -------------------------------------------------
RVA_HEX=$("$WINEDUMP" -j export "$DLL" | awk '$3 == "RHC_RhOSInDarkMode" {print $1}')
if [[ -z "$RVA_HEX" ]]; then
    echo "error: RHC_RhOSInDarkMode export not found in $DLL" >&2
    echo "       (this DLL may not need the dark-mode patch, or McNeel renamed/inlined it)" >&2
    exit 1
fi
RVA=$((16#$RVA_HEX))

# --- Map RVA -> file offset via section headers ----------------------------
IMAGEBASE_HEX=$(objdump -p "$DLL" | awk '/^ImageBase/{print $2}')
IMAGEBASE=$((16#$IMAGEBASE_HEX))

FILE_OFFSET=""
while read -r _idx _name _size vma _lma fileoff _algn; do
    [[ "$_name" == .* || "$_name" == _* ]] || continue
    sec_vma=$((16#$vma))
    sec_size=$((16#$_size))
    sec_rva=$((sec_vma - IMAGEBASE))
    if (( RVA >= sec_rva && RVA < sec_rva + sec_size )); then
        FILE_OFFSET=$(( (16#$fileoff) + (RVA - sec_rva) ))
        SECTION="$_name"
        break
    fi
done < <(objdump -h "$DLL" | awk 'NF==7 && $1 ~ /^[0-9]+$/')

if [[ -z "$FILE_OFFSET" ]]; then
    echo "error: could not map RVA 0x$RVA_HEX to a file offset" >&2
    exit 1
fi

printf 'RHC_RhOSInDarkMode: RVA 0x%x, section %s, file offset 0x%x\n' \
    "$RVA" "$SECTION" "$FILE_OFFSET"

# --- Check the bytes ---------------------------------------------------------
CURRENT=$(xxd -s "$FILE_OFFSET" -l 8 -p "$DLL")
printf 'current bytes: %s\n' "$CURRENT"

PATCHED_PATTERN="^31c0c39090909[0-9a-f]cc$"
THUNK_PATTERN="^48ff25........cc$"

if [[ "$CURRENT" =~ $PATCHED_PATTERN ]]; then
    echo "status: already patched (xor eax,eax; ret)"
    exit 0
elif [[ "$CURRENT" =~ $THUNK_PATTERN ]]; then
    echo "status: unpatched JMP thunk - patchable"
else
    echo "status: unexpected byte pattern - do not blindly patch, investigate manually" >&2
    exit 1
fi

if (( APPLY )); then
    if [[ ! -f "$DLL.bak" ]]; then
        cp "$DLL" "$DLL.bak"
        echo "backed up original to $DLL.bak"
    fi
    printf '\x31\xc0\xc3\x90\x90\x90\x90' | dd of="$DLL" bs=1 seek="$FILE_OFFSET" conv=notrunc status=none
    NEW=$(xxd -s "$FILE_OFFSET" -l 8 -p "$DLL")
    printf 'patched bytes: %s\n' "$NEW"
else
    echo "dry run - re-run with --apply to patch (backs up to $DLL.bak first)"
fi
