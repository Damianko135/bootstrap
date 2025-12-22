#!/usr/bin/env pwsh
# bootstrap-v2.ps1 - Enhanced Bootstrap Script
# Downloads and runs the sophisticated orchestrator setup

#Requires -Version 5.1

param (
    [ValidateSet("minimal", "standard", "complete", "gaming")] $Profile = "standard",
    [switch] $SkipPackages,
    [switch] $SkipProfile,
    [switch] $Force,
    [switch] $Local,
    [string] $DownloadPath = $env:TEMP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] [$Level] $Message"
    $colors = @{ "ERROR" = "Red"; "WARN" = "Yellow"; "INFO" = "White"; "SUCCESS" = "Green" }
    Write-Host $formatted -ForegroundColor $colors[$Level]
}

Write-Log "Enhanced Laptop Automation Bootstrap v2.0" "INFO"
Write-Log "========================================================" "INFO"

# Check if running as administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: This script requires administrator privileges" "ERROR"
    Write-Log "Please run PowerShell as Administrator" "ERROR"
    exit 1
}

try {
    # If -Local flag, use local orchestrator
    if ($Local) {
        Write-Log "Using local orchestrator mode" "INFO"
        
        $localOrchestratorPath = Join-Path $PSScriptRoot "orchestrator.ps1"
        if (-not (Test-Path $localOrchestratorPath)) {
            Write-Log "Local orchestrator not found: $localOrchestratorPath" "ERROR"
            exit 1
        }
        
        Write-Log "Executing local orchestrator: $localOrchestratorPath" "INFO"
        
        $arguments = @("-Profile", $Profile)
        if ($SkipPackages) { $arguments += "-SkipPackages" }
        if ($SkipProfile) { $arguments += "-SkipProfile" }
        if ($Force) { $arguments += "-Force" }
        
        & $localOrchestratorPath @arguments
        exit $LASTEXITCODE
    }
    
    # Download orchestrator from GitHub
    Write-Log "Fetching latest release from GitHub..." "INFO"
    
    $repoOwner = "Damianko135"
    $repoName = "Damianko135"
    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
    
    $latestRelease = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "PowerShell-Bootstrap" }
    $tagName = $latestRelease.tag_name
    $releaseName = $latestRelease.name
    
    Write-Log "Latest release: $releaseName ($tagName)" "INFO"
    
    # Find the main zip asset
    $windowsAsset = $latestRelease.assets | Where-Object { $_.name -like "*Bootstrap*" -or $_.name -like "*.zip" } | Select-Object -First 1
    
    if (-not $windowsAsset) {
        Write-Log "No suitable asset found in release" "ERROR"
        Write-Log "Available assets:" "INFO"
        $latestRelease.assets | ForEach-Object { Write-Log "  - $($_.name)" "INFO" }
        exit 1
    }
    
    $downloadUrl = $windowsAsset.browser_download_url
    $zipFileName = $windowsAsset.name
    $zipFilePath = Join-Path $DownloadPath $zipFileName
    $extractPath = Join-Path $DownloadPath "laptop-automation-v2"
    
    Write-Log "Asset: $zipFileName" "INFO"
    Write-Log "Downloading from: $downloadUrl" "INFO"
    
    # Clean up existing files
    if (Test-Path $zipFilePath) {
        Write-Log "Removing existing zip file..." "INFO"
        Remove-Item $zipFilePath -Force
    }
    if (Test-Path $extractPath) {
        Write-Log "Removing existing extraction directory..." "INFO"
        Remove-Item $extractPath -Recurse -Force
    }
    
    # Download with retry logic
    $maxRetries = 3
    $retryCount = 0
    $downloaded = $false
    
    while (-not $downloaded -and $retryCount -lt $maxRetries) {
        try {
            $retryCount++
            Write-Log "Download attempt $retryCount of $maxRetries..." "INFO"
            
            $progressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -UseBasicParsing -TimeoutSec 300
            $progressPreference = 'Continue'
            
            if (Test-Path $zipFilePath) {
                Write-Log "✓ Download completed" "SUCCESS"
                $downloaded = $true
            }
        } catch {
            Write-Log "Download attempt $retryCount failed: $($_.Exception.Message)" "WARN"
            
            if ($retryCount -ge $maxRetries) {
                Write-Log "All download attempts failed" "ERROR"
                exit 1
            }
            
            Start-Sleep -Seconds 5
        }
    }
    
    # Extract archive
    Write-Log "Extracting archive to: $extractPath" "INFO"
    
    try {
        Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force
        Write-Log "✓ Extraction completed" "SUCCESS"
    } catch {
        Write-Log "Extraction failed: $($_.Exception.Message)" "ERROR"
        exit 1
    }
    
    # Find and run orchestrator
    Write-Log "Searching for orchestrator script..." "INFO"
    
    $orchestratorScript = Get-ChildItem $extractPath -Recurse -File -Filter "orchestrator.ps1" | Select-Object -First 1
    
    if (-not $orchestratorScript) {
        Write-Log "Orchestrator script not found in extracted files" "ERROR"
        Write-Log "Contents:" "INFO"
        Get-ChildItem $extractPath -Recurse | ForEach-Object {
            Write-Log "  $($_.FullName)" "INFO"
        }
        exit 1
    }
    
    $orchestratorPath = $orchestratorScript.FullName
    Write-Log "Found orchestrator: $orchestratorPath" "INFO"
    
    # Build arguments for orchestrator
    $arguments = @("-Profile", $Profile)
    if ($SkipPackages) { $arguments += "-SkipPackages" }
    if ($SkipProfile) { $arguments += "-SkipProfile" }
    if ($Force) { $arguments += "-Force" }
    
    Write-Log "Starting orchestrator setup..." "INFO"
    Write-Log "========================================================" "INFO"
    
    # Execute orchestrator
    Push-Location $extractPath
    try {
        & $orchestratorPath @arguments
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    
    Write-Log "========================================================" "INFO"
    
    if ($exitCode -eq 0) {
        Write-Log "Setup completed successfully!" "SUCCESS"
    } else {
        Write-Log "Setup completed with errors (Exit code: $exitCode)" "WARN"
    }
    
    # Offer cleanup
    Write-Log "" "INFO"
    Write-Log "Cleaning up temporary files..." "INFO"
    
    try {
        if (Test-Path $zipFilePath) {
            Remove-Item $zipFilePath -Force
            Write-Log "✓ Removed zip file" "INFO"
        }
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force
            Write-Log "✓ Removed extraction directory" "INFO"
        }
    } catch {
        Write-Log "Warning: Could not clean up some temporary files" "WARN"
    }
    
    exit $exitCode
} catch {
    Write-Log "Bootstrap failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Details: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
