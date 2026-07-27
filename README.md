# Run Rhinoceros 3D on Linux with Wine

A beginner-friendly guide to running **Rhino 8** (and the **Rhino 9 WIP**) on Linux
under [Wine](https://www.winehq.org/) — **no patched Wine, no DLL hacks, no compiling.**

As of **Wine 11.14**, everything Rhino needs to launch is upstream. You install a
recent-enough Wine, run Rhino's normal Windows installer inside a Wine "prefix"
(a self-contained fake `C:\` drive), sign in, and go.

> **The one thing you must get right:** you need **Wine ≥ 11.14** from the
> **devel** or **staging** branch. The `stable` branch is still **11.0**, which
> is missing the fix and will crash Rhino on launch. See
> [Step 1](#step-1-install-wine-1114) — this is the mistake to avoid.

|  |  |
|--|--|
| ![Rhino 8 on Ubuntu](desktop_screenshot.jpeg) | ![Rhino 8 on Arch](arch_desktop_screenshot.png) |

---

## What you need

- A 64-bit Linux desktop (X11 or Wayland). Tested on Ubuntu 24.04 and Arch.
- **Wine ≥ 11.14** (devel or staging branch — *not* stable). Instructions below.
- The **Rhino installer** for Windows — download from
  [rhino3d.com/download](https://www.rhino3d.com/download/) (Rhino 8, or the Rhino 9 WIP).
- A **Rhino license** (or the free 90-day evaluation) — you'll sign in on first launch.

Rhino's installer bundles its own prerequisites (Visual C++ runtimes, WebView2,
.NET 8 Desktop Runtime, ASP.NET Core Runtime), so there is **no winetricks step**.

---

## Quick start (3 steps)

```bash
# 1. Install Wine >= 11.14 (see Step 1 for your distro), then:
git clone https://github.com/ItHasLegs/rhino8-wine
cd rhino8-wine

# 2. Install Rhino into its own prefix (point it at the installer you downloaded):
./install-rhino.sh ~/Downloads/rhino_en-us_8.x.x.x.exe

# 3. Launch it (or use the "Rhino 8 (Wine)" entry added to your app menu):
./run-rhino.sh
```

That's it. The rest of this README explains each step and how to handle the
common snags.

---

## Step 1: Install Wine (≥ 11.14)

> ⚠️ **Do not install `winehq-stable`.** At the time of writing it is **11.0**,
> which lacks the exports Rhino's dark-mode detection needs — Rhino will crash on
> launch with a stack overflow. Install the **devel** or **staging** branch, which
> is **≥ 11.14**. (Once Wine **12.0 stable** ships, stable will be fine too.)

**Arch Linux / Manjaro**
```bash
sudo pacman -S wine-staging      # rolling release — already 11.14+
```

**Ubuntu / Debian** (via the official WineHQ repository)
```bash
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key -
sudo wget -NP /etc/apt/sources.list.d/ \
  "https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -sc)/winehq-$(lsb_release -sc).sources"
sudo apt update
sudo apt install --install-recommends winehq-staging   # NOT winehq-stable
```
(Debian: swap `ubuntu` for `debian` and use your release codename.)

**Fedora**
```bash
# Fedora 41+ (dnf5):
sudo dnf config-manager addrepo --from-repofile=https://dl.winehq.org/wine-builds/fedora/$(rpm -E %fedora)/winehq.repo
# Older Fedora (dnf4): sudo dnf config-manager --add-repo https://dl.winehq.org/wine-builds/fedora/$(rpm -E %fedora)/winehq.repo
sudo dnf install winehq-staging
```

**Verify you got a new enough version:**
```bash
wine --version      # must be wine-11.14 or newer
```
If this prints `wine-11.0` (or anything below 11.14) you installed the stable
branch — remove it and install **staging** or **devel** instead.

---

## Step 2: Install Rhino

The included `install-rhino.sh` does the whole setup for you:

```bash
./install-rhino.sh /path/to/rhino_installer.exe [optional_prefix_dir]
```

It will:
1. Check that your Wine is ≥ 11.14 (and stop with a clear message if not).
2. Create a fresh, isolated prefix (default:
   `~/.local/share/wineprefixes/rhino8`).
3. Run Rhino's installer — a normal Windows installer window opens; click through it.
4. Add a **launcher** and an **application-menu entry** (e.g. "Rhino 8 (Wine)").

<details>
<summary><b>Prefer to do it by hand? (manual steps)</b></summary>

```bash
# 1. Pick an isolated prefix for Rhino
export WINEPREFIX=~/.local/share/wineprefixes/rhino8

# 2. Create it
WINEPREFIX=$WINEPREFIX wineboot -u

# 3. Run the installer (bundles all prerequisites; just click through)
WINEPREFIX=$WINEPREFIX wine /path/to/rhino_installer.exe

# 4. Launch Rhino
WINEPREFIX=$WINEPREFIX \
  wine "$WINEPREFIX/drive_c/Program Files/Rhino 8/System/Rhino.exe"
```
</details>

---

## Step 3: Launch Rhino & sign in

Use the app-menu entry, or:

```bash
./run-rhino.sh
```

On first launch Rhino asks you to **sign in** (Rhino Account / Cloud Zoo) to
activate your license.

**If licensing fails** — the browser redirects to `http://127.0.0.1:1717/` and
shows "can't connect" — it's stale internal HTTP state. Restart the licensing
server and try again:

```bash
./run-rhino.sh --fresh
```

---

## Rhino 9 WIP (experimental)

The same stock Wine runs the Rhino 9 WIP. **Use a separate prefix** so your
working Rhino 8 setup is untouched:

```bash
./install-rhino.sh ~/Downloads/rhino_9.x.x.x.exe ~/.local/share/wineprefixes/rhino9wip
```

Then launch it with:

```bash
WINEPREFIX=~/.local/share/wineprefixes/rhino9wip ./run-rhino.sh
```

**If viewports render wrong (red/black, objects vanishing):** Rhino 9 WIP
defaults to Direct3D, which can misbehave under Wine on some GPUs (seen on
Nvidia + Wayland/XWayland). Switch to OpenGL: **Options → View → GPU → GPU
Technology → OpenGL**, then restart Rhino.

The Rhino 9 WIP changes often; see
[WINE_PORTING_NOTES.md](WINE_PORTING_NOTES.md#rhino-9-wip-experimental) for
version-specific notes.

---

## Using a GUI manager instead (Bottles / Lutris)

If you'd rather not touch a terminal, GUI Wine managers like
[Bottles](https://usebottles.com/) or [Lutris](https://lutris.net/) can create
and manage the prefix for you. **One important caveat:** these ship their own
bundled Wine "runners", and **the runner must be Wine ≥ 11.14** for Rhino to
launch. Many default runners (e.g. Bottles' Proton-based *Soda*) are older or
game-focused and **may not include the fix** — if Rhino crashes on launch, the
runner is too old.

In Bottles: create a bottle, then in its settings pick a **runner that is
≥ 11.14** (a recent vanilla/staging runner) — or point Bottles at your **system
Wine** — before running the Rhino installer. Everything else (sign-in, the port
1717 note) is the same.

---

## Troubleshooting

| Symptom | Cause & fix |
|--------|-------------|
| Rhino crashes on launch with `stack overflow` | Your Wine is **older than 11.14** (probably `winehq-stable` 11.0). Install **staging/devel ≥ 11.14**. |
| Installer fails at "package verification" | You're on an **old Wine**; ≥ 11.14 verifies Rhino's Microsoft-signed packages fine. |
| Licensing page can't reach `127.0.0.1:1717` | Stale HTTP state — relaunch with `./run-rhino.sh --fresh`. |
| Rhino 9 WIP viewports are black/red | Switch **GPU Technology → OpenGL** (see above). |
| Want to start completely clean | Delete the prefix dir (e.g. `rm -rf ~/.local/share/wineprefixes/rhino8`) and re-run `install-rhino.sh`. |

Full runtime logs from the launcher are written to `/tmp/rhino.log`.

---

## Background: why this used to need patches

Getting Rhino to launch on Wine originally required a **custom-patched Wine
build**. Rhino's `RhOSInDarkMode` (in `RhinoCore.dll`) probes the OS dark-mode
setting via four undocumented `uxtheme.dll` immersive-color exports; Wine didn't
provide them, so the probe fell into a managed-callback loop that recursed until
the stack overflowed (~255,000 frames) and Rhino died on launch.

The fix was to add those exports to Wine's `uxtheme`. That change was
**contributed upstream and merged into Wine, shipping in 11.14**
([WineHQ MR !11223](https://gitlab.winehq.org/wine/wine/-/merge_requests/11223)) —
so **no patched Wine is needed anymore.** An installer-time Authenticode
signature workaround that older Wine also needed is likewise no longer required
on ≥ 11.14.

The old patched-Wine build (`wine-rhino8` / `rhino8-wine.patch`) now lives in
[`legacy/`](legacy/) for anyone stuck on Wine older than 11.14, and the full
debugging write-up is in
[WINE_PORTING_NOTES.md](WINE_PORTING_NOTES.md).

---

*Rhinoceros® and Rhino® are trademarks of Robert McNeel & Associates. This is an
unofficial community guide and is not affiliated with or endorsed by McNeel.
Claude Code was used in this project.*
