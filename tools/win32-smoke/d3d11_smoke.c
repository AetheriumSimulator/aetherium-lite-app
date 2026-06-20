#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdint.h>

#define D3D_TIMER_ID 1
#define D3D_TIMER_MS 16

static ID3D11Device *g_device;
static ID3D11DeviceContext *g_context;
static IDXGISwapChain *g_swapchain;
static ID3D11RenderTargetView *g_rtv;
static uint64_t g_frame;

static void WriteMarker(const char *message)
{
    char path[MAX_PATH];
    DWORD count = GetEnvironmentVariableA("WINE_HMOS_MARKER_PATH", path, sizeof(path));
    HANDLE file = INVALID_HANDLE_VALUE;
    DWORD written = 0;

    if (count > 0 && count < sizeof(path)) {
        file = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    }
    if (file == INVALID_HANDLE_VALUE) {
        file = CreateFileA("d3d11-smoke.txt", FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    }
    if (file == INVALID_HANDLE_VALUE) return;
    WriteFile(file, message, lstrlenA(message), &written, NULL);
    CloseHandle(file);
}

static void WriteHresult(const char *step, HRESULT hr)
{
    char message[192];
    wsprintfA(message, "HMOS ProtonD3D11Smoke %s hr=0x%08lx\r\n", step, (unsigned long)hr);
    WriteMarker(message);
}

static void ReleaseRenderTarget(void)
{
    if (g_rtv) {
        ID3D11RenderTargetView_Release(g_rtv);
        g_rtv = NULL;
    }
}

static void ReleaseD3D(void)
{
    ReleaseRenderTarget();
    if (g_swapchain) {
        IDXGISwapChain_Release(g_swapchain);
        g_swapchain = NULL;
    }
    if (g_context) {
        ID3D11DeviceContext_Release(g_context);
        g_context = NULL;
    }
    if (g_device) {
        ID3D11Device_Release(g_device);
        g_device = NULL;
    }
}

static HRESULT CreateRenderTarget(void)
{
    ID3D11Texture2D *backbuffer = NULL;
    HRESULT hr;

    hr = IDXGISwapChain_GetBuffer(g_swapchain, 0, &IID_ID3D11Texture2D, (void **)&backbuffer);
    if (FAILED(hr)) return hr;

    hr = ID3D11Device_CreateRenderTargetView(g_device, (ID3D11Resource *)backbuffer, NULL, &g_rtv);
    ID3D11Texture2D_Release(backbuffer);
    return hr;
}

static HRESULT ResizeSwapchain(UINT width, UINT height)
{
    HRESULT hr;

    if (!g_swapchain) return S_OK;
    if (width == 0 || height == 0) return S_OK;

    ReleaseRenderTarget();
    hr = IDXGISwapChain_ResizeBuffers(g_swapchain, 0, width, height, DXGI_FORMAT_UNKNOWN, 0);
    if (FAILED(hr)) return hr;
    return CreateRenderTarget();
}

static HRESULT InitD3D(HWND hwnd)
{
    DXGI_SWAP_CHAIN_DESC desc;
    D3D_FEATURE_LEVEL requested[] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0
    };
    D3D_FEATURE_LEVEL selected = D3D_FEATURE_LEVEL_10_0;
    HRESULT hr;

    ZeroMemory(&desc, sizeof(desc));
    desc.BufferDesc.Width = 896;
    desc.BufferDesc.Height = 640;
    desc.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.BufferDesc.RefreshRate.Numerator = 60;
    desc.BufferDesc.RefreshRate.Denominator = 1;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2;
    desc.OutputWindow = hwnd;
    desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    WriteMarker("HMOS ProtonD3D11Smoke D3D11CreateDeviceAndSwapChain enter\r\n");
    hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
        requested, ARRAYSIZE(requested), D3D11_SDK_VERSION, &desc, &g_swapchain,
        &g_device, &selected, &g_context);
    if (FAILED(hr)) {
        WriteHresult("D3D11CreateDeviceAndSwapChain failed", hr);
        return hr;
    }

    WriteMarker("HMOS ProtonD3D11Smoke D3D11CreateDeviceAndSwapChain ok\r\n");
    hr = CreateRenderTarget();
    if (FAILED(hr)) WriteHresult("CreateRenderTarget failed", hr);
    return hr;
}

static void RenderFrame(void)
{
    FLOAT color[4];
    HRESULT hr;
    float phase;

    if (!g_context || !g_swapchain || !g_rtv) return;

    phase = (float)((g_frame % 240) / 240.0f);
    color[0] = 0.05f + 0.65f * phase;
    color[1] = 0.10f + 0.40f * (1.0f - phase);
    color[2] = 0.35f + 0.35f * ((g_frame / 30) % 2);
    color[3] = 1.0f;

    ID3D11DeviceContext_OMSetRenderTargets(g_context, 1, &g_rtv, NULL);
    ID3D11DeviceContext_ClearRenderTargetView(g_context, g_rtv, color);
    hr = IDXGISwapChain_Present(g_swapchain, 1, 0);
    if (FAILED(hr)) {
        WriteHresult("Present failed", hr);
        return;
    }

    if ((g_frame % 120) == 0) {
        char message[128];
        wsprintfA(message, "HMOS ProtonD3D11Smoke present frame=%lu\r\n", (unsigned long)g_frame);
        WriteMarker(message);
    }
    g_frame++;
}

static LRESULT CALLBACK D3DWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {
        case WM_CREATE:
            if (FAILED(InitD3D(hwnd))) {
                MessageBoxW(hwnd, L"D3D11 initialization failed", L"Proton D3D11 smoke", MB_ICONERROR);
            }
            SetTimer(hwnd, D3D_TIMER_ID, D3D_TIMER_MS, NULL);
            return 0;
        case WM_SIZE:
            if (g_swapchain) {
                UINT width = LOWORD(lParam);
                UINT height = HIWORD(lParam);
                HRESULT hr = ResizeSwapchain(width, height);
                if (FAILED(hr)) WriteHresult("ResizeBuffers failed", hr);
            }
            return 0;
        case WM_TIMER:
            if (wParam == D3D_TIMER_ID) {
                RenderFrame();
                return 0;
            }
            break;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(hwnd, &ps);
            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_DESTROY:
            KillTimer(hwnd, D3D_TIMER_ID);
            ReleaseD3D();
            WriteMarker("HMOS ProtonD3D11Smoke WM_DESTROY\r\n");
            PostQuitMessage(0);
            return 0;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE prevInstance, PWSTR cmdLine, int showCmd)
{
    const WCHAR className[] = L"ProtonHspD3D11Smoke";
    WNDCLASSW wc;
    HWND hwnd;
    MSG msg;

    (void)prevInstance;
    (void)cmdLine;

    WriteMarker("HMOS ProtonD3D11Smoke entered wWinMain\r\n");
    ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = D3DWndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = className;

    if (!RegisterClassW(&wc)) {
        WriteMarker("HMOS ProtonD3D11Smoke RegisterClassW failed\r\n");
        return 1;
    }

    hwnd = CreateWindowExW(0, className, L"Proton.Hsp D3D11 smoke",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, 896, 640,
        NULL, NULL, instance, NULL);
    if (!hwnd) {
        WriteMarker("HMOS ProtonD3D11Smoke CreateWindowExW failed\r\n");
        return 2;
    }

    ShowWindow(hwnd, showCmd);
    UpdateWindow(hwnd);

    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return (int)msg.wParam;
}
