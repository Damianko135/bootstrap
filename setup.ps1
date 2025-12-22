#!/usr/bin/env pwsh
# Windows Laptop Automation Setup Script
# Author: Damian Korver
# Description: Minimal setup script that installs packages and configures PowerShell profile

#Requires -Version 5.1

param (
    [switch] $SkipPackages,
    [switch] $SkipProfile,
    [switch] $Force,
    [switch] $SkipOffice
)

# Mark parameters as used for analyzers
$null = $SkipPackages
$null = $SkipProfile
$null = $Force
$null = $SkipOffice

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Validation function
function Test-SetupPrerequisite {
    Write-Log "Validating setup prerequisites..."
    
    $errors = @()
    
    # Check required files
    $requiredFiles = @(
        "packageList.json",
        "profile-content.ps1"
    )
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $PSScriptRoot $file
        if (-not (Test-Path $filePath)) {
            $errors += "Required file not found: $file"
        }
    }
    
    # Validate JSON files
    $jsonFiles = @("packageList.json")
    foreach ($file in $jsonFiles) {
        $filePath = Join-Path $PSScriptRoot $file
        if (Test-Path $filePath) {
            try {
                $content = Get-Content $filePath -Raw
                $null = ConvertFrom-Json $content
                Write-Log "OK: $file is valid JSON"
            } catch {
                $errors += "$file contains invalid JSON: $($_.Exception.Message)"
            }
        }
    }
    
    # Check internet connectivity
    try {
        $dnsServer = "8.8.8.8"
        $testConnection = Test-Connection -ComputerName $dnsServer -Count 1 -Quiet
        if (-not $testConnection) {
            $errors += "No internet connectivity detected"
        } else {
            Write-Log "OK: Internet connectivity confirmed"
        }
    } catch {
        $errors += "Failed to test internet connectivity: $($_.Exception.Message)"
    }
    
    if ($errors.Count -gt 0) {
        Write-Log "Setup validation failed:"
        foreach ($validationError in $errors) {
            Write-Log "  - $validationError"
        }
        return $false
    }
    
    Write-Log "OK: All prerequisites validated successfully"
    return $true
}

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] $Message"
    Write-Information $formatted -InformationAction Continue
}

# Check if running as administrator
function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Install Chocolatey if not present
function Install-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Log "Chocolatey is already installed"
        return $true
    }
    
    try {
        Write-Log "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        
        # Download Chocolatey installer script to a temporary file
        $tempScriptPath = Join-Path $env:TEMP "InstallChocolatey.ps1"
        $chocoInstallScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
        $chocoInstallScript | Set-Content -Path $tempScriptPath -Force
        
        # Execute the script from file
        & $tempScriptPath
        
        # Clean up temporary script
        Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
        
        # Refresh environment variables
        $pathValue = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
        [System.Environment]::SetEnvironmentVariable("PATH", $pathValue, "Process")
        
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Log "Chocolatey installed successfully"
            return $true
        } else {
            Write-Log "Chocolatey installation failed"
            return $false
        }
    } catch {
        Write-Log "Failed to install Chocolatey: $($_.Exception.Message)"
        return $false
    }
}

# Check if WinGet is available
function Test-WinGet {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        Write-Log "WinGet not available"
        return $false
    }
}

# Check if a package is already installed
function Test-PackageInstalled {
    param([string]$PackageName, [string]$CommandName)
    
    if ($CommandName) {
        try {
            $null = Get-Command $CommandName -ErrorAction Stop
            Write-Log "$PackageName is already installed (found command: $CommandName)"
            return $true
        } catch {
            return $false
        }
    }
    
    # Fallback checks for common packages
    switch ($PackageName) {
        "Git" { return Test-Path "C:\Program Files\Git\bin\git.exe" }
        "Visual Studio Code" { return Test-Path "C:\Program Files\Microsoft VS Code\bin\code.cmd" }
        "PowerShell 7" { return Test-Path "C:\Program Files\PowerShell\7\pwsh.exe" }
        "Node.js" { return Get-Command node -ErrorAction SilentlyContinue }
        "Docker Desktop" { return Test-Path "C:\Program Files\Docker\Docker\Docker Desktop.exe" }
        "Mozilla Firefox" { return Test-Path "C:\Program Files\Mozilla Firefox\firefox.exe" }
        "7-Zip" { return Test-Path "C:\Program Files\7-Zip\7z.exe" }
        default { return $false }
    }
}

# Install package using Chocolatey
function Install-ChocoPackage {
    param([string]$PackageId, [string]$PackageName, [string]$CommandName)
    
    # Check if already installed
    if (Test-PackageInstalled -PackageName $PackageName -CommandName $CommandName) {
        return $true
    }
    
    try {
        Write-Log "Installing $PackageName via Chocolatey..."
        choco install $PackageId -y --no-progress
        Write-Log "$PackageName installed successfully via Chocolatey"
        return $true
    } catch {
        Write-Log "Failed to install $PackageName via Chocolatey: $($_.Exception.Message)"
        return $false
    }
}

# Install package using WinGet
function Install-WinGetPackage {
    param([string]$PackageId, [string]$PackageName, [string]$CommandName)
    
    # Check if already installed
    if (Test-PackageInstalled -PackageName $PackageName -CommandName $CommandName) {
        return $true
    }
    
    try {
        Write-Log "Installing $PackageName via WinGet..."
        winget install --id $PackageId --silent --accept-package-agreements --accept-source-agreements
        Write-Log "$PackageName installed successfully via WinGet"
        return $true
    } catch {
        Write-Log "Failed to install $PackageName via WinGet: $($_.Exception.Message)"
        return $false
    }
}

# Install packages from JSON file
function Invoke-PackageInstall {
    $packageListPath = Join-Path $PSScriptRoot "packageList.json"
    
    if (-not (Test-Path $packageListPath)) {
        Write-Log "Package list not found: $packageListPath"
        return
    }
    
    $packages = Get-Content $packageListPath | ConvertFrom-Json
    $chocoAvailable = Get-Command choco -ErrorAction SilentlyContinue
    $wingetAvailable = Test-WinGet
    
    Write-Log "Found $($packages.Count) packages to install"
    Write-Log "Chocolatey available: $($null -ne $chocoAvailable)"
    Write-Log "WinGet available: $wingetAvailable"
    
    $failedPackages = @()
    $skippedPackages = 0
    $totalPackages = $packages.Count
    $currentPackage = 0
    
    foreach ($package in $packages) {
        $currentPackage++
        $progressPercent = [math]::Round(($currentPackage / $totalPackages) * 100)
        
        Write-Progress -Activity "Installing Packages" -Status "Processing $($package.Name) - $currentPackage of $totalPackages" -PercentComplete $progressPercent
        
        Write-Log "Processing package: $($package.Name)"
        
        $installed = $false
        $commandName = if ($package.PSObject.Properties['command']) { $package.command } else { $null }
        
        # Try Chocolatey first (primary package manager)
        if ($chocoAvailable -and $package.chocoId) {
            $installed = Install-ChocoPackage -PackageId $package.chocoId -PackageName $package.Name -CommandName $commandName
        }
        
        # Fallback to WinGet if Chocolatey failed or is not available
        if (-not $installed -and $wingetAvailable -and $package.wingetId) {
            Write-Log "Falling back to WinGet for $($package.Name)"
            $installed = Install-WinGetPackage -PackageId $package.wingetId -PackageName $package.Name -CommandName $commandName
        }
        
        if (-not $installed) {
            Write-Log "Failed to install $($package.Name) with any package manager"
            $failedPackages += $package.Name
        } elseif (Test-PackageInstalled -PackageName $package.Name -CommandName $commandName) {
            $skippedPackages++
        }
        
        Write-Information "" -InformationAction Continue # Empty line for readability
    }
    
    Write-Progress -Activity "Installing Packages" -Completed
    
    # Summary
    Write-Log "Package installation summary:"
    Write-Log "  Total packages: $($packages.Count)"
    Write-Log "  Skipped (already installed): $skippedPackages"
    Write-Log "  Failed: $($failedPackages.Count)" $(if ($failedPackages.Count -gt 0) { "Red" } else { "Green" })
    
    if ($failedPackages.Count -gt 0) {
        Write-Log "Failed packages: $($failedPackages -join ', ')"
        Write-Log "You can retry failed packages by running the script again"
    }
}

# Setup PowerShell profile
function Initialize-PowerShellProfile {
    $profilePath = $PROFILE
    $profileContentPath = Join-Path $PSScriptRoot "profile-content.ps1"
    
    if (-not (Test-Path $profileContentPath)) {
        Write-Log "Profile content file not found: $profileContentPath"
        return
    }
    
    # Create profile directory if it doesn't exist
    $profileDir = Split-Path $profilePath
    if (-not (Test-Path $profileDir)) {
        Write-Log "Creating profile directory: $profileDir"
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    
    try {
        $profileContent = Get-Content $profileContentPath -Raw
        
        if ($Force -or -not (Test-Path $profilePath)) {
            Write-Log "Creating PowerShell profile: $profilePath"
            $profileContent | Set-Content -Path $profilePath -Encoding UTF8
            Write-Log "PowerShell profile created successfully"
        } else {
            Write-Log "Profile already exists. Use -Force to overwrite"
        }
    } catch {
        Write-Log "Failed to setup PowerShell profile: $($_.Exception.Message)"
    }
}

# Main execution
Write-Log "Starting Windows Laptop Automation Setup"
Write-Log "Script location: $PSScriptRoot"

# Validate prerequisites
if (-not (Test-SetupPrerequisite)) {
    Write-Log "Setup prerequisites validation failed. Please fix the issues above and try again."
    exit 1
}

# Install packages
if (-not $SkipPackages) {
    # Check admin privileges only when installing packages
    if (-not (Test-IsAdmin)) {
        Write-Log "Package installation requires administrator privileges. Please run as administrator or use -SkipPackages."
        exit 1
    }
    
    Write-Log "Installing package managers and packages..."
    
    # Ensure Chocolatey is installed
    $chocoInstalled = Install-Chocolatey
    
    if ($chocoInstalled) {
        Invoke-PackageInstall
        
        # Refresh environment variables after package installation
        Write-Log "Refreshing environment variables..."
        $pathValue = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
        [System.Environment]::SetEnvironmentVariable("PATH", $pathValue, "Process")
    } else {
        Write-Log "Cannot proceed without a package manager"
        exit 1
    }
} else {
    Write-Log "Skipping package installation" 
}

# Run office.ps1 if it exists
$officeScriptPath = Join-Path $PSScriptRoot "office.ps1"    
if (Test-Path $officeScriptPath ) {
    # Test if not wanted with the -SkipOffice switch
    if ($SkipOffice) {
        Write-Log "Skipping Office setup script as requested"
        return
    }
    Write-Log "Running Office setup script: $officeScriptPath"
    try {
        . $officeScriptPath
    } catch {
        Write-Log "Failed to run Office setup script: $($_.Exception.Message)"
    }
} else {
    Write-Log "Office setup script not found: $officeScriptPath"
}

# Setup PowerShell profile
if (-not $SkipProfile) {
    Write-Log "Setting up PowerShell profile..."
    Initialize-PowerShellProfile
} else {
    Write-Log "Skipping PowerShell profile setup"
}

Write-Log "Setup completed successfully!"
Write-Log "Please restart your PowerShell session to apply profile changes."
