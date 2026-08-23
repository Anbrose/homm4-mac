# How it works, and why it breaks without help

Notes from getting Heroes of Might and Magic IV Complete running on an Apple
Silicon Mac. Everything below was measured on the machine, not guessed: macOS
26.5.2, arm64, Wine 11.0 from Homebrew, the GOG build of the game.

Three things bite you, in this order.

## 1. The game needs its own DDRAW.dll, and Wine won't use it by default

The GOG build ships a `DDRAW.dll` next to `heroes4.exe`. It is the
[Heroes4GL wrapper by Verok](https://heroes3wog.net/heroes-of-might-and-magic-1-2-3-4-gl-wrapper/),
which redirects the game's DirectDraw calls to OpenGL and adds scaling filters.
Its settings are the `[Wrapper]` and `[FunktionKeys]` sections of `config.ini`.

Wine's default DLL load order prefers its own builtin `ddraw` over a native one
sitting in the application folder. With the builtin, the game creates its window
and then dies:

```
Runtime Error!
Program: C:\Games\HoMM4\heroes4.exe
abnormal program termination
```

The fix is one environment variable, and it is what the launcher sets:

```bash
export WINEDLLOVERRIDES="ddraw=n"
```

`n` means *native first*. This is not a discovery — the wrapper's own
documentation tells Wine users to override `ddraw` — but nothing tells you that
the symptom of forgetting it is a generic CRT abort with no other diagnostics.

## 2. The cursor trap: exactly two conditions

Run the game, turn on fullscreen, and the mouse pointer gets confined to the
picture. You cannot reach the Dock, the menu bar, the window's own title bar, or
another app's window. It feels like Wine misbehaving. It isn't.

`heroes4.exe` itself never calls `ClipCursor` — it imports only `SetCapture` and
`GetSystemMetrics`. The wrapper does. Disassembling it gives the exact gate:

```
call   GetForegroundWindow
cmpl   $0x0, ImageAspect      ; aspect preservation off?
je     release                ; -> ClipCursor(NULL)
cmpl   $0x2, coop_level       ; windowed cooperative level?
je     release                ; -> ClipCursor(NULL)
...                           ; otherwise clip to the image rectangle
```

So the pointer is confined **only when both** are true:

1. the wrapper's own fullscreen mode is active, and
2. `ImageAspect=1`, i.e. 4:3 proportions are preserved.

Measured on a 1710×1107 logical screen: the 4:3 image occupies the middle
1476 px, and `GetClipCursor` returns `(117,0)-(1593,1107)`. Moving the pointer to
`(20,1090)` lands it at `(117,1090)` — blocked. The Dock stays reachable only
because it sits inside that horizontal band, which is what makes the behaviour so
confusing to describe.

Consequences worth knowing:

* **In a window the cursor is never confined**, whatever the window size. That is
  why this repo makes the window big instead of making the game fullscreen.
* **Losing focus releases the clip.** `macdrv_app_deactivated` calls
  `NtUserClipCursor(NULL)`, so `Cmd`+`Tab` always frees the pointer.
* **`Fn`+`F5` releases it too**, by turning off aspect preservation: the image
  then covers the whole screen, so the clip rectangle equals the screen.
* macOS-native fullscreen (`Ctrl`+`Cmd`+`F`) keeps the cursor free, because the
  wrapper is still in windowed cooperative mode.

There is no wrapper option to disable the clipping. The binary reads twelve
`[Wrapper]` keys — `UseOpenGL`, `Renderer`, `ColdCPU`, `ImageAspect`,
`ImageVSync`, `Interpolation`, `Upscaling`, `ScaleNx`, `XSal`, `Eagle`,
`ScaleHQ`, `XBRZ` — and five `[FunktionKeys]` bindings, and none of them touch
the cursor.

Wine's own `winemac.drv` does have knobs named `UseConfinementCursorClipping` and
`CursorClippingLocksWindows`. They exist (they are built from 16-byte chunks in
the constant pool, so a plain string search misses them), but setting both to `n`
changes nothing here: the clip rectangle stays 1476 px wide and the pointer stays
blocked. Don't bother.

## 3. Window sizing, and why the work area matters

The game is a fixed 1024×768. The wrapper scales its output to whatever the
window size is and the window has a real resize border (`WS_THICKFRAME`), so
making it bigger is free — the only problem is that nothing does it for you.

`fitwindow.exe` waits for the game window, then asks Wine for
`SPI_GETWORKAREA`. Wine's macOS driver reports it correctly: on this machine
`(0,35)-(1710,1040)`, i.e. the screen minus 35 px of menu bar at the top and
67 px of Dock at the bottom. It fits the largest 4:3 client area into that and
centres it — 1266×997 here.

Two things not to do:

* **The green zoom button.** On a Retina display it produces a 3428×1007 window
  that runs off the screen. Relaunch to recover.
* **Wine's virtual desktop** (`explorer /desktop=NAME,WxH`). It does work — but
  only if you give the program's full Windows path; with a bare `heroes4.exe`
  explorer holds the desktop and never starts the game. It buys nothing over
  sizing the window, and adds a second window with its own title.

## 4. The installer trap (if your copy is not the GOG one)

Some redistributions wrap the game in an Inno Setup installer that uses ISDone,
botva2 and CallbackCtrl to draw a skinned UI. **These do not run on Apple
Silicon.** The language dialog appears and renders fine, but the moment the
install starts, the process dies:

```
err:virtual:virtual_setup_exception stack overflow 640 bytes addr 0x20002
```

Address `0x20002` is a jump into nothing. Those libraries generate executable
thunks at runtime, and runtime-generated 32-bit x86 code does not survive the
emulation layer that runs 32-bit code on ARM. Silent install doesn't help either:
such scripts usually show their own language dialog from `InitializeSetup`, which
is cancelled in silent mode, so setup aborts with `InitializeSetup returned
False`.

This is why the recommended route is the GOG offline installer plus
`innoextract`, which unpacks natively on macOS and never runs a line of Windows
code.

## 5. Homebrew and Wine pitfalls

Three small things that cost real time:

* `brew install --cask wine-stable` pulls in `gstreamer-runtime`, which installs
  through `sudo` and prompts for a password — and fails outright in any
  non-interactive shell. The game doesn't need it: use
  `brew install --cask --skip-cask-deps wine-stable`.
* Homebrew 6 removed the `--no-quarantine` flag. Strip quarantine afterwards
  instead, **before the first launch**, or Gatekeeper kills the app:
  `xattr -rd com.apple.quarantine "/Applications/Wine Stable.app"`.
* Wine reports Windows 10 by default. This 2002 game behaves better in Windows 7
  mode: `wine reg add 'HKCU\Software\Wine' /v Version /d win7 /f`.

## 6. Small things

* The game rewrites `[Application]` in `config.ini` when it exits, so edit that
  file only while the game is closed, or your changes are lost.
* `[FunktionKeys]` maps a feature to an F-key *number*: `WindowedMode=4` means
  F4. Empty means unbound — `AspectRatio` ships unbound, and binding it to 5 is
  what gives you the `Fn`+`F5` escape described above.
* On a Mac the F-keys are media keys unless you enable *Use F1, F2, etc. as
  standard function keys*, so it is `Fn`+`F4` rather than `F4`.
