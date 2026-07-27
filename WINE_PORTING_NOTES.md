# Rhino 8 on Linux via Wine — Porting Notes

Detailed writeup of every problem encountered getting Rhinoceros 8 running under Wine 11.9. For setup instructions see [README.md](README.md).

> **Note:** the dark-mode fix described here is now **upstream in Wine 11.14**, so
> stock Wine runs Rhino with no patches — see [README.md](README.md). The build
> files this document references (`rhino8-wine.patch`, `PKGBUILD`,
> `find-darkmode-patch.sh`, `test-uxtheme-fix.sh`) now live in
> [`legacy/`](legacy/), kept only for Wine older than 11.14. This document is
> preserved as the historical record.

---

## What Was Changed and Why

### Problem 1: Immediate Crash — Stack Overflow (turned out to be Problem 2)

**Symptom:** Rhino crashed on startup with `STATUS_STACK_OVERFLOW` /
`err:virtual:virtual_setup_exception stack overflow … bytes`, before any UI.

**Root cause:** the dark-mode mutual recursion described in **Problem 2** —
hundreds of thousands of frames deep. It was never a stack-*sizing* problem. The
whole stack investigation this section once documented was chasing the wrong
cause.

**Resolution:** fixed at the source by Problem 2 (the `uxtheme` exports). With
the recursion gone, Wine's default stack sizes are sufficient, and **every**
stack patch tried during the chase has since been removed — none survives:

- **512 MB native reservation + guard-page move + StackLimit clamp** — removed
  in commit `600e4d2`; never required.
- **VirtualQuery `AllocationBase` clamp** (`virtual.c`) — removed 2026-06-15. A
  near-no-op for the ~1 MB 64-bit stacks Rhino actually uses, and never
  upstreamable (it made `VirtualQuery` report a deliberately false value).
- **8 MB WoW64 (32-bit) stack minimum** (`thread.c`) — removed 2026-06-15. It
  only affected the 32-bit WoW64 path — i.e. the **32-bit Rhino installer**
  (`rhino_en-us_*.exe` is a PE32/i386 WiX Burn bundle), not Rhino's 64-bit
  runtime. **Verified:** with it removed, the installer completes a full install
  on a default 1 MB stack with no overflow. (The earlier claim that this fixed
  "a 32-bit thread during Rhino startup" was wrong on both counts — it was the
  installer, and the installer didn't need it either.)

Net: Problem 1 leaves **no surviving source changes**. Every ntdll/native patch
that ever existed here was a red herring for Problem 2.

> **A red herring — the opaque `virtual_setup_exception` crash:** While chasing this, a *different*-looking crash sometimes appeared instead of a clean `STATUS_STACK_OVERFLOW`:
>
> ```
> err:virtual:virtual_setup_exception stack overflow 4672 bytes addr 0x6ffffff85ebe stack 0x7ffffe0ffdc0 (0x7ffffe100000-0x7ffffe101000-0x7ffffe200000)
> ```
>
> This is *not* a normal overflow delivery — it's Wine's own signal handler double-faulting while trying to build the exception frame, because whatever was overflowing blew straight through the guard page *and* the small "guaranteed region" beneath it (just one host page, ~4 KB) before Wine could catch it. The result is an opaque internal abort with no managed stack trace — which looks exactly like "the stack is too small."
>
> It wasn't. The actual cause of *that* overflow was the dark-mode mutual-recursion bug described in Problem 2 below — hundreds of thousands of frames deep, recursing fast enough to blow through everything before an exception frame could be set up. We initially chased it as a stack-*sizing* problem: forcing native 64-bit stacks to reserve 512 MB and moving the guard page to `+64 KB` (instead of the default ~4 KB) didn't fix anything by itself, but it gave the runaway recursion enough room that the resulting `STATUS_STACK_OVERFLOW` could finally be delivered *cleanly* — complete with a full managed stack trace pointing straight at `Rhino.Runtime.AdvancedSettings.get_DarkMode()` ↔ `RHC_RhOSInDarkMode`. That trace is what led to the real fix in Problem 2.
>
> Once the recursion itself is eliminated (Problem 2's `uxtheme` fix), there's nothing left to overflow any stack — Wine's normal default stack sizes are sufficient, and *none* of the stack patches tried during the chase are needed. (Confirmed: with the Problem 2 fix and zero ntdll stack patches, Rhino launches cleanly and the 32-bit installer completes a full install without overflow.)
>
> If you ever see `virtual_setup_exception stack overflow ... bytes` rather than a clean, managed `STATUS_STACK_OVERFLOW` with a stack trace, treat it as a symptom of runaway recursion *somewhere upstream* rather than a sign that stacks need to be bigger — the fix is to find and stop the recursion, not to give it more room to run in.

---

### Problem 2: Dark Mode Mutual Recursion — 254,955 Frames Deep

**Symptom:** Rhino crashed with a stack trace showing Rhino's own code: `Rhino.Runtime.AdvancedSettings.get_DarkMode()` (C#) calling P/Invoke to `RHC_RhOSInDarkMode` in `rhcommon_c.dll`, which called back into .NET managed code, which called `get_DarkMode()` again. 254,955 frames deep.

**Root cause (verified by disassembly):** It is *not* a Wine stub returning bad
data — it is **missing `uxtheme.dll` exports**, which makes Rhino take its own
fallback-to-managed-code branch. The chain, confirmed against the binaries:

- `RHC_RhOSInDarkMode` (rhcommon_c.dll) is a JMP thunk to the imported
  `RhOSInDarkMode` (`?RhOSInDarkMode@@YA_NXZ`), which is **exported by
  `RhinoCore.dll`** — that is where the OS probe actually lives.
- On first use, `RhOSInDarkMode` lazily builds a singleton whose constructor
  does `LoadLibraryExW("uxtheme.dll")` and then four `GetProcAddress` lookups,
  storing the results in fields the probe later requires to be **all non-null**:

  | field | uxtheme export | how it's looked up |
  |-------|----------------|--------------------|
  | +0x18 | `GetImmersiveColorFromColorSetEx`   | by name |
  | +0x20 | `GetImmersiveUserColorSetPreference` | by name |
  | +0x28 | `GetImmersiveColorTypeFromName` (ordinal **96**)        | by ordinal |
  | +0x30 | `GetImmersiveColorNamedTypeByIndex` (ordinal **100**)   | by ordinal |

- If **any** of the four is null, `RhOSInDarkMode` skips the real detection and
  instead invokes the registered managed `DarkModeDelegate` hook
  (`call [vtable+0xe0]`). That hook is `Rhino.Runtime.AdvancedSettings::
  SetGetDarkModeHook(value, set=false)`, whose IL unconditionally
  `call get_DarkMode()`. `get_DarkMode()` in turn calls `RHC_RhOSInDarkMode()`
  to populate its `_DarkModeWhenRhinoStarted` cache — but the cache is stored
  only *after* the call returns, and it never returns: native → managed hook →
  `get_DarkMode` → native → … 254,955 frames deep.

- **Why Windows is fine and Wine is not:** real `uxtheme.dll` exports all four
  (the `GetImmersive*ColorSet*` family is name-exported; the dark-mode toggles
  like `ShouldAppsUseDarkMode` are the *separate* ordinal-only group). Wine
  implemented only the toggle group (ordinals 104/132/133/135/136/137/138) and
  **none** of the four immersive-color-set entry points Rhino actually resolves.
  So on Wine the four `GetProcAddress` calls return NULL, the fallback branch is
  always taken, and the recursion is unavoidable. On Windows the fallback branch
  is effectively dead code.

(The native side was read from `RhinoCore.dll` with `objdump -d`; the managed
side from `RhinoCommon.dll` with `ikdasm` — note `monodis` aborts on these
assemblies with a `System.Reflection.Metadata` load assertion.)

**Fix:** Binary-patched `rhcommon_c.dll`. The export `RHC_RhOSInDarkMode` at file offset `0xdff50` (RVA `0xe0b50`) was a JMP thunk:

```
before: 48 ff 25 19 8d 08 00 cc   (JMP [rip+...])
after:  31 c0 c3 90 90 90 90 cc   (xor eax,eax; ret; nop*4)
```

Always returns 0 (light mode), breaking the recursion. Back up the DLL before patching.

**Alternative fix (patch Wine instead of Rhino):** Because the true cause is the
four missing `uxtheme.dll` exports, you can fix it once in Wine and never touch
Rhino's signed DLL again (survives Rhino updates). Add the exports to
`dlls/uxtheme/uxtheme.spec`:

```
95  stdcall GetImmersiveColorFromColorSetEx(long long long long)
96  stdcall -noname GetImmersiveColorTypeFromName(wstr)
98  stdcall GetImmersiveUserColorSetPreference(long long)
100 stdcall -noname GetImmersiveColorNamedTypeByIndex(long)
```

(95 and 98 must be name-exported — Rhino resolves them with `GetProcAddress` by
name; 96 and 100 are resolved by ordinal.) Then implement them in
`dlls/uxtheme/system.c` next to the existing dark-mode stubs:

```c
/* UXTHEME.95 — Rhino reads ImmersiveApplicationText luminance to decide dark/light.
 * Return a color that follows AppsUseLightTheme so the OS setting is honoured:
 * dark mode -> bright text (white); light mode -> black. */
DWORD WINAPI GetImmersiveColorFromColorSetEx(UINT color_set, UINT color_type,
                                             BOOL ignore_high_contrast, UINT high_contrast_cache_mode)
{
    DWORD light_theme = TRUE, size = sizeof(light_theme);
    RegGetValueW(HKEY_CURRENT_USER,
                 L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                 L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &light_theme, &size);
    return light_theme ? 0x00000000 : 0x00ffffff;
}

int WINAPI GetImmersiveColorTypeFromName(const WCHAR *name)          /* UXTHEME.96  */
{ FIXME("%s: stub\n", debugstr_w(name)); return 0; }

int WINAPI GetImmersiveUserColorSetPreference(BOOL force, BOOL skip) /* UXTHEME.98  */
{ FIXME("%d %d: stub\n", force, skip); return 0; }

const void * WINAPI GetImmersiveColorNamedTypeByIndex(UINT index)   /* UXTHEME.100 */
{ FIXME("%u: stub\n", index); return NULL; }   /* gate-only: required non-null, never called by the probe */
```

With all four present, `RhOSInDarkMode` takes its real path, computes luminance
from the (stubbed) application-text color, and returns a definite light/dark
answer instead of falling into the managed hook — same end result as the binary
patch, but Rhino's DLL stays untouched. Requires rebuilding `uxtheme.dll`.

**Validated (2026-06-15):** with these four exports added, Rhino 8 launches
cleanly under Wine with a **completely unpatched** `rhcommon_c.dll` — no
dark-mode recursion, no stack overflow. This fix is now folded into
`rhino8-wine.patch`, so a normal `makepkg -si` build includes it and the binary
patch to Rhino's DLL is no longer required. (`test-uxtheme-fix.sh` reproduces
the test by dropping the locally-built `uxtheme.dll` over the wine builtin.)

---

### Problem 3: No X11 Display

**Symptom:** Rhino exited silently with "no driver could be loaded."

**Root cause:** The `DISPLAY` environment variable wasn't set.

**Fix:** Added `DISPLAY="${DISPLAY:-:0}"` to the launch script.

---

### Problem 4: Licensing — Port 1717 Never Bound

**Symptom:** The OAuth login flow opened Firefox. After logging in to McNeel's servers, Firefox redirected to `http://127.0.0.1:1717/` to deliver the auth token — and got "Firefox can't connect to the server."

**Investigation:** Enabled `WINEDEBUG=+http` and confirmed Rhino was correctly calling `HttpAddUrlToUrlGroup` with `http://127.0.0.1:1717/`. Wine has a real implementation of the Windows HTTP Server API: `httpapi.dll` → `IOCTL_HTTP_ADD_URL` → `http.sys` kernel driver in `winedevice.exe`. Added instrumentation to Wine's `http_add_url` confirming the ioctl reached the driver and `bind()`/`listen()` was being attempted — but the socket never appeared.

**Root cause:** Stale `http.sys` state. Between Rhino restarts, only Rhino was being killed while the wineserver (and the `winedevice.exe` running `http.sys`) stayed alive. The old `http.sys` retained state from the previous run that interfered with the new run's port binding.

**Fix:** Kill the wineserver completely before launching (`wineserver -k`). This terminates the old `http.sys` winedevice. When Rhino launches fresh, a new `http.sys` starts with clean state, port 1717 binds, and the OAuth callback completes. The `--fresh` flag in `run-rhino.sh` does this automatically.

---

## Summary of Source Changes

| File | Change |
|------|--------|
| `dlls/uxtheme/uxtheme.spec` + `system.c` | Add the four immersive-color-set exports (ord 95/96/98/100) Rhino resolves for OS dark-mode detection |
| `dlls/wintrust/wintrust_main.c` | Override Authenticode result to S_OK (Wine lacks MS CA root store needed to verify Microsoft signatures) |

All changes are in `rhino8-wine.patch`.

---

## Are the stack patches real Wine bugs? (upstreaming triage)

Useful to separate genuine Wine gaps (worth a mainline PR) from app-specific
workarounds (keep local to `rhino8-wine`).

- **`uxtheme` immersive-color exports — REAL Wine gap → upstreamable.** Real
  `uxtheme.dll` exports `GetImmersiveColorFromColorSetEx`,
  `GetImmersiveColorTypeFromName`, `GetImmersiveUserColorSetPreference`, and
  ordinal 100; Wine implements the *dark-mode toggle* group (132/133/135/…) but
  not this *immersive-color-set* family. That is a true missing-export bug, not
  Rhino-specific. **For a mainline PR, implement them properly** (registry-backed,
  like the existing `ShouldAppsUseDarkMode`) rather than the FIXME stubs here —
  Wine maintainers will likely want real behavior, and ordinal 100's true
  signature/semantics should be pinned down rather than left as a gate-only stub.

- **`thread.c` 8 MB WoW64 stack — REMOVED (2026-06-15).** Only affected the
  32-bit WoW64 path (the 32-bit Rhino installer). Verified the installer completes
  a full install on a default 1 MB stack without it, so it was dropped. Was never
  upstreamable anyway (forcing a minimum overrides the binary's own PE-header
  stack request, which Wine correctly honors).

- **`virtual.c` AllocationBase clamp — REMOVED (2026-06-15).** It made
  `VirtualQuery` report a deliberately *false* `AllocationBase` so the CLR's
  `Thread::GetStackLowerBound()` saw a ~1 MB stack — never upstreamable, since
  `VirtualQuery` reporting the truth is correct behavior. It turned out to be a
  leftover of the abandoned 512 MB-stack experiment + the (now-fixed) recursion;
  with the dark-mode fix in place Rhino launches cleanly without it, so it was
  dropped from the patch (heavier stress testing pending).

So the **only** clean mainline contribution is the `uxtheme` exports. The
ntdll/wintrust changes are environment/app shims and should stay in this repo's
patch.

---

## Rhino 9 WIP (Experimental)

The patches and DLL-patching approach above were tested against a Rhino 9
WIP build (**9.0.26160.12305**) using the same `wine-rhino8` build (Wine
11.9 + `rhino8-wine.patch`, unchanged — no source patches needed updating).
Summary: it works, with two additional steps. Rhino 9 WIP changes rapidly,
so treat the specifics below as a snapshot of this build, not a guarantee
for future ones.

### .NET 8 → .NET 10

Rhino 9 WIP bundles/requires the **.NET 10** desktop and ASP.NET Core
runtimes (`Microsoft.WindowsDesktop.App 10.0.2`, `Microsoft.AspNetCore.App
10.0.2`), not .NET 8. Despite that major jump, **no ntdll stack patches are
needed at all** — the 8 MB WoW64 minimum and the `VirtualQuery` clamp that were
present during earlier testing have both since been removed (see Problem 1).
No new stack-size patch was needed for .NET 10, once the recursion below is
fixed.

### `wintrust` Authenticode patch generalizes

The Rhino 9 WIP installer (a WiX Burn bundle, same as Rhino 8) completes its
Detect and Plan phases with zero certificate/signature errors under the
patched `wintrust`. The Authenticode override is not Rhino-8-specific.

### Dark-mode recursion recurs — at a new offset

Rhino 9's `rhcommon_c.dll` has the same `RHC_RhOSInDarkMode` JMP-thunk
(`48 ff 25 ?? ?? ?? ?? cc`) causing the same mutual-recursion stack overflow
described in Problem 2 above — confirmed by the same opaque
`err:virtual:virtual_setup_exception stack overflow ... bytes` signature
(a 1 MB-span stack, i.e. the recursion overflows the default stack almost
immediately) on launch. The export lives at a different location in
this build:

| | Rhino 8 (8.31.26126.13431) | Rhino 9 WIP (9.0.26160.12305) |
|---|---|---|
| RVA | `0xe0b50` | `0x136c40` |
| File offset | `0xdff50` | `0x136040` |

Because this offset shifts between builds, use
[`find-darkmode-patch.sh`](legacy/find-darkmode-patch.sh) instead of a hardcoded
offset:

```bash
./legacy/find-darkmode-patch.sh "$WINEPREFIX/drive_c/Program Files/Rhino 9 WIP/System/rhcommon_c.dll" --apply
```

It locates the export via the DLL's own export table and section headers,
verifies it's still the patchable JMP-thunk shape, backs up the original to
`rhcommon_c.dll.bak`, and applies the same `xor eax,eax; ret` patch as
Problem 2.

### GPU Technology: Direct3D rendering issues (platform-dependent?)

Rhino 9 WIP defaults to **Direct3D** for viewport rendering (Rhino 8 used
OpenGL). On the system this was tested on (Nvidia, Wayland/XWayland), Direct3D
mode ran without crashing but rendered incorrectly: some viewports showed
solid red or black, and objects vanished after the command that created them
finished (dynamic/preview drawing worked during the command, final scene
rendering did not).

Switching **Options → View → GPU → GPU Technology** to **OpenGL** (and
restarting Rhino) fixed this completely on this system — all viewports
rendered correctly and objects persisted after commands completed.

Direct3D under Wine goes through `wined3d`/`vkd3d`, whose D3D11/D3D12 support
varies a lot by GPU vendor, driver (proprietary vs. Mesa), and Vulkan setup —
so this may or may not reproduce on other hardware/driver combinations. If
you hit similar symptoms (vanishing geometry, solid-color viewports), try
switching to OpenGL as above. Either way this isn't something addressable
with a small binary patch like the dark-mode fix above.

### Known pre-existing issue: delayed viewport refresh

Independent of the above, Rhino 8 and 9 both show occasional delayed
viewport refreshes on Wine/Wayland/Nvidia. The documented community
workarounds (disabling theming, disabling vblank) did not resolve it here.
This is a general Wine/Wayland/Nvidia compositor interaction issue, not
specific to these patches.

### Burn installer still needs a real display

As with Rhino 8, the WiX Burn bootstrapper requires a window handle to reach
its Apply phase — even with `/quiet` it fails with `BA passed NULL hwndParent
to Apply` and hangs if no display is available. The installer must be run
under a real X11/Wayland session.

---

## TODO / Backlog

- **Investigate "black box" / mis-rendered windows reported by users.** The
  immersive-color singleton in `RhinoCore.dll` (getter `0x18037ecf0`) has **6
  call sites**, only one of which is the launch dark-mode probe; the others
  resolve UI colours through the same four `uxtheme` exports that are missing on
  Wine (see Problem 2). With those exports absent, non-dark-mode UI code also
  gets NULL function pointers and may fall back to zero/black colours — a
  plausible cause of black-box artifacts that the *binary* patch cannot fix but
  the *Wine spec-stub* fix might. **Not confirmed.** To verify: rebuild
  `uxtheme.dll` with the stubs (which carry `FIXME` traces), run with
  `WINEDEBUG=+uxtheme`, reproduce a black-box window, and check whether
  `GetImmersiveColorFromColorSetEx` / `GetImmersiveColorTypeFromName` fire
  *during* that window's rendering (vs. only once at startup). If they do, return
  the real accent palette from the registry instead of the current black/white.
  If they don't, the black boxes are a separate GL/compositing problem (see the
  Direct3D→OpenGL note above). Deferred for now.

- **Crash on shutdown: `Win32Exception (1412): Class has open windows`.** When
  Rhino is closed normally it writes `RhinoDotNetCrash.txt` + `RhinoCrashDump.dmp`
  with:
  `MS.Win32.HwndWrapper.UnregisterClass` → `ERROR_CLASS_HAS_WINDOWS (1412)`,
  unhandled in the WPF Dispatcher. WPF unregisters a window class while windows
  of that class are still alive — a WPF-on-Wine teardown-ordering issue (Wine
  destroys windows at process exit in a different order/timing than Windows).
  **Not caused by these patches** (nothing here touches window-class lifecycle);
  it only became *reachable* once the dark-mode fix let Rhino launch and reach a
  clean shutdown. Low severity (occurs after the app is already exiting; only
  cost is the crash dumps). To pursue later: check whether it's a known Wine
  `UnregisterClass`/window-teardown bug, or whether a specific Eto/WPF panel
  leaks past shutdown. Deferred.

- **`virtual.c` AllocationBase clamp — REMOVED, pending stress validation.**
  Removed via a full `makepkg` rebuild (2026-06-15); Rhino 8 launches cleanly
  without it. Still needs heavier real-world exercise (large models, deep
  booleans/SubD/meshing, scripting) to confirm no legitimate deep-recursion path
  trips a `StackOverflowException`. If one ever does, restore the clamp hunk
  (`git show <pre-removal commit>:rhino8-wine.patch`) and `makepkg -sif` — but the
  "leaner upstream approach" notes apply: don't re-add the VirtualQuery lie;
  prefer making Wine reserve the true PE-header size.

  Methodology reminder: native `ntdll.so` changes must be validated with a full
  `makepkg` rebuild, **never** an incremental `.so` hot-swap. Doing the latter
  crashed the entire native service layer (`services/rpcss/svchost/plugplay/
  winedevice` SEGV'd at init) — an artifact of mixing one freshly-built object
  with a months-old build, not a real result. (PE DLLs like `uxtheme.dll` are
  portable and can be swapped; native `.so` cannot.)

- **`thread.c` 8 MB WoW64 stack — RESOLVED (removed 2026-06-15).** Tested: the
  32-bit Rhino installer completes a full install on a default 1 MB stack with the
  bump removed. No ntdll stack patches remain in the tree.
