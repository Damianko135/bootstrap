#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Uninstall script for Windows Laptop Automation.

.DESCRIPTION
    Removes packages listed in uninstallList.json via Chocolatey/WinGet.

.EXAMPLE
    .\uninstall.ps1

.NOTES
    Author: Damian Korver
    Requires: PowerShell 5.1 or later, Administrator privileges
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import shared functions module
Import-Module (Join-Path $PSScriptRoot 'functions.psd1')

# ============================
# Package Uninstallation
# ============================
function Uninstall-Package {
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
        Write-LogEntry "Uninstalling $Name via Chocolatey..."
        try {
            choco uninstall $ChocoId -y 2>&1 | Out-Null
            Write-LogEntry "$Name uninstalled via Chocolatey"
            return $true
        }
        catch {
            Write-LogEntry "Chocolatey uninstall failed for $Name : $_" -Level Warning
        }
    }

    # Fallback to WinGet
    if ($WingetId -and (Test-PackageManagerAvailable -PackageManager WinGet)) {
        Write-LogEntry "Uninstalling $Name via WinGet..."
        try {
            winget uninstall --id $WingetId --silent 2>&1 | Out-Null
            Write-LogEntry "$Name uninstalled via WinGet"
            return $true
        }
        catch {
            Write-LogEntry "WinGet uninstall failed for $Name : $_" -Level Warning
        }
    }

    return $false
}

function Invoke-PackageUninstallation {
    $uninstallList = Join-Path $PSScriptRoot 'uninstallList.json'
    $packages = Get-Content $uninstallList | ConvertFrom-Json

    Write-LogEntry "Uninstalling $($packages.Count) packages..."

    $failed = @()
    $currentIndex = 0

    foreach ($package in $packages) {
        $currentIndex++
        $percent = [math]::Round(($currentIndex / $packages.Count) * 100)

        Write-Progress -Activity 'Uninstalling Packages' `
                      -Status "$($package.Name) ($currentIndex / $($packages.Count))" `
                      -PercentComplete $percent

        $success = Uninstall-Package -Name $package.Name `
                                     -ChocoId $package.chocoId `
                                     -WingetId $package.wingetId

        if (-not $success) {
            $failed += $package.Name
        }
    }

    Write-Progress -Activity 'Uninstalling Packages' -Completed

    if ($failed.Count -gt 0) {
        Write-LogEntry "Failed to uninstall: $($failed -join ', ')" -Level Warning
    }

    Write-LogEntry "Package uninstallation completed. Failed: $($failed.Count) / $($packages.Count)"
}

# ============================
# Main Execution
# ============================
try {
    Write-LogEntry "Starting uninstallation process..."

    if (-not (Test-Administrator)) {
        Write-LogEntry "Uninstallation requires administrator privileges" -Level Error
        Write-LogEntry "Please run this script as administrator"
        exit 1
    }

    Invoke-PackageUninstallation

    Write-LogEntry "Uninstallation completed!"
}
catch {
    Write-LogEntry "Uninstallation failed: $_" -Level Error
    exit 1
}
