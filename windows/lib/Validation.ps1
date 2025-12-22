#!/usr/bin/env pwsh
# Validation.ps1 - Post-installation verification and health checks
# Validates installed packages and system integration

Set-StrictMode -Version Latest

# ============================================================================
# POST-INSTALLATION VALIDATION
# ============================================================================

<#
.SYNOPSIS
    Test if an installed package is functioning correctly
.PARAMETER PackageName
    Name of the package to test
.PARAMETER ValidateCommand
    Command to run to validate the installation
.PARAMETER ExpectedOutput
    Pattern that should be found in the output (optional)
#>
function Test-PackageInstallation {
    param(
        [string] $PackageName,
        [string] $ValidateCommand,
        [string] $ExpectedOutput = $null,
        [int] $TimeoutSeconds = 10
    )
    
    if (-not $ValidateCommand) {
        Write-Log "No validation command specified for $PackageName" "WARN"
        return $true  # Assume success if no test specified
    }
    
    try {
        # Refresh PATH to pickup new installations
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        
        # Simple command existence check
        if (Test-CommandExists $ValidateCommand) {
            Write-Log "✓ Package validation passed: $PackageName (command: $ValidateCommand)" "INFO"
            
            # If expected output specified, try to match it
            if ($ExpectedOutput) {
                try {
                    $output = & $ValidateCommand --version 2>&1 | Out-String
                    if ($output -match $ExpectedOutput) {
                        Write-Log "  ✓ Output validation passed: matched '$ExpectedOutput'" "DEBUG"
                        return $true
                    } else {
                        Write-Log "  ⚠ Output did not match expected pattern" "WARN"
                    }
                } catch {
                    Write-Log "  ⚠ Could not verify output: $($_.Exception.Message)" "DEBUG"
                }
            }
            
            return $true
        } else {
            Write-Log "✗ Package validation failed: $PackageName (command: $ValidateCommand not found)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "✗ Package validation error for $PackageName`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Validate all installed packages against a package list
.PARAMETER Packages
    Array of package definitions
#>
function Test-AllPackagesInstalled {
    param([array] $Packages)
    
    Write-Log "PHASE: Post-Installation Validation" "INFO"
    Initialize-Progress -TotalSteps $Packages.Count
    
    $validationResults = @{
        Total = $Packages.Count
        Passed = 0
        Failed = 0
        Skipped = 0
        Details = @()
    }
    
    foreach ($package in $Packages) {
        Update-Progress -Task "Validating $($package.Name)" -Increment
        
        if (-not $package.command) {
            Write-Log "Skipping validation for $($package.Name) (no command specified)" "DEBUG"
            $validationResults.Skipped++
            continue
        }
        
        $result = Test-PackageInstallation -PackageName $package.Name -ValidateCommand $package.command
        
        $validationResults.Details += @{
            Package = $package.Name
            Status = if ($result) { "PASSED" } else { "FAILED" }
            Timestamp = Get-Date
        }
        
        if ($result) {
            $validationResults.Passed++
        } else {
            $validationResults.Failed++
        }
    }
    
    Write-Log "Validation complete: $($validationResults.Passed) passed, $($validationResults.Failed) failed, $($validationResults.Skipped) skipped" "INFO"
    
    return $validationResults
}

# ============================================================================
# SHELL INTEGRATION VALIDATION
# ============================================================================

<#
.SYNOPSIS
    Test PowerShell profile integration
#>
function Test-PowerShellIntegration {
    Write-Log "Validating PowerShell integration..." "INFO"
    
    $results = @{
        ProfileExists = $false
        ProfileValid = $false
        ProfileLoads = $false
        Issues = @()
    }
    
    $profilePath = $PROFILE.CurrentUserAllHosts
    
    # Check if profile exists
    if (Test-Path $profilePath) {
        $results.ProfileExists = $true
        Write-Log "✓ PowerShell profile exists: $profilePath" "INFO"
    } else {
        $results.Issues += "PowerShell profile not found"
        Write-Log "✗ PowerShell profile not found" "WARN"
        return $results
    }
    
    # Validate syntax
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $profilePath -Raw), [ref]$null)
        $results.ProfileValid = $true
        Write-Log "✓ PowerShell profile syntax is valid" "INFO"
    } catch {
        $results.Issues += "Profile has syntax errors: $($_.Exception.Message)"
        Write-Log "✗ PowerShell profile has syntax errors: $($_.Exception.Message)" "ERROR"
    }
    
    # Check if profile loads without errors
    try {
        & $profilePath 2>&1 | Out-Null
        $results.ProfileLoads = $true
        Write-Log "✓ PowerShell profile loads without errors" "INFO"
    } catch {
        $results.Issues += "Profile fails to load: $($_.Exception.Message)"
        Write-Log "⚠ PowerShell profile loading: $($_.Exception.Message)" "WARN"
    }
    
    return $results
}

<#
.SYNOPSIS
    Test Windows Terminal integration
#>
function Test-WindowsTerminalIntegration {
    Write-Log "Validating Windows Terminal integration..." "INFO"
    
    $results = @{
        Installed = $false
        ConfigExists = $false
        Issues = @()
    }
    
    # Check if Windows Terminal is installed
    if (Test-CommandExists "wt") {
        $results.Installed = $true
        Write-Log "✓ Windows Terminal is installed" "INFO"
    } else {
        $results.Issues += "Windows Terminal not found"
        Write-Log "⚠ Windows Terminal not installed (optional)" "WARN"
        return $results
    }
    
    # Check settings file
    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $settingsPath) {
        $results.ConfigExists = $true
        Write-Log "✓ Windows Terminal settings found" "INFO"
    } else {
        $results.Issues += "Windows Terminal settings not found (will use defaults)"
        Write-Log "⚠ Windows Terminal settings not found" "WARN"
    }
    
    return $results
}

# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================

<#
.SYNOPSIS
    Test environment variable configuration
#>
function Test-EnvironmentConfiguration {
    Write-Log "Validating environment configuration..." "INFO"
    
    $results = @{
        PathValid = $false
        Issues = @()
        Details = @{}
    }
    
    # Test PATH variable
    $pathVar = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    if ($pathVar -and $pathVar.Length -gt 0) {
        $results.PathValid = $true
        $results.Details.PathLength = $pathVar.Length
        Write-Log "✓ PATH environment variable is set" "INFO"
    } else {
        $results.Issues += "PATH environment variable is empty"
        Write-Log "✗ PATH environment variable is empty" "ERROR"
    }
    
    # Common tools in PATH
    $commonTools = @("PowerShell", "git", "python", "node")
    $foundTools = @()
    
    foreach ($tool in $commonTools) {
        if (Test-CommandExists $tool) {
            $foundTools += $tool
        }
    }
    
    $results.Details.CommonToolsFound = $foundTools
    Write-Log "Common tools found in PATH: $($foundTools -join ', ')" "INFO"
    
    return $results
}

# ============================================================================
# SYSTEM INTEGRATION VALIDATION
# ============================================================================

<#
.SYNOPSIS
    Run comprehensive post-installation validation
#>
function Invoke-FullValidation {
    param(
        [array] $Packages,
        [switch] $StopOnError
    )
    
    Write-Log "PHASE: Full Post-Installation Validation" "INFO"
    
    $allResults = @{
        Timestamp = Get-Date
        PackageValidation = $null
        PowerShellIntegration = $null
        WindowsTerminalIntegration = $null
        EnvironmentConfiguration = $null
        OverallStatus = "PASSED"
        Issues = @()
    }
    
    # 1. Package validation
    Write-Log "`nValidating installed packages..." "INFO"
    $allResults.PackageValidation = Test-AllPackagesInstalled $Packages
    
    if ($allResults.PackageValidation.Failed -gt 0) {
        $allResults.OverallStatus = "WARNING"
        $allResults.Issues += "Some packages failed validation: $($allResults.PackageValidation.Failed) failures"
        
        if ($StopOnError) {
            Write-Log "Stopping due to package validation failures" "ERROR"
            return $allResults
        }
    }
    
    # 2. PowerShell integration
    Write-Log "`nValidating PowerShell integration..." "INFO"
    $allResults.PowerShellIntegration = Test-PowerShellIntegration
    
    if ($allResults.PowerShellIntegration.Issues.Count -gt 0) {
        $allResults.OverallStatus = "WARNING"
        $allResults.Issues += $allResults.PowerShellIntegration.Issues
    }
    
    # 3. Windows Terminal integration
    Write-Log "`nValidating Windows Terminal integration..." "INFO"
    $allResults.WindowsTerminalIntegration = Test-WindowsTerminalIntegration
    
    # 4. Environment configuration
    Write-Log "`nValidating environment configuration..." "INFO"
    $allResults.EnvironmentConfiguration = Test-EnvironmentConfiguration
    
    if ($allResults.EnvironmentConfiguration.Issues.Count -gt 0) {
        $allResults.OverallStatus = "WARNING"
        $allResults.Issues += $allResults.EnvironmentConfiguration.Issues
    }
    
    return $allResults
}

<#
.SYNOPSIS
    Self-repair broken installations
#>
function Repair-Installation {
    param(
        [array] $Packages,
        [string] $Profile = "standard"
    )
    
    Write-Log "PHASE: Installation Repair" "INFO"
    
    $repairResults = @{
        Timestamp = Get-Date
        Repaired = @()
        Failed = @()
    }
    
    # First, get validation results
    $validation = Test-AllPackagesInstalled $Packages
    
    # Repair failed packages
    foreach ($result in $validation.Details | Where-Object { $_.Status -eq "FAILED" }) {
        $package = $Packages | Where-Object { $_.Name -eq $result.Package }
        
        if ($package) {
            Write-Log "Attempting to repair: $($package.Name)" "INFO"
            
            # Try reinstalling
            try {
                if ($package.wingetId) {
                    winget install -e --id $package.wingetId --accept-source-agreements --accept-package-agreements -q
                } elseif ($package.chocoId) {
                    choco install $package.chocoId -y -q
                } else {
                    Write-Log "No valid package ID for repair: $($package.Name)" "WARN"
                    $repairResults.Failed += $package.Name
                    continue
                }
                
                # Re-validate
                Start-Sleep -Seconds 2
                if (Test-PackageInstallation -PackageName $package.Name -ValidateCommand $package.command) {
                    $repairResults.Repaired += $package.Name
                    Write-Log "✓ Successfully repaired: $($package.Name)" "INFO"
                } else {
                    $repairResults.Failed += $package.Name
                    Write-Log "✗ Repair failed for: $($package.Name)" "ERROR"
                }
            } catch {
                $repairResults.Failed += $package.Name
                Write-Log "✗ Repair error for $($package.Name): $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    Write-Log "Repair complete: $($repairResults.Repaired.Count) repaired, $($repairResults.Failed.Count) failed" "INFO"
    
    return $repairResults
}
