# ==============================================================================
# Nova Systems Programming Language - Windows Toolchain Installer
# Installs novac.exe, orbit.exe, standard library, and C99 runtime
# Supports both local archive installation and online one-line install:
#   irm https://raw.githubusercontent.com/novasystems-dev/nova/master/install.ps1 | iex
# ==============================================================================
param(
    [string]$Prefix = "$HOME\.nova",
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  NOVA SYSTEMS PROGRAMMING LANGUAGE - WINDOWS INSTALLER" -ForegroundColor Cyan
Write-Host "  Target Prefix: $Prefix" -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor Cyan

$BinDir = Join-Path $Prefix "bin"
$LibDir = Join-Path $Prefix "lib"
$RuntimeDir = Join-Path $LibDir "runtime"
$StdDir = Join-Path $LibDir "std"

# Ensure target directories exist
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $StdDir | Out-Null

$CurrentScriptDir = $PSScriptRoot
if (-not $CurrentScriptDir) {
    $CurrentScriptDir = Get-Location
}

# Determine if we are running inside an extracted release archive or need to download
$LocalBinExists = Test-Path (Join-Path $CurrentScriptDir "bin\novac.exe") -or (Test-Path (Join-Path $CurrentScriptDir "bin\novac"))

if (-not $LocalBinExists) {
    Write-Host "-> Fetching latest Windows binary distribution from GitHub Releases..." -ForegroundColor Yellow
    $ZipUrl = "https://github.com/novasystems-dev/nova/releases/latest/download/nova-windows-x86_64.zip"
    $TempZip = Join-Path $env:TEMP "nova-windows-install.zip"
    $TempExtract = Join-Path $env:TEMP "nova-windows-extracted"
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Host "   Downloading from: $ZipUrl" -ForegroundColor Gray
        Invoke-WebRequest -Uri $ZipUrl -OutFile $TempZip -UseBasicParsing
        if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract }
        Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
        $CurrentScriptDir = $TempExtract
        # Check if subfolder was created
        $SubFolder = Get-ChildItem -Directory -Path $TempExtract | Where-Object { Test-Path (Join-Path $_.FullName "bin") } | Select-Object -First 1
        if ($SubFolder) {
            $CurrentScriptDir = $SubFolder.FullName
        }
    }
    catch {
        Write-Host "   Falling back to tar.gz asset if .zip is unavailable..." -ForegroundColor Gray
        $TarUrl = "https://github.com/novasystems-dev/nova/releases/latest/download/nova-dev-full-windows-x86_64.tar.gz"
        $TempTar = Join-Path $env:TEMP "nova-windows-install.tar.gz"
        Invoke-WebRequest -Uri $TarUrl -OutFile $TempTar -UseBasicParsing
        tar -xzf $TempTar -C $env:TEMP
        $SubDir = Get-ChildItem -Directory -Path $env:TEMP -Filter "nova-dev-full-*" | Select-Object -First 1
        if ($SubDir) { $CurrentScriptDir = $SubDir.FullName }
    }
}

Write-Host "-> Installing binaries into $BinDir..." -ForegroundColor Green
$BinFiles = @("novac.exe", "orbit.exe", "nova-runner.exe", "nova-fmt.exe", "nova-lint.exe", "nova-doc.exe", "novac", "orbit", "nova-runner")
foreach ($bf in $BinFiles) {
    $src = Join-Path $CurrentScriptDir "bin\$bf"
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $BinDir -Force
        Write-Host "   Installed: $bf" -ForegroundColor DarkGray
    }
}

Write-Host "-> Installing runtime headers into $RuntimeDir..." -ForegroundColor Green
$RuntimeSrc = Join-Path $CurrentScriptDir "runtime"
if (Test-Path $RuntimeSrc) {
    Copy-Item -Path (Join-Path $RuntimeSrc "*") -Destination $RuntimeDir -Recurse -Force
}

Write-Host "-> Installing standard library into $StdDir..." -ForegroundColor Green
$StdSrc = Join-Path $CurrentScriptDir "std"
if (Test-Path $StdSrc) {
    Copy-Item -Path (Join-Path $StdSrc "*.nova") -Destination $StdDir -Force
}

Write-Host "-> Configuring User Environment Variables..." -ForegroundColor Green
# 1. Set NOVA_RUNTIME
[Environment]::SetEnvironmentVariable("NOVA_RUNTIME", $RuntimeDir, "User")
$env:NOVA_RUNTIME = $RuntimeDir

# 2. Add BinDir to User PATH permanently if not already present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $UserPath) { $UserPath = "" }
$Paths = $UserPath -split ";" | Where-Object { $_ -ne "" }
if ($Paths -notcontains $BinDir) {
    $NewUserPath = "$UserPath;$BinDir".TrimStart(";")
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
    Write-Host "   Added $BinDir to User PATH permanently." -ForegroundColor Cyan
} else {
    Write-Host "   $BinDir is already in User PATH." -ForegroundColor DarkGray
}

# Update current session PATH
if ($env:Path -notlike "*$BinDir*") {
    $env:Path = "$BinDir;$env:Path"
}

Write-Host "`n-> Checking Toolchain Prerequisites:" -ForegroundColor Yellow
$GccPath = Get-Command gcc -ErrorAction SilentlyContinue
if ($GccPath) {
    Write-Host "   [OK] GCC found: $($GccPath.Source)" -ForegroundColor Green
} else {
    Write-Host "   [!] Warning: 'gcc' not found in PATH." -ForegroundColor DarkYellow
    Write-Host "       Nova requires GCC / Clang (MinGW-w64 or w64devkit) to produce native .exe binaries." -ForegroundColor DarkYellow
    Write-Host "       Install via WinGet: 'winget install MSYS2.MSYS2' or download w64devkit." -ForegroundColor DarkYellow
}

$Z3Path = Get-Command z3 -ErrorAction SilentlyContinue
if ($Z3Path) {
    Write-Host "   [OK] Z3 SMT Solver found: $($Z3Path.Source)" -ForegroundColor Green
} else {
    Write-Host "   [i] Info: 'z3' not found in PATH (Optional, recommended for refinement type verification)." -ForegroundColor DarkGray
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "🎉 NOVA SYSTEMS TOOLCHAIN INSTALLED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "   Location: $Prefix" -ForegroundColor Gray
Write-Host "   Compiler: $BinDir\novac.exe" -ForegroundColor Gray
Write-Host "   Manager : $BinDir\orbit.exe" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Open a new PowerShell or Command Prompt window and try:" -ForegroundColor White
Write-Host "   novac version" -ForegroundColor Yellow
Write-Host "   novac run examples\01_hello.nova" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
