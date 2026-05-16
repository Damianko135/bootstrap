#!/usr/bin/env pwsh
<#
Single-entry bootstrap with subcommands: install (default), uninstall, office, test, fetch

Examples:
  .\bootstrap.ps1                      # runs install
  .\bootstrap.ps1 -Action uninstall
  .\bootstrap.ps1 -Action fetch -DownloadPath C:\tmp
#>

[CmdletBinding()]
param(
    [ValidateSet('install','uninstall','office','test','fetch')]
    [string] $Action = 'install',

    [switch] $SkipPackages,
    [switch] $SkipProfile,
    [switch] $Force,
    [switch] $SkipOffice,

    [string] $DownloadPath = $env:TEMP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# load helpers
. (Join-Path $PSScriptRoot 'helpers.ps1')

function Invoke-FetchLatestRelease {
    param([string]$RepoOwner = 'Damianko135', [string]$RepoName = 'bootstrap')
    $api = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
    Write-Log "Fetching release from $api"
    $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'PowerShell-Bootstrap' }
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    return @{ Name = $asset.name; Url = $asset.browser_download_url }
}

switch ($Action) {
    'fetch' {
        $asset = Invoke-FetchLatestRelease
        $zip = Join-Path $DownloadPath $asset.Name
        Invoke-FileDownload -Uri $asset.Url -OutFile $zip
        Write-Log "Downloaded: $zip"
    }

    'test' {
        # create a local zip of repository and run extracted setup (mimics previous run-test)
        $testZip = Join-Path $DownloadPath 'BootstrapTest.zip'
        if (Test-Path $testZip) { Remove-Item $testZip -Force }
        $files = Get-ChildItem -Path $PSScriptRoot -Recurse -File | Where-Object { $_.Name -ne 'BootstrapTest.zip' }
        Compress-Archive -Path $files.FullName -DestinationPath $testZip -Force
        $extract = Join-Path $DownloadPath 'laptop-automation-temp'
        Expand-ArchiveIfNeeded -ArchivePath $testZip -Destination $extract
        $setup = Get-ChildItem $extract -Recurse -Filter 'setup.ps1' -File | Select-Object -First 1
        if ($setup) { Push-Location $extract; try { & $setup.FullName } finally { Pop-Location } }
        else { Write-Log 'no setup.ps1 found in test archive' 'WARN' }
    }

    'office' {
        if ($SkipOffice) { Write-Log 'Skipping Office' ; break }
        if (Test-Path (Join-Path $PSScriptRoot 'office.ps1')) { & (Join-Path $PSScriptRoot 'office.ps1') }
        else { Write-Log 'office.ps1 not found' 'WARN' }
    }

    'uninstall' {
        if (-not (Test-Administrator)) { Write-Log 'Must run as Administrator to uninstall' 'ERROR'; exit 1 }
        Invoke-PackageAction -Action Uninstall
    }

    'install' {
        if (-not $SkipPackages) {
            if (-not (Test-Administrator)) { Write-Log 'Package installation requires Administrator' 'ERROR'; exit 1 }
            # ensure at least one manager
            if (-not (Test-PackageManagerAvailable -PackageManager Chocolatey)) {
                Write-Log 'Chocolatey missing, attempting install' 'INFO'
                Ensure-Chocolatey | Out-Null
            }
            Invoke-PackageAction -Action Install
        }

        if (-not $SkipOffice) { if (Test-Path (Join-Path $PSScriptRoot 'office.ps1')) { & (Join-Path $PSScriptRoot 'office.ps1') } }

        if (-not $SkipProfile) { Invoke-ProfileInstall -Force:$Force }
    }

    default { Write-Log "Unknown action: $Action" 'ERROR' }
}

