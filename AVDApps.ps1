# ==============================================================
# AVD Winget App Installer – Run as SYSTEM during provisioning
# ==============================================================

$ErrorActionPreference = 'Stop'
$LogPath = 'C:\AVD-Provision\WingetInstall.log'
$Apps = @(
    'Google.Chrome',
    '7zip.7zip',
    'Notepad++.Notepad++',
    'Microsoft.VisualStudioCode'
    # Add your Winget IDs here ↑
)

# --------------------------------------------------------------
# Helper: Write log with timestamp
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host "$ts - $Message"
}

# --------------------------------------------------------------
# Ensure log directory exists
if (-not (Test-Path 'C:\AVD-Provision')) {
    New-Item -ItemType Directory -Path 'C:\AVD-Provision' -Force | Out-Null
}
Write-Log "=== AVD Winget Provisioning Started ==="

# --------------------------------------------------------------
# 1. Install Winget (if not present)
Write-Log "Checking for Winget..."
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log "Winget not found. Installing via Microsoft Store package..."

    try {
        # Download latest Winget CLI + Microsoft UI XAML + VCLibs
        $ProgressPreference = 'SilentlyContinue'
        $wingetUrl = 'https://aka.ms/getwinget'
        $installerPath = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Invoke-WebRequest -Uri $wingetUrl -OutFile $installerPath -UseBasicParsing

        # Install dependencies first
        Add-AppxPackage -Path "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.VCLibs.x64.14.00.Desktop.appx" -ErrorAction Stop
        Add-AppxPackage -Path "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" -ErrorAction Stop

        # Install Winget
        Add-AppxPackage -Path $installerPath -ErrorAction Stop
        Remove-Item $installerPath -Force

        Write-Log "Winget installed successfully via MSIX."
    }
    catch {
        Write-Log "ERROR installing Winget: $($_.Exception.Message)"
        throw $_
    }
}
else {
    Write-Log "Winget already installed: $(winget --version)"
}

# --------------------------------------------------------------
# 2. Upgrade Winget sources (optional but recommended)
Write-Log "Updating Winget sources..."
winget source update --name winget | Out-Null

# --------------------------------------------------------------
# 3. Install each app with retry logic
foreach ($appId in $Apps) {
    $attempt = 0
    $maxAttempts = 3
    $installed = $false

    do {
        $attempt++
        Write-Log "[$attempt/$maxAttempts] Installing $appId ..."

        try {
            $result = winget install --id $appId --silent --accept-package-agreements --accept-source-agreements --force --scope machine 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "SUCCESS: $appId installed."
                $installed = $true
                break
            }
            else {
                Write-Log "Winget exit code: $LASTEXITCODE. Output: $result"
            }
        }
        catch {
            Write-Log "Exception during install: $($_.Exception.Message)"
        }

        if (-not $installed -and $attempt -lt $maxAttempts) {
            Write-Log "Retrying in 30 seconds..."
            Start-Sleep -Seconds 30
        }
    } while (-not $installed -and $attempt -lt $maxAttempts)

    if (-not $installed) {
        Write-Log "FAILED: $appId after $maxAttempts attempts."
    }
}

# --------------------------------------------------------------
# 4. Force Intune check-in (so required apps show as compliant fast)
Write-Log "Triggering Intune MDM check-in..."
try {
    # Trigger device check-in
    $namespace = "root\cimv2\mdm\dmmap"
    $class = "MDM_EnterpriseModernAppManagement_AppManagement01"
    $instance = Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction SilentlyContinue
    if ($instance) {
        Invoke-CimMethod -Namespace $namespace -ClassName $class -MethodName UpdateScanMethod | Out-Null
        Write-Log "Intune check-in triggered."
    }
}
catch { Write-Log "Could not trigger Intune check-in: $($_.Exception.Message)" }

# --------------------------------------------------------------
# 5. Restart IME (Intune Management Extension) to process apps faster
Write-Log "Restarting Intune Management Extension..."
Restart-Service -Name "IntuneManagementExtension" -Force -ErrorAction SilentlyContinue

Write-Log "=== AVD Winget Provisioning Complete ==="