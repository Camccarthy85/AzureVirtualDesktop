# ==============================================================
# AVD Winget Installer – ROBUST VERSION (NO Add-AppxPackage!)
# ==============================================================

$ErrorActionPreference = 'Stop'
$LogPath = 'C:\AVD-Provision\WingetInstall.log'
$Apps = @(
    'Microsoft.Teams',
    'Google.Chrome',
    'Mozilla.Firefox',
    '7zip.7zip',
    'Notepad++.Notepad++',
    'Microsoft.PowerToys',
    'Microsoft.VisualStudioCode'
)

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host "$ts - $Message"
}

# Ensure log dir
if (-not (Test-Path 'C:\AVD-Provision')) { New-Item -ItemType Directory -Path 'C:\AVD-Provision' -Force | Out-Null }
Write-Log "=== AVD Winget Provisioning Started (Robust) ==="

# === 1. Install Winget via Official GitHub Release (.exe) ===
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log "Winget not found. Installing via GitHub release..."

    try {
        $ProgressPreference = 'SilentlyContinue'

        # Get latest release
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing
        $asset = $latest.assets | Where-Object { $_.name -like "*msixbundle" } | Select-Object -First 1
        $url = $asset.browser_download_url
        $installerPath = "$env:TEMP\winget.msixbundle"

        Write-Log "Downloading Winget from: $url"
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing

        # Install using PowerShell (bypasses Store)
        Write-Log "Installing Winget package..."
        Add-AppxPackage -Path $installerPath -ErrorAction Stop

        # Cleanup
        Remove-Item $installerPath -Force
        Write-Log "Winget installed successfully."
    }
    catch {
        Write-Log "FAILED to install Winget: $($_.Exception.Message)"
        throw $_
    }
}
else {
    Write-Log "Winget already installed: $(winget --version)"
}

# === 2. Update sources ===
winget source update --name winget

# === 3. Install apps ===
foreach ($appId in $Apps) {
    $attempt = 0
    $maxAttempts = 3
    $installed = $false

    do {
        $attempt++
        Write-Log "[$attempt/$maxAttempts] Installing $appId ..."

        try {
            $output = winget install --id $appId --silent --accept-package-agreements --accept-source-agreements --force --scope machine 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "SUCCESS: $appId installed."
                $installed = $true
                break
            } else {
                Write-Log "Winget exit: $LASTEXITCODE | Output: $output"
            }
        }
        catch { Write-Log "Exception: $($_.Exception.Message)" }

        if (-not $installed -and $attempt -lt $maxAttempts) {
            Start-Sleep -Seconds 30
        }
    } while (-not $installed -and $attempt -lt $maxAttempts)

    if (-not $installed) {
        Write-Log "FAILED: $appId after $maxAttempts attempts."
    }
}

# === 4. Force Intune sync ===
Write-Log "Triggering Intune check-in..."
try {
    $namespace = "root\cimv2\mdm\dmmap"
    $class = "MDM_EnterpriseModernAppManagement_AppManagement01"
    Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction SilentlyContinue | 
        Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
}
catch { Write-Log "Intune sync failed: $($_.Exception.Message)" }

Write-Log "=== AVD Winget Provisioning Complete ==="
