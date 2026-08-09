#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Install','Chinese','GogAchievement','Rollback','Validate','Import','ImportLanguage','ImportFfnx','ClearLogs')]
    [string]$Mode = 'Install',
    [string]$GameRoot,
    [string]$LanguagePack,
    [string]$SourcePackage,
    [Alias('Backup')]
    [string]$BackupRoot,
    [string]$KeepLog,
    [switch]$NoLaunch,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PatchRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$StateRoot = Join-Path $PatchRoot 'state'
$StatePath = Join-Path $StateRoot 'install-manifest.json'
$SelectedLanguagePath = Join-Path $StateRoot 'selected-language-pack.txt'
$LanguageRoot = Join-Path $PatchRoot 'language-packs'
$RuntimeRoot = Join-Path $PatchRoot 'runtime-payload'
$RuntimeModulePath = Join-Path $RuntimeRoot 'ffnx-module.json'
$PackageVersion = '0.7.8'
$ExpectedFfnxVersion = '1.24.2.26'
$ExpectedFfnxUpstreamSha256 = '8a21e5a990ea9d28e4b85f814d0c8923bcb7456438765663d5c8daaab1db5de7'
$ExpectedFfnxPatchedSha256 = '2ccb5282417a04c6370dcfe56f2fa05c919bb57ce944461feaa881b102c1f873'
$ExpectedAf4dnSha256 = '28117cdc956b764e35650a3856b5cf942dfe317c68abaaabb693cb3d83ae333c'
$OfficialSteamApiSha1 = '03bd9f3e352553a0af41f5fe006f6249a168c243'
$script:LanguageImported = $false
$script:ImportedLanguageSource = $null
$script:ImportedLanguageBackup = $null
$script:ImportedLanguageBackupContainsPack = $false
$script:ImportedLanguageTarget = $null

New-Item -ItemType Directory -Path $StateRoot,$LanguageRoot,$RuntimeRoot -Force | Out-Null

function FullPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path is empty.' }
    $value = [Environment]::ExpandEnvironmentVariables($Path).Trim()
    if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'"))) {
        $value = $value.Substring(1, $value.Length - 2).Trim()
    }
    try { [IO.Path]::GetFullPath($value) } catch { throw "Invalid path '$value': $($_.Exception.Message)" }
}

function ChildPath([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.?([\\/]|$)') { throw "Unsafe relative path: $Relative" }
    $base = (FullPath $Root).TrimEnd([char[]]@([char]92,[char]47))
    $path = FullPath (Join-Path $base ($Relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $path.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes root: $Relative" }
    $path
}

function HashFile([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function IsAdministrator {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function AssertGameRoot([string]$Root) {
    $rootPath = FullPath $Root
    $hasMarker = (Test-Path -LiteralPath (Join-Path $rootPath 'FFVII.exe') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $rootPath 'FFVII_LAUNCHER.exe') -PathType Leaf)
    $ff7Path = Join-Path $rootPath 'ff7'
    if (-not $hasMarker -or -not (Test-Path -LiteralPath $ff7Path -PathType Container)) {
        throw "Not a GOG FFVII game root: $rootPath (expected FFVII.exe/FFVII_LAUNCHER.exe and ff7 directory)"
    }
    $rootPath
}

function GetWorkingRoot([string]$Root) {
    $preferred = Join-Path $Root 'ff7\workingdir'
    if (Test-Path -LiteralPath $preferred -PathType Container) { return FullPath $preferred }
    $fallback = Join-Path $Root 'ff7'
    if (Test-Path -LiteralPath $fallback -PathType Container) { return FullPath $fallback }
    throw "FFNx working directory is missing below $Root\ff7"
}

function FindLanguagePack {
    if (-not (Test-Path -LiteralPath $LanguageRoot -PathType Container)) {
        throw "Language pack directory is missing: $LanguageRoot"
    }
    if (-not [string]::IsNullOrWhiteSpace($LanguagePack)) {
        $candidate = if ([IO.Path]::IsPathRooted($LanguagePack)) { FullPath $LanguagePack } else { ChildPath $LanguageRoot $LanguagePack }
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Language pack not found: $candidate" }
        return $candidate
    }
    if (Test-Path -LiteralPath $SelectedLanguagePath -PathType Leaf) {
        $selected = (Get-Content -LiteralPath $SelectedLanguagePath -Raw -Encoding UTF8).Trim()
        if ($selected -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
            $candidate = Join-Path $LanguageRoot $selected
            if (Test-Path -LiteralPath (Join-Path $candidate 'ff7') -PathType Container) { return FullPath $candidate }
        }
    }
    $candidates = @(Get-ChildItem -LiteralPath $LanguageRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'ff7') -PathType Container })
    if ($candidates.Count -eq 1) { return FullPath $candidates[0].FullName }
    if ($candidates.Count -eq 0) { throw "No language pack found. Import a module into imports\\language or restore the built-in language-packs\\traditional-cht-1.47 module." }
    throw ('Multiple language packs found. Pass -LanguagePack with one of: ' + (($candidates | ForEach-Object Name) -join ', '))
}

function FindImportSource([ValidateSet('language','ffnx')][string]$Kind) {
    $imports = Join-Path $PatchRoot 'imports'
    if (-not (Test-Path -LiteralPath $imports -PathType Container)) {
        New-Item -ItemType Directory -Path $imports -Force | Out-Null
    }
    $kindRoot = Join-Path $imports $Kind
    New-Item -ItemType Directory -Path $kindRoot -Force | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($SourcePackage)) {
        $candidate = if ([IO.Path]::IsPathRooted($SourcePackage)) { FullPath $SourcePackage } else { ChildPath $kindRoot $SourcePackage }
        if (-not (Test-Path -LiteralPath $candidate)) { throw "Import source not found: $candidate" }
        return $candidate
    }
    $directories = @(Get-ChildItem -LiteralPath $kindRoot -Force -Directory)
    $archives = @(Get-ChildItem -LiteralPath $kindRoot -Force -File | Where-Object { Test-ArchiveFile $_.FullName })
    $candidates = @($directories + $archives)
    if ($candidates.Count -eq 1) { return FullPath $candidates[0].FullName }
    if ($candidates.Count -eq 0) { return $null }
    throw ("Multiple $Kind import sources found. Keep one archive/folder in $kindRoot or pass -SourcePackage with one of: " + (($candidates | ForEach-Object Name) -join ', '))
}

function Get-ArchiveEntries([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    try {
        $tar = Get-Command tar.exe -ErrorAction Stop
        @(& $tar.Source -tf $Path 2>$null)
    } catch { @() }
}

function Test-ArchiveFile([string]$Path) {
    $entries = @(Get-ArchiveEntries $Path)
    return ($entries.Count -gt 0)
}

function Expand-ImportArchive([string]$ArchivePath, [string]$Destination, [string]$Activity = '补丁模块') {
    $entries = @(Get-ArchiveEntries $ArchivePath)
    if ($entries.Count -eq 0) { throw "无法识别压缩包格式，需提供可由 Windows tar 解压的 ZIP/RAR 文件: $ArchivePath" }
    foreach ($entry in $entries) {
        $name = [string]$entry
        $parts = $name -split '[\\/]'
        if ([IO.Path]::IsPathRooted($name) -or ($parts -contains '..')) {
            throw "拒绝包含不安全路径的压缩包条目: $name"
        }
    }
    $tar = Get-Command tar.exe -ErrorAction Stop
    $archiveSize = (Get-Item -LiteralPath $ArchivePath).Length
    $startedAt = Get-Date
    Write-Host "正在解压 ${Activity}: $(Split-Path -Leaf $ArchivePath)" -ForegroundColor Cyan
    Write-Host ("压缩包大小: {0:N1} MB；大型 RAR 可能需要几分钟，请不要关闭窗口。" -f ($archiveSize / 1MB)) -ForegroundColor DarkGray
    $arguments = @('-xf', ('"{0}"' -f $ArchivePath), '-C', ('"{0}"' -f $Destination))
    $process = Start-Process -FilePath $tar.Source -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $fileCount = 0
    $lastScanAt = Get-Date
    while (-not $process.HasExited) {
        $now = Get-Date
        if (($now - $lastScanAt).TotalSeconds -ge 2) {
            $fileCount = @(Get-ChildItem -LiteralPath $Destination -Recurse -File -ErrorAction SilentlyContinue).Count
            $elapsed = ($now - $startedAt).ToString('hh\:mm\:ss')
            Write-Progress -Activity "正在解压 ${Activity}" -Status ("已发现 {0} 个文件，已用时 {1}" -f $fileCount, $elapsed) -PercentComplete -1
            $lastScanAt = $now
        }
        Start-Sleep -Milliseconds 400
        $process.Refresh()
    }
    $process.WaitForExit()
    Write-Progress -Activity "正在解压 ${Activity}" -Completed
    if ($process.ExitCode -ne 0) { throw "压缩包解压失败 (tar exit $($process.ExitCode)): $ArchivePath" }
    $fileCount = @(Get-ChildItem -LiteralPath $Destination -Recurse -File -ErrorAction SilentlyContinue).Count
    $elapsed = ((Get-Date) - $startedAt).ToString('hh\:mm\:ss')
    Write-Host ("解压完成：发现 {0} 个文件，用时 {1}。现在开始校验模块内容..." -f $fileCount, $elapsed) -ForegroundColor Green
}

function RemoveImportedSource([string]$SourcePath) {
    $importsRoot = (FullPath (Join-Path $PatchRoot 'imports')).TrimEnd([char[]]@([char]92,[char]47))
    $source = FullPath $SourcePath
    if ($source.StartsWith($importsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $source -Recurse -Force
        Write-Host "已清理导入源: $source" -ForegroundColor DarkCyan
    } else {
        Write-Host "外部导入源已保留: $source" -ForegroundColor DarkGray
    }
}

function FindFilesRoot([string]$SourceRoot, [switch]$Optional) {
    $root = FullPath $SourceRoot
    if (Test-Path -LiteralPath (Join-Path $root 'files') -PathType Container) { return FullPath (Join-Path $root 'files') }
    $found = @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Filter files -ErrorAction SilentlyContinue)
    if ($found.Count -eq 1) { return FullPath $found[0].FullName }
    if ($found.Count -eq 0 -and $Optional) { return $null }
    if ($found.Count -eq 0) { throw "The language import does not contain the original patch's files folder: $root" }
    throw "The import source contains multiple files folders: $root"
}

function CopyImportTree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "Failed to import $Source (robocopy exit $LASTEXITCODE)" }
}

function AssertImportCanChangeModules {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return }
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$state.status -eq 'Installed') {
        throw 'The game is currently installed from these modules. Run rollback before importing or updating a language/FFNx module.'
    }
}

function GetActiveInstallState {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return $null }
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$state.status -eq 'Installed') { return $state }
    return $null
}

function TestLanguageFf7Root([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $direct = Join-Path $Path 'direct'
    $override = Join-Path $Path 'override'
    (Test-Path -LiteralPath $direct -PathType Container) -and
        (Test-Path -LiteralPath $override -PathType Container) -and
        (@(Get-ChildItem -LiteralPath $direct -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0) -and
        (@(Get-ChildItem -LiteralPath $override -Recurse -File -ErrorAction SilentlyContinue).Count -gt 0)
}

function FindLanguageModuleRoot([string]$SourceRoot) {
    $root = FullPath $SourceRoot
    $candidates = New-Object Collections.Generic.List[string]
    if ((Test-Path -LiteralPath (Join-Path $root 'ff7') -PathType Container) -and (TestLanguageFf7Root (Join-Path $root 'ff7'))) {
        $candidates.Add($root)
    }
    foreach ($ff7 in @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Filter ff7 -ErrorAction SilentlyContinue)) {
        if (TestLanguageFf7Root $ff7.FullName) { $candidates.Add((Split-Path -Parent $ff7.FullName)) }
    }
    $unique = @($candidates | Sort-Object -Unique)
    if ($unique.Count -eq 1) { return FullPath $unique[0] }
    if ($unique.Count -eq 0) { return $null }
    throw 'The language import contains multiple normalized language modules. Keep only one module in imports\language.'
}

function GetLanguageModuleIdentity([string]$ModuleRoot, [string]$FallbackId) {
    $id = $FallbackId
    $displayName = $FallbackId
    $manifestPath = Join-Path $ModuleRoot 'language-pack.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace([string]$manifest.id)) { $id = [string]$manifest.id }
        if (-not [string]::IsNullOrWhiteSpace([string]$manifest.displayName)) { $displayName = [string]$manifest.displayName }
    }
    if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Unsafe language module id: $id" }
    [pscustomobject]@{ Id=$id; DisplayName=$displayName }
}

function InstallNormalizedLanguageModule([string]$ModuleRoot, [string]$OriginalSource) {
    $identity = GetLanguageModuleIdentity $ModuleRoot (Split-Path -Leaf $ModuleRoot)
    $sourceFf7 = Join-Path $ModuleRoot 'ff7'
    if (-not (TestLanguageFf7Root $sourceFf7)) { throw "Normalized language module needs ff7\direct and ff7\override: $ModuleRoot" }
    $pack = Join-Path $LanguageRoot $identity.Id
    $packFf7 = Join-Path $pack 'ff7'
    $backup = $null
    if (Test-Path -LiteralPath $packFf7 -PathType Container) {
        $backup = Join-Path $StateRoot ("language-backups\{0}\{1}\ff7" -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$identity.Id)
        CopyImportTree $packFf7 $backup
        Remove-Item -LiteralPath $packFf7 -Recurse -Force
        Write-Host "旧语言模块已备份: $backup" -ForegroundColor DarkGray
    }
    New-Item -ItemType Directory -Path $packFf7 -Force | Out-Null
    foreach ($name in @('direct','override','hext','mods')) {
        $tree = Join-Path $sourceFf7 $name
        if (Test-Path -LiteralPath $tree -PathType Container) { CopyImportTree $tree (Join-Path $packFf7 $name) }
    }
    [ordered]@{
        id=$identity.Id; displayName=$identity.DisplayName; importedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');
        sourceName=(Split-Path -Leaf $OriginalSource); status='imported-normalized-module'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $pack 'language-pack.json') -Encoding UTF8
    Set-Content -LiteralPath $SelectedLanguagePath -Value $identity.Id -Encoding UTF8
    $script:LanguageImported = $true
    $script:ImportedLanguageSource = $OriginalSource
    $script:ImportedLanguageBackup = $backup
    $script:ImportedLanguageBackupContainsPack = $false
    $script:ImportedLanguageTarget = $pack
    Write-Host "语言模块导入完成并已选中: $($identity.DisplayName) [$($identity.Id)]" -ForegroundColor Green
}

function ImportTraditionalLanguagePack {
    $originalSource = FindImportSource 'language'
    if ([string]::IsNullOrWhiteSpace([string]$originalSource)) {
        $embedded = @(Get-ChildItem -LiteralPath $LanguageRoot -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'ff7') -PathType Container })
        Write-Host '没有发现外部语言包，这不是错误。' -ForegroundColor Yellow
        if ($embedded.Count -gt 0) {
            Write-Host ("当前包已内置语言包: {0}" -f (($embedded | ForEach-Object Name) -join ', ')) -ForegroundColor Green
            Write-Host '直接返回菜单选择“只安装”或“一键安装并启动”即可，不需要执行导入。' -ForegroundColor Cyan
        } else {
            Write-Host "如需导入，请把一个语言包 ZIP/RAR 或解压目录放入: $(Join-Path $PatchRoot 'imports\language')" -ForegroundColor Cyan
        }
        return
    }
    $source = $originalSource
    $temporary = $null
    $moduleStaging = $null
    try {
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and (Test-ArchiveFile $source)) {
            Write-Host '已找到压缩包，准备解压并校验汉化资源...' -ForegroundColor Cyan
            $temporary = Join-Path $StateRoot ('imports\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            New-Item -ItemType Directory -Path $temporary -Force | Out-Null
            Expand-ImportArchive $source $temporary '语言包'
            $source = $temporary
        }
        $files = FindFilesRoot $source -Optional
        if (-not $files) {
            $module = FindLanguageModuleRoot $source
            if (-not $module) {
                throw '无法识别语言包。原始包应包含 files\direct/override/hext/mods/fonts\msjh_bd；规范模块应包含 <id>\ff7\direct 和 override。'
            }
            InstallNormalizedLanguageModule $module $originalSource
            return
        }
        Write-Host '正在校验 files\direct、override、hext、mods 和 fonts\msjh_bd ...' -ForegroundColor Cyan
        foreach ($required in @('direct','override','hext','mods','fonts\msjh_bd')) {
            $requiredPath = Join-Path $files $required
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Container) -or
                @(Get-ChildItem -LiteralPath $requiredPath -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0) {
                throw "Traditional patch resource is missing: files\$required"
            }
        }

        $packId = 'traditional-cht-1.47'
        $pack = Join-Path $LanguageRoot $packId
        $moduleStaging = Join-Path $StateRoot ('language-imports\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $stagedPack = Join-Path $moduleStaging $packId
        $stagedFf7 = Join-Path $stagedPack 'ff7'
        New-Item -ItemType Directory -Path $stagedFf7 -Force | Out-Null
        CopyImportTree (Join-Path $files 'direct') (Join-Path $stagedFf7 'direct')
        CopyImportTree (Join-Path $files 'override') (Join-Path $stagedFf7 'override')
        CopyImportTree (Join-Path $files 'mods') (Join-Path $stagedFf7 'mods')
        CopyImportTree (Join-Path $files 'fonts\msjh_bd') (Join-Path $stagedFf7 'direct')
        CopyImportTree (Join-Path $files 'hext') (Join-Path $stagedFf7 'hext')
        $battlePreset = Join-Path $files 'hext-bat1'
        if (Test-Path -LiteralPath $battlePreset -PathType Container) {
            CopyImportTree $battlePreset (Join-Path $stagedFf7 'hext')
        }
        [ordered]@{
            id='traditional-cht-1.47'; displayName='Traditional Chinese FFNx v1.47';
            importedAtUtc=[DateTimeOffset]::UtcNow.ToString('O'); sourceName=(Split-Path -Leaf $originalSource);
            status='imported'; excluded=@('7th_iro','*.htm','*.png tutorials','vcredist installers')
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stagedPack 'language-pack.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $stagedPack 'README.txt') -Value 'Imported Traditional Chinese FFNx resources. The installer uses only ff7/direct, override, hext, mods and msjh_bd font resources.' -Encoding UTF8
        if (-not (TestLanguageFf7Root $stagedFf7)) { throw '暂存语言模块校验失败，旧语言模块未被替换。' }

        $backup = $null
        try {
            if (Test-Path -LiteralPath $pack -PathType Container) {
                $backup = Join-Path $StateRoot ("language-backups\{0}\{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$packId)
                CopyImportTree $pack $backup
                Remove-Item -LiteralPath $pack -Recurse -Force
                Write-Host "旧语言模块已备份: $backup" -ForegroundColor DarkGray
            }
            Move-Item -LiteralPath $stagedPack -Destination $pack
        } catch {
            if ($backup -and (Test-Path -LiteralPath $backup -PathType Container)) {
                if (Test-Path -LiteralPath $pack) { Remove-Item -LiteralPath $pack -Recurse -Force }
                CopyImportTree $backup $pack
            }
            throw
        }
        Set-Content -LiteralPath $SelectedLanguagePath -Value $packId -Encoding UTF8
        $script:LanguageImported = $true
        $script:ImportedLanguageSource = $originalSource
        $script:ImportedLanguageBackup = $backup
        $script:ImportedLanguageBackupContainsPack = $true
        $script:ImportedLanguageTarget = $pack
        Write-Host "繁体中文语言包导入完成: $pack" -ForegroundColor Green
    } finally {
        if ($temporary -and (Test-Path -LiteralPath $temporary)) {
            Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($moduleStaging -and (Test-Path -LiteralPath $moduleStaging)) {
            Remove-Item -LiteralPath $moduleStaging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function GetPeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE file: $Path" }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Invalid PE signature: $Path" }
        $machine = $reader.ReadUInt16()
        if ($machine -eq 0x014C) { return 'x86' }
        if ($machine -eq 0x8664) { return 'x64' }
        return ('0x{0:X4}' -f $machine)
    } finally { $reader.Dispose(); $stream.Dispose() }
}

function FindFfnxFilesRoot([string]$SourceRoot) {
    $root = FullPath $SourceRoot
    $candidates = New-Object Collections.Generic.List[string]
    $directories = @($root) + @(Get-ChildItem -LiteralPath $root -Recurse -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)
    foreach ($directory in $directories) {
        $ok = $true
        foreach ($name in @('AF3DN.P','AF4DN.P','FFNx.toml','COPYING.TXT')) {
            if (-not (Test-Path -LiteralPath (Join-Path $directory $name) -PathType Leaf)) { $ok = $false; break }
        }
        if ($ok) { $candidates.Add((FullPath $directory)) }
    }
    $unique = @($candidates | Sort-Object -Unique)
    if ($unique.Count -eq 1) { return $unique[0] }
    if ($unique.Count -eq 0) { throw '无法识别 FFNx 模块。需要官方 FFNx-Steam 包中的 AF3DN.P、AF4DN.P、FFNx.toml 和 COPYING.TXT。' }
    throw 'FFNx 导入包内存在多个运行时目录，请只保留一个 FFNx-Steam 模块。'
}

function GetAsciiMarkerCount([string]$Path, [string]$Marker) {
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))
    [regex]::Matches($text,[regex]::Escape($Marker)).Count
}

function ReplaceAsciiOnce([string]$Path, [string]$Before, [string]$After) {
    if ($Before.Length -ne $After.Length) { throw 'FFNx binary marker replacement must preserve length.' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $old = [Text.Encoding]::ASCII.GetBytes($Before)
    $new = [Text.Encoding]::ASCII.GetBytes($After)
    $matches = New-Object Collections.Generic.List[int]
    for ($i = 0; $i -le $bytes.Length - $old.Length; $i++) {
        $same = $true
        for ($j = 0; $j -lt $old.Length; $j++) {
            if ($bytes[$i + $j] -ne $old[$j]) { $same = $false; break }
        }
        if ($same) { $matches.Add($i); $i += $old.Length - 1 }
    }
    if ($matches.Count -ne 1) { throw "Expected one FFNx adapter marker, found $($matches.Count)." }
    [Array]::Copy($new,0,$bytes,$matches[0],$new.Length)
    [IO.File]::WriteAllBytes($Path,$bytes)
}

function AssertFfnxRuntime([string]$FfnxRoot, [switch]$AllowUpstream) {
    $root = FullPath $FfnxRoot
    foreach ($name in @('AF3DN.P','AF4DN.P','FFNx.toml','COPYING.TXT')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) { throw "FFNx runtime is missing $name below $root" }
    }
    $af3 = Join-Path $root 'AF3DN.P'
    $af4 = Join-Path $root 'AF4DN.P'
    $version = [string](Get-Item -LiteralPath $af3).VersionInfo.FileVersion
    $machine = GetPeMachine $af3
    $af3Hash = HashFile $af3
    $af4Hash = HashFile $af4
    if ($version -ne $ExpectedFfnxVersion) { throw "Unsupported FFNx version $version. This candidate is verified only with FFNx $ExpectedFfnxVersion." }
    if ($machine -ne 'x86') { throw "Unsupported FFNx architecture $machine. FF7 ff7_en.exe requires x86 FFNx-Steam." }
    if ($af4Hash -ne $ExpectedAf4dnSha256) { throw "Unexpected AF4DN.P hash: $af4Hash" }
    $allowedHashes = @($ExpectedFfnxPatchedSha256)
    if ($AllowUpstream) { $allowedHashes += $ExpectedFfnxUpstreamSha256 }
    if ($af3Hash -notin $allowedHashes) { throw "Unexpected FFNx AF3DN.P hash: $af3Hash" }
    [pscustomobject]@{ Root=$root; Version=$version; Architecture=$machine; AF3DN=$af3Hash; AF4DN=$af4Hash }
}

function ImportFfnxRuntime {
    $originalSource = FindImportSource 'ffnx'
    if ([string]::IsNullOrWhiteSpace([string]$originalSource)) {
        $existing = AssertFfnxRuntime (Join-Path $RuntimeRoot 'ffnx')
        Write-Host '没有发现外部 FFNx 模块，这不是错误。' -ForegroundColor Yellow
        Write-Host "当前包已内置并验证 FFNx $($existing.Version) $($existing.Architecture)。" -ForegroundColor Green
        Write-Host '直接返回菜单安装即可；只有更新或恢复 FFNx 时才需要这个导入选项。' -ForegroundColor Cyan
        Write-Host "如需导入，请把一个 FFNx-Steam ZIP 或解压目录放入: $(Join-Path $PatchRoot 'imports\ffnx')" -ForegroundColor DarkGray
        return
    }
    AssertImportCanChangeModules
    $source = $originalSource
    $temporary = $null
    $stagingRoot = $null
    try {
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and (Test-ArchiveFile $source)) {
            $temporary = Join-Path $StateRoot ('imports\ffnx-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            New-Item -ItemType Directory -Path $temporary -Force | Out-Null
            Expand-ImportArchive $source $temporary 'FFNx 模块'
            $source = $temporary
        }
        $ffnxSource = FindFfnxFilesRoot $source
        $sourceInfo = AssertFfnxRuntime $ffnxSource -AllowUpstream
        Write-Host "检测到 FFNx $($sourceInfo.Version) $($sourceInfo.Architecture)" -ForegroundColor Cyan
        Write-Host "AF3DN.P SHA-256: $($sourceInfo.AF3DN)" -ForegroundColor DarkGray

        $stagingRoot = Join-Path $StateRoot ('runtime-imports\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $stagedFfnx = Join-Path $stagingRoot 'ffnx'
        New-Item -ItemType Directory -Path $stagedFfnx -Force | Out-Null
        foreach ($name in @('AF3DN.P','AF4DN.P','COPYING.TXT','FFNx.toml')) {
            Copy-Item -LiteralPath (Join-Path $ffnxSource $name) -Destination (Join-Path $stagedFfnx $name) -Force
        }
        foreach ($name in @('ambient','hext','lighting','music','sfx','shaders','time','vibrate','voice')) {
            $tree = Join-Path $ffnxSource $name
            if (Test-Path -LiteralPath $tree -PathType Container) { CopyImportTree $tree (Join-Path $stagedFfnx $name) }
        }

        $bridgeSha1 = (Get-FileHash -LiteralPath (Join-Path $RuntimeRoot 'bridge\steam_api.dll') -Algorithm SHA1).Hash.ToLowerInvariant()
        $stagedAf3 = Join-Path $stagedFfnx 'AF3DN.P'
        if ((GetAsciiMarkerCount $stagedAf3 $OfficialSteamApiSha1) -eq 1) {
            ReplaceAsciiOnce $stagedAf3 $OfficialSteamApiSha1 $bridgeSha1
            Write-Host '已为 FFNx 应用可复现的 GOG 适配桥 SHA-1 白名单补丁。' -ForegroundColor Cyan
        } elseif ((GetAsciiMarkerCount $stagedAf3 $bridgeSha1) -ne 1) {
            throw 'FFNx AF3DN.P neither contains the upstream Steam marker nor this package bridge marker.'
        }
        $stagedInfo = AssertFfnxRuntime $stagedFfnx
        if ($stagedInfo.AF3DN -ne $ExpectedFfnxPatchedSha256) { throw "Patched FFNx hash is not the verified candidate hash: $($stagedInfo.AF3DN)" }

        $target = Join-Path $RuntimeRoot 'ffnx'
        if (Test-Path -LiteralPath $target -PathType Container) {
            $backup = Join-Path $StateRoot ('runtime-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '\ffnx')
            CopyImportTree $target $backup
            Remove-Item -LiteralPath $target -Recurse -Force
            Write-Host "旧 FFNx 模块已备份: $backup" -ForegroundColor DarkGray
        }
        Move-Item -LiteralPath $stagedFfnx -Destination $target
        [ordered]@{
            format='ffnx-gog-runtime-module-v1'; packageVersion=$PackageVersion; upstreamProject='https://github.com/julianxhokaxhiu/FFNx';
            upstreamVersion=$ExpectedFfnxVersion; upstreamCommit='7b7799027a02ce279a34e4ecc69bd8c676430a53';
            upstreamSourceArchive='https://github.com/julianxhokaxhiu/FFNx/archive/7b7799027a02ce279a34e4ecc69bd8c676430a53.zip';
            architecture='x86'; importedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');
            sourceName=(Split-Path -Leaf $originalSource); upstreamAF3DNSha256=$ExpectedFfnxUpstreamSha256;
            installedAF3DNSha256=$ExpectedFfnxPatchedSha256; bridgeAdapterSha1=$bridgeSha1;
            modification='The upstream Valve steam_api.dll SHA-1 allowlist marker is replaced with the packaged GOG adapter SHA-1.'
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $RuntimeModulePath -Encoding UTF8
        Write-Host "FFNx 模块导入完成: $target" -ForegroundColor Green
        RemoveImportedSource $originalSource
    } finally {
        if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
        if ($stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function ClearLogs {
    $logRoot = Join-Path $PatchRoot 'logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $keep = $null
    if (-not [string]::IsNullOrWhiteSpace($KeepLog)) { $keep = FullPath $KeepLog }
    $removed = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $logRoot -Recurse -File -Filter '*.log')) {
        if ($keep -and ((FullPath $file.FullName) -eq $keep)) { continue }
        Remove-Item -LiteralPath $file.FullName -Force
        $removed++
    }
    Write-Host "已清理安装器日志 $removed 个。" -ForegroundColor Green
    if ($keep) { Write-Host "当前日志已保留: $keep" -ForegroundColor DarkGray }
}

function GetSourceWorking([string]$PackRoot) {
    $ff7 = ChildPath $PackRoot 'ff7'
    $nested = Join-Path $ff7 'workingdir'
    if (Test-Path -LiteralPath $nested -PathType Container) { return FullPath $nested }
    FullPath $ff7
}

function AddPlan([hashtable]$Plan, [string]$Source, [string]$Target) {
    $sourcePath = FullPath $Source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Language/runtime source is missing: $sourcePath" }
    $targetRelative = $Target.Replace([string][char]92, [string][char]47)
    if ($targetRelative -match '(^|/)\.\.?(/|$)' -or -not $targetRelative.StartsWith('ff7/workingdir/', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Install target is outside ff7/workingdir: $targetRelative"
    }
    $Plan[$targetRelative] = $sourcePath
}

function AddTreePlan([hashtable]$Plan, [string]$SourceRoot, [string]$TargetRoot) {
    $source = FullPath $SourceRoot
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File)) {
        $relative = $file.FullName.Substring($source.Length).TrimStart([char[]]@([char]92,[char]47))
        AddPlan $Plan $file.FullName (($TargetRoot.TrimEnd([char]47)) + '/' + $relative.Replace([string][char]92, [string][char]47))
    }
}

function AddLanguageTreePlan([hashtable]$Plan, [string]$SourceRoot) {
    $source = FullPath $SourceRoot
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return }
    $override = Join-Path $source 'override'
    if (Test-Path -LiteralPath $override -PathType Container) {
        foreach ($name in @('battle','kernel','movies')) {
            $legacy = Join-Path $override $name
            if (Test-Path -LiteralPath $legacy -PathType Container) {
                AddTreePlan $Plan $legacy ('ff7/workingdir/override/lang-en/' + $name)
            }
        }
        foreach ($child in @(Get-ChildItem -LiteralPath $override -Force)) {
            if (-not $child.PSIsContainer) { continue }
            switch ($child.Name.ToLowerInvariant()) {
                'window' {
                    # FFNx reads the rerelease window resource from the kernel override path.
                    AddTreePlan $Plan $child.FullName 'ff7/workingdir/override/kernel'
                    continue
                }
                'movies-skip' {
                    # The patch's optional logo skip file is an override/movies resource.
                    AddTreePlan $Plan $child.FullName 'ff7/workingdir/override/movies'
                    continue
                }
                'battle' { continue }
                'kernel' { continue }
                'movies' { continue }
                default { AddTreePlan $Plan $child.FullName ('ff7/workingdir/override/' + $child.Name) }
            }
        }
    }
    foreach ($name in @('direct','hext','mods')) {
        $tree = Join-Path $source $name
        if (Test-Path -LiteralPath $tree -PathType Container) {
            AddTreePlan $Plan $tree ('ff7/workingdir/' + $name)
        }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $source -File)) {
        AddPlan $Plan $file.FullName ('ff7/workingdir/' + $file.Name)
    }
}

function GetRuntimeRoot {
    if (Test-Path -LiteralPath (Join-Path $RuntimeRoot 'ffnx') -PathType Container) {
        $null = AssertFfnxRuntime (Join-Path $RuntimeRoot 'ffnx')
        return FullPath $RuntimeRoot
    }
    $fallback = Join-Path $PatchRoot 'test-packages\FFNx-GOG-Traditional-CHT-Two-Stage-Candidate-0.5.1\payload'
    if (Test-Path -LiteralPath (Join-Path $fallback 'ffnx') -PathType Container) {
        $null = AssertFfnxRuntime (Join-Path $fallback 'ffnx')
        return FullPath $fallback
    }
    throw "FFNx runtime payload is missing. Import the verified module through imports\ffnx or restore $RuntimeRoot\ffnx."
}

function GetPlan([string]$Root, [string]$PackRoot) {
    $working = GetWorkingRoot $Root
    $runtime = GetRuntimeRoot
    $sourceFf7 = ChildPath $PackRoot 'ff7'
    $sourceWorking = GetSourceWorking $PackRoot
    $markers = @('direct','override','hext','mods','FFNx.toml')
    $hasFfnxTree = @($markers | Where-Object { ((Test-Path -LiteralPath (Join-Path $sourceFf7 $_)) -or (Test-Path -LiteralPath (Join-Path $sourceWorking $_))) }).Count -gt 0
    if ((Test-Path -LiteralPath (Join-Path $sourceFf7 'data') -PathType Container) -and -not $hasFfnxTree) {
        throw "This language pack is a legacy data replacement (data/*.lgp). Convert it to FFNx override/direct resources first: $PackRoot"
    }
    $plan = @{}
    AddTreePlan $plan (Join-Path $runtime 'ffnx') 'ff7/workingdir'
    $baseTraditional = Join-Path $runtime 'traditional/runtime'
    AddTreePlan $plan $baseTraditional 'ff7/workingdir'
    AddLanguageTreePlan $plan $sourceWorking
    if ($sourceWorking -ne $sourceFf7) {
        foreach ($child in @(Get-ChildItem -LiteralPath $sourceFf7 -Force)) {
            if ($child.Name -ne 'workingdir' -and $child.PSIsContainer) {
                AddLanguageTreePlan $plan $sourceFf7
                break
            }
        }
    }

    $gogApiCandidates = @((Join-Path $Root 'steam_api.dll'), (Join-Path $Root 'ff7\steam_api.dll'))
    $gogApi = @($gogApiCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($gogApi.Count -eq 0) { throw "GOG steam_api.dll is missing from the game root; refusing to replace an unknown API chain." }
    AddPlan $plan $gogApi[0] 'ff7/workingdir/steam_api_gog.dll'

    $galaxyCandidates = @((Join-Path $Root 'Galaxy.dll'), (Join-Path $Root 'ff7\Galaxy.dll'))
    $galaxy = @($galaxyCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($galaxy.Count -gt 0) { AddPlan $plan $galaxy[0] 'ff7/workingdir/Galaxy.dll' }
    $configCandidates = @((Join-Path $Root 'GalaxyConfig.json'), (Join-Path $Root 'ff7\GalaxyConfig.json'))
    $config = @($configCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($config.Count -gt 0) { AddPlan $plan $config[0] 'ff7/workingdir/GalaxyConfig.json' }

    $bridge = Join-Path $runtime 'bridge\steam_api.dll'
    if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) { throw "GOG bridge is missing: $bridge" }
    AddPlan $plan $bridge 'ff7/workingdir/steam_api.dll'

    $audioSource = Join-Path $working 'data\sound\audio.dat'
    if (Test-Path -LiteralPath $audioSource -PathType Leaf) { AddPlan $plan $audioSource 'ff7/workingdir/data/music/audio.dat' }

    [pscustomobject]@{ Working = $working; Plan = $plan; Runtime = $runtime; Pack = $PackRoot }
}

function WriteJson([string]$Path, $Value) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function CopyVerified([string]$Source, [string]$Destination, [string]$ExpectedHash) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    $actual = HashFile $Destination
    if ($actual -ne $ExpectedHash) { throw "Hash mismatch after copy: $Destination (expected $ExpectedHash, got $actual)" }
}

function AssertNoRunningGame([string]$Root) {
    $rootPath = (FullPath $Root).TrimEnd([char[]]@([char]92,[char]47)) + ([string][char]92)
    $names = @('FFVII','FFVII_LAUNCHER','ff7','ff7_en','7th Heaven')
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $names -contains $_.ProcessName })) {
        try {
            if ((FullPath $process.Path).StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) { throw "Close running process $($process.ProcessName) (PID $($process.Id)) first." }
        } catch [System.Management.Automation.PropertyNotFoundException] { }
        catch [System.ComponentModel.Win32Exception] { }
    }
}

function Install([string]$Root, [string]$PackRoot) {
    if (-not (IsAdministrator)) { throw 'Administrator privileges are required to install into the GOG directory. Re-run this command as Administrator.' }
    AssertNoRunningGame $Root
    $details = GetPlan $Root $PackRoot
    $plan = $details.Plan
    $id = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = if ([string]::IsNullOrWhiteSpace($BackupRoot)) { Join-Path $PatchRoot "backups\$id" } else { FullPath $BackupRoot }
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        $existingState = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$existingState.status -notin @('Restored','FailedRolledBack')) {
            throw "An active install manifest already exists ($($existingState.status)): $StatePath. Run Rollback first."
        }
    }
    $staging = Join-Path $StateRoot "staging\$id"
    New-Item -ItemType Directory -Path $backup,$staging -Force | Out-Null
    $items = @()
    foreach ($entry in $plan.GetEnumerator()) {
        $targetRel = [string]$entry.Key; $source = [string]$entry.Value
        $target = ChildPath $Root $targetRel
        $sourceHash = HashFile $source
        $backupRel = $targetRel
        $backupPath = ChildPath $backup $backupRel
        $existed = Test-Path -LiteralPath $target -PathType Leaf
        $originalHash = $null
        $originalSize = 0
        if ($existed) {
            $originalHash = HashFile $target; $originalSize = (Get-Item -LiteralPath $target).Length
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $backupPath -Force
            if ((HashFile $backupPath) -ne $originalHash) { throw "Backup verification failed: $targetRel" }
        }
        $stagePath = ChildPath $staging $targetRel
        CopyVerified $source $stagePath $sourceHash
        $items += [ordered]@{ gameRelativePath=$targetRel; sourcePath=$source; sourceSha256=$sourceHash; sourceSize=(Get-Item -LiteralPath $source).Length; stagedPath=$stagePath; existedBefore=$existed; originalSha256=$originalHash; originalSize=$originalSize; backupRelativePath=if($existed){$backupRel}else{$null}; installedSha256=$sourceHash }
    }
    $state = [ordered]@{ format='ffnx-gog-real-install-v1'; status='Applying'; version=$PackageVersion; installId=$id; gameRoot=(FullPath $Root); languagePack=$PackRoot; gogAchievementBridge='installed-with-ffnx-runtime'; backupRoot=$backup; createdAtUtc=[DateTimeOffset]::UtcNow.ToString('O'); items=$items }
    WriteJson $StatePath $state
    try {
        foreach ($item in $items) { CopyVerified ([string]$item.stagedPath) (ChildPath $Root ([string]$item.gameRelativePath)) ([string]$item.installedSha256) }
        $state.status = 'Installed'; $state.updatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O'); WriteJson $StatePath $state
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "繁体中文和 GOG 成就桥已安装，今后可直接运行启动文件。" -ForegroundColor Green
        Write-Host "Backup: $backup" -ForegroundColor Cyan
    } catch {
        Write-Host "Install failed; restoring the recorded backups..." -ForegroundColor Yellow
        foreach ($item in @($items | Sort-Object { $_.gameRelativePath } -Descending)) {
            $target = ChildPath $Root ([string]$item.gameRelativePath)
            if ([bool]$item.existedBefore) { Copy-Item -LiteralPath (ChildPath $backup ([string]$item.backupRelativePath)) -Destination $target -Force }
            elseif (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
        }
        $state.status = 'FailedRolledBack'; $state.error = $_.Exception.Message; WriteJson $StatePath $state
        throw
    } finally { if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Rollback([string]$Root) {
    if (-not (IsAdministrator)) { throw 'Administrator privileges are required to roll back the GOG directory.' }
    AssertNoRunningGame $Root
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { throw "Install manifest is missing: $StatePath" }
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ((FullPath ([string]$state.gameRoot)) -ne (FullPath $Root)) { throw 'Install manifest belongs to a different game root.' }
    if ([string]$state.status -notin @('Installed','FailedRolledBack')) { throw "Install state is not restorable: $($state.status)" }
    foreach ($item in @($state.items | Sort-Object gameRelativePath -Descending)) {
        $target = ChildPath $Root ([string]$item.gameRelativePath)
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $current = HashFile $target
            if ($current -ne [string]$item.installedSha256 -and -not $Force) {
                throw "Refusing to overwrite a file changed after installation: $($item.gameRelativePath). Pass -Force only after reviewing it."
            }
        }
        if ([bool]$item.existedBefore) {
            $backup = ChildPath ([string]$state.backupRoot) ([string]$item.backupRelativePath)
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "Backup is missing: $backup" }
            if ((HashFile $backup) -ne [string]$item.originalSha256) { throw "Backup hash changed: $backup" }
            Copy-Item -LiteralPath $backup -Destination $target -Force
        } elseif (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
    }
    $state.status = 'Restored'; $state.updatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O'); WriteJson $StatePath $state
    Write-Host "Rollback complete. Backup retained at $($state.backupRoot)" -ForegroundColor Green
}

function TryReuseInstall([string]$Root, [string]$PackRoot) {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return $false }
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$state.status -ne 'Installed') { return $false }
    if ((FullPath ([string]$state.gameRoot)) -ne (FullPath $Root)) { return $false }
    if ((FullPath ([string]$state.languagePack)) -ne (FullPath $PackRoot)) { return $false }

    $details = GetPlan $Root $PackRoot
    $desired = @{}
    foreach ($entry in $details.Plan.GetEnumerator()) {
        $desired[[string]$entry.Key] = HashFile ([string]$entry.Value)
    }
    if (@($state.items).Count -ne $desired.Count) {
        throw 'The installed file set belongs to a different package revision. Roll back once, then install again.'
    }
    foreach ($item in @($state.items)) {
        $relativePath = [string]$item.gameRelativePath
        if (-not $desired.ContainsKey($relativePath) -or $desired[$relativePath] -ne [string]$item.installedSha256) {
            throw "The installed file set differs from this package revision: $relativePath. Roll back once, then install again."
        }
        $target = ChildPath $Root ([string]$item.gameRelativePath)
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Installed file is missing; run Rollback and Install again: $($item.gameRelativePath)"
        }
        if ((HashFile $target) -ne [string]$item.installedSha256) {
            throw "Installed file changed after repair; run Rollback before reinstalling: $($item.gameRelativePath)"
        }
    }
    $state.version = $PackageVersion
    $state.updatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    $state | Add-Member -NotePropertyName lastVerifiedAtUtc -NotePropertyValue $state.updatedAtUtc -Force
    WriteJson $StatePath $state
    Write-Host '现有安装校验通过，无需重复复制文件。' -ForegroundColor Cyan
    return $true
}

function LaunchGame([string]$Root, [switch]$AchievementMode) {
    $working = GetWorkingRoot $Root
    $candidates = @((Join-Path $working 'ff7_en.exe'), (Join-Path $Root 'ff7_en.exe'), (Join-Path $Root 'FFVII.exe'))
    $exe = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($exe.Count -eq 0) { throw "No launchable FF7 executable found below $Root" }
    $process = Start-Process -FilePath $exe[0] -WorkingDirectory (Split-Path -Parent $exe[0]) -PassThru
    Write-Host "Game started: PID $($process.Id)" -ForegroundColor Green
    Write-Host "FFNx log: $(Join-Path $working 'FFNx.log')"
    Write-Host "GOG bridge log: $(Join-Path $working 'FFNxGOGBridge.log')"
    if ($AchievementMode) { Write-Host 'GOG 成就链路已启用：游戏会通过 Galaxy/FFNx 桥接运行，无需每次单独验证。' -ForegroundColor Cyan }
}

function Validate([string]$Root, [string]$PackRoot) {
    $details = GetPlan $Root $PackRoot
    $ffnx = AssertFfnxRuntime (Join-Path $details.Runtime 'ffnx')
    $items = @($details.Plan.GetEnumerator() | ForEach-Object { [ordered]@{ target=$_.Key; source=$_.Value; sha256=(HashFile $_.Value) } })
    WriteJson (Join-Path $StateRoot 'last-plan.json') ([ordered]@{ format='ffnx-gog-plan-v1'; packageVersion=$PackageVersion; gameRoot=$Root; languagePack=$PackRoot; ffnxVersion=$ffnx.Version; ffnxArchitecture=$ffnx.Architecture; ffnxAF3DNSha256=$ffnx.AF3DN; itemCount=$items.Count; items=$items })
    Write-Host "Valid FFNx language pack: $(Split-Path -Leaf $PackRoot)" -ForegroundColor Green
    Write-Host "Valid FFNx runtime: $($ffnx.Version) $($ffnx.Architecture)" -ForegroundColor Green
    Write-Host "Planned files: $($items.Count)"
}

$resolvedGameRoot = if ([string]::IsNullOrWhiteSpace($GameRoot)) { Split-Path -Parent $PatchRoot } else { $GameRoot }
$resolvedGameRoot = FullPath $resolvedGameRoot
if ($Mode -in @('Import','ImportLanguage')) {
    $activeState = GetActiveInstallState
    if ($activeState -and -not (IsAdministrator)) {
        throw 'Administrator privileges are required to update a language module used by the installed game.'
    }
    $previousSelected = $null
    if ($activeState) {
        if (Test-Path -LiteralPath $SelectedLanguagePath -PathType Leaf) {
            $previousSelected = (Get-Content -LiteralPath $SelectedLanguagePath -Raw -Encoding UTF8).Trim()
        }
        if ([string]::IsNullOrWhiteSpace([string]$previousSelected)) {
            $previousSelected = Split-Path -Leaf ([string]$activeState.languagePack)
        }
    }
    ImportTraditionalLanguagePack
    if ($script:LanguageImported -and $activeState) {
        $installedRoot = AssertGameRoot ([string]$activeState.gameRoot)
        try {
            Write-Host '检测到现有安装，正在自动回滚旧模块并应用新语言包...' -ForegroundColor Cyan
            Rollback $installedRoot
            $newPack = FindLanguagePack
            Install $installedRoot $newPack
            Write-Host '语言包已导入，并已自动更新到当前游戏安装。' -ForegroundColor Green
        } catch {
            $currentState = GetActiveInstallState
            if ($currentState) {
                $sameTarget = (FullPath ([string]$script:ImportedLanguageTarget)) -eq (FullPath ([string]$activeState.languagePack))
                if ($sameTarget -and $script:ImportedLanguageBackup -and (Test-Path -LiteralPath $script:ImportedLanguageBackup -PathType Container)) {
                    if (Test-Path -LiteralPath $script:ImportedLanguageTarget) {
                        Remove-Item -LiteralPath $script:ImportedLanguageTarget -Recurse -Force
                    }
                    if ($script:ImportedLanguageBackupContainsPack) {
                        CopyImportTree $script:ImportedLanguageBackup $script:ImportedLanguageTarget
                    } else {
                        CopyImportTree $script:ImportedLanguageBackup (Join-Path $script:ImportedLanguageTarget 'ff7')
                    }
                    Write-Host '自动更新失败，已恢复更新前的语言模块。' -ForegroundColor Yellow
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$previousSelected)) {
                    Set-Content -LiteralPath $SelectedLanguagePath -Value $previousSelected -Encoding UTF8
                }
            }
            throw
        }
    }
    if ($script:LanguageImported -and $script:ImportedLanguageSource) {
        RemoveImportedSource $script:ImportedLanguageSource
    }
    exit 0
}
if ($Mode -eq 'ImportFfnx') { ImportFfnxRuntime; exit 0 }
if ($Mode -eq 'ClearLogs') { ClearLogs; exit 0 }
$resolvedGameRoot = AssertGameRoot $resolvedGameRoot
if ($Mode -eq 'Rollback') { Rollback $resolvedGameRoot; exit 0 }
$pack = FindLanguagePack
if ($Mode -eq 'Validate') { Validate $resolvedGameRoot $pack; exit 0 }
if ($Mode -in @('Install','Chinese','GogAchievement')) {
    $reused = TryReuseInstall $resolvedGameRoot $pack
    if (-not $reused) { Install $resolvedGameRoot $pack }
}
if (-not $NoLaunch -and $Mode -in @('Chinese','GogAchievement')) { LaunchGame $resolvedGameRoot ($Mode -eq 'GogAchievement') }
