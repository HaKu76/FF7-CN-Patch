#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GameRoot,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GameRoot)) { $GameRoot = Split-Path -Parent $projectRoot }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $projectRoot 'build\ffnx-gog-thirdparty-bridge' }
$sourceRoot = Join-Path $PSScriptRoot 'bridge'
$output = [IO.Path]::GetFullPath($OutputRoot)
$bin = Join-Path $output 'bin'
$selftest = Join-Path $output 'selftest'
$vcvars = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat'
$cl = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x86\cl.exe'

foreach ($required in @(
    $vcvars, $cl,
    (Join-Path $sourceRoot 'steam_api_bridge.cpp'),
    (Join-Path $sourceRoot 'steam_api.def'),
    (Join-Path $sourceRoot 'bridge_selftest.cpp'),
    (Join-Path $GameRoot 'steam_api.dll'),
    (Join-Path $GameRoot 'Galaxy.dll'),
    (Join-Path $GameRoot 'GalaxyConfig.json')
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Build input is missing: $required" }
}

cmd.exe /c "call `"$vcvars`" x86 >nul 2>&1 && set" | ForEach-Object {
    $pair = $_ -split '=', 2
    if ($pair.Count -eq 2) { Set-Item -Path ("Env:" + $pair[0]) -Value $pair[1] }
}
New-Item -ItemType Directory -Path $bin,$selftest -Force | Out-Null

$bridge = Join-Path $bin 'steam_api.dll'
& $cl /nologo /LD /EHsc /std:c++17 /O2 /MT /Brepro /DUNICODE /D_UNICODE `
    "/Fo$(Join-Path $output 'steam_api_bridge.obj')" "/Fe:$bridge" `
    (Join-Path $sourceRoot 'steam_api_bridge.cpp') `
    user32.lib /link /Brepro /INCREMENTAL:NO "/DEF:$(Join-Path $sourceRoot 'steam_api.def')"
if ($LASTEXITCODE -ne 0) { throw "Bridge compilation failed: $LASTEXITCODE" }

$selftestHost = Join-Path $bin 'ffnx-gog-bridge-selftest.exe'
& $cl /nologo /EHsc /std:c++17 /O2 /MT /Brepro /DUNICODE /D_UNICODE `
    "/Fo$(Join-Path $output 'bridge_selftest.obj')" "/Fe:$selftestHost" `
    (Join-Path $sourceRoot 'bridge_selftest.cpp') /link /Brepro /INCREMENTAL:NO
if ($LASTEXITCODE -ne 0) { throw "Self-test host compilation failed: $LASTEXITCODE" }

Copy-Item -LiteralPath $bridge -Destination (Join-Path $selftest 'steam_api.dll') -Force
Copy-Item -LiteralPath $selftestHost -Destination (Join-Path $selftest 'ffnx-gog-bridge-selftest.exe') -Force
Copy-Item -LiteralPath (Join-Path $GameRoot 'steam_api.dll') -Destination (Join-Path $selftest 'steam_api_gog.dll') -Force
Copy-Item -LiteralPath (Join-Path $GameRoot 'Galaxy.dll') -Destination (Join-Path $selftest 'Galaxy.dll') -Force
Copy-Item -LiteralPath (Join-Path $GameRoot 'GalaxyConfig.json') -Destination (Join-Path $selftest 'GalaxyConfig.json') -Force

Push-Location $selftest
try {
    & (Join-Path $selftest 'ffnx-gog-bridge-selftest.exe')
    if ($LASTEXITCODE -ne 0) { throw "Bridge self-test failed: $LASTEXITCODE" }
} finally {
    Pop-Location
}

$manifest = [ordered]@{
    format = 'ffnx-gog-x86-steam-bridge-v1'
    version = '0.1.0-test'
    architecture = 'x86'
    bridgeSha256 = (Get-FileHash -LiteralPath $bridge -Algorithm SHA256).Hash.ToLowerInvariant()
    bridgeSize = (Get-Item -LiteralPath $bridge).Length
    hostSha256 = (Get-FileHash -LiteralPath $selftestHost -Algorithm SHA256).Hash.ToLowerInvariant()
    gogSteamApiSha256 = (Get-FileHash -LiteralPath (Join-Path $GameRoot 'steam_api.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
    gogGalaxySha256 = (Get-FileHash -LiteralPath (Join-Path $GameRoot 'Galaxy.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
    requiredFfnxImports = @(
        'SteamAPI_Init','SteamAPI_RegisterCallback','SteamAPI_RestartAppIfNecessary',
        'SteamAPI_RunCallbacks','SteamAPI_Shutdown','SteamAPI_UnregisterCallback',
        'SteamUser','SteamUserStats','SteamUtils'
    )
    gogInterfaceExports = @(
        'SteamAPI_SteamUser_v023','SteamAPI_SteamUserStats_v012','SteamAPI_SteamUtils_v010'
    )
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $bin 'bridge-manifest.json') -Encoding UTF8
Write-Host "Bridge build and resolve-only self-test passed: $bin"
