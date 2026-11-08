# ==============================================================================
# Nova Systems Programming Language - Universal Windows Toolchain Installer
# Features:
#   - Java / VS Code Style Modern GUI Setup Wizard (System.Windows.Forms)
#   - Zero-Dependency Operation: Auto-bundles portable GCC if missing
#   - Full CLI / Headless / Silent support for CI/CD and automation
# Usage:
#   GUI Setup : .\install.bat   (or: powershell .\install.ps1 -GUI)
#   CLI Setup : irm https://raw.githubusercontent.com/novasystems-dev/nova/master/install.ps1 | iex
# ==============================================================================
param(
    [switch]$GUI = $false,
    [switch]$CLI = $false,
    [string]$Prefix = "$HOME\.nova",
    [string]$Version = "latest",
    [switch]$BundleToolchain = $false
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# CORE INSTALLATION LOGIC FUNCTION
# ==============================================================================
function Invoke-NovaInstallCore {
    param(
        [string]$TargetPrefix,
        [bool]$AddPath = $true,
        [bool]$InstallToolchain = $true,
        [System.Action[int, string]]$ProgressCallback = $null
    )

    function Report-Progress([int]$pct, [string]$msg) {
        if ($ProgressCallback) {
            $ProgressCallback.Invoke($pct, $msg)
        } else {
            Write-Host "-> $msg" -ForegroundColor Cyan
        }
    }

    Report-Progress 10 "Initializing installation directories..."
    $BinDir = Join-Path $TargetPrefix "bin"
    $LibDir = Join-Path $TargetPrefix "lib"
    $RuntimeDir = Join-Path $LibDir "runtime"
    $StdDir = Join-Path $LibDir "std"

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    New-Item -ItemType Directory -Force -Path $StdDir | Out-Null

    $CurrentScriptDir = $PSScriptRoot
    if (-not $CurrentScriptDir) {
        $CurrentScriptDir = Get-Location
    }

    $LocalBinExists = Test-Path (Join-Path $CurrentScriptDir "bin\novac.exe") -or (Test-Path (Join-Path $CurrentScriptDir "bin\novac"))

    if (-not $LocalBinExists) {
        Report-Progress 25 "Fetching prebuilt binary release from GitHub..."
        $Tag = "v0.31.02"
        try {
            $Req = [System.Net.WebRequest]::Create("https://github.com/novasystems-dev/nova/releases/latest")
            $Req.AllowAutoRedirect = $false
            $Resp = $Req.GetResponse()
            $Loc = $Resp.GetResponseHeader("Location")
            $TagPart = $Loc.Substring($Loc.LastIndexOf('/') + 1)
            if ($TagPart) { $Tag = $TagPart }
            $Resp.Close()
        } catch {
            $Tag = "v0.31.02"
        }

        $ZipUrl = "https://github.com/novasystems-dev/nova/releases/download/$Tag/nova-dev-full-$Tag-windows-x86_64.zip"
        $TempZip = Join-Path $env:TEMP "nova-windows-install.zip"
        $TempExtract = Join-Path $env:TEMP "nova-windows-extracted"
        
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $ZipUrl -OutFile $TempZip -UseBasicParsing
            if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract }
            Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
            $CurrentScriptDir = $TempExtract
            $SubFolder = Get-ChildItem -Directory -Path $TempExtract | Where-Object { Test-Path (Join-Path $_.FullName "bin") } | Select-Object -First 1
            if ($SubFolder) { $CurrentScriptDir = $SubFolder.FullName }
        }
        catch {
            Report-Progress 35 "Falling back to archive distribution..."
            $TarUrl = "https://github.com/novasystems-dev/nova/releases/download/$Tag/nova-dev-full-$Tag-windows-x86_64.tar.gz"
            $TempTar = Join-Path $env:TEMP "nova-windows-install.tar.gz"
            Invoke-WebRequest -Uri $TarUrl -OutFile $TempTar -UseBasicParsing
            tar -xzf $TempTar -C $env:TEMP
            $SubDir = Get-ChildItem -Directory -Path $env:TEMP -Filter "nova-dev-full-*" | Select-Object -First 1
            if ($SubDir) { $CurrentScriptDir = $SubDir.FullName }
        }
    }

    Report-Progress 50 "Deploying compiler & developer tools..."
    $BinFiles = @("novac.exe", "orbit.exe", "nova-runner.exe", "nova-fmt.exe", "nova-lint.exe", "nova-doc.exe", "nova-repl.exe", "nova-lsp.exe", "novac", "orbit", "nova-runner", "nova-fmt", "nova-lint", "nova-doc", "nova-repl", "nova-lsp")
    foreach ($bf in $BinFiles) {
        $src = Join-Path $CurrentScriptDir "bin\$bf"
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $BinDir -Force
        }
    }

    Report-Progress 65 "Installing Super-Runtime headers and libraries..."
    $RuntimeSrc = Join-Path $CurrentScriptDir "runtime"
    if (Test-Path $RuntimeSrc) {
        Copy-Item -Path (Join-Path $RuntimeSrc "*") -Destination $RuntimeDir -Recurse -Force
    }

    Report-Progress 75 "Deploying Nova Standard Library (std/*.nv)..."
    $StdSrc = Join-Path $CurrentScriptDir "std"
    if (Test-Path $StdSrc) {
        Copy-Item -Path (Join-Path $StdSrc "*") -Destination $StdDir -Recurse -Force
    }

    # Zero-Dependency Fallback: Check if GCC is installed, otherwise download portable toolchain
    $GccPath = Get-Command gcc -ErrorAction SilentlyContinue
    if (-not $GccPath -and $InstallToolchain) {
        Report-Progress 82 "No C compiler detected. Fetching standalone portable MinGW toolchain..."
        $ToolchainDir = Join-Path $TargetPrefix "toolchain"
        $ToolchainBin = Join-Path $ToolchainDir "bin"
        if (-not (Test-Path (Join-Path $ToolchainBin "gcc.exe"))) {
            New-Item -ItemType Directory -Force -Path $ToolchainDir | Out-Null
            $ToolchainZip = Join-Path $env:TEMP "w64devkit-mini.zip"
            $ToolchainUrl = "https://github.com/skeeto/w64devkit/releases/download/v1.20.0/w64devkit-1.20.0.zip"
            try {
                Invoke-WebRequest -Uri $ToolchainUrl -OutFile $ToolchainZip -UseBasicParsing
                Expand-Archive -Path $ToolchainZip -DestinationPath $env:TEMP -Force
                $ExtractedW64 = Join-Path $env:TEMP "w64devkit"
                if (Test-Path $ExtractedW64) {
                    Copy-Item -Path (Join-Path $ExtractedW64 "*") -Destination $ToolchainDir -Recurse -Force
                    Remove-Item -Recurse -Force $ExtractedW64
                }
            } catch {
                # Non-fatal if offline
            }
        }
        if (Test-Path (Join-Path $ToolchainBin "gcc.exe")) {
            Report-Progress 88 "Configuring portable toolchain in environment..."
            $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($UserPath -notlike "*$ToolchainBin*") {
                [Environment]::SetEnvironmentVariable("Path", "$UserPath;$ToolchainBin", "User")
                $env:Path = "$ToolchainBin;$env:Path"
            }
        }
    }

    if ($AddPath) {
        Report-Progress 92 "Registering User Environment Variables (NOVA_RUNTIME, PATH)..."
        [Environment]::SetEnvironmentVariable("NOVA_RUNTIME", $RuntimeDir, "User")
        $env:NOVA_RUNTIME = $RuntimeDir

        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not $UserPath) { $UserPath = "" }
        $Paths = $UserPath -split ";" | Where-Object { $_ -ne "" }
        if ($Paths -notcontains $BinDir) {
            $NewUserPath = "$UserPath;$BinDir".TrimStart(";")
            [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
        }
        if ($env:Path -notlike "*$BinDir*") {
            $env:Path = "$BinDir;$env:Path"
        }
    }

    Report-Progress 100 "Installation completed successfully!"
}

# ==============================================================================
# JAVA / VS CODE STYLE WINDOWS FORMS SETUP WIZARD
# ==============================================================================
function Show-NovaSetupWizard {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Nova Systems Toolchain Setup (v0.31.02)"
    $Form.Size = New-Object System.Drawing.Size(680, 520)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog"
    $Form.MaximizeBox = $false
    $Form.BackColor = [System.Drawing.Color]::FromArgb(26, 27, 38)
    $Form.ForeColor = [System.Drawing.Color]::FromArgb(192, 202, 245)
    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    # Header Banner Panel
    $HeaderPanel = New-Object System.Windows.Forms.Panel
    $HeaderPanel.Size = New-Object System.Drawing.Size(680, 75)
    $HeaderPanel.Location = New-Object System.Drawing.Point(0, 0)
    $HeaderPanel.BackColor = [System.Drawing.Color]::FromArgb(36, 40, 59)
    $Form.Controls.Add($HeaderPanel)

    $HeaderTitle = New-Object System.Windows.Forms.Label
    $HeaderTitle.Text = "Nova Systems Setup Wizard"
    $HeaderTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $HeaderTitle.ForeColor = [System.Drawing.Color]::FromArgb(234, 162, 172) # Nova Coral
    $HeaderTitle.Location = New-Object System.Drawing.Point(25, 12)
    $HeaderTitle.AutoSize = $true
    $HeaderPanel.Controls.Add($HeaderTitle)

    $HeaderSubtitle = New-Object System.Windows.Forms.Label
    $HeaderSubtitle.Text = "Genesis v0.31.02 - Industrial-Grade Type-Safe Systems Language"
    $HeaderSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 190)
    $HeaderSubtitle.Location = New-Object System.Drawing.Point(26, 40)
    $HeaderSubtitle.AutoSize = $true
    $HeaderPanel.Controls.Add($HeaderSubtitle)

    # Path Section
    $LblPath = New-Object System.Windows.Forms.Label
    $LblPath.Text = "Destination Folder:"
    $LblPath.Location = New-Object System.Drawing.Point(30, 95)
    $LblPath.AutoSize = $true
    $Form.Controls.Add($LblPath)

    $TxtPath = New-Object System.Windows.Forms.TextBox
    $TxtPath.Text = "$HOME\.nova"
    $TxtPath.Location = New-Object System.Drawing.Point(30, 120)
    $TxtPath.Size = New-Object System.Drawing.Size(490, 26)
    $TxtPath.BackColor = [System.Drawing.Color]::FromArgb(36, 40, 59)
    $TxtPath.ForeColor = [System.Drawing.Color]::White
    $Form.Controls.Add($TxtPath)

    $BtnBrowse = New-Object System.Windows.Forms.Button
    $BtnBrowse.Text = "Browse..."
    $BtnBrowse.Location = New-Object System.Drawing.Point(530, 118)
    $BtnBrowse.Size = New-Object System.Drawing.Size(100, 28)
    $BtnBrowse.BackColor = [System.Drawing.Color]::FromArgb(50, 56, 80)
    $BtnBrowse.FlatStyle = "Flat"
    $BtnBrowse.Add_Click({
        $FBD = New-Object System.Windows.Forms.FolderBrowserDialog
        $FBD.Description = "Select Nova Installation Directory"
        $FBD.SelectedPath = $TxtPath.Text
        if ($FBD.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $TxtPath.Text = $FBD.SelectedPath
        }
    })
    $Form.Controls.Add($BtnBrowse)

    # Options Checkboxes
    $ChkCore = New-Object System.Windows.Forms.CheckBox
    $ChkCore.Text = "Nova Core Compiler (novac.exe) & Orbit Package Manager"
    $ChkCore.Location = New-Object System.Drawing.Point(30, 165)
    $ChkCore.Size = New-Object System.Drawing.Size(550, 24)
    $ChkCore.Checked = $true
    $ChkCore.Enabled = $false
    $Form.Controls.Add($ChkCore)

    $ChkTools = New-Object System.Windows.Forms.CheckBox
    $ChkTools.Text = "Developer Suite (nova-repl, nova-fmt, nova-lint, nova-doc, nova-runner)"
    $ChkTools.Location = New-Object System.Drawing.Point(30, 195)
    $ChkTools.Size = New-Object System.Drawing.Size(550, 24)
    $ChkTools.Checked = $true
    $Form.Controls.Add($ChkTools)

    $ChkPath = New-Object System.Windows.Forms.CheckBox
    $ChkPath.Text = "Add Nova binaries and runtime to User Environment PATH"
    $ChkPath.Location = New-Object System.Drawing.Point(30, 225)
    $ChkPath.Size = New-Object System.Drawing.Size(550, 24)
    $ChkPath.Checked = $true
    $Form.Controls.Add($ChkPath)

    $ChkToolchain = New-Object System.Windows.Forms.CheckBox
    $ChkToolchain.Text = "Zero-Dependency Toolchain: Tự động tải MinGW GCC nếu máy chưa có GCC"
    $ChkToolchain.Location = New-Object System.Drawing.Point(30, 255)
    $ChkToolchain.Size = New-Object System.Drawing.Size(600, 24)
    $ChkToolchain.Checked = $true
    $Form.Controls.Add($ChkToolchain)

    # Progress Bar & Status
    $ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $ProgressBar.Location = New-Object System.Drawing.Point(30, 310)
    $ProgressBar.Size = New-Object System.Drawing.Size(600, 22)
    $ProgressBar.Style = "Continuous"
    $Form.Controls.Add($ProgressBar)

    $LblStatus = New-Object System.Windows.Forms.Label
    $LblStatus.Text = "Ready to install. Click 'Install Now' to proceed."
    $LblStatus.Location = New-Object System.Drawing.Point(30, 340)
    $LblStatus.Size = New-Object System.Drawing.Size(600, 22)
    $LblStatus.ForeColor = [System.Drawing.Color]::FromArgb(150, 160, 190)
    $Form.Controls.Add($LblStatus)

    # Action Buttons
    $BtnInstall = New-Object System.Windows.Forms.Button
    $BtnInstall.Text = "Install Now"
    $BtnInstall.Location = New-Object System.Drawing.Point(410, 420)
    $BtnInstall.Size = New-Object System.Drawing.Size(110, 36)
    $BtnInstall.BackColor = [System.Drawing.Color]::FromArgb(234, 162, 172)
    $BtnInstall.ForeColor = [System.Drawing.Color]::FromArgb(26, 27, 38)
    $BtnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $BtnInstall.FlatStyle = "Flat"
    $Form.Controls.Add($BtnInstall)

    $BtnCancel = New-Object System.Windows.Forms.Button
    $BtnCancel.Text = "Cancel"
    $BtnCancel.Location = New-Object System.Drawing.Point(530, 420)
    $BtnCancel.Size = New-Object System.Drawing.Size(100, 36)
    $BtnCancel.BackColor = [System.Drawing.Color]::FromArgb(50, 56, 80)
    $BtnCancel.FlatStyle = "Flat"
    $BtnCancel.Add_Click({ $Form.Close() })
    $Form.Controls.Add($BtnCancel)

    $IsInstalled = $false

    $BtnInstall.Add_Click({
        if ($IsInstalled) {
            $ReplBin = Join-Path $TxtPath.Text "bin\nova-repl.exe"
            if (Test-Path $ReplBin) {
                Start-Process $ReplBin
            }
            $Form.Close()
            return
        }

        $BtnInstall.Enabled = $false
        $BtnBrowse.Enabled = $false
        $TxtPath.Enabled = $false
        $ChkPath.Enabled = $false
        $ChkTools.Enabled = $false
        $ChkToolchain.Enabled = $false

        $Target = $TxtPath.Text
        $DoPath = $ChkPath.Checked
        $DoToolchain = $ChkToolchain.Checked

        $Callback = {
            param([int]$pct, [string]$msg)
            $ProgressBar.Value = [Math]::Min(100, [Math]::Max(0, $pct))
            $LblStatus.Text = $msg
            $Form.Refresh()
        }

        try {
            Invoke-NovaInstallCore -TargetPrefix $Target -AddPath $DoPath -InstallToolchain $DoToolchain -ProgressCallback $Callback
            $IsInstalled = $true
            $BtnInstall.Text = "Launch REPL"
            $BtnCancel.Text = "Finish"
            $BtnInstall.Enabled = $true
            $BtnCancel.Enabled = $true
            $LblStatus.Text = "🎉 Installation completed successfully! Welcome to Nova Systems."
            $LblStatus.ForeColor = [System.Drawing.Color]::FromArgb(158, 206, 106) # Green
        } catch {
            $LblStatus.Text = "Error during installation: $($_.Exception.Message)"
            $LblStatus.ForeColor = [System.Drawing.Color]::FromArgb(247, 118, 142) # Red
            $BtnInstall.Enabled = $true
        }
    })

    [void]$Form.ShowDialog()
}

# ==============================================================================
# MAIN DISPATCH ENTRY POINT
# ==============================================================================
if ($GUI -and (-not $CLI)) {
    Show-NovaSetupWizard
} else {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  NOVA SYSTEMS PROGRAMMING LANGUAGE - WINDOWS INSTALLER" -ForegroundColor Cyan
    Write-Host "  Target Prefix: $Prefix" -ForegroundColor DarkCyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    Invoke-NovaInstallCore -TargetPrefix $Prefix -AddPath $true -InstallToolchain $true

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "🎉 NOVA SYSTEMS TOOLCHAIN INSTALLED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "   Location: $Prefix" -ForegroundColor Gray
    Write-Host "   Compiler: $Prefix\bin\novac.exe" -ForegroundColor Gray
    Write-Host "   Manager : $Prefix\bin\orbit.exe" -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "Open a new PowerShell or Command Prompt window and try:" -ForegroundColor White
    Write-Host "   novac version" -ForegroundColor Yellow
    Write-Host "   novac run examples\01_hello.nova" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Cyan
}
