#!/usr/bin/env pwsh
# Bootstrap Script for Windows Laptop Automation v2.1
# Author: Damian Korver
# Description: Downloads the latest release and runs the setup orchestrator
# This is the unified entry point for laptop automation setup
# Use the following command to run it on a fresh Windows installation:
# Aliases: IWR (Invoke-WebRequest); IEX (Invoke-Expression)
# iwr "https://raw.githubusercontent.com/Damianko135/Damianko135/main/laptopAutomation/windows/bootstrap.ps1" -OutFile "$env:TEMP\bootstrap.ps1"; powershell -nop -ep Bypass -f "$env:TEMP\bootstrap.ps1"

#Requires -Version 5.1

param (
    [ValidateSet("minimal", "standard", "complete", "gaming")] $Profile = "standard",
    [switch] $SkipPackages,
    [switch] $SkipProfile,
    [switch] $SkipValidation,
    [switch] $Force,
    [switch] $Recover,
    [switch] $Repair,
    [switch] $DryRun,
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

Write-Log "Windows Laptop Automation Bootstrap v2.1 - Unified Entry Point" "INFO"
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
        if ($SkipValidation) { $arguments += "-SkipValidation" }
        if ($Force) { $arguments += "-Force" }
        if ($Recover) { $arguments += "-Recover" }
        if ($Repair) { $arguments += "-Repair" }
        if ($DryRun) { $arguments += "-DryRun" }
        
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
    $extractPath = Join-Path $DownloadPath "laptop-automation-v2.1"
    
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
    
    # Download the zip file
    Write-Log "Downloading..." "INFO"
    
    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -UseBasicParsing
        } else {
            $oldProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -UseBasicParsing
            } finally {
                $ProgressPreference = $oldProgressPreference
            }
        }
    } catch {
        Write-Log "Invoke-WebRequest failed, trying WebClient..." "WARN"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($downloadUrl, $zipFilePath)
    }
    
    if (-not (Test-Path $zipFilePath)) {
        throw "Failed to download the release zip file"
    }
    
    Write-Log "Download completed" "INFO"
    
    # Extract the zip file
    Write-Log "Extracting files..." "INFO"
    
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force
    } else {
        Write-Log "Using .NET extraction..." "DEBUG"
        if (-not ("System.IO.Compression.ZipFile" -as [type])) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $extractPath)
    }
    
    # Find the orchestrator script
    Write-Log "Searching for orchestrator.ps1..." "INFO"
    $orchestratorScript = Get-ChildItem $extractPath -Recurse -File -Filter "orchestrator.ps1" | Select-Object -First 1
    
    if (-not $orchestratorScript) {
        Write-Log "Orchestrator script not found in extracted files" "ERROR"
        throw "Could not find orchestrator.ps1"
    }
    
    $orchestratorPath = $orchestratorScript.FullName
    Write-Log "Found orchestrator: $orchestratorPath" "INFO"
    
    # Build arguments for the orchestrator
    $arguments = @("-Profile", $Profile)
    if ($SkipPackages) { $arguments += "-SkipPackages" }
    if ($SkipProfile) { $arguments += "-SkipProfile" }
    if ($SkipValidation) { $arguments += "-SkipValidation" }
    if ($Force) { $arguments += "-Force" }
    if ($Recover) { $arguments += "-Recover" }
    if ($Repair) { $arguments += "-Repair" }
    if ($DryRun) { $arguments += "-DryRun" }
    
    # Run the orchestrator
    Write-Log "Executing orchestrator..." "INFO"
    
    $extractDir = Split-Path $orchestratorPath
    Push-Location $extractDir
    try {
        & $orchestratorPath @arguments
        $orchestratorSucceeded = $?
    } finally {
        Pop-Location
    }
    
    if ($orchestratorSucceeded) {
        Write-Log "Bootstrap completed successfully!" "SUCCESS"
    } else {
        Write-Log "Orchestrator failed to complete" "ERROR"
        exit 1
    }
    
} catch {
    Write-Log "Bootstrap failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Error details: $($_.ScriptStackTrace)" "ERROR"
    exit 1
} finally {
    # Cleanup downloaded files
    try {
        if (Test-Path $zipFilePath) {
            Write-Log "Cleaning up temporary files..." "DEBUG"
            Remove-Item $zipFilePath -Force
        }
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force
        }
    } catch {
        Write-Log "Warning: Could not clean up all temporary files" "WARN"
    }
}
