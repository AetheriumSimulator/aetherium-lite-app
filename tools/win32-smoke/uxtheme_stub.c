typedef void *HINSTANCE;
typedef unsigned int DWORD;
typedef void *LPVOID;
typedef int BOOL;

#define TRUE 1
#define WINAPI

BOOL WINAPI DllMainCRTStartup(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)instance;
    (void)reason;
    (void)reserved;
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI IsThemeActive(void)
{
    return TRUE;
}
