#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Local test script for Windows Laptop Automation.

.DESCRIPTION
    Simulates the bootstrap process by creating a local test archive and running setup.ps1
    without downloading from GitHub. Useful for testing changes before release.

.PARAMETER SkipPackages
    Skip package installation during test.

.PARAMETER SkipProfile
    Skip PowerShell profile setup during test.

.PARAMETER Force
    Force overwrite of existing configurations.

.PARAMETER DownloadPath
    Path for temporary test files. Defaults to $env:TEMP.

.EXAMPLE
    .\run-test.ps1
    .\run-test.ps1 -SkipPackages -Force

.NOTES
    Author: Damian Korver
    Requires: PowerShell 5.1 or later
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [switch]
    $SkipPackages,

    [switch]
    $SkipProfile,

    [switch]
    $Force,

    [string]
    $DownloadPath = $env:TEMP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================
# Constants
# ============================
$TestZipPath = Join-Path $DownloadPath 'BootstrapTest.zip'
$ExtractPath = Join-Path $DownloadPath 'laptop-automation-temp'

# ============================
# Logging
# ============================
function Write-LogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]
        $Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[$timestamp]"

    switch ($Level) {
        'Info'    { Write-Information "$prefix $Message" -InformationAction Continue }
        'Warning' { Write-Warning "$prefix $Message" }
        'Error'   { Write-Error "$prefix $Message" }
    }
}

# ============================
# Helper Functions
# ============================
function Invoke-ArchiveCreation {
    Write-LogEntry "Creating test archive..."

    if (Test-Path $TestZipPath) {
        Remove-Item $TestZipPath -Force
    }

    $filesToZip = Get-ChildItem -Path . -File | Where-Object { $_.Name -ne 'run-test.ps1' }

    if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
        Compress-Archive -Path $filesToZip.FullName -DestinationPath $TestZipPath -Force
    }
    else {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        $zipArchive = [System.IO.Compression.ZipFile]::Open($TestZipPath, [System.IO.Compression.ZipArchiveMode]::Create)

        try {
            foreach ($file in $filesToZip) {
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipArchive, $file.FullName, $file.Name)
            }
        }
        finally {
            $zipArchive.Dispose()
        }
    }

    Write-LogEntry "Test archive created: $TestZipPath"
}

function Invoke-ArchiveExtraction {
    Write-LogEntry "Extracting archive to: $ExtractPath"

    if (Test-Path $ExtractPath) {
        Remove-Item $ExtractPath -Recurse -Force
    }

    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $TestZipPath -DestinationPath $ExtractPath -Force
    }
    else {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($TestZipPath, $ExtractPath)
    }

    Write-LogEntry "Extraction completed"
}

function Invoke-TestSetup {
    Write-LogEntry "Running setup.ps1 from extracted archive..."

    $setupScript = Get-ChildItem $ExtractPath -Recurse -Filter 'setup.ps1' -File | Select-Object -First 1

    if (-not $setupScript) {
        throw "setup.ps1 not found in extracted files"
    }

    Write-LogEntry "Found setup script: $($setupScript.FullName)"

    $setupParams = @{}
    if ($SkipPackages) { $setupParams['SkipPackages'] = $true }
    if ($SkipProfile) { $setupParams['SkipProfile'] = $true }
    if ($Force) { $setupParams['Force'] = $true }

    Push-Location $ExtractPath
    try {
        & $setupScript.FullName @setupParams
    }
    finally {
        Pop-Location
    }
}

function Invoke-Cleanup {
    @($TestZipPath, $ExtractPath) | ForEach-Object {
        if (Test-Path $_) {
            Write-LogEntry "Cleaning up: $_"
            Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================
# Main Execution
# ============================
try {
    Write-LogEntry "Starting local test of Windows Laptop Automation"

    Invoke-ArchiveCreation
    Invoke-ArchiveExtraction
    Invoke-TestSetup

    Write-LogEntry "Local test completed successfully!"
}
catch {
    Write-LogEntry "Test failed: $_" -Level Error
    exit 1
}
finally {
    Invoke-Cleanup
}
