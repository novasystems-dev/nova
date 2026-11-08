@echo off
REM Nova Runtime Desktop Integration Script (Windows)
REM Part of Nova Programming Language v0.31.02
echo ==========================================================
echo   NOVA SYSTEMS - WINDOWS RUNTIME FILE ASSOCIATION (.nova)
echo ==========================================================

REM Check administrative privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [Notice] Requesting elevated association or configuring current user shell...
)

set SCRIPT_DIR=%~dp0
set BIN_DIR=%SCRIPT_DIR%..\bin

echo ==> Associating .nova extension with NovaApp...
assoc .nova=NovaApp >nul 2>&1
ftype NovaApp="%BIN_DIR%\nova-runner.exe" --hold "%%1" %%* >nul 2>&1

echo ==> Adding registry keys for Windows Explorer context menu...
reg add "HKCU\Software\Classes\.nova" /ve /d "NovaApp" /f >nul 2>&1
reg add "HKCU\Software\Classes\NovaApp\shell\open\command" /ve /d "\"%BIN_DIR%\nova-runner.exe\" --hold \"%%1\" %%*" /f >nul 2>&1
reg add "HKCU\Software\Classes\NovaApp\DefaultIcon" /ve /d "\"%SCRIPT_DIR%..\assets\branding\favicon.ico\",0" /f >nul 2>&1

echo ==> Registration complete! Double-clicking any .nova binary will launch it in Nova Runtime.
pause
