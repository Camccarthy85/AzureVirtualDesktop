#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Installs WinGet + dependencies on Windows 11 Multi-Session (AVD) and installs a list of apps.
    Updated for dynamic UI.Xaml version fetching (as of Oct 2025).

.DESCRIPTION
    - Dynamically fetches latest 2.8.x UI.Xaml from NuGet API.
    - Downloads VCLibs and WinGet for current architecture.
    - Installs machine-wide with Add-AppxPackage.
    - Adds winget to HKLM PATH.
    - Installs apps from $AppsToInstall.

.NOTES
    Run as SYSTEM during AVD image provisioning.
    Logs to console for CSE diagnostics.
#>

# -------------------------------------------------
# Configuration
# -------------------------------------------------
$AppsToInstall = @(
    "Microsoft.WindowsCamera"
    "Microsoft.Teams"
    "Google.Chrome"
    "Notepad++.Notepad++"
    # Add more winget IDs here
)

# Temp folder (cleaned up at end)
$TempDir = Join-Path $env:TEMP "WinGetInstall_$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Write-Host "Temp dir: $TempDir"

# -------------------------------------------------
# Helper functions
# -------------------------------------------------
function Get-LatestWinGetRelease {
    try {
        $api = "https://api.github.com/repos/microsoft/winget-cli/releases"
        $releases = Invoke-RestMethod -Uri $api -UseBasicParsing -ErrorAction Stop
        $latest = $releases | Where-Object { $_.prerelease -eq $false } | Select-Object -First 1

        $assetBundle = $latest.assets | Where-Object { $_.name -like "*msixbundle" } | Select-Object -First 1
        $assetLicense = $latest.assets | Where-Object { $_.name -eq "License1.xml" } | Select-Object -First 1

        if (-not $assetBundle -or -not $assetLicense) { throw "Missing assets in release" }

        [PSCustomObject]@{
            Version = $latest.tag_name.TrimStart('v')
            BundleUrl = $assetBundle.browser_download_url
            LicenseUrl = $assetLicense.browser_download_url
        }
    } catch {
        Write-Error "Failed to fetch WinGet release: $_"
        throw
    }
}

function Get-Architecture {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        default { "x86" }
    }
}

function Get-LatestUIXamlVersion {
    try {
        # Fetch NuGet search for Microsoft.UI.Xaml, filter to latest 2.8.x
        $searchApi = "https://azuresearch-usnc.nuget.org/query?q=Microsoft.UI.Xaml&prerelease=false&semVerLevel=2.0.0"
        $searchResult = Invoke-RestMethod -Uri $searchApi -UseBasicParsing -ErrorAction Stop
        $versions = $searchResult.data | ForEach-Object { $_.version } | Where-Object { $_ -like "2.8.*" } | Sort-Object { [Version]$_ } -Descending
        if ($versions) { return $versions[0] }
        else { throw "No 2.8.x versions found" }
    } catch {
        Write-Warning "Failed to fetch UI.Xaml version: $_ . Using fallback 2.8.7"
        return "2.8.7"
    }
}

function Download-File ($Url, $Destination) {
    if ([string]::IsNullOrEmpty($Url)) { throw "Download URL is null or empty" }
    Write-Host "Downloading $Url -> $Destination"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
}

# -------------------------------------------------
# 1. Get latest WinGet release info
# -------------------------------------------------
Write-Host "Fetching WinGet release..."
$wg = Get-LatestWinGetRelease
Write-Host "Latest stable WinGet: $($wg.Version)"

$bundlePath   = Join-Path $TempDir "Microsoft.DesktopAppInstaller.msixbundle"
$licensePath  = Join-Path $TempDir "License1.xml"

Download-File $wg.BundleUrl  $bundlePath
Download-File $wg.LicenseUrl $licensePath

# -------------------------------------------------
# 2. VCLibs Desktop Framework (architecture specific)
# -------------------------------------------------
Write-Host "Fetching architecture..."
$arch = Get-Architecture
$vclibsUrl = "https://aka.ms/Microsoft.VCLibs.$arch.14.00.Desktop.appx"
$vclibsPath = Join-Path $TempDir "Microsoft.VCLibs.$arch.14.00.Desktop.appx"
Download-File $vclibsUrl $vclibsPath
Write-Host "VCLibs downloaded for $arch"

# -------------------------------------------------
# 3. Microsoft.UI.Xaml (dynamic 2.8.x version)
# -------------------------------------------------
Write-Host "Fetching latest UI.Xaml 2.8.x version..."
$uiXamlVersion = Get-LatestUIXamlVersion
Write-Host "Using UI.Xaml version: $uiXamlVersion"

$uiXamlNuGet = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/$uiXamlVersion"
$uiXamlZip   = Join-Path $TempDir "Microsoft.UI.Xaml.$uiXamlVersion.zip"
Download-File $uiXamlNuGet $uiXamlZip

# Extract the correct .appx
Write-Host "Extracting UI.Xaml for $arch..."
Expand-Archive -Path $uiXamlZip -DestinationPath "$TempDir\UIXamlZip" -Force -ErrorAction Stop
$uiXamlAppx = Get-ChildItem -Path "$TempDir\UIXamlZip\tools\AppX\$arch\Release" -Filter "*.appx" -ErrorAction Stop | Select-Object -First 1 -ExpandProperty FullName
if (-not $uiXamlAppx -or -not (Test-Path $uiXamlAppx)) { throw "UI.Xaml appx not found for $arch at $uiXamlAppx" }
Write-Host "UI.Xaml appx extracted: $uiXamlAppx"

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
    $resolved = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
}
if (-not (Test-Path $resolved)) { throw "winget.exe not found after install at $resolved" }

# Add folder to HKLM PATH
$winGetDir = Split-Path $resolved -Parent
$machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($machinePath -notlike "*$winGetDir*") {
    $newPath = "$machinePath;$winGetDir"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    $env:PATH += ";$winGetDir"
    Write-Host "Updated machine PATH with: $winGetDir"
}
Write-Host "winget.exe located at: $resolved"

# -------------------------------------------------
# 6. Test winget
# -------------------------------------------------
Write-Host "Testing winget..."
$wingetVersion = & winget --version 2>&1
if ($LASTEXITCODE -ne 0) { throw "winget test failed: $wingetVersion" }
Write-Host "WinGet version: $wingetVersion"

# -------------------------------------------------
# 7. Install requested applications (silent)
# -------------------------------------------------
foreach ($app in $AppsToInstall) {
    Write-Host "Installing $app ..."
    & winget install --id $app --silent --accept-package-agreements --accept-source-agreements --force 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install $app (exit code $LASTEXITCODE)"
    } else {
        Write-Host "Successfully installed $app"
    }
}

# -------------------------------------------------
# Cleanup
# -------------------------------------------------
Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
Write-Host "Installation complete! Exit code 0."
exit 0  # Explicit success for CSE
