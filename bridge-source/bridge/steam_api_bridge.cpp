#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdint>
#include <string>

extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace {

constexpr std::uint32_t kGogAppId = 3837340;

HMODULE g_real = nullptr;
INIT_ONCE g_init_once = INIT_ONCE_STATIC_INIT;
std::wstring g_directory;

using RestartFn = bool(__cdecl *)(std::uint32_t);
using InitFn = bool(__cdecl *)();
using VoidFn = void(__cdecl *)();
using RegisterFn = void(__cdecl *)(void *, int);
using UnregisterFn = void(__cdecl *)(void *);
using InterfaceFn = void *(__cdecl *)();

RestartFn g_restart = nullptr;
InitFn g_init = nullptr;
VoidFn g_run_callbacks = nullptr;
VoidFn g_shutdown = nullptr;
RegisterFn g_register_callback = nullptr;
UnregisterFn g_unregister_callback = nullptr;
InterfaceFn g_user = nullptr;
InterfaceFn g_user_stats = nullptr;
InterfaceFn g_utils = nullptr;

void append_log(const wchar_t *message) {
    if (g_directory.empty()) return;
    const std::wstring path = g_directory + L"\\FFNxGOGBridge.log";
    HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;

    SYSTEMTIME now{};
    GetSystemTime(&now);
    wchar_t line[512]{};
    const int count = wsprintfW(
        line, L"%04u-%02u-%02uT%02u:%02u:%02uZ pid=%lu %s\r\n",
        now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
        GetCurrentProcessId(), message);
    if (count > 0) {
        DWORD written = 0;
        WriteFile(file, line, static_cast<DWORD>(count * sizeof(wchar_t)),
                  &written, nullptr);
    }
    CloseHandle(file);
}

template <typename T>
bool resolve(T &target, const char *name) {
    target = reinterpret_cast<T>(GetProcAddress(g_real, name));
    return target != nullptr;
}

BOOL CALLBACK load_real_bridge(PINIT_ONCE, PVOID, PVOID *) {
    wchar_t module_path[MAX_PATH]{};
    const DWORD length = GetModuleFileNameW(
        reinterpret_cast<HMODULE>(&__ImageBase), module_path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return TRUE;

    wchar_t *slash = wcsrchr(module_path, L'\\');
    if (slash == nullptr) return TRUE;
    *slash = L'\0';
    g_directory = module_path;

    const std::wstring real_path = g_directory + L"\\steam_api_gog.dll";
    g_real = LoadLibraryExW(real_path.c_str(), nullptr,
                            LOAD_WITH_ALTERED_SEARCH_PATH);
    if (g_real == nullptr) {
        append_log(L"LOAD_FAILED steam_api_gog.dll");
        return TRUE;
    }

    bool ok = true;
    ok &= resolve(g_restart, "SteamAPI_RestartAppIfNecessary");
    ok &= resolve(g_init, "SteamAPI_Init");
    ok &= resolve(g_run_callbacks, "SteamAPI_RunCallbacks");
    ok &= resolve(g_shutdown, "SteamAPI_Shutdown");
    ok &= resolve(g_register_callback, "SteamAPI_RegisterCallback");
    ok &= resolve(g_unregister_callback, "SteamAPI_UnregisterCallback");

    // Steam interface versions only append methods. FFNx 1.24.3 uses the
    // compatible prefixes User016, UserStats011, and Utils005.
    ok &= resolve(g_user, "SteamAPI_SteamUser_v023");
    ok &= resolve(g_user_stats, "SteamAPI_SteamUserStats_v012");
    ok &= resolve(g_utils, "SteamAPI_SteamUtils_v010");

    append_log(ok ? L"RESOLVE_OK gog-v160-to-ffnx-legacy"
                  : L"RESOLVE_FAILED required-export-missing");
    return TRUE;
}

bool ensure_loaded() {
    InitOnceExecuteOnce(&g_init_once, load_real_bridge, nullptr, nullptr);
    return g_real != nullptr && g_restart != nullptr && g_init != nullptr &&
           g_run_callbacks != nullptr && g_shutdown != nullptr &&
           g_register_callback != nullptr && g_unregister_callback != nullptr &&
           g_user != nullptr && g_user_stats != nullptr && g_utils != nullptr;
}

}  // namespace

extern "C" __declspec(dllexport) bool __cdecl
SteamAPI_RestartAppIfNecessary(std::uint32_t app_id) {
    if (!ensure_loaded()) return false;
    if (app_id != kGogAppId) {
        append_log(L"APPID_REMAP requested-appid-to-3837340");
        app_id = kGogAppId;
    }
    return g_restart(app_id);
}

extern "C" __declspec(dllexport) bool __cdecl SteamAPI_Init() {
    if (!ensure_loaded()) return false;
    const bool result = g_init();
    append_log(result ? L"STEAMAPI_INIT_OK" : L"STEAMAPI_INIT_FAILED");
    return result;
}

extern "C" __declspec(dllexport) void __cdecl SteamAPI_RunCallbacks() {
    if (ensure_loaded()) g_run_callbacks();
}

extern "C" __declspec(dllexport) void __cdecl SteamAPI_Shutdown() {
    if (!ensure_loaded()) return;
    g_shutdown();
    append_log(L"STEAMAPI_SHUTDOWN");
}

extern "C" __declspec(dllexport) void __cdecl
SteamAPI_RegisterCallback(void *callback, int callback_id) {
    if (ensure_loaded()) g_register_callback(callback, callback_id);
}

extern "C" __declspec(dllexport) void __cdecl
SteamAPI_UnregisterCallback(void *callback) {
    if (ensure_loaded()) g_unregister_callback(callback);
}

extern "C" __declspec(dllexport) void *__cdecl SteamUser() {
    return ensure_loaded() ? g_user() : nullptr;
}

extern "C" __declspec(dllexport) void *__cdecl SteamUserStats() {
    return ensure_loaded() ? g_user_stats() : nullptr;
}

extern "C" __declspec(dllexport) void *__cdecl SteamUtils() {
    return ensure_loaded() ? g_utils() : nullptr;
}

extern "C" __declspec(dllexport) int __cdecl FFNxGOGBridge_ResolveOnly() {
    return ensure_loaded() ? 0 : 1;
}

