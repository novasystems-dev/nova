@echo off
setlocal enabledelayedexpansion

echo ==========================================================
echo   NOVA TOOLCHAIN INSTALLER FOR WINDOWS
echo ==========================================================

where powershell >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] PowerShell is required to run the Nova installer.
    exit /b 1
)

:: Launch GUI Setup Wizard by default if no arguments provided
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "& { & '%~dp0install.ps1' -GUI }"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
)

endlocal
