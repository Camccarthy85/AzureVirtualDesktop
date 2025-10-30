# AVD Intune Rush - Hybrid Join + MDM + Sync
$ErrorActionPreference = 'Stop'
$Log = 'C:\AVD-Provision\IntuneRush.log'

function Log { param([string]$m)
    $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$t - $m" | Out-File -FilePath $Log -Append -Encoding UTF8
    Write-Host "$t - $m"
}

# create log folder
if(!(Test-Path 'C:\AVD-Provision')) { New-Item -ItemType Directory -Path 'C:\AVD-Provision' -Force | Out-Null }
Log '=== Intune Rush START ==='

# 1. Wait for Intune endpoints
$max = 300
$sw  = [Diagnostics.Stopwatch]::StartNew()
$ok  = $false
$urls = 'https://login.microsoftonline.com','https://graph.microsoft.com'

while(-not $ok -and $sw.Elapsed.TotalSeconds -lt $max){
    foreach($u in $urls){
        try{
            $r = Invoke-WebRequest -Uri $u -Method Head -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
            if($r.StatusCode -eq 200){ $ok=$true; Log "Internet OK via $u"; break }
        }catch{ Log "Ping $u failed: $($_.Exception.Message)" }
    }
    if(-not $ok){ Log "Waiting for net... $($sw.Elapsed.Seconds)s"; Start-Sleep -Seconds 10 }
}
if(-not $ok){ Log 'FATAL - no internet'; exit 1 }

# 2. Force hybrid Entra ID join
Log 'Checking hybrid join...'
$status = & dsregcmd.exe /status 2>$null
$joined = $status -match 'AzureAdJoined\s*:\s*YES'

if(-not $joined){
    Log 'Forcing hybrid join...'
    & dsregcmd.exe /join /debug | Out-Null
    $t = [Diagnostics.Stopwatch]::StartNew()
    while($t.Elapsed.TotalSeconds -lt 180){
        if((& dsregcmd.exe /status 2>$null) -match 'AzureAdJoined\s*:\s*YES'){
            Log 'Hybrid join SUCCESS'; break
        }
        Log "Waiting for join... $($t.Elapsed.Seconds)s"; Start-Sleep -Seconds 15
    }
    if(-not ((& dsregcmd.exe /status 2>$null) -match 'AzureAdJoined\s*:\s*YES')){
        Log 'WARN - join did not finish, continuing'
    }
}else{ Log 'Already hybrid joined' }

# 3. Trigger MDM enrollment
Log 'Triggering MDM enrollment...'
try{
    $ns = 'root\cimv2\mdm\dmmap'
    $cls = 'MDM_Scope01'
    $o = Get-CimInstance -Namespace $ns -ClassName $cls -ErrorAction Stop
    Invoke-CimMethod -Namespace $ns -ClassName $cls -MethodName Enroll -Arguments @{FriendlyName=$o.FriendlyName; SessionId=(New-Guid).Guid} | Out-Null
    Log 'MDM enroll command sent'
}catch{ Log "WARN - MDM enroll failed: $($_.Exception.Message)" }

# 4. Force Intune sync + restart IME
Log 'Forcing Intune sync...'
try{
    $ns = 'root\cimv2\mdm\dmmap'
    $cls = 'MDM_EnterpriseModernAppManagement_AppManagement01'
    $o = Get-CimInstance -Namespace $ns -ClassName $cls -ErrorAction SilentlyContinue
    if($o){ Invoke-CimMethod -Namespace $ns -ClassName $cls -MethodName UpdateScanMethod | Out-Null }
    Log 'Sync command sent'
}catch{ Log "WARN - sync command failed: $($_.Exception.Message)" }

Log 'Restarting IntuneManagementExtension...'
Restart-Service -Name IntuneManagementExtension -Force -ErrorAction SilentlyContinue

Log '=== Intune Rush COMPLETE ==='
