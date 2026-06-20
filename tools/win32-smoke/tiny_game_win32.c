#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define GAME_TIMER_ID 1
#define GAME_TIMER_MS 16
#define PLAYER_SIZE 28
#define TARGET_SIZE 24
#define HMOS_FRAME_MAGIC 0x46574d48u
#define HMOS_FRAME_FORMAT_BGRA8888 1u

typedef struct GameState {
    int width;
    int height;
    int playerX;
    int playerY;
    int velX;
    int velY;
    int targetX;
    int targetY;
    int score;
    int ticks;
    BOOL left;
    BOOL right;
    BOOL up;
    BOOL down;
    BOOL pointerDown;
} GameState;

typedef struct HmosFrameHeader {
    uint32_t magic;
    uint32_t headerSize;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
    uint64_t frameNumber;
} HmosFrameHeader;

static GameState g_game;
static int g_paintMarkerCount;
static uint64_t g_frameNumber;

static void PaintGame(HWND hwnd, HDC hdc);

static BOOL ReadMarkerPath(char *path, DWORD pathSize)
{
    DWORD count;
    if (!path || pathSize == 0) {
        return FALSE;
    }
    count = GetEnvironmentVariableA("WINE_HMOS_MARKER_PATH", path, pathSize);
    return count > 0 && count < pathSize;
}

static void WriteTinyGameMarker(const char *message)
{
    DWORD written = 0;
    char markerPath[MAX_PATH];
    HANDLE file = INVALID_HANDLE_VALUE;
    if (ReadMarkerPath(markerPath, sizeof(markerPath))) {
        file = CreateFileA(markerPath, FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    }
    if (file == INVALID_HANDLE_VALUE) {
        file = CreateFileA("tinygame-entry.txt", FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    }
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }
    WriteFile(file, message, lstrlenA(message), &written, NULL);
    CloseHandle(file);
}

static void WriteTinyGameLastError(const char *step)
{
    char message[192];
    wsprintfA(message, "HMOS ProtonTinyGame %s failed last_error=%lu\r\n", step, GetLastError());
    WriteTinyGameMarker(message);
}

static BOOL ReadFramePath(char *path, DWORD pathSize)
{
    DWORD count;
    if (!path || pathSize == 0) {
        return FALSE;
    }
    count = GetEnvironmentVariableA("WINE_HMOS_FRAME_PATH", path, pathSize);
    if (count > 0 && count < pathSize) {
        return TRUE;
    }
    lstrcpynA(path, "hmos-frame-default.bgra", pathSize);
    return TRUE;
}

static BOOL ReadInputPath(char *path, DWORD pathSize)
{
    DWORD count;
    if (!path || pathSize == 0) {
        return FALSE;
    }
    count = GetEnvironmentVariableA("WINE_HMOS_INPUT_PATH", path, pathSize);
    return count > 0 && count < pathSize;
}

static BOOL WriteAll(HANDLE file, const void *data, DWORD size)
{
    const BYTE *cursor = (const BYTE *)data;
    DWORD remaining = size;
    while (remaining > 0) {
        DWORD written = 0;
        if (!WriteFile(file, cursor, remaining, &written, NULL) || written == 0) {
            return FALSE;
        }
        cursor += written;
        remaining -= written;
    }
    return TRUE;
}

static void MirrorTinyGameFrame(HWND hwnd)
{
    char path[MAX_PATH];
    char tempPath[MAX_PATH];
    RECT client;
    BITMAPINFO bmi;
    void *bits = NULL;
    HDC screenDc = NULL;
    HDC memoryDc = NULL;
    HBITMAP dib = NULL;
    HGDIOBJ oldBitmap = NULL;
    HANDLE file = INVALID_HANDLE_VALUE;
    HmosFrameHeader header;
    DWORD payloadSize;
    int width;
    int height;
    int stride;

    if (!ReadFramePath(path, sizeof(path))) {
        return;
    }

    GetClientRect(hwnd, &client);
    width = client.right - client.left;
    height = client.bottom - client.top;
    if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
        return;
    }
    stride = width * 4;
    payloadSize = (DWORD)(stride * height);

    ZeroMemory(&bmi, sizeof(bmi));
    bmi.bmiHeader.biSize = sizeof(bmi.bmiHeader);
    bmi.bmiHeader.biWidth = width;
    bmi.bmiHeader.biHeight = -height;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    screenDc = GetDC(hwnd);
    if (!screenDc) {
        return;
    }
    memoryDc = CreateCompatibleDC(screenDc);
    dib = CreateDIBSection(screenDc, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!memoryDc || !dib || !bits) {
        if (dib) DeleteObject(dib);
        if (memoryDc) DeleteDC(memoryDc);
        ReleaseDC(hwnd, screenDc);
        return;
    }

    oldBitmap = SelectObject(memoryDc, dib);
    PaintGame(hwnd, memoryDc);
    SelectObject(memoryDc, oldBitmap);

    lstrcpynA(tempPath, path, sizeof(tempPath));
    lstrcatA(tempPath, ".tmp");
    file = CreateFileA(tempPath, GENERIC_WRITE, FILE_SHARE_READ, NULL,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file != INVALID_HANDLE_VALUE) {
        header.magic = HMOS_FRAME_MAGIC;
        header.headerSize = sizeof(header);
        header.width = (uint32_t)width;
        header.height = (uint32_t)height;
        header.stride = (uint32_t)stride;
        header.format = HMOS_FRAME_FORMAT_BGRA8888;
        header.frameNumber = ++g_frameNumber;
        if (WriteAll(file, &header, sizeof(header)) && WriteAll(file, bits, payloadSize)) {
            FlushFileBuffers(file);
            CloseHandle(file);
            file = INVALID_HANDLE_VALUE;
            MoveFileExA(tempPath, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
        }
    }

    if (file != INVALID_HANDLE_VALUE) {
        CloseHandle(file);
    }
    DeleteObject(dib);
    DeleteDC(memoryDc);
    ReleaseDC(hwnd, screenDc);
}

static int ClampInt(int value, int minValue, int maxValue)
{
    if (value < minValue) {
        return minValue;
    }
    if (value > maxValue) {
        return maxValue;
    }
    return value;
}

static int NextRandom(int limit)
{
    static uint32_t seed = 0x5eed1234u;
    seed = seed * 1664525u + 1013904223u;
    if (limit <= 0) {
        return 0;
    }
    return (int)((seed >> 8) % (uint32_t)limit);
}

static void ResetTarget(void)
{
    const int maxX = g_game.width > TARGET_SIZE ? g_game.width - TARGET_SIZE : 1;
    const int maxY = g_game.height > TARGET_SIZE ? g_game.height - TARGET_SIZE : 1;
    g_game.targetX = NextRandom(maxX);
    g_game.targetY = NextRandom(maxY);
}

static void ResetGame(HWND hwnd)
{
    RECT rect;
    GetClientRect(hwnd, &rect);
    g_game.width = rect.right - rect.left;
    g_game.height = rect.bottom - rect.top;
    g_game.playerX = g_game.width / 2 - PLAYER_SIZE / 2;
    g_game.playerY = g_game.height / 2 - PLAYER_SIZE / 2;
    g_game.velX = 0;
    g_game.velY = 0;
    g_game.score = 0;
    g_game.ticks = 0;
    g_game.left = FALSE;
    g_game.right = FALSE;
    g_game.up = FALSE;
    g_game.down = FALSE;
    g_game.pointerDown = FALSE;
    ResetTarget();
}

static void SetKeyState(WPARAM key, BOOL pressed)
{
    switch (key) {
        case VK_LEFT:
        case 'A':
            g_game.left = pressed;
            break;
        case VK_RIGHT:
        case 'D':
            g_game.right = pressed;
            break;
        case VK_UP:
        case 'W':
            g_game.up = pressed;
            break;
        case VK_DOWN:
        case 'S':
            g_game.down = pressed;
            break;
        default:
            break;
    }
}

static BOOL RectsOverlap(int ax, int ay, int aw, int ah, int bx, int by, int bw, int bh)
{
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
}

static int HmosKeyToVirtualKey(int code)
{
    switch (code) {
        case 2012:
            return VK_UP;
        case 2013:
            return VK_DOWN;
        case 2014:
            return VK_LEFT;
        case 2015:
            return VK_RIGHT;
        case 2017:
            return 'A';
        case 2020:
            return 'D';
        case 2034:
            return 'R';
        case 2035:
            return 'S';
        case 2039:
            return 'W';
        case 2050:
            return VK_SPACE;
        case 2054:
            return VK_RETURN;
        case 2070:
            return VK_ESCAPE;
        default:
            return 0;
    }
}

static void ApplyBridgeKey(HWND hwnd, const char *action, int code)
{
    int virtualKey = HmosKeyToVirtualKey(code);
    BOOL pressed = lstrcmpiA(action, "KEY_DOWN") == 0;
    BOOL released = lstrcmpiA(action, "KEY_UP") == 0;
    if (!virtualKey || (!pressed && !released)) {
        return;
    }
    if (pressed && virtualKey == VK_ESCAPE) {
        DestroyWindow(hwnd);
        return;
    }
    if (pressed && virtualKey == 'R') {
        ResetGame(hwnd);
        return;
    }
    SetKeyState((WPARAM)virtualKey, pressed);
}

static void ApplyBridgePointer(HWND hwnd, const char *action, int x, int y)
{
    if (lstrcmpiA(action, "DOWN") == 0) {
        g_game.pointerDown = TRUE;
        SetCapture(hwnd);
    } else if (lstrcmpiA(action, "UP") == 0 || lstrcmpiA(action, "CANCEL") == 0) {
        if (!g_game.pointerDown) {
            return;
        }
        g_game.pointerDown = FALSE;
        ReleaseCapture();
    } else if (lstrcmpiA(action, "MOVE") != 0 || !g_game.pointerDown) {
        return;
    }

    g_game.playerX = ClampInt(x - PLAYER_SIZE / 2, 0, g_game.width - PLAYER_SIZE);
    g_game.playerY = ClampInt(y - PLAYER_SIZE / 2, 0, g_game.height - PLAYER_SIZE);
    g_game.velX = 0;
    g_game.velY = 0;
    InvalidateRect(hwnd, NULL, FALSE);
}

static void PollHmosInputBridge(HWND hwnd)
{
    char path[MAX_PATH];
    HANDLE file;
    DWORD size;
    DWORD readBytes = 0;
    char *buffer;
    char *line;

    if (!ReadInputPath(path, sizeof(path))) {
        return;
    }

    file = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }

    size = GetFileSize(file, NULL);
    if (size == INVALID_FILE_SIZE || size == 0 || size > 64 * 1024) {
        CloseHandle(file);
        return;
    }

    buffer = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size + 1);
    if (!buffer) {
        CloseHandle(file);
        return;
    }

    if (ReadFile(file, buffer, size, &readBytes, NULL) && readBytes > 0) {
        SetFilePointer(file, 0, NULL, FILE_BEGIN);
        SetEndOfFile(file);
        buffer[readBytes] = 0;
        line = buffer;
        while (line && *line) {
            char *next = strchr(line, '\n');
            unsigned long long seq = 0;
            char action[16] = { 0 };
            char tool[32] = { 0 };
            char source[32] = { 0 };
            double x = 0;
            double y = 0;
            double force = 0;
            int pointId = 0;
            int keyCode = 0;
            unsigned long long modifiers = 0;
            if (next) {
                *next++ = 0;
            }
            if (sscanf(line, "%llu %15s %d %llu", &seq, action, &keyCode, &modifiers) >= 3 &&
                    (lstrcmpiA(action, "KEY_DOWN") == 0 || lstrcmpiA(action, "KEY_UP") == 0)) {
                ApplyBridgeKey(hwnd, action, keyCode);
                line = next;
                continue;
            }
            if (sscanf(line, "%llu %15s %lf %lf %31s %31s %d %lf",
                    &seq, action, &x, &y, tool, source, &pointId, &force) >= 4) {
                ApplyBridgePointer(hwnd, action, (int)x, (int)y);
            }
            line = next;
        }
    }

    HeapFree(GetProcessHeap(), 0, buffer);
    CloseHandle(file);
}

static void TickGame(HWND hwnd)
{
    int accelX = 0;
    int accelY = 0;
    PollHmosInputBridge(hwnd);
    if (g_game.left) {
        accelX -= 2;
    }
    if (g_game.right) {
        accelX += 2;
    }
    if (g_game.up) {
        accelY -= 2;
    }
    if (g_game.down) {
        accelY += 2;
    }

    g_game.velX = ClampInt((g_game.velX + accelX) * 9 / 10, -10, 10);
    g_game.velY = ClampInt((g_game.velY + accelY) * 9 / 10, -10, 10);
    g_game.playerX = ClampInt(g_game.playerX + g_game.velX, 0, g_game.width - PLAYER_SIZE);
    g_game.playerY = ClampInt(g_game.playerY + g_game.velY, 0, g_game.height - PLAYER_SIZE);
    g_game.ticks++;

    if (RectsOverlap(g_game.playerX, g_game.playerY, PLAYER_SIZE, PLAYER_SIZE,
            g_game.targetX, g_game.targetY, TARGET_SIZE, TARGET_SIZE)) {
        g_game.score++;
        ResetTarget();
    }

    InvalidateRect(hwnd, NULL, FALSE);
}

static void PaintGame(HWND hwnd, HDC hdc)
{
    RECT client;
    WCHAR hud[160];
    HBRUSH background = CreateSolidBrush(RGB(12, 17, 24));
    HBRUSH player = CreateSolidBrush(RGB(72, 196, 168));
    HBRUSH target = CreateSolidBrush(RGB(255, 204, 92));
    HPEN gridPen = CreatePen(PS_SOLID, 1, RGB(32, 42, 54));
    HGDIOBJ oldPen;
    RECT playerRect;
    RECT targetRect;

    GetClientRect(hwnd, &client);
    FillRect(hdc, &client, background);

    oldPen = SelectObject(hdc, gridPen);
    for (int x = 0; x < client.right; x += 40) {
        MoveToEx(hdc, x, 0, NULL);
        LineTo(hdc, x, client.bottom);
    }
    for (int y = 0; y < client.bottom; y += 40) {
        MoveToEx(hdc, 0, y, NULL);
        LineTo(hdc, client.right, y);
    }
    SelectObject(hdc, oldPen);

    targetRect.left = g_game.targetX;
    targetRect.top = g_game.targetY;
    targetRect.right = g_game.targetX + TARGET_SIZE;
    targetRect.bottom = g_game.targetY + TARGET_SIZE;
    FillRect(hdc, &targetRect, target);

    playerRect.left = g_game.playerX;
    playerRect.top = g_game.playerY;
    playerRect.right = g_game.playerX + PLAYER_SIZE;
    playerRect.bottom = g_game.playerY + PLAYER_SIZE;
    FillRect(hdc, &playerRect, player);

    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, RGB(238, 244, 246));
    wsprintfW(hud, L"Proton Tiny Game  |  WASD / arrows  |  score %d  |  frame %d",
        g_game.score, g_game.ticks);
    TextOutW(hdc, 18, 16, hud, lstrlenW(hud));

    DeleteObject(gridPen);
    DeleteObject(target);
    DeleteObject(player);
    DeleteObject(background);
}

static LRESULT CALLBACK TinyGameWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {
        case WM_CREATE:
            WriteTinyGameMarker("HMOS ProtonTinyGame WM_CREATE enter\r\n");
            ResetGame(hwnd);
            SetTimer(hwnd, GAME_TIMER_ID, GAME_TIMER_MS, NULL);
            WriteTinyGameMarker("HMOS ProtonTinyGame WM_CREATE done\r\n");
            return 0;
        case WM_SIZE:
            g_game.width = LOWORD(lParam);
            g_game.height = HIWORD(lParam);
            g_game.playerX = ClampInt(g_game.playerX, 0, g_game.width - PLAYER_SIZE);
            g_game.playerY = ClampInt(g_game.playerY, 0, g_game.height - PLAYER_SIZE);
            ResetTarget();
            return 0;
        case WM_KEYDOWN:
            if (wParam == VK_ESCAPE) {
                DestroyWindow(hwnd);
                return 0;
            }
            if (wParam == 'R') {
                ResetGame(hwnd);
                return 0;
            }
            SetKeyState(wParam, TRUE);
            return 0;
        case WM_KEYUP:
            SetKeyState(wParam, FALSE);
            return 0;
        case WM_LBUTTONDOWN:
            g_game.playerX = LOWORD(lParam) - PLAYER_SIZE / 2;
            g_game.playerY = HIWORD(lParam) - PLAYER_SIZE / 2;
            return 0;
        case WM_LBUTTONUP:
            g_game.pointerDown = FALSE;
            ReleaseCapture();
            return 0;
        case WM_TIMER:
            TickGame(hwnd);
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);
            BOOL writePaintMarker = g_paintMarkerCount < 4;
            if (writePaintMarker) {
                WriteTinyGameMarker("HMOS ProtonTinyGame WM_PAINT enter\r\n");
            }
            PaintGame(hwnd, hdc);
            EndPaint(hwnd, &ps);
            MirrorTinyGameFrame(hwnd);
            if (writePaintMarker) {
                WriteTinyGameMarker("HMOS ProtonTinyGame WM_PAINT done\r\n");
                g_paintMarkerCount++;
            }
            return 0;
        }
        case WM_DESTROY:
            WriteTinyGameMarker("HMOS ProtonTinyGame WM_DESTROY\r\n");
            KillTimer(hwnd, GAME_TIMER_ID);
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE prevInstance, PWSTR cmdLine, int showCmd)
{
    (void)prevInstance;
    (void)cmdLine;

    WriteTinyGameMarker("HMOS ProtonTinyGame entered wWinMain\r\n");

    const WCHAR className[] = L"ProtonTinyGame";
    WNDCLASSW wc;
    HWND hwnd;
    MSG msg;

    WriteTinyGameMarker("HMOS ProtonTinyGame before WNDCLASS init\r\n");
    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = TinyGameWndProc;
    wc.hInstance = instance;
    wc.hCursor = NULL;
    wc.lpszClassName = className;
    WriteTinyGameMarker("HMOS ProtonTinyGame after WNDCLASS init\r\n");

    WriteTinyGameMarker("HMOS ProtonTinyGame before RegisterClassW\r\n");
    if (!RegisterClassW(&wc)) {
        WriteTinyGameLastError("RegisterClassW");
        return 1;
    }
    WriteTinyGameMarker("HMOS ProtonTinyGame after RegisterClassW\r\n");

    WriteTinyGameMarker("HMOS ProtonTinyGame before CreateWindowExW\r\n");
    hwnd = CreateWindowExW(0, className, L"Proton Tiny Game",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, 800, 520,
        NULL, NULL, instance, NULL);
    if (!hwnd) {
        WriteTinyGameLastError("CreateWindowExW");
        return 2;
    }
    WriteTinyGameMarker("HMOS ProtonTinyGame after CreateWindowExW\r\n");

    WriteTinyGameMarker("HMOS ProtonTinyGame before ShowWindow\r\n");
    ShowWindow(hwnd, showCmd);
    WriteTinyGameMarker("HMOS ProtonTinyGame after ShowWindow\r\n");
    WriteTinyGameMarker("HMOS ProtonTinyGame before UpdateWindow\r\n");
    UpdateWindow(hwnd);
    WriteTinyGameMarker("HMOS ProtonTinyGame after UpdateWindow\r\n");

    WriteTinyGameMarker("HMOS ProtonTinyGame before message loop\r\n");
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    WriteTinyGameMarker("HMOS ProtonTinyGame message loop exited\r\n");
    return (int)msg.wParam;
}
