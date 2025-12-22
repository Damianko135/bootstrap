#!/usr/bin/env pwsh
# Run Test Script for Windows Laptop Automation
# This script simulates the bootstrap process locally for testing

param (
    [switch] $SkipPackages,
    [switch] $SkipProfile,
    [switch] $Force,
    [string] $DownloadPath = $env:TEMP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] $Message"
    Write-Information $formatted -InformationAction Continue
}

Write-Log "Starting local test of Windows Laptop Automation Setup"

# Simulate the bootstrap process by creating and extracting a zip archive
$zipFilePath = "$DownloadPath\BootstrapTest.zip"
$extractPath = "$DownloadPath\laptop-automation-temp"

# Remove existing files
if (Test-Path $zipFilePath) {
    Write-Log "Removing existing test zip file..."
    Remove-Item $zipFilePath -Force
}

if (Test-Path $extractPath) {
    Write-Log "Removing existing test directory..."
    Remove-Item $extractPath -Recurse -Force
}

Write-Log "Creating test zip archive..."

# Create zip archive of current directory contents (excluding .git and run-test.ps1)
$filesToZip = Get-ChildItem -Path . -File | Where-Object {
    $_.Name -ne "run-test.ps1"
}

if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
    Compress-Archive -Path $filesToZip.FullName -DestinationPath $zipFilePath -Force
} else {
    # Fallback for older PowerShell versions
    Write-Log "Compress-Archive not available, using .NET compression..."
    if (-not ("System.IO.Compression.ZipFile" -as [type])) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }
    $zipArchive = [System.IO.Compression.ZipFile]::Open($zipFilePath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $filesToZip) {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipArchive, $file.FullName, $file.Name)
        }
    } finally {
        $zipArchive.Dispose()
    }
}

Write-Log "Test zip created: $zipFilePath"

Write-Log "Extracting to: $extractPath"

# Extract the zip file
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

Write-Log "Extraction completed successfully"

# Run the test setup
try {
    # Find the setup script in the extracted files
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
    
    Write-Log "Arguments to pass to setup.ps1: $($arguments -join ' ')"
    
    # Run the setup script
    Push-Location $extractPath
    try {
        if ($arguments.Count -gt 0) {
            Write-Log "Running: & $setupScriptPath $($arguments -join ' ')"
            & $setupScriptPath @arguments
        } else {
            Write-Log "Running: & $setupScriptPath"
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
    # Cleanup test files
    try {
        if (Test-Path $zipFilePath) {
            Write-Log "Cleaning up test zip file..."
            Remove-Item $zipFilePath -Force
        }
        
        if (Test-Path $extractPath) {
            Write-Log "Cleaning up extracted test files..."
            Remove-Item $extractPath -Recurse -Force
        }
    } catch {
        Write-Log "Warning: Could not clean up test files: $($_.Exception.Message)"
    }
}

Write-Log "Local test completed!"
