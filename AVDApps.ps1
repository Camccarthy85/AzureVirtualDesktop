#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Installs WinGet + dependencies on Windows 11 Multi-Session (AVD) and installs a list of apps.

.DESCRIPTION
    - Downloads the latest stable WinGet release from GitHub.
    - Downloads VCLibs and Microsoft.UI.Xaml for the current architecture.
    - Installs everything with Add-AppxPackage (no Store needed).
    - Adds winget to the machine PATH (HKLM).
    - Installs the apps listed in $AppsToInstall.

.NOTES
    Run during image creation / provisioning (e.g. in a Custom Script Extension or Packer provisioner).
    Tested on Windows 11 24H2 Multi-Session (AVD).
#>

# -------------------------------------------------
# Configuration
# -------------------------------------------------
$AppsToInstall = @(
    "Microsoft.WindowsCamera"
    "Microsoft.Teams"
    "Google.Chrome"
    "Notepad++.Notepad++"
    # Add any other winget IDs here
)

# Temp folder (cleaned up at the end)
$TempDir = Join-Path $env:TEMP "WinGetInstall_$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# -------------------------------------------------
# Helper functions
# -------------------------------------------------
function Get-LatestWinGetRelease {
    $api = "https://api.github.com/repos/microsoft/winget-cli/releases"
    $releases = Invoke-RestMethod -Uri $api -UseBasicParsing
    $latest = $releases | Where-Object { $_.prerelease -eq $false } | Select-Object -First 1

    $assetBundle = $latest.assets | Where-Object { $_.name -like "*msixbundle" }
    $assetLicense = $latest.assets | Where-Object { $_.name -eq "License1.xml" }

    [PSCustomObject]@{
        Version = $latest.tag_name.TrimStart('v')
        BundleUrl = $assetBundle.browser_download_url
        LicenseUrl = $assetLicense.browser_download_url
    }
}

function Get-Architecture {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        default { "x86" }
    }
}

function Download-File ($Url, $Destination) {
    Write-Host "Downloading $Url -> $Destination"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

# -------------------------------------------------
# 1. Get latest WinGet release info
# -------------------------------------------------
$wg = Get-LatestWinGetRelease
Write-Host "Latest stable WinGet: $($wg.Version)"

$bundlePath   = Join-Path $TempDir "Microsoft.DesktopAppInstaller.msixbundle"
$licensePath  = Join-Path $TempDir "License1.xml"

Download-File $wg.BundleUrl  $bundlePath
Download-File $wg.LicenseUrl $licensePath

# -------------------------------------------------
# 2. VCLibs Desktop Framework (architecture specific)
# -------------------------------------------------
$arch = Get-Architecture
$vclibsUrl = "https://aka.ms/Microsoft.VCLibs.$arch.14.00.Desktop.appx"
$vclibsPath = Join-Path $TempDir "Microsoft.VCLibs.$arch.14.00.Desktop.appx"
Download-File $vclibsUrl $vclibsPath

# -------------------------------------------------
# 3. Microsoft.UI.Xaml (latest 2.8.x – works for all recent WinGet)
# -------------------------------------------------
# NuGet page: https://www.nuget.org/packages/Microsoft.UI.Xaml
# We fetch the newest 2.8.x package (as of 2025-10 the latest is 2.8.6)
$uiXamlVersion = "2.8.6"   # <-- update if a newer 2.8.x appears
$uiXamlNuGet = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/$uiXamlVersion"
$uiXamlZip   = Join-Path $TempDir "Microsoft.UI.Xaml.$uiXamlVersion.zip"
Download-File $uiXamlNuGet $uiXamlZip

# Extract the correct .appx from the zip
Expand-Archive -Path $uiXamlZip -DestinationPath "$TempDir\UIXamlZip" -Force
$uiXamlAppx = Get-ChildItem -Path "$TempDir\UIXamlZip\tools\AppX\$arch\Release" -Filter "*.appx" | Select-Object -First 1 -ExpandProperty FullName
if (-not $uiXamlAppx) { throw "UI.Xaml appx not found for $arch" }

# -------------------------------------------------
# 4. Install dependencies + WinGet (machine-wide)
# -------------------------------------------------
Write-Host "Installing VCLibs..."
Add-AppxPackage -Path $vclibsPath -ErrorAction Stop

Write-Host "Installing Microsoft.UI.Xaml..."
Add-AppxPackage -Path $uiXamlAppx -ErrorAction Stop

Write-Host "Installing WinGet bundle..."
Add-AppxPackage -Path $bundlePath -ErrorAction Stop

Write-Host "Provisioning WinGet with license (machine-wide)..."
Add-AppxProvisionedPackage -Online -PackagePath $bundlePath -LicensePath $licensePath -ErrorAction Stop

# -------------------------------------------------
# 5. Ensure winget.exe is on the machine PATH
# -------------------------------------------------
$wingetExe = "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*\winget.exe"
$resolved = (Get-Item $wingetExe -ErrorAction SilentlyContinue).FullName
if (-not $resolved) {
    # Fallback: search under LocalState (per-user install)
    $resolved = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
}
if (-not (Test-Path $resolved)) { throw "winget.exe not found after install" }

# Add the folder to HKLM PATH (persists for all users)
$winGetDir = Split-Path $resolved -Parent
$machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($machinePath -notlike "*$winGetDir*") {
    $newPath = "$machinePath;$winGetDir"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    $env:PATH += ";$winGetDir"
}
Write-Host "winget.exe located at: $resolved"

# -------------------------------------------------
# 6. Test winget
# -------------------------------------------------
& winget --version | Out-String | Write-Host

# -------------------------------------------------
# 7. Install requested applications (silent, no prompts)
# -------------------------------------------------
foreach ($app in $AppsToInstall) {
    Write-Host "Installing $app ..."
    & winget install --id $app --silent --accept-package-agreements --accept-source-agreements --force
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install $app (exit code $LASTEXITCODE)"
    }
}

# -------------------------------------------------
# Cleanup
# -------------------------------------------------
Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
Write-Host "Installation complete!"
