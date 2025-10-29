# ==============================================================
# AVD Winget Installer – BULLETPROOF v5 (NO VARIABLE SCOPE ISSUES)
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
    $logMessage = "$ts - $Message"
    $logMessage | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host $logMessage
}

function Invoke-RobustDownload {
    param(
        [string]$Url,
        [string]$OutputPath,
        [int]$MaxRetries = 5
    )

    Write-Log "Entering Invoke-RobustDownload with URL: $Url, Output: $OutputPath, Retries: $MaxRetries"
    $attempt = 0

    while ($attempt -lt $MaxRetries) {
        $attempt++
        Write-Log ("Download attempt {0} of {1}: {2}" -f $attempt, $MaxRetries, $Url)

        try {
            $ProgressPreference = 'SilentlyContinue'
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "AVD-Provisioner/1.0")
            $webClient.DownloadFile($Url, $OutputPath)

            $fileSize = (Get-Item $OutputPath -ErrorAction Stop).Length
            if ($fileSize -gt 1MB) {
                Write-Log "Download SUCCESS: $fileSize bytes"
                return $true
            }
            throw "Downloaded file is too small or corrupt"
        }
        catch {
            Write-Log "Download failed: $($_.Exception.Message)"
            if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue }
        }

        if ($attempt -lt $MaxRetries) {
            $retryDelay = [Math]::Min([Math]::Pow(2, $attempt) * 10, 120)
            Write-Log "Retrying in $retryDelay seconds..."
            Start-Sleep -Seconds $retryDelay
        }
    }

    Write-Log "All $MaxRetries download attempts failed"
    return $false
}

# === Create log directory ===
if (-not (Test-Path 'C:\AVD-Provision')) {
    New-Item -ItemType Directory -Path 'C:\AVD-Provision' -Force | Out-Null
}
Write-Log "=== AVD Winget Installer v5 Started ==="

# === Wait for internet ===
$timeout = 300
$timer = [Diagnostics.Stopwatch]::StartNew()
$internetReady = $false

while (-not $internetReady -and $timer.Elapsed.TotalSeconds -lt $timeout) {
    try {
        $response = Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $internetReady = $true
            Write-Log "Internet connectivity confirmed"
        }
    }
    catch {
        Write-Log "Waiting for internet... ($([int]$timer.Elapsed.TotalSeconds)s)"
        Start-Sleep -Seconds 10
    }
}
if (-not $internetReady) {
    Write-Log "ERROR: No internet connectivity after $timeout seconds"
    exit 1
}

# === Install Winget ===
$wingetExe = "$env:ProgramFiles\Winget\winget.exe"
$wingetUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.9.2561-preview/winget-1.9.2561-preview-x64.exe"
$installerPath = "$env:TEMP\winget.exe"

if (-not (Test-Path $wingetExe)) {
    Write-Log "Starting Winget download..."
    if (-not (Invoke-RobustDownload -Url $wingetUrl -OutputPath $installerPath -MaxRetries 5)) {
        Write-Log "FATAL: Failed to download Winget after retries"
        exit 1
    }

    $installDir = Split-Path $wingetExe -Parent
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    Move-Item -Path $installerPath -Destination $wingetExe -Force
    Write-Log "Winget installed to: $wingetExe"

    # Add to system PATH
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($machinePath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$installDir", "Machine")
        $env:PATH += ";$installDir"
        Write-Log "Added Winget to system PATH"
    }
}
else {
    Write-Log "Winget already installed at: $wingetExe"
}

# === Install Apps ===
foreach ($appId in $Apps) {
    $attempt = 0
    $maxAttempts = 3
    do {
        $attempt++
        Write-Log ("[{0}/{1}] Installing {2} ..." -f $attempt, $maxAttempts, $appId)
        $output = & $wingetExe install --id $appId --silent --accept-package-agreements --accept-source-agreements --force --scope machine 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "SUCCESS: $appId installed"
            break
        }
        else {
            Write-Log "Failed (attempt $attempt): $output"
            if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 30 }
        }
    } while ($attempt -lt $maxAttempts)
}

# === Trigger Intune Sync ===
Write-Log "Triggering Intune check-in..."
try {
    Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" -ErrorAction SilentlyContinue |
        Invoke-CimMethod -MethodName UpdateScanMethod | Out-Null
    Write-Log "Intune sync triggered"
}
catch {
    Write-Log "Intune sync failed: $($_.Exception.Message)"
}

Write-Log "=== AVD WINGET INSTALLER v5 COMPLETE ==="
