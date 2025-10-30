# ==============================================================
# AVD Intune Enrollment & Sync – BULLETPROOF v2
# ==============================================================

$ErrorActionPreference = 'Stop'
$LogPath = 'C:\AVD-Provision\IntuneSync.log'

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$ts - $Message"
    $logMessage | Out-File -FilePath $LogPath -Append -Encoding UTF8 -Force
    Write-Host $logMessage
}

# === Create log directory ===
if (-not (Test-Path 'C:\AVD-Provision')) {
    New-Item -ItemType Directory -Path 'C:\AVD-Provision' -Force | Out-Null
}
Write-Log "=== AVD Intune Enrollment & Sync v2 Started ==="

# === Wait for internet (robust check) ===
$timeout = 300
$timer = [Diagnostics.Stopwatch]::StartNew()
$internetReady = $false
$testUrls = @("https://graph.microsoft.com", "https://login.microsoftonline.com")

while (-not $internetReady -and $timer.Elapsed.TotalSeconds -lt $timeout) {
    foreach ($url in $testUrls) {
        try {
            $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                $internetReady = $true
                Write-Log "Internet confirmed via $url"
                break
            }
        }
        catch {
            Write-Log "Internet check failed for $url: $($_.Exception.Message)"
        }
    }
    if (-not $internetReady) {
        Write-Log "Waiting for internet... ($([int]$timer.Elapsed.TotalSeconds)s)"
        Start-Sleep -Seconds 10
    }
}
if (-not $internetReady) {
    Write-Log "FATAL: No internet after $timeout seconds"
    exit 1
}

# === Check & Force Entra ID Join ===
Write-Log "Checking Entra ID join status..."
try {
    $dsregOutput = & dsregcmd.exe /status 2>&1
    $joinStatus = ($dsregOutput | Select-String "AzureAdJoined : YES").Count -gt 0

    if (-not $joinStatus) {
        Write-Log "Not Entra ID joined. Attempting to join..."
        try {
            $joinResult = & dsregcmd.exe /join /debug 2>&1
            Write-Log "Entra ID join result: $joinResult"

            # Wait up to 5 min for join
            $joinTimer = [Diagnostics.Stopwatch]::StartNew()
            $joinTimeout = 300
            while (($joinTimer.Elapsed.TotalSeconds -lt $joinTimeout) -and (-not (& dsregcmd.exe /status | Select-String "AzureAdJoined : YES"))) {
                Write-Log "Waiting for Entra ID join... ($([int]$joinTimer.Elapsed.TotalSeconds)s)"
                Start-Sleep -Seconds 15
            }
            $joinStatus = (& dsregcmd.exe /status | Select-String "AzureAdJoined : YES").Count -gt 0
            if (-not $joinStatus) {
                Write-Log "WARNING: Entra ID join failed after $joinTimeout seconds. Proceeding to MDM enrollment."
            }
            else {
                Write-Log "Entra ID joined successfully"
            }
        }
        catch {
            Write-Log "WARNING: Entra ID join attempt failed: $($_.Exception.Message). Proceeding to MDM enrollment."
        }
    }
    else {
        Write-Log "Already Entra ID joined"
    }
}
catch {
    Write-Log "WARNING: Error checking Entra ID join status: $($_.Exception.Message). Proceeding to MDM enrollment."
}

# === Force Intune MDM Enrollment ===
Write-Log "Checking Intune MDM enrollment..."
$mdmStatus = (Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" -ClassName "MDM_DevDetail_Ext01" -ErrorAction SilentlyContinue).DeviceName

if (-not $mdmStatus) {
    Write-Log "Not enrolled in Intune. Forcing enrollment..."
    try {
        $namespace = "root\cimv2\mdm\dmmap"
        $class = "MDM_Scope01"
        $obj = Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction Stop
        if ($obj) {
            Invoke-CimMethod -Namespace $namespace -ClassName $class -MethodName Enroll -Arguments @{FriendlyName=$obj.FriendlyName; SessionId=(New-Guid).Guid} | Out-Null
            Write-Log "MDM enrollment triggered"

            # Wait up to 5 min for enrollment
            $enrollTimer = [Diagnostics.Stopwatch]::StartNew()
            while (($enrollTimer.Elapsed.TotalSeconds -lt 300) -and (-not (Get-CimInstance -Namespace $namespace -ClassName "MDM_DevDetail_Ext01" -ErrorAction SilentlyContinue))) {
                Write-Log "Waiting for MDM enrollment... ($([int]$enrollTimer.Elapsed.TotalSeconds)s)"
                Start-Sleep -Seconds 15
            }
            $mdmStatus = (Get-CimInstance -Namespace $namespace -ClassName "MDM_DevDetail_Ext01" -ErrorAction SilentlyContinue).DeviceName
            if (-not $mdmStatus) {
                Write-Log "WARNING: MDM enrollment failed after 300 seconds"
            }
            else {
                Write-Log "Intune MDM enrolled successfully: $mdmStatus"
            }
        }
        else {
            Write-Log "WARNING: MDM_Scope01 not found"
        }
    }
    catch {
        Write-Log "WARNING: MDM enrollment failed: $($_.Exception.Message)"
    }
}
else {
    Write-Log "Already enrolled in Intune: $mdmStatus"
}

# === Force Intune Policy/App Sync ===
Write-Log "Triggering Intune policy and app sync..."
try {
    $namespace = "root\cimv2\mdm\dmmap"
    $class = "MDM_EnterpriseModernAppManagement_AppManagement01"
    $syncObj = Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction SilentlyContinue
    if ($syncObj) {
        Invoke-CimMethod -Namespace $namespace -ClassName $class -MethodName UpdateScanMethod | Out-Null
        Write-Log "Intune policy/app sync triggered"

        # Wait up to 10 min for sync
        $syncTimer = [Diagnostics.Stopwatch]::StartNew()
        while ($syncTimer.Elapsed.TotalSeconds -lt 600) {
            $syncStatus = Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction SilentlyContinue
            if ($syncStatus.LastSyncStatus -eq 0) {
                Write-Log "Intune sync completed successfully"
                break
            }
            Write-Log "Waiting for Intune sync... ($([int]$syncTimer.Elapsed.TotalSeconds)s)"
            Start-Sleep -Seconds 20
        }
        if ($syncStatus.LastSyncStatus -ne 0) {
            Write-Log "WARNING: Intune sync did not complete successfully"
        }
    }
    else {
        Write-Log "WARNING: Could not find MDM_EnterpriseModernAppManagement_AppManagement01"
    }

    # Restart Intune Management Extension
    Write-Log "Restarting Intune Management Extension..."
    Restart-Service -Name "IntuneManagementExtension" -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Log "WARNING: Intune sync failed: $($_.Exception.Message)"
}

Write-Log "=== AVD Intune Enrollment & Sync v2 COMPLETE ==="
