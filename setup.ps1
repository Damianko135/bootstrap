#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup script for Windows Laptop Automation.

.DESCRIPTION
    Installs packages via Chocolatey/WinGet, uninstalls unwanted packages, and configures PowerShell profile.

.PARAMETER SkipPackages
    Skip package installation and uninstallation.

.PARAMETER SkipProfile
    Skip PowerShell profile setup.

.PARAMETER Force
    Force overwrite of existing profile.

.PARAMETER SkipOffice
    Skip Office installation script.

.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -SkipPackages -Force

.NOTES
    Author: Damian Korver
    Requires: PowerShell 5.1 or later, Administrator privileges for package installation
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [switch]
    $SkipPackages,

    [switch]
    $SkipProfile,

    [switch]
    $Force,

    [switch]
    $SkipOffice
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import shared functions module
Import-Module (Join-Path $PSScriptRoot 'functions.psd1')

# ============================
# Chocolatey Installation
# ============================
function Install-ChocolateyPackageManager {
    Write-LogEntry "Installing Chocolatey..."

    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    $tempScript = Join-Path $env:TEMP 'InstallChocolatey.ps1'
    $chocoScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
    $chocoScript | Set-Content -Path $tempScript -Force

    & $tempScript
    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

    # Refresh PATH
    $pathValue = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    [System.Environment]::SetEnvironmentVariable('PATH', $pathValue, 'Process')

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-LogEntry "Chocolatey installed successfully"
        return $true
    }

    Write-LogEntry "Chocolatey installation failed" -Level Error
    return $false
}

# ============================
# Package Installation
# ============================
function Install-Package {
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,

        [string]
        $ChocoId,

        [string]
        $WingetId
    )

    # Try Chocolatey first
    if ($ChocoId -and (Test-PackageManagerAvailable -PackageManager Chocolatey)) {
        Write-LogEntry "Installing $Name via Chocolatey..."
        try {
            choco install $ChocoId -y --no-progress | Out-Null
            Write-LogEntry "$Name installed via Chocolatey"
            return $true
        }
        catch {
            Write-LogEntry "Chocolatey install failed for $Name : $_" -Level Warning
        }
    }

    # Fallback to WinGet
    if ($WingetId -and (Test-PackageManagerAvailable -PackageManager WinGet)) {
        Write-LogEntry "Installing $Name via WinGet..."
        try {
            winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Write-LogEntry "$Name installed via WinGet"
            return $true
        }
        catch {
            Write-LogEntry "WinGet install failed for $Name : $_" -Level Warning
        }
    }

    return $false
}

function Invoke-PackageInstallation {
    $packageList = Join-Path $PSScriptRoot 'packageList.json'
    $packages = Get-Content $packageList | ConvertFrom-Json

    Write-LogEntry "Installing $($packages.Count) packages..."

    $failed = @()
    $currentIndex = 0

    foreach ($package in $packages) {
        $currentIndex++
        $percent = [math]::Round(($currentIndex / $packages.Count) * 100)

        Write-Progress -Activity 'Installing Packages' `
                      -Status "$($package.Name) ($currentIndex / $($packages.Count))" `
                      -PercentComplete $percent

        $success = Install-Package -Name $package.Name `
                                   -ChocoId $package.chocoId `
                                   -WingetId $package.wingetId

        if (-not $success) {
            $failed += $package.Name
        }
    }

    Write-Progress -Activity 'Installing Packages' -Completed

    if ($failed.Count -gt 0) {
        Write-LogEntry "Failed to install: $($failed -join ', ')" -Level Warning
    }

    Write-LogEntry "Package installation completed. Failed: $($failed.Count) / $($packages.Count)"
}

# ============================
# Profile Setup
# ============================
function Invoke-ProfileSetup {
    $profilePath = $PROFILE
    $profileSource = Join-Path $PSScriptRoot 'profile-content.ps1'

    Write-LogEntry "Setting up PowerShell profile..."

    $profileDir = Split-Path $profilePath
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (-not $Force -and (Test-Path $profilePath)) {
        Write-LogEntry "Profile already exists. Use -Force to overwrite"
        return
    }

    $content = Get-Content $profileSource -Raw
    $content | Set-Content -Path $profilePath -Encoding UTF8

    Write-LogEntry "Profile created at: $profilePath"
}

# ============================
# Office Setup
# ============================
function Invoke-OfficeSetup {
    $officeScript = Join-Path $PSScriptRoot 'office.ps1'

    if (-not (Test-Path $officeScript)) {
        return
    }

    if ($SkipOffice) {
        Write-LogEntry "Skipping Office setup"
        return
    }

    Write-LogEntry "Running Office setup..."
    try {
        . $officeScript
    }
    catch {
        Write-LogEntry "Office setup failed: $_" -Level Warning
    }
}

# ============================
# Main Execution
# ============================
try {
    Write-LogEntry "Starting setup..."

    if (-not $SkipPackages) {
        if (-not (Test-Administrator)) {
            Write-LogEntry "Package installation requires administrator privileges" -Level Error
            Write-LogEntry "Run as administrator or use -SkipPackages"
            exit 1
        }

        if (-not (Test-PackageManagerAvailable -PackageManager Chocolatey)) {
            if (-not (Install-ChocolateyPackageManager)) {
                Write-LogEntry "Cannot proceed without Chocolatey" -Level Error
                exit 1
            }
        }

        # Uninstall unwanted packages first
        $uninstallScript = Join-Path $PSScriptRoot 'uninstall.ps1'
        if (Test-Path $uninstallScript) {
            Write-LogEntry "Running uninstall script..."
            & $uninstallScript
        }

        # Then install desired packages
        Invoke-PackageInstallation
    }

    Invoke-OfficeSetup

    if (-not $SkipProfile) {
        Invoke-ProfileSetup
    }

    Write-LogEntry "Setup completed successfully!"
    Write-LogEntry "Restart PowerShell to apply profile changes"
}
catch {
    Write-LogEntry "Setup failed: $_" -Level Error
    exit 1
}
