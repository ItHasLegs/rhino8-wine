# Rhinoceros 3D on Linux with Wine

Scripts and instructions to install and run **Rhino 8** and the **Rhino 9 WIP** on
Linux under [Wine](https://www.winehq.org/).

As of **Wine 11.14**, Rhino runs on **stock Wine**. This repo provides two scripts:

- `install-rhino.sh` — creates an isolated Wine prefix, runs the Rhino installer, and
  adds a launcher and application-menu entry.
- `run-rhino.sh` — launches Rhino, with a `--fresh` option for licensing issues.

**Wine version requirement:** Wine **≥ 11.14**, from the WineHQ **devel** or **staging**
branch. `winehq-stable` is 11.0 and lacks the fix — Rhino crashes on launch with a stack
overflow. This applies until Wine 12.0 stable ships.

| |  |
|--|--|
| ![Rhino 8 on Ubuntu](desktop_screenshot.jpeg) | ![Rhino 8 on Arch](arch_desktop_screenshot.png) |

## Requirements

- 64-bit Linux desktop (X11 or Wayland). Tested on Ubuntu and Arch.
- Wine ≥ 11.14 (devel or staging — not stable).
- The Rhino installer for Windows from [rhino3d.com/download](https://www.rhino3d.com/download/).
- A Rhino license or the 90-day evaluation (sign in on first launch).

The Rhino installer bundles its own prerequisites (Visual C++ runtimes, WebView2, .NET 8
Desktop Runtime, ASP.NET Core Runtime); no winetricks step is needed.

## Quick start

```bash
# Install Wine >= 11.14 first (see below), then:
git clone https://github.com/ItHasLegs/rhino8-wine
cd rhino8-wine
./install-rhino.sh ~/Downloads/rhino_en-us_8.x.x.x.exe
./run-rhino.sh
```

## 1. Install Wine (≥ 11.14)

Install the **devel** or **staging** branch, not stable.

**Arch / Manjaro**
```bash
sudo pacman -S wine-staging
```

**Ubuntu / Debian**
```bash
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key -
sudo wget -NP /etc/apt/sources.list.d/ \
  "https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -sc)/winehq-$(lsb_release -sc).sources"
sudo apt update
sudo apt install --install-recommends winehq-staging
```
(Debian: replace `ubuntu` with `debian`.)

**Fedora**
```bash
# Fedora 41+ (dnf5):
sudo dnf config-manager addrepo --from-repofile=https://dl.winehq.org/wine-builds/fedora/$(rpm -E %fedora)/winehq.repo
# Older Fedora (dnf4): sudo dnf config-manager --add-repo https://dl.winehq.org/wine-builds/fedora/$(rpm -E %fedora)/winehq.repo
sudo dnf install winehq-staging
```

Verify:
```bash
wine --version      # must be wine-11.14 or newer
```

## 2. Install Rhino

```bash
./install-rhino.sh /path/to/rhino_installer.exe [prefix_dir]
```

The script checks Wine ≥ 11.14, creates an isolated prefix (default
`~/.local/share/wineprefixes/rhino8`), runs the installer, and adds a launcher and
application-menu entry.

Manual equivalent:
```bash
export WINEPREFIX=~/.local/share/wineprefixes/rhino8
WINEPREFIX=$WINEPREFIX wineboot -u
WINEPREFIX=$WINEPREFIX wine /path/to/rhino_installer.exe
WINEPREFIX=$WINEPREFIX wine "$WINEPREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
```

## 3. Launch and sign in

```bash
./run-rhino.sh
```

Manual equivalent:
```bash
export WINEPREFIX=~/.local/share/wineprefixes/rhino8
wine "$WINEPREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
```

On first launch, Rhino prompts for sign-in (Rhino Account / Cloud Zoo) to activate the
license. If the browser redirects to `http://127.0.0.1:1717/` and cannot connect, restart
the licensing server and launch again:
```bash
./run-rhino.sh --fresh
# or manually:
WINEPREFIX=~/.local/share/wineprefixes/rhino8 wineserver -k    # then relaunch
```

## Rhino 9 WIP

Use a separate prefix so the Rhino 8 setup is unaffected:
```bash
./install-rhino.sh ~/Downloads/rhino_9.x.x.x.exe ~/.local/share/wineprefixes/rhino9wip
WINEPREFIX=~/.local/share/wineprefixes/rhino9wip ./run-rhino.sh
```

If viewports render incorrectly (red/black, objects vanishing), switch **Options → View →
GPU → GPU Technology → OpenGL** and restart Rhino. Rhino 9 WIP defaults to Direct3D, which
misbehaves under Wine on some GPUs (seen on Nvidia + Wayland/XWayland).

## Bottles / Lutris

GUI managers ([Bottles](https://usebottles.com/), [Lutris](https://lutris.net/)) work if
their Wine runner is ≥ 11.14. Many default runners (e.g. Bottles' Proton-based *Soda*) are
older and will crash Rhino on launch. Select a vanilla/staging runner ≥ 11.14, or point the
manager at system Wine, before running the installer.

## Troubleshooting

| Symptom | Cause / fix |
|--------|-------------|
| Stack overflow on launch | Wine older than 11.14 (likely `winehq-stable` 11.0). Install staging/devel ≥ 11.14. |
| Installer fails at "package verification" | Wine older than 11.14. ≥ 11.14 verifies Rhino's signed packages. |
| Licensing can't reach `127.0.0.1:1717` | Stale HTTP state. Relaunch with `./run-rhino.sh --fresh`. |
| Rhino 9 WIP viewports black/red | Switch GPU Technology to OpenGL (see above). |
| Start clean | Delete the prefix (`rm -rf ~/.local/share/wineprefixes/rhino8`) and re-run `install-rhino.sh`. |

Launcher logs are written to `/tmp/rhino.log`.

---

*Rhinoceros® and Rhino® are trademarks of Robert McNeel & Associates. This is an unofficial
community guide, not affiliated with or endorsed by McNeel. Claude Code was used in this
project.*
