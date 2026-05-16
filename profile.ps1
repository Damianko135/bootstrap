# ====================================================
# PowerShell Profile - Damian Korver
# Clean, functional, cross-version compatible
# ====================================================

# ====================================================
# Encoding & History
# ====================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$MaximumHistoryCount      = 10000

# ====================================================
# PSReadLine Configuration
# ====================================================
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue

    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -HistorySaveStyle SaveAtExit
    Set-PSReadLineOption -BellStyle None

    # Type a partial command then press Up/Down to search matching history entries
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # Tab shows a selectable menu instead of cycling blindly through completions
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
        if ($PSVersionTable.PSVersion -ge [version]'7.2') {
            Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
        }
    }
}

# ====================================================
# Aliases
# ====================================================
Set-Alias -Name ll   -Value Get-ChildItem
Set-Alias -Name grep -Value Select-String

function la { Get-ChildItem -Force @args }

# ====================================================
# Git Aliases
# ====================================================
function gs  { git status @args }
function gb  { git branch @args }
function gc  { git commit @args }
function gp  { git push @args }
function gpl { git pull @args }
function gco { git checkout @args }
function gd  { git diff @args }
function gst { git stash @args }

function gl {
    if ($args) { git log @args }
    else       { git log --oneline --graph --decorate -20 }
}

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

Set-Alias -Name myip     -Value Get-ExternalIP
Set-Alias -Name flushdns -Value Clear-DnsCache

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
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null) -join ''
    if ($LASTEXITCODE -eq 0) { $branch }
}

# ====================================================
# Custom Prompt
# ====================================================
function prompt {
    $cwd    = Get-Location
    $branch = Get-GitBranch
    $text   = "PS $cwd"

    if ($branch) { $text += " [$branch]" }

    "$text > "
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

# WinGet completion
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast  = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }
}

# ====================================================
# Startup
# ====================================================
Write-Host "PowerShell v$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor) Ready"
