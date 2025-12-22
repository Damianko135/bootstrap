# ====================================================
# PowerShell Profile - Damian Korver
# Clean, functional, cross-version compatible
# ====================================================

# ====================================================
# Console Setup
# ====================================================
if ($Host.Name -eq 'ConsoleHost') {
    $Host.UI.RawUI.ForegroundColor = 'White'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    Clear-Host
}

# ====================================================
# PSReadLine Configuration
# ====================================================
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue

    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -HistorySaveStyle SaveAtExit

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
    }
}

# ====================================================
# Encoding & History
# ====================================================
$MaximumHistoryCount = 5000
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ====================================================
# Aliases
# ====================================================
Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name grep -Value Select-String

# ====================================================
# Git Aliases
# ====================================================
function gs { git status @args }
function gb { git branch @args }
function gl { git log @args }
function gc { git commit @args }
function gp { git push @args }
function gco { git checkout @args }

# ====================================================
# Utility Functions
# ====================================================
function Reprof {
    Write-Host "Reloading PowerShell profile..."
    . $PROFILE
}

function Up {
    [CmdletBinding()]
    param([int]$Levels = 1)

    $path = (Get-Location).Path
    for ($i = 0; $i -lt $Levels; $i++) {
        $path = Split-Path $path
    }
    Set-Location $path
}

function Get-ExternalIP {
    try {
        (Invoke-RestMethod 'https://api.ipify.org?format=text' -TimeoutSec 5).Trim()
    }
    catch {
        Write-Error "Failed to retrieve external IP: $_"
    }
}

function Clear-DnsCache {
    ipconfig /flushdns
}

# ====================================================
# Go Helper
# ====================================================
function Gonit {
    [CmdletBinding()]
    param(
        [string]
        $Remote = 'origin'
    )

    $url = git remote get-url $Remote 2>$null

    if (-not $url) {
        Write-Error "Remote '$Remote' not found"
        return
    }

    # Normalize URL
    $path = switch -Regex ($url) {
        '^https://' { $url -replace '^https://', '' -replace '\.git$', '' }
        '^git@'     { $url -replace '^git@', '' -replace ':', '/' -replace '\.git$', '' }
        default     { Write-Error "Unsupported URL format: $url"; return }
    }

    go mod init $path
}

Set-Alias -Name ginit -Value Gonit

# ====================================================
# Git Branch Detection
# ====================================================
function Get-GitBranch {
    if (Test-Path .git) {
        git rev-parse --abbrev-ref HEAD 2>$null
    }
}

# ====================================================
# Custom Prompt
# ====================================================
function prompt {
    $cwd = Get-Location
    $branch = Get-GitBranch
    $prompt = "PS $cwd"

    if ($branch) {
        $prompt += " [$branch]"
    }

    "$prompt > "
}

# ====================================================
# Optional Module Imports
# ====================================================

# posh-git (enhanced git prompt)
if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git -ErrorAction SilentlyContinue
}

# Chocolatey completion
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path $ChocolateyProfile) {
    Import-Module $ChocolateyProfile -ErrorAction SilentlyContinue
}

# ====================================================
# Startup
# ====================================================
Write-Host "PowerShell v$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) Ready"
