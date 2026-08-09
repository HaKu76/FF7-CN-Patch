# GOG API Bridge Source

This directory contains the compatibility bridge used by the FFNx GOG candidate.

`steam_api_bridge.cpp` exports the legacy Steam API entry points expected by the traditional FF7 runtime, loads the original GOG `steam_api_gog.dll`, resolves the required user/statistics/utils interfaces, and forwards callbacks. The bridge remaps `SteamAPI_RestartAppIfNecessary` to GOG App ID `3837340`.

`bridge_selftest.cpp` checks the bridge exports and verifies that the neighboring original GOG DLL can be loaded. `build-bridge.ps1` expects the Visual Studio 2022 x86 C++ toolchain and a GOG game root containing the original `steam_api.dll`, `Galaxy.dll`, and `GalaxyConfig.json`.

The compiled bridge in `runtime-payload/bridge/steam_api.dll` is a compatibility candidate. It is not an implementation of the private GOG Galaxy SDK and does not guarantee an in-game achievement popup. Verify account state and bridge logs on every target game build.
