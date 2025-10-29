# ==============================================================
# AVD Winget Installer – STANDALONE EXE VERSION (NO AppX!)
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
    Write-Host $Message
}

# Create log dir
if (-not (Test-Path 'C:\AVD-Provision')) { New-Item -ItemType Directory -Path 'C:\AVD-Provision' -Force | Out-Null }
Write-Log "=== AVD Winget Standalone Installer Started ==="

# === 1. Install Winget CLI as standalone .exe ===
$wingetExe = "$env:ProgramFiles\Winget\winget.exe"

if (-not (Test-Path $wingetExe)) {
    Write-Log "Winget not found. Installing standalone CLI..."

    try {
        $ProgressPreference = 'SilentlyContinue'

        # Get latest release
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -UseBasicParsing
        $asset = $latest.assets | Where-Object { $_.name -like "*x64.exe" -and $_.name -notlike "*symbols*" } | Select-Object -First 1
        $url = $asset.browser_download_url
        $installerPath = "$env:TEMP\winget.exe"

        Write-Log "Downloading Winget from: $url"
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing

        # Create install dir
        $installDir = Split-Path $wingetExe -Parent
        if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }

        # Install
        Move-Item -Path $installerPath -Destination $wingetExe -Force
        Write-Log "Winget installed to: $wingetExe"

        # Add to PATH for this session
        $env:PATH += ";$installDir"
    }
    catch {
        Write-Log "FAILED to install Winget: $($_.Exception.Message)"
        throw $_
    }
}
else {
    Write-Log "Winget already at: $wingetExe"
}

# === 2. Register winget source (first run) ===
& $wingetExe source update --name winget 2>$null

# === 3. Install apps ===
foreach ($appId in $Apps) {
    $attempt = 0
    $maxAttempts = 3
    $installed = $false

    do {
        $attempt++
        Write-Log "[$attempt/$maxAttempts] Installing $appId ..."

        try {
            $output = & $wingetExe install --id $appId --silent --accept-package-agreements --accept-source-agreements --force --scope machine 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "SUCCESS: $appId"
                $installed = $true
                break
            } else {
                Write-Log "Exit: $LASTEXITCODE | $output"
            }
        }
        catch { Write-Log "Error: $($_.Exception.Message)" }

        if (-not $installed -and $attempt -lt $maxAttempts) {
            Start-Sleep -Seconds 30
        }
    } while (-not $installed -and $attempt -lt $maxAttempts)

    if (-not $installed) {
        Write-Log "FAILED: $appId"
    }
}

# === 4. Force Intune sync ===
Write-Log "Triggering Intune check-in..."
try {
    $ns = "root\cimv2\mdm\dmmap"
    Get-CimInstance -Namespace $ns -ClassName MDM_EnterpriseModernAppManagement_AppManagement01 -ErrorAction SilentlyContinue |
        Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
}
catch { Write-Log "Intune sync failed: $($_.Exception.Message)" }

Write-Log "=== AVD Winget Install Complete ==="
