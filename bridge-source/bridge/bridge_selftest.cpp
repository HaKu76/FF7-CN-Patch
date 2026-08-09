#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdio>

int wmain() {
    HMODULE bridge = LoadLibraryW(L"steam_api.dll");
    if (bridge == nullptr) {
        std::printf("BRIDGE_LOAD_FAILED error=%lu\n", GetLastError());
        return 2;
    }

    const char *required[] = {
        "SteamAPI_Init",
        "SteamAPI_RegisterCallback",
        "SteamAPI_RestartAppIfNecessary",
        "SteamAPI_RunCallbacks",
        "SteamAPI_Shutdown",
        "SteamAPI_UnregisterCallback",
        "SteamUser",
        "SteamUserStats",
        "SteamUtils",
    };
    for (const char *name : required) {
        if (GetProcAddress(bridge, name) == nullptr) {
            std::printf("BRIDGE_EXPORT_MISSING name=%s\n", name);
            FreeLibrary(bridge);
            return 3;
        }
    }

    using ResolveOnlyFn = int(__cdecl *)();
    auto resolve_only = reinterpret_cast<ResolveOnlyFn>(
        GetProcAddress(bridge, "FFNxGOGBridge_ResolveOnly"));
    if (resolve_only == nullptr || resolve_only() != 0) {
        std::printf("GOG_EXPORT_RESOLUTION_FAILED\n");
        FreeLibrary(bridge);
        return 4;
    }

    wchar_t bridge_path[MAX_PATH]{};
    wchar_t real_path[MAX_PATH]{};
    GetModuleFileNameW(bridge, bridge_path, MAX_PATH);
    HMODULE real = GetModuleHandleW(L"steam_api_gog.dll");
    if (real == nullptr) {
        std::printf("GOG_MODULE_NOT_LOADED\n");
        FreeLibrary(bridge);
        return 5;
    }
    GetModuleFileNameW(real, real_path, MAX_PATH);
    ::wprintf(L"BRIDGE_RESOLVE_OK\nbridge=%ls\ngog=%ls\n", bridge_path,
              real_path);
    FreeLibrary(bridge);
    return 0;
}
