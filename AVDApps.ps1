# ==============================================================
# AVD Intune Enrollment & Sync – BULLETPROOF
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
Write-Log "=== AVD Intune Enrollment & Sync Started ==="

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
            Write-Log "Internet check failed for $url : $($_.Exception.Message)"
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
$dsreg = dsregcmd /status
$joinStatus = ($dsreg | Select-String "AzureAdJoined : YES").Count -gt 0

if (-not $joinStatus) {
    Write-Log "Not Entra ID joined. Attempting to join..."
    try {
        # Force Entra ID join
        $result = dsregcmd /join /debug
        Write-Log "Entra ID join result: $result"
        
        # Wait up to 2 min for join to complete
        $joinTimer = [Diagnostics.Stopwatch]::StartNew()
        while (($joinTimer.Elapsed.TotalSeconds -lt 120) -and (-not ($dsregcmd /status | Select-String "AzureAdJoined : YES"))) {
            Write-Log "Waiting for Entra ID join..."
            Start-Sleep -Seconds 10
        }
        $joinStatus = ($dsregcmd /status | Select-String "AzureAdJoined : YES").Count -gt 0
        if (-not $joinStatus) {
            Write-Log "FATAL: Entra ID join failed after 120 seconds"
            exit 1
        }
        Write-Log "Entra ID joined successfully"
    }
    catch {
        Write-Log "FATAL: Entra ID join failed: $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-Log "Already Entra ID joined"
}

# === Force Intune MDM Enrollment ===
Write-Log "Checking Intune MDM enrollment..."
$mdmStatus = (Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" -ClassName "MDM_DevDetail_Ext01" -ErrorAction SilentlyContinue).DeviceName

if (-not $mdmStatus) {
    Write-Log "Not enrolled in Intune. Forcing enrollment..."
    try {
        # Trigger MDM enrollment
        $namespace = "root\cimv2\mdm\dmmap"
        $class = "MDM_Scope01"
        $obj = Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction Stop
        if ($obj) {
            Invoke-CimMethod -Namespace $namespace -ClassName $class -MethodName Enroll -Arguments @{FriendlyName=$obj.FriendlyName; SessionId=(New-Guid).Guid} | Out-Null
            Write-Log "MDM enrollment triggered"
            
            # Wait up to 2 min for enrollment
            $enrollTimer = [Diagnostics.Stopwatch]::StartNew()
            while (($enrollTimer.Elapsed.TotalSeconds -lt 120) -and (-not (Get-CimInstance -Namespace $namespace -ClassName "MDM_DevDetail_Ext01" -ErrorAction SilentlyContinue))) {
                Write-Log "Waiting for MDM enrollment..."
                Start-Sleep -Seconds 10
            }
            $mdmStatus = (Get-CimInstance -Namespace $namespace -ClassName "MDM_DevDetail_Ext01" -ErrorAction SilentlyContinue).DeviceName
            if (-not $mdmStatus) {
                Write-Log "FATAL: MDM enrollment failed after 120 seconds"
                exit 1
            }
            Write-Log "Intune MDM enrolled successfully"
        }
        else {
            Write-Log "FATAL: MDM_Scope01 not found"
            exit 1
        }
    }
    catch {
        Write-Log "FATAL: MDM enrollment failed: $($_.Exception.Message)"
        exit 1
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

        # Wait up to 5 min for sync to complete
        $syncTimer = [Diagnostics.Stopwatch]::StartNew()
        while ($syncTimer.Elapsed.TotalSeconds -lt 300) {
            $syncStatus = Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction SilentlyContinue
            if ($syncStatus.LastSyncStatus -eq 0) {
                Write-Log "Intune sync completed successfully"
                break
            }
            Write-Log "Waiting for Intune sync... ($([int]$syncTimer.Elapsed.TotalSeconds)s)"
            Start-Sleep -Seconds 15
        }
        if ($syncStatus.LastSyncStatus -ne 0) {
            Write-Log "WARNING: Intune sync did not complete successfully"
        }
    }
    else {
        Write-Log "WARNING: Could not find MDM_EnterpriseModernAppManagement_AppManagement01"
    }

    # Restart Intune Management Extension for immediate processing
    Write-Log "Restarting Intune Management Extension..."
    Restart-Service -Name "IntuneManagementExtension" -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Log "WARNING: Intune sync failed: $($_.Exception.Message)"
}

Write-Log "=== AVD Intune Enrollment & Sync COMPLETE ==="
