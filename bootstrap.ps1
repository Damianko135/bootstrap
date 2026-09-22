#Requires -Version 5.1
<#
Single-entry bootstrap with subcommands: install (default), office, test, fetch

Works with the Windows PowerShell 5.1 that ships with Windows, no PowerShell 7 (pwsh) required.

Examples:
  .\bootstrap.ps1                      # runs install
  .\bootstrap.ps1 -Action fetch -DownloadPath C:\tmp
  .\bootstrap.ps1 -SkipDebloat         # install without removing bloatware
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('install','office','test','fetch')]
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

# Fail fast with a clear message on a locked-down/managed machine (AppLocker, WDAC, Device
# Guard) instead of hitting confusing errors deep into the script (e.g. from Add-Type or
# ConvertFrom-Json, which behave differently or are blocked outside FullLanguage mode).
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Error "PowerShell execution is restricted by a security policy (LanguageMode: $($ExecutionContext.SessionState.LanguageMode)) - this script requires FullLanguage mode."
    exit 1
}

## Determine script root (works when run locally, via -File, or as an in-memory scriptblock via
## iex / [scriptblock]::Create()+&). In the in-memory case $MyInvocation.MyCommand is a real
## System.Management.Automation.ScriptInfo object (not null) that simply has no .Path property at
## all, and Set-StrictMode's PropertyNotFoundStrict fires on that regardless of null-ness - so this
## is wrapped in try/catch rather than a truthiness check, to tolerate whatever shape .MyCommand
## turns out to have in a given invocation context.
$ScriptRoot = $null
if ($PSScriptRoot) { $ScriptRoot = $PSScriptRoot }
if (-not $ScriptRoot) {
    try { if ($MyInvocation.MyCommand.Path) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path } } catch {}
}
if (-not $ScriptRoot) { $ScriptRoot = (Get-Location).Path }

# Functions needed regardless of whether this script is running from a local checkout
# or standalone (e.g. via iwr|iex, where only this file exists on disk - no helpers.ps1
# alongside it yet). Defined here, before first use, since helpers.ps1 isn't available yet.
# Write-LogEntry is duplicated in helpers.ps1 for office.ps1's benefit - see the comment there.
function Write-LogEntry {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    switch ($Level.ToUpper()) {
        'ERROR'   { Write-Error  "[$ts] $Message"; return }
        'WARN'    { Write-Warning "[$ts] $Message"; return }
        default   { Write-Information "[$ts] $Message" -InformationAction Continue }
    }
}

function Invoke-FileDownload {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$OutFile)
    Write-LogEntry "Downloading $Uri -> $OutFile"
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile
}

function Expand-ArchiveIfNeeded {
    param([string]$ArchivePath, [string]$Destination)
    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue }
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $ArchivePath -DestinationPath $Destination -Force
    }
    else {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $Destination)
    }
}

function Invoke-FetchLatestRelease {
    param([string]$RepoOwner = 'Damianko135', [string]$RepoName = 'bootstrap')
    $api = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
    Write-LogEntry "Fetching release from $api"
    $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'PowerShell-Bootstrap' }
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) { throw "No .zip asset found on latest release of $RepoOwner/$RepoName" }
    return @{ Name = $asset.name; Url = $asset.browser_download_url }
}

# If helpers.ps1 exists (local repo), load it. Otherwise assume this script was invoked remotely
# and fetch the latest release zip + run setup.ps1 from the release (preserves iwr | iex flow).
if (Test-Path (Join-Path $ScriptRoot 'helpers.ps1')) {
    . (Join-Path $ScriptRoot 'helpers.ps1')
}
else {
    # Remote bootstrap behavior: download latest release and execute setup.ps1 from it
    Write-LogEntry 'helpers.ps1 not found locally - running remote bootstrap (download latest release)'

    $asset = Invoke-FetchLatestRelease
    $zipPath = Join-Path $DownloadPath $asset.Name
    $extractPath = Join-Path $DownloadPath 'laptop-automation-temp'

    Invoke-FileDownload -Uri $asset.Url -OutFile $zipPath
    Expand-ArchiveIfNeeded -ArchivePath $zipPath -Destination $extractPath

    $setupScript = Get-ChildItem $extractPath -Recurse -Filter 'bootstrap.ps1' -File | Select-Object -First 1
    if (-not $setupScript) { Write-LogEntry 'bootstrap.ps1 not found in release' 'ERROR'; exit 1 }

    # Hashtable splat, not array splat: array splatting binds positionally (it does NOT parse
    # '-Name','Value' pairs the way command-line tokens do), so it would bind the literal string
    # '-Action' to the $Action parameter instead of the intended value.
    $setupParams = @{ Action = $Action }
    if ($SkipPackages) { $setupParams.SkipPackages = $true }
    if ($SkipProfile)  { $setupParams.SkipProfile = $true }
    if ($Force)        { $setupParams.Force = $true }
    if ($SkipOffice)   { $setupParams.SkipOffice = $true }
    if ($SkipDebloat)  { $setupParams.SkipDebloat = $true }
    if ($DownloadPath) { $setupParams.DownloadPath = $DownloadPath }

    Push-Location $extractPath
    try { & $setupScript.FullName @setupParams }
    finally { Pop-Location }

    # Cleanup
    @($zipPath, $extractPath) | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue } }
    exit
}

# If an action requires elevation, relaunch elevated when not running as administrator.
# 'office' needs it too: the Office Deployment Tool's /extract and /configure steps fail with
# "the requested operation requires elevation" when run as a standard user.
$needsElevation = $Action -in @('install','office')
if ($needsElevation -and -not (Test-Administrator)) {
    Write-LogEntry 'Not running as Administrator - relaunching elevated' 'INFO'

    # Relaunch with whichever PowerShell host is already running this script (Windows PowerShell
    # 5.1 or pwsh) rather than assuming pwsh is installed - the script only needs 5.1+.
    $hostExe = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    if (-not $hostExe) { $hostExe = (Get-Command powershell -ErrorAction SilentlyContinue).Source }
    if (-not $hostExe) { $hostExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if (-not $hostExe) { Write-LogEntry 'Could not locate a PowerShell executable to relaunch elevated' 'ERROR'; exit 1 }

    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $ScriptRoot 'bootstrap.ps1'), '-Action', $Action)
    if ($SkipPackages) { $argList += '-SkipPackages' }
    if ($SkipProfile)  { $argList += '-SkipProfile' }
    if ($Force)        { $argList += '-Force' }
    if ($SkipOffice)   { $argList += '-SkipOffice' }
    if ($SkipDebloat)  { $argList += '-SkipDebloat' }
    if ($DownloadPath) { $argList += '-DownloadPath'; $argList += $DownloadPath }

    Start-Process -FilePath $hostExe -ArgumentList $argList -Verb RunAs
    exit
}

switch ($Action) {
    'fetch' {
        $asset = Invoke-FetchLatestRelease
        $zip = Join-Path $DownloadPath $asset.Name
        Invoke-FileDownload -Uri $asset.Url -OutFile $zip
        Write-LogEntry "Downloaded: $zip"
    }

    'test' {
        # Non-destructive smoke test: package the local checkout the same way the release
        # workflow does, extract it, and verify the archive is complete and every script/JSON
        # file in it is well-formed. Does not install, uninstall, or elevate anything.
        Write-LogEntry 'Running archive smoke test (extraction + syntax check, no installs performed)'

        $testZip = Join-Path $DownloadPath 'BootstrapTest.zip'
        if (Test-Path $testZip) { Remove-Item $testZip -Force }
        $files = Get-ChildItem -Path $ScriptRoot -Recurse -File | Where-Object { $_.Name -ne 'BootstrapTest.zip' }
        Compress-Archive -Path $files.FullName -DestinationPath $testZip -Force

        $extract = Join-Path $DownloadPath 'laptop-automation-temp'
        Expand-ArchiveIfNeeded -ArchivePath $testZip -Destination $extract

        try {
            $required = @('bootstrap.ps1','helpers.ps1','office.ps1','office.xml','packages.json','uninstallList.json','profile.ps1')
            $missing = $required | Where-Object { -not (Test-Path (Join-Path $extract $_)) }
            if ($missing) { throw "Archive missing required files: $($missing -join ', ')" }

            Get-ChildItem -Path $extract -Filter '*.ps1' -Recurse | ForEach-Object {
                $parseErrors = $null
                [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$parseErrors)
                if ($parseErrors.Count) { throw "Syntax errors in $($_.Name): $($parseErrors -join '; ')" }
                Write-LogEntry "OK: $($_.Name) parses cleanly"
            }

            @('packages.json','uninstallList.json') | ForEach-Object {
                $p = Join-Path $extract $_
                try { Get-Content $p -Raw | ConvertFrom-Json | Out-Null; Write-LogEntry "OK: $_ is valid JSON" }
                catch { throw "Invalid JSON in $_`: $_" }
            }

            Write-LogEntry 'Smoke test passed'
        }
        finally {
            @($testZip, $extract) | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue } }
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

    'install' {
        if (-not $SkipDebloat) {
            if (-not (Test-Administrator)) { Write-LogEntry 'Debloat requires Administrator' 'ERROR'; exit 1 }
            Invoke-Debloat -WhatIf:$WhatIfPreference -Confirm:$ConfirmPreference
        }

        if (-not $SkipPackages) {
            if (-not (Test-Administrator)) { Write-LogEntry 'Package installation requires Administrator' 'ERROR'; exit 1 }
            if (-not (Test-PackageManagerAvailable -PackageManager Chocolatey)) {
                Write-LogEntry 'Chocolatey missing, attempting install' 'INFO'
                Install-Chocolatey | Out-Null
            }
            Invoke-PackageAction -WhatIf:$WhatIfPreference -Confirm:$ConfirmPreference
        }

        if (-not $SkipOffice) { if (Test-Path (Join-Path $ScriptRoot 'office.ps1')) { & (Join-Path $ScriptRoot 'office.ps1') } }

        if (-not $SkipProfile) { Invoke-ProfileInstall -Force:$Force }
    }

    default { Write-LogEntry "Unknown action: $Action" 'ERROR' }
}
