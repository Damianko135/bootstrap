# Office Deployment Automation Script
# Author: Damian Korver

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] $Message"
    Write-Information $formatted -InformationAction Continue
}

$workingDir = "$env:TEMP\OfficeInstall"
$odtUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_18827-20140.exe"
$odtExe = Join-Path $workingDir "odt.exe"
$setupExe = Join-Path $workingDir "setup.exe"
$configSource = Join-Path $PSScriptRoot "office-configuration.xml"
$configPath = Join-Path $workingDir "configuration.xml"

# Function to check if Office is installed
function Test-OfficeInstalled {
    # Check for common Office executables
    $officePaths = @(
        "C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE",
        "C:\Program Files (x86)\Microsoft Office\root\Office16\WINWORD.EXE"
    )
    foreach ($path in $officePaths) {
        if (Test-Path $path) {
            return $true
        }
    }
    return $false
}

# Check if Office is already installed
if (Test-OfficeInstalled) {
    Write-Log "Office is already installed. Skipping installation."
    exit 0
}

# Ensure working directory exists
if (-Not (Test-Path $workingDir)) {
    New-Item -Path $workingDir -ItemType Directory -Force | Out-Null
}

# Download ODT if not already downloaded
if (-Not (Test-Path $odtExe)) {
    Write-Log "Downloading Office Deployment Tool..."
    Invoke-WebRequest -Uri $odtUrl -OutFile $odtExe
} else {
    Write-Log "ODT already downloaded."
}

# Extract ODT if setup.exe not already present
if (-Not (Test-Path $setupExe)) {
    Write-Log "Extracting Office Deployment Tool..."
    try {
        Start-Process -FilePath $odtExe -ArgumentList "/extract:`"$workingDir`" /quiet" -Wait
    } catch {
        Write-Log "Failed to extract Office Deployment Tool: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Log "ODT already extracted."
}

# Copy config XML
if (-Not (Test-Path $configSource)) {
    Write-Log "Missing config file: $configSource"
    exit 1
}
Copy-Item -Path $configSource -Destination $configPath -Force
Write-Log "Using Office config from: $configSource"

# Download Office installation files
Write-Log "Downloading Office installation files (this may take a while)..."
try {
    Start-Process -FilePath $setupExe -ArgumentList "/download `"$configPath`"" -Wait
} catch {
    Write-Log "Failed to download Office installation files: $($_.Exception.Message)"
    exit 1
}

# Install Office
Write-Log "Installing Office..."
try {
    Start-Process -FilePath $setupExe -ArgumentList "/configure `"$configPath`"" -Wait
} catch {
    Write-Log "Failed to install Office: $($_.Exception.Message)"
    exit 1
}

Write-Log "Office installation process finished."
