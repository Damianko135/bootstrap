#!/usr/bin/env pwsh
<#
Single-entry bootstrap with subcommands: install (default), uninstall, office, test, fetch

Examples:
  .\bootstrap.ps1                      # runs install
  .\bootstrap.ps1 -Action uninstall
  .\bootstrap.ps1 -Action fetch -DownloadPath C:\tmp
  .\bootstrap.ps1 -SkipDebloat         # install without removing bloatware
#>

[CmdletBinding()]
param(
    [ValidateSet('install','uninstall','office','test','fetch')]
    [string] $Action = 'install',

    [switch] $SkipPackages,
    [switch] $SkipProfile,
    [switch] $Force,
    [switch] $SkipOffice,
    [switch] $SkipDebloat,

    [string] $DownloadPath = $env:TEMP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

## Determine script root (works when run locally or via iwr|iex)
if ($PSScriptRoot) { $ScriptRoot = $PSScriptRoot }
elseif ($MyInvocation.MyCommand.Path) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
else { $ScriptRoot = (Get-Location).Path }

# If helpers.ps1 exists (local repo), load it. Otherwise assume this script was invoked remotely
# and fetch the latest release zip + run setup.ps1 from the release (preserves iwr | iex flow).
if (Test-Path (Join-Path $ScriptRoot 'helpers.ps1')) {
    . (Join-Path $ScriptRoot 'helpers.ps1')
}
else {
    # Remote bootstrap behavior: download latest release and execute setup.ps1 from it
    Write-Output 'helpers.ps1 not found locally — running remote bootstrap (download latest release)'

    $asset = Invoke-FetchLatestRelease
    $zipPath = Join-Path $DownloadPath $asset.Name
    $extractPath = Join-Path $DownloadPath 'laptop-automation-temp'

    Invoke-FileDownload -Uri $asset.Url -OutFile $zipPath
    Expand-ArchiveIfNeeded -ArchivePath $zipPath -Destination $extractPath

    $setupScript = Get-ChildItem $extractPath -Recurse -Filter 'bootstrap.ps1' -File | Select-Object -First 1
    if (-not $setupScript) { Write-Output 'bootstrap.ps1 not found in release'; exit 1 }

    $setupParams = @()
    if ($SkipPackages) { $setupParams += '-SkipPackages' }
    if ($SkipProfile)  { $setupParams += '-SkipProfile' }
    if ($Force)        { $setupParams += '-Force' }
    if ($SkipOffice)   { $setupParams += '-SkipOffice' }
    if ($SkipDebloat)  { $setupParams += '-SkipDebloat' }

    Push-Location $extractPath
    try { & $setupScript.FullName @setupParams }
    finally { Pop-Location }

    # Cleanup
    @($zipPath, $extractPath) | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue } }
    exit
}

# If an action requires elevation, relaunch elevated when not running as administrator.
$needsElevation = $Action -in @('install','uninstall')
if ($needsElevation -and -not (Test-Administrator)) {
    Write-LogEntry 'Not running as Administrator — relaunching elevated' 'INFO'

    $pwshCmd = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshCmd) { $pwshCmd = (Get-Command powershell -ErrorAction SilentlyContinue).Source }

    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $ScriptRoot 'bootstrap.ps1'), '-Action', $Action)
    if ($SkipPackages) { $argList += '-SkipPackages' }
    if ($SkipProfile)  { $argList += '-SkipProfile' }
    if ($Force)        { $argList += '-Force' }
    if ($SkipOffice)   { $argList += '-SkipOffice' }
    if ($SkipDebloat)  { $argList += '-SkipDebloat' }
    if ($DownloadPath) { $argList += '-DownloadPath'; $argList += $DownloadPath }

    Start-Process -FilePath $pwshCmd -ArgumentList $argList -Verb RunAs
    exit
}

function Invoke-FetchLatestRelease {
    param([string]$RepoOwner = 'Damianko135', [string]$RepoName = 'bootstrap')
    $api = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
    Write-LogEntry "Fetching release from $api"
    $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'PowerShell-Bootstrap' }
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    return @{ Name = $asset.name; Url = $asset.browser_download_url }
}

switch ($Action) {
    'fetch' {
        $asset = Invoke-FetchLatestRelease
        $zip = Join-Path $DownloadPath $asset.Name
        Invoke-FileDownload -Uri $asset.Url -OutFile $zip
        Write-LogEntry "Downloaded: $zip"
    }

    'test' {
        # create a local zip of repository and run extracted setup (mimics previous run-test)
        $testZip = Join-Path $DownloadPath 'BootstrapTest.zip'
        if (Test-Path $testZip) { Remove-Item $testZip -Force }
        $files = Get-ChildItem -Path $ScriptRoot -Recurse -File | Where-Object { $_.Name -ne 'BootstrapTest.zip' }
        Compress-Archive -Path $files.FullName -DestinationPath $testZip -Force
        $extract = Join-Path $DownloadPath 'laptop-automation-temp'
        Expand-ArchiveIfNeeded -ArchivePath $testZip -Destination $extract
        $setup = Get-ChildItem $extract -Recurse -Filter 'bootstrap.ps1' -File | Select-Object -First 1
        if ($setup) {
            Push-Location $extract
            try {
                & $setup.FullName
            }
            finally {
                Pop-Location
            }
        }
        else {
            Write-LogEntry 'no bootstrap.ps1 found in test archive' 'WARN'
        }
    }

    'office' {
        if ($SkipOffice) {
            Write-LogEntry 'Skipping Office'
            break
        }
        if (Test-Path (Join-Path $ScriptRoot 'office.ps1')) {
            & (Join-Path $ScriptRoot 'office.ps1')
        }
        else {
            Write-LogEntry 'office.ps1 not found' 'WARN'
        }
    }

    'uninstall' {
        if (-not (Test-Administrator)) { Write-LogEntry 'Must run as Administrator to uninstall' 'ERROR'; exit 1 }
        Invoke-PackageAction -Action Uninstall
    }

    'install' {
        if (-not $SkipDebloat) {
            if (-not (Test-Administrator)) { Write-LogEntry 'Debloat requires Administrator' 'ERROR'; exit 1 }
            Invoke-Debloat
        }

        if (-not $SkipPackages) {
            if (-not (Test-Administrator)) { Write-LogEntry 'Package installation requires Administrator' 'ERROR'; exit 1 }
            if (-not (Test-PackageManagerAvailable -PackageManager Chocolatey)) {
                Write-LogEntry 'Chocolatey missing, attempting install' 'INFO'
                Install-Chocolatey | Out-Null
            }
            Invoke-PackageAction -Action Install
        }

        if (-not $SkipOffice) { if (Test-Path (Join-Path $ScriptRoot 'office.ps1')) { & (Join-Path $ScriptRoot 'office.ps1') } }

        if (-not $SkipProfile) { Invoke-ProfileInstall -Force:$Force }
    }

    default { Write-LogEntry "Unknown action: $Action" 'ERROR' }
}

