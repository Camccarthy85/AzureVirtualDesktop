#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# -------------------------------------------------
# 1. Install Chocolatey
# -------------------------------------------------
Write-Output "Installing Chocolatey..."
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = 
    [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    throw "Chocolatey installation failed."
}
Write-Output "Chocolatey installed."

# -------------------------------------------------
# 2. Install applications
# -------------------------------------------------
$apps = 'notepadplusplus', 'googlechrome', 'putty', 'winscp'

foreach ($app in $apps) {
    Write-Output "Installing $app..."
    & choco install $app -y --force --no-progress --limit-output
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install $app (exit: $LASTEXITCODE)"
        # Do NOT throw — let CSE see full log
    } else {
        Write-Output "$app installed."
    }
}

# -------------------------------------------------
# 3. FULLY REMOVE Chocolatey
# -------------------------------------------------
Write-Output "Removing Chocolatey..."

Get-Process -Name choco -ErrorAction SilentlyContinue | Stop-Process -Force

$chocoPath = Join-Path $env:ProgramData 'chocolatey'
if (Test-Path $chocoPath) {
    Remove-Item $chocoPath -Recurse -Force -ErrorAction Continue
    Write-Output "Removed $chocoPath"
}

[Environment]::SetEnvironmentVariable('ChocolateyInstall', $null, 'Machine')
[Environment]::SetEnvironmentVariable('ChocolateyLastPathUpdate', $null, 'Machine')

# Clean PATH
$machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
$newPath = ($machinePath -split ';' | Where-Object { $_ -notmatch 'chocolatey' }) -join ';'
[Environment]::SetEnvironmentVariable('PATH', $newPath, 'Machine')

# Remove shims
Get-ChildItem "$env:SystemRoot\System32" -Filter "*.shim" -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Output "Chocolatey removed."

# -------------------------------------------------
# 4. Final success (use Write-Output!)
# -------------------------------------------------
Write-Output "Deployment script completed successfully."
exit 0
