#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bootstrap script for Windows Laptop Automation.

.DESCRIPTION
    Downloads the latest release from GitHub and executes the setup script.

.PARAMETER SkipPackages
    Skip package installation.

.PARAMETER SkipProfile
    Skip PowerShell profile setup.

.PARAMETER Force
    Force overwrite of existing configurations.

.PARAMETER DownloadPath
    Path to download release files. Defaults to $env:TEMP.

.EXAMPLE
    .\bootstrap.ps1
    .\bootstrap.ps1 -Force -SkipPackages
    iwr "https://raw.githubusercontent.com/Damianko135/bootstrap/master/bootstrap.ps1" | iex

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
$ProgressPreference = 'SilentlyContinue'

# Import shared functions module
Import-Module (Join-Path $PSScriptRoot 'functions.psd1')

# ============================
# Constants
# ============================
$RepoOwner = 'Damianko135'

# ============================
# Main Functions
# ============================
function Get-LatestReleaseAsset {
    Write-LogEntry "Fetching latest release from $GitHubApiUrl"

    $release = Invoke-RestMethod -Uri $GitHubApiUrl -Headers @{ 'User-Agent' = 'PowerShell-Bootstrap' }
    Write-LogEntry "Found release: $($release.name) ($($release.tag_name))"

    $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1

    return @{
        Name         = $asset.name
        DownloadUrl  = $asset.browser_download_url
    }
}

function Invoke-FileDownload {
    param (
        [Parameter(Mandatory)]
        [string]
        $Uri,

        [Parameter(Mandatory)]
        [string]
        $OutFile
    )

    Write-LogEntry "Downloading: $Uri"

    if (Test-Path $OutFile) {
        Remove-Item $OutFile -Force
    }

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
    }
    else {
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
        }
        finally {
            $ProgressPreference = $oldProgress
        }
    }

    Write-LogEntry "Download completed"
}

function Expand-ReleaseArchive {
    param (
        [Parameter(Mandatory)]
        [string]
        $ArchivePath,

        [Parameter(Mandatory)]
        [string]
        $DestinationPath
    )

    Write-LogEntry "Extracting to: $DestinationPath"

    if (Test-Path $DestinationPath) {
        Remove-Item $DestinationPath -Recurse -Force
    }

    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
    }
    else {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $DestinationPath)
    }

    Write-LogEntry "Extraction completed"
}

# ============================
# Main Execution
# ============================
try {
    Write-LogEntry "Bootstrap: Windows Laptop Automation Setup"
    Write-LogEntry "Repository: $RepoOwner/$RepoName"

    # Get and download latest release
    $asset = Get-LatestReleaseAsset
    $zipPath = Join-Path $DownloadPath $asset.Name
    $extractPath = Join-Path $DownloadPath 'laptop-automation-temp'

    Invoke-FileDownload -Uri $asset.DownloadUrl -OutFile $zipPath
    Expand-ReleaseArchive -ArchivePath $zipPath -DestinationPath $extractPath

    # Find and run setup script
    $setupScript = Get-ChildItem $extractPath -Recurse -Filter 'setup.ps1' -File | Select-Object -First 1

    Write-LogEntry "Executing setup script: $($setupScript.FullName)"

    $setupParams = @{}
    if ($SkipPackages) { $setupParams['SkipPackages'] = $true }
    if ($SkipProfile) { $setupParams['SkipProfile'] = $true }
    if ($Force) { $setupParams['Force'] = $true }

    Push-Location $extractPath
    try {
        & $setupScript.FullName @setupParams
    }
    finally {
        Pop-Location
    }

    Write-LogEntry "Bootstrap completed successfully!"
}
catch {
    Write-LogEntry "Bootstrap failed: $_" -Level Error
    exit 1
}
finally {
    # Cleanup
    @($zipPath, $extractPath) | ForEach-Object {
        if (Test-Path $_) {
            Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
