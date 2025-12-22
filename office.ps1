#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Office Deployment Automation Script

.DESCRIPTION
    Downloads and installs Microsoft Office using the Office Deployment Tool (ODT).
    This script is called by setup.ps1 and should not be run directly.

.NOTES
    Author: Damian Korver
    Requires: PowerShell 5.1 or later
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import shared functions module
Import-Module (Join-Path $PSScriptRoot 'functions.psd1')

# ============================
# Constants
# ============================
$WorkingDir = Join-Path $env:TEMP 'OfficeInstall'
$OdtUrl = 'https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_18827-20140.exe'
$OdtExe = Join-Path $WorkingDir 'odt.exe'
$SetupExe = Join-Path $WorkingDir 'setup.exe'
$ConfigSource = Join-Path $PSScriptRoot 'office-configuration.xml'
$ConfigPath = Join-Path $WorkingDir 'configuration.xml'

$OfficePaths = @(
    'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE',
    'C:\Program Files (x86)\Microsoft Office\root\Office16\WINWORD.EXE'
)

# ============================
# Helper Functions
# ============================
function Test-OfficeInstalled {
    foreach ($path in $OfficePaths) {
        if (Test-Path $path) {
            return $true
        }
    }
    return $false
}

function Invoke-Process {
    param (
        [Parameter(Mandatory)]
        [string]
        $FilePath,

        [string[]]
        $ArgumentList
    )

    try {
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -NoNewWindow
    }
    catch {
        throw "Process execution failed: $_"
    }
}

# ============================
# Main Execution
# ============================
try {
    Write-LogEntry "Office Deployment Script started"

    # Check if Office is already installed
    if (Test-OfficeInstalled) {
        Write-LogEntry "Office is already installed. Skipping."
        return
    }

    # Ensure working directory exists
    if (-not (Test-Path $WorkingDir)) {
        New-Item -Path $WorkingDir -ItemType Directory -Force | Out-Null
    }

    # Download ODT if needed
    if (-not (Test-Path $OdtExe)) {
        Write-LogEntry "Downloading Office Deployment Tool..."
        Invoke-WebRequest -Uri $OdtUrl -OutFile $OdtExe
    }
    else {
        Write-LogEntry "ODT already downloaded"
    }

    # Extract ODT if needed
    if (-not (Test-Path $SetupExe)) {
        Write-LogEntry "Extracting Office Deployment Tool..."
        Invoke-Process -FilePath $OdtExe -ArgumentList "/extract:`"$WorkingDir`"", '/quiet'
    }
    else {
        Write-LogEntry "ODT already extracted"
    }

    # Copy configuration file
    Write-LogEntry "Copying Office configuration..."
    Copy-Item -Path $ConfigSource -Destination $ConfigPath -Force

    # Download Office installation files
    Write-LogEntry "Downloading Office installation files (this may take several minutes)..."
    Invoke-Process -FilePath $SetupExe -ArgumentList "/download", "`"$ConfigPath`""

    # Install Office
    Write-LogEntry "Installing Office..."
    Invoke-Process -FilePath $SetupExe -ArgumentList "/configure", "`"$ConfigPath`""

    Write-LogEntry "Office installation completed"
}
catch {
    Write-LogEntry "Office installation failed: $_" -Level Error
    exit 1
}
