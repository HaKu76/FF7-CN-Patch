@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 936 >nul
title FFVII GOG + FFNx 简体中文一键安装器
cd /d "%~dp0"

rem Run this file with "Run as administrator" before installing or rolling back.
fltmc >nul 2>&1
if errorlevel 1 (
    echo.
    echo ============================================================
    echo [错误] 当前没有管理员权限。
    echo 请右键此文件，选择“以管理员身份运行”。
    echo ============================================================
    pause
    exit /b 740
)

if not exist "%~dp0FFNx-GOG-Repair.ps1" (
    echo.
    echo ============================================================
    echo [错误] 安装器文件不完整。
    echo 找不到 FFNx-GOG-Repair.ps1，请重新解压完整补丁包。
    echo ============================================================
    pause
    exit /b 2
)
if not exist "%~dp0logs" md "%~dp0logs" >nul 2>&1
if not exist "%~dp0imports\language" md "%~dp0imports\language" >nul 2>&1
if not exist "%~dp0imports\ffnx" md "%~dp0imports\ffnx" >nul 2>&1
for /f "usebackq tokens=*" %%I in (`powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"`) do set "STAMP=%%I"
if not defined STAMP set "STAMP=run"
set "LOGFILE=%~dp0logs\one-click-!STAMP!.log"

:menu
cls
echo ============================================================
echo   FFVII GOG + FFNx 简体中文一键安装器 0.7.7
echo ============================================================
echo   游戏目录: %~dp0..
echo   日志文件: !LOGFILE!
echo.
echo   [内置] 繁体中文 v1.47，可直接安装，无需执行导入
echo   [内置] FFNx 1.24.2.26 x86，可直接安装，无需执行导入
echo.
echo   [1] 导入/更新语言包（可选；放入 imports\language）
echo   [2] 导入/更新 FFNx（可选；放入 imports\ffnx）
echo   [3] 安装或校验繁体中文与 GOG 成就桥
echo   [4] 一键安装并启动中文游戏（首次使用推荐）
echo   [5] 启动已安装的 GOG 中文游戏
echo   [6] 回滚到安装前文件
echo   [7] 清除安装器日志
echo   [8] 打开日志目录
echo   [9] 退出
echo.
choice /c 123456789 /n /m "请选择 [1-9]: "
if errorlevel 9 goto :done
if errorlevel 8 (
    start "" "%~dp0logs"
    goto :menu
)
if errorlevel 7 (
    call :clearlogs
    goto :menu
)
if errorlevel 6 (
    call :run "-Mode Rollback"
    goto :menu
)
if errorlevel 5 (
    call :run "-Mode GogAchievement"
    goto :menu
)
if errorlevel 4 (
    call :run "-Mode Chinese"
    goto :menu
)
if errorlevel 3 (
    call :run "-Mode Install -NoLaunch"
    goto :menu
)
if errorlevel 2 (
    echo.
    echo [提示] 正在检查 imports\ffnx。
    echo 如果目录为空，程序会继续使用内置 FFNx，不会报错。
    call :run "-Mode ImportFfnx"
    goto :menu
)
if errorlevel 1 (
    echo.
    echo [提示] 正在检查 imports\language。
    echo 如果目录为空，程序会继续使用内置繁体中文包，不会报错。
    echo 大型 ZIP/RAR 解压可能需要几分钟，窗口请勿关闭。
    call :run "-Mode ImportLanguage"
    goto :menu
)
goto :menu

:run
echo.
echo [处理中] 请稍候，不要关闭此窗口...
echo [%date% %time%] Running: powershell %~1>>"!LOGFILE!"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FFNx-GOG-Repair.ps1" %~1 >>"!LOGFILE!" 2>&1
set "RC=!errorlevel!"
echo [%date% %time%] ExitCode: !RC!>>"!LOGFILE!"
echo.
if "!RC!"=="0" (
    echo ============================================================
    echo [完成] 操作成功完成。
    echo ============================================================
) else (
    echo ============================================================
    echo [错误] 操作失败，未能完成所选功能。
    echo 请将下面的日志文件发送给维护者：
    echo !LOGFILE!
    echo ============================================================
)
pause
exit /b 0

:clearlogs
echo.
echo [处理中] 正在清理旧日志...
echo [%date% %time%] Running: powershell -Mode ClearLogs>>"!LOGFILE!"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FFNx-GOG-Repair.ps1" -Mode ClearLogs -KeepLog "!LOGFILE!" >>"!LOGFILE!" 2>&1
set "RC=!errorlevel!"
echo [%date% %time%] ExitCode: !RC!>>"!LOGFILE!"
echo.
if "!RC!"=="0" (
    echo ============================================================
    echo [完成] 旧日志已经清理。
    echo ============================================================
) else (
    echo ============================================================
    echo [错误] 日志清理失败。
    echo 详细信息：!LOGFILE!
    echo ============================================================
)
pause
exit /b 0

:done
echo 日志目录：%~dp0logs
endlocal
exit /b 0
