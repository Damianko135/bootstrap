#!/usr/bin/env pwsh
# Bootstrap Script for Windows Laptop Automation
# Author: Damian Korver
# Description: Downloads the latest release and runs the setup script
# This script is designed to be run in PowerShell 5.1 or later.
# Use the following command to run it on a fresh Windows installation:
# Aliases: IWR (Invoke-WebRequest); IEX (Invoke-Expression)
# iwr "https://raw.githubusercontent.com/Damianko135/Damianko135/main/laptopAutomation/windows/bootstrap.ps1" -OutFile "$env:TEMP\bootstrap.ps1"; powershell -nop -ep Bypass -f "$env:TEMP\bootstrap.ps1"
# Or use this one-liner:
# iwr "https://raw.githubusercontent.com/Damianko135/Damianko135/main/laptopAutomation/windows/bootstrap.ps1" | iex


#Requires -Version 5.1

param (
    [switch] $SkipPackages,
    [switch] $SkipProfile,
    [switch] $Force,
    [string] $DownloadPath = $env:TEMP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging function
# Parameters:
#   - Message: The log message to display.
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] $Message"
    Write-Information $formatted -InformationAction Continue
}

# Set the GitHub repository owner (username or organization)
$repoOwner = "Damianko135"
# Set the GitHub repository name
$repoName = "Damianko135"
$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
# NOTE: If the repository owner and name differ, update these variables accordingly.

Write-Log "Bootstrap: Windows Laptop Automation Setup"
Write-Log "Repository: $repoOwner/$repoName"

try {
    # Get latest release information
    Write-Log "Fetching latest release information..."
    $latestRelease = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "PowerShell-Bootstrap" }
    
    $tagName = $latestRelease.tag_name
    $releaseName = $latestRelease.name
    Write-Log "Latest release: $releaseName ($tagName)"
    
    # Find the Windows automation zip asset
    $windowsAsset = $latestRelease.assets | Where-Object { $_.name -like "*Bootstrap*" }
    
    if (-not $windowsAsset) {
        # Fallback to any zip asset
        $windowsAsset = $latestRelease.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    }
    
    if (-not $windowsAsset) {
        Write-Log "No suitable zip asset found in release. Available assets:"
        $latestRelease.assets | ForEach-Object { Write-Log "  - $($_.name)" }
        throw "No zip asset found in the latest release"
    }
    
    # Use the release asset download URL
    $downloadUrl = $windowsAsset.browser_download_url
    $zipFileName = $windowsAsset.name
    $zipFilePath = Join-Path $DownloadPath $zipFileName
    
    Write-Log "Selected asset: $($windowsAsset.name)"
    
    # Download with better compatibility
    Write-Log "Downloading release from: $downloadUrl"
    Write-Log "Saving to: $zipFilePath"
    
    # Remove existing zip if it exists
    if (Test-Path $zipFilePath) {
        Write-Log "Removing existing zip file..."
        Remove-Item $zipFilePath -Force
    }
    
    # Use Invoke-WebRequest for better PowerShell 5.1 compatibility
    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell 6+ method
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -UseBasicParsing
        } else {
            # PowerShell 5.1 method - disable progress bar for performance
            $oldProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -UseBasicParsing
            } finally {
                $ProgressPreference = $oldProgressPreference
            }
        }
    } catch {
        # Fallback to WebClient if Invoke-WebRequest fails
        Write-Log "Invoke-WebRequest failed, trying WebClient..."
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($downloadUrl, $zipFilePath)
    }
    
    if (-not (Test-Path $zipFilePath)) {
        throw "Failed to download the release zip file"
    }
    
    Write-Log "Download completed successfully"
    
    # Extract the zip file
    $extractPath = Join-Path $DownloadPath "laptop-automation-temp"
    
    # Remove existing extraction directory
    if (Test-Path $extractPath) {
        Write-Log "Removing existing extraction directory..."
        Remove-Item $extractPath -Recurse -Force
    }
    
    Write-Log "Extracting to: $extractPath"
    
    # Use Expand-Archive with PowerShell 5.1+ compatibility
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force
    } else {
        # Fallback for very old PowerShell versions
        Write-Log "Expand-Archive not available, using .NET extraction..."
        if (-not ("System.IO.Compression.ZipFile" -as [type])) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $extractPath)
    }
    
    # Find the setup script (look for it in the extracted contents)
    Write-Log "Searching for setup.ps1..."
    $setupScript = Get-ChildItem $extractPath -Recurse -File -Filter "setup.ps1" | Select-Object -First 1
    
    if ($setupScript) {
        $setupScriptPath = $setupScript.FullName
        Write-Log "Found setup script: $setupScriptPath"
    } else {
        Write-Log "Setup script not found. Listing extracted contents:"
        Get-ChildItem $extractPath -Recurse | ForEach-Object {
            Write-Log "  $($_.FullName)"
        }
        throw "Could not find setup.ps1 in the extracted files"
    }
    
    # Build arguments for the setup script
    $arguments = @()
    if ($SkipPackages) { $arguments += "-SkipPackages" }
    if ($SkipProfile) { $arguments += "-SkipProfile" }
    if ($Force) { $arguments += "-Force" }
    
    # Run the setup script
    Push-Location $extractPath
    try {
        if ($arguments.Count -gt 0) {
            & $setupScriptPath @arguments
        } else {
            & $setupScriptPath
        }
        $setupSucceeded = $?
    } finally {
        Pop-Location
    }
    
    if ($setupSucceeded) {
        Write-Log "Setup completed successfully!"
    } else {
        Write-Log "Setup script failed to complete successfully."
        exit 1
    }
    
} catch {
    Write-Log "Bootstrap failed: $($_.Exception.Message)"
    Write-Log "Error details: $($_.ScriptStackTrace)"
    exit 1
} finally {
    # Cleanup downloaded files
    try {
        if (Test-Path $zipFilePath) {
            Write-Log "Cleaning up downloaded zip file..."
            Remove-Item $zipFilePath -Force
        }
        
        if (Test-Path $extractPath) {
            Write-Log "Cleaning up extracted files..."
            Remove-Item $extractPath -Recurse -Force
        }
    } catch {
        Write-Log "Warning: Could not clean up temporary files: $($_.Exception.Message)"
    }
}

Write-Log "Bootstrap completed!"
