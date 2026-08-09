@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 936 >nul
title FFVII GOG + FFNx 中文启动器
cd /d "%~dp0"

if not exist "%~dp0FFNx-GOG-Repair.ps1" (
    echo [错误] 找不到 FFNx-GOG-Repair.ps1。
    pause
    exit /b 2
)
if not exist "%~dp0state\install-manifest.json" (
    echo [提示] 尚未安装繁体中文和 GOG 成就桥。
    echo 请先右键“安裝 繁體中文補丁.cmd”，选择“以管理员身份运行”，再选择 3 或 4。
    echo 当前完整包已内置语言包和 FFNx，无需先执行导入。
    pause
    exit /b 1
)
if not exist "%~dp0logs" md "%~dp0logs" >nul 2>&1
for /f "usebackq tokens=*" %%I in (`powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "STAMP=%%I"
if not defined STAMP set "STAMP=run"
set "LOGFILE=%~dp0logs\launcher-!STAMP!.log"

echo 正在校验已安装文件并启动 GOG 中文版...
echo [%date% %time%] Starting permanent GOG/FFNx launcher>>"!LOGFILE!"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FFNx-GOG-Repair.ps1" -Mode GogAchievement >>"!LOGFILE!" 2>&1
set "RC=!errorlevel!"
echo [%date% %time%] ExitCode: !RC!>>"!LOGFILE!"
if "!RC!"=="0" (
    echo [完成] 游戏已启动，GOG 成就链路已启用。
) else (
    echo [错误] 启动失败，请查看日志：
    echo !LOGFILE!
)
pause
endlocal
exit /b %RC%
