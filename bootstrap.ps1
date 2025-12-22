# Windows Bootstrap
# Simple entry point for Windows-only bootstrapping
# Usage: .\bootstrap.ps1 -Profile standard

param(
    [string]$Profile = "standard",
    [switch]$SkipPackages,
    [switch]$SkipProfile,
    [switch]$Force,
    [switch]$Local
)

try {
    if ($Local) {
        & "$PSScriptRoot\windows\bootstrap.ps1" @PSBoundParameters
    } else {
        $bootstrapUrl = "https://raw.githubusercontent.com/Damianko135/bootstrap/main/windows/bootstrap.ps1"
        $tempFile = [System.IO.Path]::GetTempFileName()
        Invoke-WebRequest -Uri $bootstrapUrl -OutFile $tempFile
        & $tempFile @PSBoundParameters
        Remove-Item $tempFile -Force
    }
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
    exit 1
}
