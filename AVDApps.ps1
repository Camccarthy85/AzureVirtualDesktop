#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# Start logging
$logPath = "C:\AVDApps.log"
Start-Transcript -Path $logPath -Append -Force
Write-Output "=== AVD App Deployment Started: $(Get-Date) ==="

# -------------------------------------------------
# 1. Install Chocolatey
# -------------------------------------------------
Write-Output "Installing Chocolatey..."
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = 
    [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

try {
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    Write-Output "Chocolatey installed."
} catch {
    Write-Error "Failed to install Chocolatey: $_"
    throw
}

# Verify choco
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    throw "choco command not found after install."
}

# -------------------------------------------------
# 2. Install Applications (with retry + version pinning)
# -------------------------------------------------
$apps = @(
    @{ Name = 'Notepad++';           ID = 'notepadplusplus';     Version = $null }
    @{ Name = 'Google Chrome';       ID = 'googlechrome';        Version = $null }
    @{ Name = 'PuTTY';               ID = 'putty';               Version = $null }
    @{ Name = 'WinSCP';              ID = 'winscp';              Version = $null }
    @{ Name = 'Visual Studio Code';  ID = 'vscode';              Version = $null }
    @{ Name = 'mRemoteNG';           ID = 'mremoteng';           Version = $null }
    @{ Name = 'SSMS 21';             ID = 'sql-server-management-studio'; Version = $null }
)

foreach ($app in $apps) {
    $installArgs = @('install', $app.ID, '-y', '--force', '--no-progress', '--limit-output')
    if ($app.Version) { $installArgs += "--version=$($app.Version)" }

    Write-Output "Installing $($app.Name) ($($app.ID))..."
    $attempt = 0
    $maxAttempts = 3
    do {
        $attempt++
        & choco @installArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Output "$($app.Name) installed successfully."
            break
        } else {
            Write-Warning "Attempt $attempt failed (exit: $LASTEXITCODE). Retrying in 5s..."
            Start-Sleep -Seconds 5
        }
    } while ($attempt -lt $maxAttempts)

    if ($LASTEXITCODE -ne 0) {
        Write-Error "FAILED to install $($app.Name) after $maxAttempts attempts."
        # Do not exit — continue with others
    }
}

# -------------------------------------------------
# 3. FULLY REMOVE Chocolatey
# -------------------------------------------------
Write-Output "Removing Chocolatey..."

Get-Process -Name choco -ErrorAction SilentlyContinue | Stop-Process -Force -PassThru | ForEach-Object {
    Write-Output "Stopped choco process: $($_.Id)"
}

$chocoPath = Join-Path $env:ProgramData 'chocolatey'
if (Test-Path $chocoPath) {
    Remove-Item $chocoPath -Recurse -Force -ErrorAction Continue
    Write-Output "Deleted: $chocoPath"
}

# Clean environment variables
@('ChocolateyInstall', 'ChocolateyLastPathUpdate') | ForEach-Object {
    [Environment]::SetEnvironmentVariable($_, $null, 'Machine')
    Remove-Item "Env:\$_" -ErrorAction SilentlyContinue
}

# Clean PATH
$machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
$newPath = ($machinePath -split ';' | Where-Object { $_ -notmatch 'chocolatey' -and $_ -ne '' }) -join ';'
[Environment]::SetEnvironmentVariable('PATH', $newPath, 'Machine')

# Remove shims
Get-ChildItem "$env:SystemRoot\System32" -Filter "*.shim" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Output "Removed shim: $($_.Name)"
}

Write-Output "Chocolatey fully removed."

# -------------------------------------------------
# 4. Final Success
# -------------------------------------------------
Write-Output "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
Write-Output "Log: $logPath"
Stop-Transcript

exit 0
