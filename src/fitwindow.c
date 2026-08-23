/* fitwindow — size a Wine game window to the macOS work area.
 *
 * Waits for the game window to appear, asks Wine for the screen work area (the
 * display minus the menu bar and the Dock), then fits the largest 4:3 window
 * into it and centres it. Written for Heroes of Might and Magic IV, but not
 * tied to it — change the window class on the line below for another game.
 *
 * Build: i686-w64-mingw32-gcc -O2 -o fitwindow.exe fitwindow.c -luser32
 *
 * MIT licensed, see LICENSE.
 */
#include <windows.h>
#include <stdio.h>

#define GAME_WINDOW_CLASS "Heroes4"

static HWND g_win = NULL;
static BOOL CALLBACK find_game(HWND h, LPARAM lp){
    char cls[64] = {0};
    GetClassNameA(h, cls, sizeof cls);
    if(!strcmp(cls, GAME_WINDOW_CLASS) && IsWindowVisible(h)){ g_win = h; return FALSE; }
    return TRUE;
}

int main(int argc, char **argv){
    /* Wait for the game window to appear (game start takes a while under Wine). */
    for(int i = 0; i < 120 && !g_win; i++){ EnumWindows(find_game, 0); if(!g_win) Sleep(500); }
    if(!g_win){ fprintf(stderr, "fitwindow: game window not found\n"); return 1; }

    /* Work area excludes the macOS menu bar and the Dock. */
    RECT wa;
    if(!SystemParametersInfoA(SPI_GETWORKAREA, 0, &wa, 0)){
        wa.left = 0; wa.top = 0;
        wa.right = GetSystemMetrics(SM_CXSCREEN);
        wa.bottom = GetSystemMetrics(SM_CYSCREEN);
    }
    long waw = wa.right - wa.left, wah = wa.bottom - wa.top;
    printf("workarea=(%ld,%ld)-(%ld,%ld) %ldx%ld\n", wa.left,wa.top,wa.right,wa.bottom, waw, wah);

    /* Frame size = window minus client, so we can size the CLIENT area to 4:3. */
    RECT w, c;
    GetWindowRect(g_win, &w);
    GetClientRect(g_win, &c);
    long fw = (w.right - w.left) - c.right;
    long fh = (w.bottom - w.top) - c.bottom;

    /* Largest 4:3 client that fits the work area, minus a small margin. */
    long availw = waw - fw - 8, availh = wah - fh - 8;
    long ch = availh, cw = ch * 4 / 3;
    if(cw > availw){ cw = availw; ch = cw * 3 / 4; }

    long ww = cw + fw, wh = ch + fh;
    long x = wa.left + (waw - ww) / 2;
    long y = wa.top + (wah - wh) / 2;

    SetWindowPos(g_win, NULL, x, y, ww, wh, SWP_NOZORDER | SWP_NOACTIVATE);
    Sleep(400);
    GetWindowRect(g_win, &w); GetClientRect(g_win, &c);
    printf("window now %ldx%ld at (%ld,%ld), client %ldx%ld\n",
        w.right-w.left, w.bottom-w.top, w.left, w.top, c.right, c.bottom);
    return 0;
}
