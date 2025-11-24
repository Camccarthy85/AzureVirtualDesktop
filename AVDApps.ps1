# PowerShell Script to Download and Install Latest Versions of Specified Apps
# Uses only built-in PowerShell cmdlets (Invoke-WebRequest, Invoke-RestMethod, Start-Process, etc.)
# Run as Administrator for installations

# Function to check if an app is installed
function Test-AppInstalled {
    param(
        [string]$DisplayName
    )
    
    $uninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    foreach ($path in $uninstallPaths) {
        try {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$DisplayName*" }
            if ($apps) {
                Write-Host "$DisplayName is already installed. Skipping."
                return $true
            }
        }
        catch {
            # Ignore errors if path doesn't exist
        }
    }
    return $false
}

# Function to install an app from GitHub release
function Install-GitHubApp {
    param(
        [string]$RepoOwner,
        [string]$RepoName,
        [string]$AssetPattern,
        [string]$InstallerPath,
        [string]$SilentArgs,
        [string]$AppName,
        [bool]$IsMsi = $false
    )
    
    if (Test-AppInstalled $AppName) { return }
    
    try {
        $latestRelease = Invoke-RestMethod "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
        $asset = $latestRelease.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
        if (-not $asset) {
            Write-Warning "No matching asset found for $RepoName"
            return
        }
        
        $downloadUrl = $asset.browser_download_url
        Write-Host "Downloading $RepoName from $downloadUrl"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $InstallerPath
        
        Write-Host "Installing $RepoName..."
        if ($IsMsi) {
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$InstallerPath`" $SilentArgs" -Wait -NoNewWindow
        } else {
            Start-Process -FilePath $InstallerPath -ArgumentList $SilentArgs -Wait -NoNewWindow
        }
        Write-Host "$RepoName installed successfully."
    }
    catch {
        Write-Error "Failed to install $RepoName : $_"
    }
}

# Temporary directory for downloads
$tempDir = "$env:TEMP\AppInstallers"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

# 1. Notepad++
if (-not (Test-AppInstalled "Notepad++")) {
    $npPath = "$tempDir\npp-installer.exe"
    Install-GitHubApp -RepoOwner "notepad-plus-plus" -RepoName "notepad-plus-plus" -AssetPattern "Installer.*x64.*\.exe$" -InstallerPath $npPath -SilentArgs "/S" -AppName "Notepad++"
}

# 2. Google Chrome Enterprise x64
if (-not (Test-AppInstalled "Google Chrome")) {
    $chromeMsiPath = "$tempDir\GoogleChromeEnterprise.msi"
    $chromeUrl = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
    Write-Host "Downloading Google Chrome Enterprise x64..."
    Invoke-WebRequest -Uri $chromeUrl -OutFile $chromeMsiPath
    Write-Host "Installing Google Chrome Enterprise..."
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$chromeMsiPath`" /qn /norestart" -Wait -NoNewWindow
    Write-Host "Google Chrome Enterprise installed successfully."
}

# 3. MongoDB Compass
if (-not (Test-AppInstalled "MongoDB Compass")) {
    $compassPageUrl = "https://www.mongodb.com/try/download/compass"
    Write-Host "Fetching MongoDB Compass latest page..."
    $compassContent = (Invoke-WebRequest -Uri $compassPageUrl -UseBasicParsing).Content
    $verMatch = [regex]::Match($compassContent, '(\d+\.\d+\.\d+) \(Stable\)')
    if ($verMatch.Success) {
        $version = $verMatch.Groups[1].Value
        $compassMsiUrl = "https://downloads.mongodb.com/compass/mongodb-compass-$version-win32-x64.msi"
        $compassPath = "$tempDir\mongodb-compass.msi"
        Write-Host "Downloading MongoDB Compass from $compassMsiUrl"
        Invoke-WebRequest -Uri $compassMsiUrl -OutFile $compassPath
        Write-Host "Installing MongoDB Compass..."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$compassPath`" /qn /norestart" -Wait -NoNewWindow
        Write-Host "MongoDB Compass installed successfully."
    } else {
        Write-Warning "Could not find MongoDB Compass version. Skipping."
    }
}

# 4. Visual Studio Code (System-wide)
if (-not (Test-AppInstalled "Visual Studio Code")) {
    $vscodeUrl = "https://update.code.visualstudio.com/latest/win32-x64/stable"
    $vscodePath = "$tempDir\vscode-setup.exe"
    Write-Host "Downloading Visual Studio Code (system-wide)..."
    Invoke-WebRequest -Uri $vscodeUrl -OutFile $vscodePath
    Write-Host "Installing Visual Studio Code..."
    Start-Process -FilePath $vscodePath -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=!runcode" -Wait -NoNewWindow
    Write-Host "Visual Studio Code installed successfully."
}

# 5. mRemoteNG
Install-GitHubApp -RepoOwner "mRemoteNG" -RepoName "mRemoteNG" -AssetPattern "mRemoteNG-Installer-.*\.msi$" -InstallerPath "$tempDir\mremoteng.msi" -SilentArgs "/qn /l*v `"$tempDir\mremoteng.log`" REBOOT=ReallySuppress ALLUSERS=1" -AppName "mRemoteNG" -IsMsi $true

# 6. SQL Server Management Studio 22
if (-not (Test-AppInstalled "SQL Server Management Studio")) {
    $ssmsUrl = "https://aka.ms/ssms/22/release/vs_SSMS.exe"
    $ssmsPath = "$tempDir\vs_SSMS.exe"
    $ssmsInstallPath = "C:\Program Files\Microsoft SQL Server Management Studio 22\Release"
    Write-Host "Downloading SSMS 22..."
    Invoke-WebRequest -Uri $ssmsUrl -OutFile $ssmsPath
    Write-Host "Installing SSMS 22..."
    Start-Process -FilePath $ssmsPath -ArgumentList "--quiet --norestart --installPath `"$ssmsInstallPath`" --add SSMS" -Wait -NoNewWindow
    Write-Host "SSMS 22 installed successfully."
}

# 7. RSAT Active Directory Tools
$rsatName = "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
$rsatCap = Get-WindowsCapability -Online -Name $rsatName -ErrorAction SilentlyContinue
if ($rsatCap -and $rsatCap.State -eq "Installed") {
    Write-Host "RSAT Active Directory Tools are already installed. Skipping."
} else {
    Write-Host "Installing RSAT Active Directory Tools..."
    Add-WindowsCapability -Online -Name $rsatName
    Write-Host "RSAT Active Directory Tools installed successfully."
}

# 8. PuTTY
if (-not (Test-AppInstalled "PuTTY")) {
    # Parse the latest.html page to get version and construct MSI URL
    $puttyPageUrl = "https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html"
    Write-Host "Fetching PuTTY latest page..."
    $puttyContent = (Invoke-WebRequest -Uri $puttyPageUrl -UseBasicParsing).Content
    $versionMatch = [regex]::Match($puttyContent, 'Currently this is (\d+\.\d+)')
    if ($versionMatch.Success) {
        $version = $versionMatch.Groups[1].Value
        $puttyMsiUrl = "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-$version-installer.msi"
        $puttyPath = "$tempDir\putty.msi"
        Write-Host "Downloading PuTTY from $puttyMsiUrl"
        Invoke-WebRequest -Uri $puttyMsiUrl -OutFile $puttyPath
        Write-Host "Installing PuTTY..."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$puttyPath`" /quiet /norestart" -Wait -NoNewWindow
        Write-Host "PuTTY installed successfully."
    } else {
        Write-Warning "Could not find PuTTY version. Skipping."
    }
}

# Configure FSLogix Profile Containers Registry Settings
Write-Host "Configuring FSLogix Profile Containers..."
$fslogixPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
if (!(Test-Path $fslogixPath)) {
    New-Item -Path $fslogixPath -Force | Out-Null
}

# Enable Profile Containers
Set-ItemProperty -Path $fslogixPath -Name "Enabled" -Value 1 -Type DWord

# VHD Locations
Set-ItemProperty -Path $fslogixPath -Name "VHDLocations" -Value @("\\vpcuvadpsa1.file.core.windows.net\fslogix-vhd-desktop-c1-pool") -Type MultiString

# Delete local profile when VHD should apply
Set-ItemProperty -Path $fslogixPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWord

# Is dynamic VHD
Set-ItemProperty -Path $fslogixPath -Name "IsDynamic" -Value 1 -Type DWord

# Prevent login with failure
Set-ItemProperty -Path $fslogixPath -Name "PreventLoginWithFailure" -Value 1 -Type DWord

# Prevent login with temp profile
Set-ItemProperty -Path $fslogixPath -Name "PreventLoginWithTempProfile" -Value 1 -Type DWord

# Redirection XML source folder
Set-ItemProperty -Path $fslogixPath -Name "RedirXMLSourceFolder" -Value "\\vpcuvadpsa1.file.core.windows.net\vad-misc-files" -Type String

# Flip Flop Profile Directory Name
Set-ItemProperty -Path $fslogixPath -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWord

# Volume Type VHDX
Set-ItemProperty -Path $fslogixPath -Name "VolumeType" -Value "vhdx" -Type String

Write-Host "FSLogix configuration completed."

# Cleanup (optional)
# Remove-Item -Path $tempDir -Recurse -Force

Write-Host "All installations and configurations completed."
