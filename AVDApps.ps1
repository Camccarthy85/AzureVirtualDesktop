#Requires -RunAsAdministrator

# -------------------------------------------------
# 1. Install Chocolatey (official one-liner)
# -------------------------------------------------
Write-Host "Installing Chocolatey..." -ForegroundColor Cyan
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Verify installation
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Throw "Chocolatey failed to install."
}
Write-Host "Chocolatey installed successfully." -ForegroundColor Green

# -------------------------------------------------
# 2. Install applications
# -------------------------------------------------
$apps = @(
    'notepadplusplus'
    'googlechrome'
    'putty'
    'winscp'
)

Write-Host "Installing applications via Chocolatey..." -ForegroundColor Cyan
foreach ($app in $apps) {
    Write-Host "  Installing $app..." -ForegroundColor Yellow
    choco install $app -y --force --no-progress --limit-output
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install $app (exit code: $LASTEXITCODE)"
    } else {
        Write-Host "  $app installed." -ForegroundColor Green
    }
}

# -------------------------------------------------
# 3. FULLY REMOVE Chocolatey (no traces)
# -------------------------------------------------
Write-Host "Removing Chocolatey and all traces..." -ForegroundColor Cyan

# Stop any running choco processes
Get-Process -Name choco -ErrorAction SilentlyContinue | Stop-Process -Force

# Remove Chocolatey bin from PATH (current session)
$env:PATH = ($env:PATH.Split(';') | Where-Object { $_ -notmatch 'chocolatey\\bin' }) -join ';'

# Remove Chocolatey folder
$chocoPath = Join-Path $env:ProgramData 'chocolatey'
if (Test-Path $chocoPath) {
    Remove-Item $chocoPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed $chocoPath" -ForegroundColor Green
}

# Remove Chocolatey environment variables
[Environment]::SetEnvironmentVariable('ChocolateyInstall', $null, 'Machine')
[Environment]::SetEnvironmentVariable('ChocolateyLastPathUpdate', $null, 'Machine')
Remove-Item Env:\ChocolateyInstall -ErrorAction SilentlyContinue
Remove-Item Env:\ChocolateyLastPathUpdate -ErrorAction SilentlyContinue

# Remove Chocolatey shim files from System32 (if any)
Get-ChildItem "$env:SystemRoot\System32" -Filter "*.shim" | Remove-Item -Force -ErrorAction SilentlyContinue

# Remove Chocolatey from machine PATH
$machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
$newMachinePath = ($machinePath -split ';' | Where-Object { $_ -notmatch 'chocolatey' }) -join ';'
[Environment]::SetEnvironmentVariable('PATH', $newMachinePath, 'Machine')

# Remove Chocolatey tools location if exists
$toolsPath = Join-Path $env:ProgramData 'chocolatey\bin'
if (Test-Path $toolsPath) {
    Remove-Item $toolsPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Final cleanup of any leftover .old files
Get-ChildItem "$env:ProgramData\chocolatey" -Recurse -Include *.old -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Host "Chocolatey completely removed." -ForegroundColor Green

# -------------------------------------------------
# 4. Final verification
# -------------------------------------------------
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Warning "choco command still available — manual cleanup may be needed."
} else {
    Write-Host "choco command no longer exists." -ForegroundColor Green
}

Write-Host "Deployment script completed successfully." -ForegroundColor Cyan
