# Heroes of Might and Magic IV on macOS

Play **Heroes of Might and Magic IV Complete** on Apple Silicon (M1–M4) and Intel Macs.
One script, plain Wine from Homebrew. No CrossOver, no Whisky, no subscription.

The game opens in a large window sized to your screen, the mouse cursor stays free,
and the Dock and menu bar keep working — which is not what you get if you just run
the game and turn on its own fullscreen mode.

<!-- Add a screenshot here: press Cmd+Shift+4, drag over the game window,
     save it as docs/screenshot.png, then uncomment the line below.
![Heroes of Might and Magic IV running on macOS](docs/screenshot.png)
-->

## What you need

* An Apple Silicon or Intel Mac with macOS 13 or newer
* [Homebrew](https://brew.sh)
* **Your own copy of the game.** No game data is included here.
  The GOG offline installer is the easy route.

## Install

```bash
git clone https://github.com/AntonOzhigin/homm4-mac.git
cd homm4-mac
```

Get the game files out of your GOG offline installer — `innoextract` unpacks it
natively on macOS, no Wine needed for this step:

```bash
brew install innoextract
innoextract setup_heroes_of_might_and_magic_4_*.exe -d homm4
```

Then point the installer at the folder that contains `heroes4.exe` (GOG puts it
in `app/`):

```bash
./install.sh homm4/app
```

That installs Wine if you don't have it, creates a dedicated Wine prefix in
`~/Games/HoMM4`, copies the game into it, and writes a launcher.

Play:

```bash
open ~/Games/HoMM4/HoMM4.command
```

Double-clicking `HoMM4.command` in Finder works too. Drag it to your Dock to keep
it handy.

Already have the game unpacked somewhere else? Skip the innoextract step and pass
that folder instead. Anything containing `heroes4.exe` works.

## What the launcher does for you

Two things, both of which the game gets wrong on its own.

**It forces the game's own DirectDraw wrapper.** The GOG build ships a
`DDRAW.dll` (the Heroes4GL wrapper by Verok). Wine loads its own builtin `ddraw`
by default and the game dies with `Runtime Error! ... abnormal program
termination`. The launcher sets `WINEDLLOVERRIDES="ddraw=n"` so the shipped
wrapper wins.

**It sizes the window to your screen's work area.** Out of the box the game is a
1024×768 window, which is tiny on a modern display. `fitwindow.exe` waits for the
game window, asks Wine for the work area — the screen minus the menu bar and the
Dock — and fits the largest 4:3 window into it. On a 14" MacBook Pro that is
1266×997 instead of 1032×821. Nothing to press, it happens at launch.

## Using it

| Keys | What it does |
|---|---|
| `Fn`+`F4` | the wrapper's own fullscreen ↔ window |
| `Fn`+`F5` | stretch to fill ↔ keep 4:3 with black bars |
| `Fn`+`F3` | image smoothing filter |
| `Ctrl`+`Cmd`+`F` | macOS-native fullscreen (own Space, cursor stays free) |
| `Cmd`+`Tab` | switch away — this also releases the cursor if it got confined |

`Fn` is needed because macOS treats the F-keys as media keys unless you turn on
*Use F1, F2, etc. as standard function keys* in System Settings → Keyboard.

**Don't turn on the wrapper's own fullscreen** (`Fn`+`F4`, or `full_screen=1` in
`config.ini`) unless you want the trade-off: in that mode it calls `ClipCursor`
and confines the pointer to the 4:3 image area, so you can't reach the Dock, the
menu bar or the window's own title bar. `Cmd`+`Tab` gets you out. The window
sizing above exists precisely so you don't need that mode.

If you want an actual fullscreen, use the macOS one (`Ctrl`+`Cmd`+`F`): the game
goes to its own Space and the cursor stays free, because the wrapper only confines
it in *its* fullscreen mode, never in a window.

## Tested on

| | |
|---|---|
| Hardware | MacBook Pro, Apple Silicon (arm64) |
| macOS | 26.5.2 |
| Wine | 11.0 (`wine-stable` from Homebrew) |
| Game | Heroes of Might and Magic IV Complete v3.0 (GOG build 1207658915) |

## Why it breaks without this

The interesting parts — why 32-bit installers die on Apple Silicon, the exact rule
that decides when your cursor gets trapped, and the Homebrew pitfalls that cost me
an evening — are in **[docs/how-it-works.md](docs/how-it-works.md)**.

## Repo contents

```
install.sh          sets up Wine, the prefix, the game and the launcher
src/fitwindow.c     the window-fitting helper, MIT licensed
bin/fitwindow.exe   the same, prebuilt, so you don't need a cross-compiler
tools/h4r.py        extracts the game's .h4r resource archives (format documented inside)
tools/h4sprite.py   decodes sprites (creatures, heroes, map objects, spells) to PNG
tools/h4terrain.py  decodes terrain tile sets to a PNG sheet
tools/h4map.py      decodes .h4c maps: header, objects, terrain grid -> JSON + minimap
docs/               how it works, and why
```

`tools/h4r.py` unpacks any `Data/*.h4r` archive into a folder tree — the Bink
cutscenes come out playable with ffmpeg, the menu backgrounds come out as PNG,
everything else as the game's internal `.h4d` objects:

```bash
python3 tools/h4r.py list    ~/Games/HoMM4/prefix/drive_c/Games/HoMM4/Data/heroes4.h4r actor_sequence.
python3 tools/h4r.py extract ~/Games/HoMM4/prefix/drive_c/Games/HoMM4/Data/heroes4.h4r out/
```

`tools/h4sprite.py` turns a sprite file from that output into PNGs: every
frame and shadow as RGBA with its 4-bit alpha, a `strip.png` of the whole
animation, and `meta.json` with each image's bounding box. It handles the
11,000 `actor_sequence` creature and hero animations, the `adv_object`
adventure-map objects (towns, mines, dwellings), `combat_object` obstacles and
most `animation` spell effects — they share one palette-indexed, span-encoded
image format, documented in the script.

```bash
python3 tools/h4sprite.py "out/actor_sequence/actor_sequence.Gold Golem.combat.walk.sw.h4d" golem/
```

`tools/h4terrain.py` reassembles a `terrain.*.h4d` file — 100 diamond tiles
that make up one ragged-edged patch of dirt, grass, lava, water, road… — into
a single PNG.

`tools/h4map.py` opens a scenario (`maps/*.h4c`): the gzip container, the
header (size, levels, players, name), every placed object with its map
position, and the terrain grid — a diamond of cells inside the size×size
square, each with a terrain type and variant. It writes a JSON and a minimap:

```bash
python3 tools/h4map.py ~/Games/HoMM4/prefix/drive_c/Games/HoMM4/Data/heroes4.h4r \
    ~/Games/HoMM4/prefix/drive_c/Games/HoMM4/maps/"Three Queens.h4c" out/three_queens
``` Sounds come out of `h4r.py` as
`.wav`/`.mp3` and the Bink cutscenes play with ffmpeg. UI layers, fonts and
the town screens are still undecoded.

`fitwindow` is not specific to this game. It fits *any* Wine window to the macOS
work area — point it at another old game and it will do the same thing. Rebuild it
with:

```bash
brew install mingw-w64
i686-w64-mingw32-gcc -O2 -o bin/fitwindow.exe src/fitwindow.c -luser32
```

## License

MIT, see [LICENSE](LICENSE). This covers the scripts and `fitwindow` only.
Heroes of Might and Magic IV is not mine and is not distributed here.

---

# По-русски

Heroes of Might and Magic IV Complete на маках с Apple Silicon и Intel. Один
скрипт, обычный Wine из Homebrew, без CrossOver и без подписок.

Игра открывается большим окном по размеру экрана, курсор не запирается, Dock и
строка меню остаются доступны — а именно это ломается, если просто запустить игру
и включить её собственный полноэкранный режим.

### Что нужно

Мак с macOS 13 или новее, [Homebrew](https://brew.sh) и **ваша собственная копия
игры** — файлов игры здесь нет. Проще всего взять офлайн-инсталлятор с GOG.

### Установка

```bash
git clone https://github.com/AntonOzhigin/homm4-mac.git
cd homm4-mac
brew install innoextract
innoextract setup_heroes_of_might_and_magic_4_*.exe -d homm4
./install.sh homm4/app
open ~/Games/HoMM4/HoMM4.command
```

`innoextract` распаковывает инсталлятор GOG прямо в macOS, Wine для этого шага не
нужен. Скрипт поставит Wine, создаст отдельный префикс в `~/Games/HoMM4`,
перенесёт туда игру и сделает ярлык запуска. Если игра у вас уже распакована —
просто укажите папку, в которой лежит `heroes4.exe`.

### Что делает ярлык

Заставляет игру использовать её собственную `DDRAW.dll` (обёртка Heroes4GL от
Verok) вместо встроенной в Wine — без этого игра падает с `Runtime Error!` — и
растягивает окно по рабочей области экрана, то есть на весь экран, но без
залезания на строку меню и Dock. Вместо 1024×768 получается, например, 1266×997.

### Управление

`Fn`+`F4` — полноэкранный режим обёртки, `Fn`+`F5` — растянуть или оставить 4:3,
`Ctrl`+`Cmd`+`F` — полноэкранный режим самой macOS, `Cmd`+`Tab` — переключиться и
заодно освободить курсор. `Fn` нужен потому, что macOS по умолчанию считает
F-клавиши медиа-кнопками.

**Полноэкранный режим обёртки лучше не включать**: в нём она вызывает
`ClipCursor` и запирает курсор в области картинки 4:3, из-за чего не добраться ни
до Dock, ни до заголовка окна. Ради этого и сделано растягивание окна. Нужен
настоящий полный экран — берите `Ctrl`+`Cmd`+`F`, там курсор остаётся свободным.

### Подробный разбор

Почему 32-битные инсталляторы не запускаются на Apple Silicon, при каких ровно
двух условиях запирается курсор и на какие грабли Homebrew я наступил —
в [docs/how-it-works.md](docs/how-it-works.md).
