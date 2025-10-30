#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    Installs WinGet and optional applications on AVD session hosts.
#>

# -------------------------------------------------
# CONFIG
# -------------------------------------------------
$AppsToInstall = @(
    "Google.Chrome",
    "Notepad++.Notepad++",
    "Microsoft.Teams"
)

# Winget build (2025-10 verified)
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
# TEMP FOLDER
# -------------------------------------------------
$TempDir = Join-Path $env:TEMP "WinGet_AVD_$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Write-Host "Temp folder: $TempDir"

# -------------------------------------------------
# FUNCTIONS
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
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
    } catch {
        throw ("Download failed: " + $Url + " - " + $_.Exception.Message)
    }
}

# -------------------------------------------------
# 1. DETECT ARCH
# -------------------------------------------------
$arch = Get-Arch
Write-Host "Architecture: $arch"

# -------------------------------------------------
# 2. DOWNLOAD FILES
# -------------------------------------------------
$bundlePath  = Join-Path $TempDir "WinGet.msixbundle"
$licensePath = Join-Path $TempDir "License1.xml"
Download $WinGet.BundleUrl  $bundlePath
Download $WinGet.LicenseUrl $licensePath

$vclibsPath = Join-Path $TempDir "VCLibs.$arch.appx"
Download ($VCLibsBase -f $arch) $vclibsPath

$zipPath = Join-Path $TempDir "UIXaml.zip"
Download $UIXaml.NuGetUrl $zipPath
$extractDir = Join-Path $TempDir "UIXamlZip"
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

$uiAppx = Join-Path $extractDir ($UIXaml.AppxPath -f $arch)
if (-not (Test-Path $uiAppx)) { throw "UI.Xaml appx not found: $uiAppx" }

# -------------------------------------------------
# 3. INSTALL DEPENDENCIES + WINGET
# -------------------------------------------------
Write-Host "Installing dependencies and WinGet..."

# Order matters: VCLibs → XAML → Winget
Add-AppxPackage -Path $vclibsPath -ErrorAction Stop
Add-AppxPackage -Path $uiAppx -ErrorAction Stop
Add-AppxPackage -Path $bundlePath -ErrorAction Stop

# Provision WinGet for all users (persistent on AVD)
Add-AppxProvisionedPackage -Online -PackagePath $bundlePath -LicensePath $licensePath -ErrorAction SilentlyContinue

# -------------------------------------------------
# 4. VALIDATE INSTALL
# -------------------------------------------------
Start-Sleep -Seconds 3
$wingetExe = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Recurse -Filter "winget.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wingetExe) { throw "winget.exe not found" }
Write-Host "winget.exe found at: $($wingetExe.FullName)"

# Add to PATH if missing
$winGetDir = Split-Path $wingetExe.FullName -Parent
$machinePath = [Environment]::GetEnvironmentVariable("PATH","Machine")
if ($machinePath -notlike "*$winGetDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$winGetDir", "Machine")
    $env:PATH += ";$winGetDir"
}

# Verify version
$ver = & $wingetExe.FullName --version 2>&1
if ($LASTEXITCODE) { throw "WinGet failed to launch: $ver" }
Write-Host "WinGet version: $ver"

# -------------------------------------------------
# 5. INSTALL APPS
# -------------------------------------------------
foreach ($app in $AppsToInstall) {
    Write-Host "Installing $app..."
    & $wingetExe.FullName install --id $app --silent --accept-package-agreements --accept-source-agreements --force
    if ($LASTEXITCODE) { Write-Warning "$app failed (code $LASTEXITCODE)" }
    else { Write-Host "$app installed successfully" }
}

# -------------------------------------------------
# 6. CLEANUP
# -------------------------------------------------
Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
Write-Host "=== INSTALLATION COMPLETE ==="
exit 0

