# ==================================================
# Damian Korver's PowerShell Profile
# Clean, Functional, and Cross-Version Compatible
# ==================================================

# ---- Console Setup ----
if ($Host.Name -eq 'ConsoleHost') {
    $Host.UI.RawUI.ForegroundColor = 'White'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    Clear-Host
}

# ---- Basic PSReadLine Configuration ----
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine | Out-Null

    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -HistorySaveStyle SaveAtExit

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        try {
            Set-PSReadLineOption -PredictionSource History
        } catch {
            Write-Verbose "PredictionSource not supported on this PS version."
        }
    }
}

# ---- Encoding & History ----
$MaximumHistoryCount = 5000
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ---- Aliases ----
Set-Alias ll Get-ChildItem
Set-Alias la "Get-ChildItem -Force -Hidden"
Set-Alias grep Select-String

# Git command aliases (function-based for argument handling)
function gs { git status @args }
function gb { git branch @args }
function gl { git log @args }
function gc { git commit @args }
function gp { git push @args }
function gco { git checkout @args }

# ---- Network Helpers ----
function Flush { ipconfig /flushdns }

# ---- Utility Functions ----
function Reprof {
    Write-Information "Reloading PowerShell profile..." -InformationAction Continue
    . $PROFILE
}

function Up {
    param([int]$Levels = 1)
    $Path = (Get-Location).Path
    for ($i = 0; $i -lt $Levels; $i++) {
        $Path = Split-Path $Path
    }
    Set-Location $Path
}

function Get-ExternalIP {
    try {
        (Invoke-RestMethod 'https://api.ipify.org?format=text').Trim()
    } catch {
        Write-Error "Unable to retrieve external IP."
    }
}

# ---- Go Helper ----
function ginit {
    param([string]$Remote = "origin")

    try {
        $url = git remote get-url $Remote 2>$null
        if (-not $url) { throw "No such remote: $Remote" }
    } catch {
        Write-Error $_
        return
    }

    # Normalize URL (handles HTTPS and SSH)
    switch -Regex ($url) {
        '^https://' { $path = $url -replace '^https://', '' -replace '\.git$', '' }
        '^git@'     { $path = $url -replace '^git@', '' -replace ':', '/' -replace '\.git$', '' }
        default     { Write-Error "Unsupported remote URL format: $url"; return }
    }

    go mod init $path
}

# ---- Git Branch for Prompt ----
function Get-GitBranch {
    if (Test-Path .git) {
        git rev-parse --abbrev-ref HEAD 2>$null
    }
}

# ---- Custom Prompt ----
$env:PROMPT_SYMBOL = "PS"  # PowerShell symbol

function Prompt {
    $Cwd = (Get-Location).Path
    $Branch = Get-GitBranch
    $Prompt = "$($env:PROMPT_SYMBOL) $Cwd"
    if ($Branch) { $Prompt += " [$Branch]" }
    return "$Prompt "
}

# ---- Modules ----
# posh-git (if installed)
if (Get-Module -ListAvailable posh-git) {
    Import-Module posh-git | Out-Null
}

# Chocolatey Tab Completion (if installed)
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path $ChocolateyProfile) {
    Import-Module $ChocolateyProfile | Out-Null
}

# ---- Startup Message ----
Write-Information "PowerShell Ready (v$($PSVersionTable.PSVersion.Major))." -InformationAction Continue
