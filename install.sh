#!/bin/bash
# Heroes of Might and Magic IV Complete on macOS (Apple Silicon and Intel).
#
#   ./install.sh /path/to/folder/with/heroes4.exe
#
# Sets up a dedicated Wine prefix, puts the game in it, and creates a launcher
# that opens the game in a large window sized to your screen's work area.
#
# This script ships NO game data. Bring your own copy — the GOG offline
# installer is the easy route, see README.md.

set -euo pipefail

SRC="${1:-}"
ROOT="${HOMM4_ROOT:-$HOME/Games/HoMM4}"
PREFIX="$ROOT/prefix"
TOOLS="$ROOT/tools"
GAME_DIR="$PREFIX/drive_c/Games/HoMM4"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- source files

if [ -z "$SRC" ]; then
    cat >&2 <<USAGE
Usage: ./install.sh <folder containing heroes4.exe>

Get that folder from your own copy of the game. With the GOG offline installer:

    brew install innoextract
    innoextract setup_heroes_of_might_and_magic_4_*.exe -d homm4
    ./install.sh homm4/app

USAGE
    exit 2
fi

[ -d "$SRC" ] || die "not a folder: $SRC"

# Accept either the game folder itself or a parent one level up (GOG puts the
# files in app/, so pointing at the extracted root should also work).
if [ ! -f "$SRC/heroes4.exe" ]; then
    FOUND="$(find "$SRC" -maxdepth 2 -iname heroes4.exe -print -quit 2>/dev/null || true)"
    [ -n "$FOUND" ] || die "heroes4.exe not found in $SRC (looked two levels deep)"
    SRC="$(dirname "$FOUND")"
fi
say "Game files: $SRC"

# ----------------------------------------------------------------------- wine

command -v brew >/dev/null 2>&1 || die "Homebrew is required: https://brew.sh"

if ! command -v wine >/dev/null 2>&1; then
    # gstreamer-runtime is a cask dependency that installs via sudo and asks for
    # a password. The game does not need it, so skip cask deps.
    say "Installing Wine"
    brew install --cask --skip-cask-deps wine-stable
    # Strip quarantine before the first run or Gatekeeper kills the app.
    xattr -rd com.apple.quarantine "/Applications/Wine Stable.app" 2>/dev/null || true
fi
say "Wine: $(wine --version 2>/dev/null || echo unknown)"

export WINEPREFIX="$PREFIX"
export WINEDEBUG=-all

if [ ! -d "$PREFIX" ]; then
    say "Creating Wine prefix: $PREFIX"
    mkdir -p "$PREFIX"
    WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -i >/dev/null 2>&1 || true
fi

# The game is from 2002; Windows 7 mode behaves better than the Windows 10
# default that Wine reports out of the box.
wine reg add 'HKCU\Software\Wine' /v Version /d win7 /f >/dev/null 2>&1 || true

# ------------------------------------------------------------------ game files

if [ -f "$GAME_DIR/heroes4.exe" ]; then
    say "Game already present in $GAME_DIR — skipping copy"
else
    say "Copying game into the prefix (this takes a minute)"
    mkdir -p "$GAME_DIR"
    (cd "$SRC" && tar cf - .) | (cd "$GAME_DIR" && tar xf -)
fi
[ -f "$GAME_DIR/heroes4.exe" ] || die "heroes4.exe missing after copy"

if [ ! -f "$GAME_DIR/DDRAW.dll" ]; then
    printf '\nNOTE: no DDRAW.dll next to heroes4.exe.\n'
    printf 'The GOG build ships one (the Heroes4GL wrapper) and the launcher\n'
    printf 'expects it. Without it the game may fail to start.\n'
fi

# Windowed mode: the wrapper only confines the mouse cursor in its own
# fullscreen mode, never in a window. See docs/how-it-works.md.
if [ -f "$GAME_DIR/config.ini" ]; then
    perl -pi -e 's/^full_screen=1\r?$/full_screen=0\r/' "$GAME_DIR/config.ini" || true
fi

# ---------------------------------------------------------------------- tools

mkdir -p "$TOOLS"
if [ -f "$HERE/bin/fitwindow.exe" ]; then
    cp "$HERE/bin/fitwindow.exe" "$TOOLS/fitwindow.exe"
elif command -v i686-w64-mingw32-gcc >/dev/null 2>&1; then
    say "Building fitwindow.exe from source"
    i686-w64-mingw32-gcc -O2 -o "$TOOLS/fitwindow.exe" "$HERE/src/fitwindow.c" -luser32
else
    printf '\nNOTE: fitwindow.exe not found and mingw-w64 is not installed.\n'
    printf 'The game will still run, just in its original small window.\n'
fi

# -------------------------------------------------------------------- launcher

say "Creating the launcher"
cat > "$ROOT/HoMM4.command" <<LAUNCHER
#!/bin/bash
export WINEPREFIX="$PREFIX"
# The game needs its own DDRAW.dll (the Heroes4GL wrapper). With Wine's builtin
# ddraw it dies with "Runtime Error! ... abnormal program termination".
export WINEDLLOVERRIDES="ddraw=n"
export WINEDEBUG=-all
cd "$GAME_DIR" || exit 1
wine heroes4.exe &
GAME_PID=\$!
# Resize the window to the screen's work area: as large as possible without
# covering the menu bar or the Dock.
[ -x "$TOOLS/fitwindow.exe" ] && wine "$TOOLS/fitwindow.exe" >/dev/null 2>&1 &
wait \$GAME_PID
LAUNCHER
chmod +x "$ROOT/HoMM4.command"

say "Done. Launch the game with:"
printf '    open "%s/HoMM4.command"\n' "$ROOT"
printf '\nOr double-click HoMM4.command in Finder.\n'
du -sh "$GAME_DIR" 2>/dev/null || true
