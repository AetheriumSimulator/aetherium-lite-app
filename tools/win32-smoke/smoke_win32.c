#include <windows.h>
#include <winreg.h>
#include <stdio.h>

typedef LONG (WINAPI *RtlGetVersionFn)(PRTL_OSVERSIONINFOW);

static WCHAR g_info[1024];

static void ReadWineVersion(WCHAR *buffer, DWORD count)
{
    HKEY key = NULL;
    DWORD type = REG_SZ;
    DWORD bytes = count * sizeof(WCHAR);
    LONG status = RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Wine", 0, KEY_QUERY_VALUE, &key);
    if (status != ERROR_SUCCESS) {
        lstrcpynW(buffer, L"HKCU\\Software\\Wine Version: <missing>", count);
        return;
    }

    status = RegQueryValueExW(key, L"Version", NULL, &type, (LPBYTE)buffer, &bytes);
    RegCloseKey(key);
    if (status != ERROR_SUCCESS || type != REG_SZ) {
        lstrcpynW(buffer, L"HKCU\\Software\\Wine Version: <missing>", count);
        return;
    }
}

static void BuildInfo(void)
{
    WCHAR wineVersion[128];
    RTL_OSVERSIONINFOW osVersion;
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    RtlGetVersionFn rtlGetVersion = ntdll ? (RtlGetVersionFn)GetProcAddress(ntdll, "RtlGetVersion") : NULL;

    ZeroMemory(&osVersion, sizeof(osVersion));
    osVersion.dwOSVersionInfoSize = sizeof(osVersion);
    if (rtlGetVersion) {
        rtlGetVersion(&osVersion);
    }
    ReadWineVersion(wineVersion, ARRAYSIZE(wineVersion));

    swprintf(g_info, ARRAYSIZE(g_info),
        L"Proton.Hsp Win32 smoke test\\n"
        L"Window class, message pump and GDI paint are alive.\\n\\n"
        L"RtlGetVersion: %lu.%lu build %lu\\n"
        L"%ls\\n\\n"
        L"Expected Wine compatibility target: win11",
        osVersion.dwMajorVersion,
        osVersion.dwMinorVersion,
        osVersion.dwBuildNumber,
        wineVersion);
}

static LRESULT CALLBACK SmokeWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {
        case WM_CREATE:
            BuildInfo();
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            RECT rect;
            HDC hdc = BeginPaint(hwnd, &ps);
            GetClientRect(hwnd, &rect);
            SetBkMode(hdc, TRANSPARENT);
            SetTextColor(hdc, RGB(24, 38, 50));
            InflateRect(&rect, -24, -24);
            DrawTextW(hdc, g_info, -1, &rect, DT_LEFT | DT_TOP | DT_WORDBREAK);
            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_DESTROY:
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

    const WCHAR className[] = L"ProtonHspWin32Smoke";
    WNDCLASSW wc;
    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = SmokeWndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = className;

    if (!RegisterClassW(&wc)) {
        MessageBoxW(NULL, L"RegisterClassW failed", L"Proton.Hsp smoke", MB_ICONERROR);
        return 1;
    }

    HWND hwnd = CreateWindowExW(0, className, L"Proton.Hsp Win32 smoke",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, 760, 420,
        NULL, NULL, instance, NULL);
    if (!hwnd) {
        MessageBoxW(NULL, L"CreateWindowExW failed", L"Proton.Hsp smoke", MB_ICONERROR);
        return 2;
    }

    ShowWindow(hwnd, showCmd);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return (int)msg.wParam;
}
