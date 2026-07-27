# Legacy: the old patched-Wine method (Wine < 11.14)

**You almost certainly don't need anything in this folder.**

As of **Wine 11.14**, Rhino runs on **stock Wine** with no patches — the fix that
made it work was contributed upstream and merged into Wine
([WineHQ MR !11223](https://gitlab.winehq.org/wine/wine/-/merge_requests/11223)).
Just follow the [top-level README](../README.md).

This folder is kept only for people stuck on **Wine older than 11.14** who can't
upgrade, and as a historical record.

## Contents

| File | What it was for |
|------|-----------------|
| `rhino8-wine.patch` | The Wine source patch: the four `uxtheme` immersive-color exports (Rhino's dark-mode probe) + a `wintrust` Authenticode override for the installer. Both are unnecessary on Wine ≥ 11.14. |
| `PKGBUILD` | Arch package (`wine-rhino8`) that builds Wine at the pinned commit with `rhino8-wine.patch` applied and installs it to `/opt/wine-rhino8` (does not touch system Wine). Build with `makepkg -si` from inside this folder. |
| `find-darkmode-patch.sh` | Binary fallback that patched Rhino's own `rhcommon_c.dll` when running under *unpatched* Wine that lacked the uxtheme exports. Obsolete once the exports are present (≥ 11.14). |
| `test-uxtheme-fix.sh` | Reproduces / verifies the dark-mode uxtheme fix under a built Wine. |

## Building the patched Wine (Arch)

```bash
cd legacy
makepkg -si          # builds wine-rhino8, installs to /opt/wine-rhino8
```

Then install and launch Rhino against that build by pointing the top-level
scripts at it:

```bash
# ALLOW_OLD_WINE=1 tells install-rhino.sh to skip its ">= 11.14" gate, since the
# patched build supplies the missing exports itself even on older Wine.
ALLOW_OLD_WINE=1 WINE=/opt/wine-rhino8/bin/wine ../install-rhino.sh /path/to/rhino_installer.exe
WINE=/opt/wine-rhino8/bin/wine ../run-rhino.sh
```

For the full debugging story behind these patches, see
[../WINE_PORTING_NOTES.md](../WINE_PORTING_NOTES.md).
