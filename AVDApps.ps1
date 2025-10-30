#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Installs WinGet + apps on Windows 11 Multi-Session (AVD) - CSE & GitHub safe
#>

# -------------------------------------------------
# CONFIG - EDIT THIS
# -------------------------------------------------
$AppsToInstall = @(
    "Microsoft.WindowsCamera"
    "Microsoft.Teams"
    "Google.Chrome"
    "Notepad++.Notepad++"
)

# -------------------------------------------------
# FIXED URLs (Oct 30, 2025) - NO API CALLS
# -------------------------------------------------
$WinGet = @{
    Version     = "1.9.0"
    BundleUrl   = "https://github.com/microsoft/winget-cli/releases/download/v1.9.0/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    LicenseUrl  = "https://github.com/microsoft/winget-cli/releases/download/v1.9.0/License1.xml"
}

$VCLibsBase = "https://aka.ms/Microsoft.VCLibs.{0}.14.00.Desktop.appx"

$UIXaml = @{
    Version   = "2.8.7"
    NuGetUrl  = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.7"
    AppxPath  = "tools\AppX\{0}\Release\Microsoft.UI.Xaml.2.8.appx"
}

# -------------------------------------------------
# Temp folder
# -------------------------------------------------
$TempDir = Join-Path $env:TEMP "WinGet_AVD_$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Write-Host "Temp folder: $TempDir"

# -------------------------------------------------
# Helpers
# -------------------------------------------------
function Get-Arch {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        default { "x86" }
    }
}

function Download ($Url, $Dest) {
    if (-not $Url) { throw "URL is empty" }
    Write-Host "Downloading $Url -> $Dest"
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
}

# -------------------------------------------------
# 1. Architecture
# -------------------------------------------------
$arch = Get-Arch
Write-Host "Architecture: $arch"

# -------------------------------------------------
# 2. Download WinGet
# -------------------------------------------------
$bundlePath  = Join-Path $TempDir "WinGet.msixbundle"
$licensePath = Join-Path $TempDir "License1.xml"
Download $WinGet.BundleUrl  $bundlePath
Download $WinGet.LicenseUrl $licensePath

# -------------------------------------------------
# 3. VCLibs
# -------------------------------------------------
$vclibsUrl  = $VCLibsBase -f $arch
$vclibsPath = Join-Path $TempDir "VCLibs.$arch.appx"
Download $vclibsUrl $vclibsPath

# -------------------------------------------------
# 4. UI.Xaml
# -------------------------------------------------
$zipPath = Join-Path $TempDir "UIXaml.zip"
Download $UIXaml.NuGetUrl $zipPath

$extractDir = Join-Path $TempDir "UIXamlZip"
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force -ErrorAction Stop

$uiAppx = Join-Path $extractDir ($UIXaml.AppxPath -f $arch)
if (-not (Test-Path $uiAppx)) { throw "UI.Xaml appx not found: $uiAppx" }

# -------------------------------------------------
# 5. Install
# -------------------------------------------------
Write-Host "Installing VCLibs..."
Add-AppxPackage -Path $vclibsPath -ErrorAction Stop

Write-Host "Installing UI.Xaml..."
Add-AppxPackage -Path $uiAppx -ErrorAction Stop

Write-Host "Installing WinGet..."
Add-AppxPackage -Path $bundlePath -ErrorAction Stop

Write-Host "Provisioning WinGet..."
Add-AppxProvisionedPackage -Online -PackagePath $bundlePath -LicensePath $licensePath -ErrorAction Stop

# -------------------------------------------------
# 6. PATH
# -------------------------------------------------
$wingetExe = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*\winget.exe" -ErrorAction SilentlyContinue).FullName
if (-not $wingetExe) { $wingetExe = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
if (-not (Test-Path $wingetExe)) { throw "winget.exe not found" }

$winGetDir = Split-Path $wingetExe -Parent
$machinePath = [Environment]::GetEnvironmentVariable("PATH","Machine")
if ($machinePath -notlike "*$winGetDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$winGetDir", "Machine")
    $env:PATH += ";$winGetDir"
}
Write-Host "winget.exe at: $wingetExe"

# -------------------------------------------------
# 7. Test
# -------------------------------------------------
$ver = & winget --version 2>&1
if ($LASTEXITCODE) { throw "winget failed: $ver" }
Write-Host "WinGet version: $ver"

# -------------------------------------------------
# 8. Install Apps
# -------------------------------------------------
foreach ($app in $AppsToInstall) {
    Write-Host "Installing $app..."
    & winget install --id $app --silent --accept-package-agreements --accept-source-agreements --force
    if ($LASTEXITCODE) { Write-Warning "$app failed (code $LASTEXITCODE)" }
    else { Write-Host "$app installed" }
}

# -------------------------------------------------
# Cleanup
# -------------------------------------------------
Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
Write-Host "=== INSTALLATION COMPLETE - EXIT 0 ==="
exit 0
