@'
# Minimal PowerShell profile (migrated from profile-content.ps1)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$MaximumHistoryCount      = 10000

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    Set-PSReadLineOption -EditMode Windows
}

# Basic aliases and helpers
Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name grep -Value Select-String

function Reprof { . $PROFILE }
'@ | Set-Content -Path (Join-Path $PSScriptRoot 'profile.ps1') -Force
