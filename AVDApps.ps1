# ==============================================================
# AVD Winget Standalone Installer – BULLETPROOF
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

if (-not (Test-Path 'C:\AVD-Provision')) { New-Item -ItemType Directory -Path 'C:\AVD-Provision' -Force | Out-Null }
Write-Log "=== AVD Winget Installer Started ==="

# === Wait for network ===
$timeout = 300
$timer = [Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Connection -ComputerName github.com -Count 1 -Quiet) -and $timer.Elapsed.TotalSeconds -lt $timeout) {
    Write-Log "Waiting for network... ($([int]$timer.Elapsed.TotalSeconds)s)"
    Start-Sleep -Seconds 5
}
if (-not (Test-Connection -ComputerName github.com -Count 1 -Quiet)) {
    Write-Log "ERROR: No internet after $timeout seconds"
    exit 1
}

# === Install Winget (direct URL) ===
$wingetExe = "$env:ProgramFiles\Winget\winget.exe"
$wingetUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.9.2561-preview/winget-1.9.2561-preview-x64.exe"
$installerPath = "$env:TEMP\winget.exe"

if (-not (Test-Path $wingetExe)) {
    Write-Log "Downloading Winget from: $wingetUrl"
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $wingetUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        $installDir = Split-Path $wingetExe -Parent
        if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }
        Move-Item -Path $installerPath -Destination $wingetExe -Force
        Write-Log "Winget installed."

        $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($machinePath -notlike "*$installDir*") {
            [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$installDir", "Machine")
            $env:PATH += ";$installDir"
        }
    }
    catch {
        Write-Log "FAILED: $($_.Exception.Message)"
        throw $_
    }
}
else {
    Write-Log "Winget already installed."
}

# === Install Apps ===
foreach ($appId in $Apps) {
    $attempt = 0
    do {
        $attempt++
        Write-Log "[$attempt/3] Installing $appId ..."
        $output = & $wingetExe install --id $appId --silent --accept-package-agreements --accept-source-agreements --force --scope machine 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "SUCCESS: $appId"
            break
        } else {
            Write-Log "Failed (attempt $attempt): $output"
            if ($attempt -lt 3) { Start-Sleep -Seconds 30 }
        }
    } while ($attempt -lt 3)
}

# === Intune Sync ===
Write-Log "Triggering Intune check-in..."
try {
    Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" -ClassName MDM_EnterpriseModernAppManagement_AppManagement01 -ErrorAction SilentlyContinue |
        Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
}
catch { Write-Log "Intune sync failed." }

Write-Log "=== COMPLETE ==="
