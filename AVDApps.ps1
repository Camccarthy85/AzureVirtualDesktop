# ==============================================================
# AVD Winget Installer – BULLETPROOF v2
# ==============================================================

$ErrorActionPreference = 'Stop'
$LogPath = 'C:\AVD-Provision\WingetInstall.log'
$Apps = @(
    'Microsoft.Teams', 'Google.Chrome', 'Mozilla.Firefox',
    '7zip.7zip', 'Notepad++.Notepad++', 'Microsoft.PowerToys', 'Microsoft.VisualStudioCode'
)

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host $Message
}

function Invoke-RobustDownload {
    param([string]$Url, [string]$OutputPath, [int]$Retries = 5)
    $attempt = 0
    do {
        $attempt++
        Write-Log "Download attempt $attempt/$Retries: $Url"
        try {
            $ProgressPreference = 'SilentlyContinue'
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "AVD-Provisioner/1.0")
            $webClient.DownloadFile($Url, $OutputPath)
            if ((Get-Item $OutputPath).Length -gt 1000000) {
                Write-Log "Download SUCCESS"
                return $true
            }
        }
        catch { Write-Log "Failed: $($_.Exception.Message)" }
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }
        if ($attempt -lt $Retries) { Start-Sleep -Seconds ([Math]::Pow(2, $attempt) * 10) }
    } while ($attempt -lt $Retries)
    return $false
}

# Create log dir
if (-not (Test-Path 'C:\AVD-Provision')) { New-Item -ItemType Directory -Path 'C:\AVD-Provision' -Force | Out-Null }
Write-Log "=== AVD Winget Installer Started ==="

# === Wait for FULL internet ===
$timeout = 300
$timer = [Diagnostics.Stopwatch]::StartNew()
$internetReady = $false
while (-not $internetReady -and $timer.Elapsed.TotalSeconds -lt $timeout) {
    try {
        $test = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -Method Head -TimeoutSec 10
        if ($test.StatusCode -eq 200) { $internetReady = $true; Write-Log "Internet ready" }
    }
    catch { }
    if (-not $internetReady) {
        Write-Log "Waiting for internet... ($([int]$timer.Elapsed.TotalSeconds)s)"
        Start-Sleep -Seconds 10
    }
}
if (-not $internetReady) { Write-Log "ERROR: No internet"; exit 1 }

# === Install Winget ===
$wingetExe = "$env:ProgramFiles\Winget\winget.exe"
$wingetUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.9.2561-preview/winget-1.9.2561-preview-x64.exe"
$installerPath = "$env:TEMP\winget.exe"

if (-not (Test-Path $wingetExe)) {
    if (-not (Invoke-RobustDownload -Url $wingetUrl -OutputPath $installerPath)) {
        Write-Log "CRITICAL: Winget download failed"; exit 1
    }
    $installDir = Split-Path $wingetExe -Parent
    if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }
    Move-Item -Path $installerPath -Destination $wingetExe -Force
    Write-Log "Winget installed"

    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($machinePath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$installDir", "Machine")
        $env:PATH += ";$installDir"
    }
}
else { Write-Log "Winget already installed" }

# === Install Apps ===
foreach ($appId in $Apps) {
    $attempt = 0
    do {
        $attempt++
        Write-Log "[$attempt/3] Installing $appId ..."
        $output = & $wingetExe install --id $appId --silent --accept-package-agreements --accept-source-agreements --force --scope machine 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Log "SUCCESS: $appId"; break }
        else { Write-Log "Failed: $output"; if ($attempt -lt 3) { Start-Sleep -Seconds 30 } }
    } while ($attempt -lt 3)
}

# === Intune Sync ===
Write-Log "Triggering Intune check-in..."
try {
    Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" -ClassName MDM_EnterpriseModernAppManagement_AppManagement01 -ErrorAction SilentlyContinue |
        Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
}
catch { Write-Log "Intune sync failed" }

Write-Log "=== COMPLETE ==="
