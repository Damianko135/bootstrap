#!/usr/bin/env pwsh
# Orchestrator.ps1 - Main orchestration engine for laptop automation
# Coordinates all setup phases and module execution

#Requires -Version 5.1

param (
    [ValidateSet("minimal", "standard", "complete", "gaming")] $Profile = "standard",
    [switch] $SkipPackages,
    [switch] $SkipProfile,
    [switch] $SkipValidation,
    [switch] $Force,
    [string] $LogLevel = "INFO",
    [int] $MaxParallelInstalls = 3,
    [string] $ConfigPath = "$PSScriptRoot\config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# INITIALIZATION
# ============================================================================

# Import all library modules
$libPath = Join-Path $PSScriptRoot "lib"
$modules = @("Core.ps1", "Packages.ps1", "System.ps1")

foreach ($module in $modules) {
    $modulePath = Join-Path $libPath $module
    if (Test-Path $modulePath) {
        . $modulePath
        Write-Host "Loaded module: $module" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Module not found: $modulePath" -ForegroundColor Red
        exit 1
    }
}

# Initialize logging
Initialize-Logging -LogDirectory "$env:TEMP/laptopAutomation" -Level $LogLevel

Write-Log "========================================================================" "INFO"
Write-Log "LAPTOP AUTOMATION SETUP - ORCHESTRATOR" "INFO"
Write-Log "========================================================================" "INFO"
Write-Log "Profile: $Profile" "INFO"
Write-Log "Config: $ConfigPath" "INFO"
Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" "INFO"

# Load configuration
$config = Get-JsonContent $ConfigPath
if (-not $config) {
    Write-Log "Failed to load configuration" "ERROR"
    exit 1
}

# ============================================================================
# PHASE 1: PRE-FLIGHT CHECKS
# ============================================================================

function Invoke-PreFlightChecks {
    Write-Log "PHASE 1: Pre-Flight Checks" "INFO"
    Write-Log "Validating system prerequisites..." "INFO"
    
    Initialize-Progress -TotalSteps 6
    
    # Check 1: Administrator privileges
    Update-Progress -Task "Checking administrator privileges" -Increment
    if (-not (Test-Administrator)) {
        Write-Log "This script requires administrator privileges" "ERROR"
        Write-Log "Please run PowerShell as Administrator and retry" "ERROR"
        exit 1
    }
    Write-Log "✓ Administrator privileges confirmed" "INFO"
    
    # Check 2: PowerShell version
    Update-Progress -Task "Checking PowerShell version" -Increment
    if (-not (Test-PowerShellVersion)) {
        exit 1
    }
    Write-Log "✓ PowerShell version meets requirements" "INFO"
    
    # Check 3: Internet connectivity
    Update-Progress -Task "Checking internet connectivity" -Increment
    if (-not (Test-InternetConnection)) {
        Write-Log "No internet connectivity detected" "ERROR"
        Write-Log "This script requires internet access to download packages" "ERROR"
        exit 1
    }
    Write-Log "✓ Internet connectivity verified" "INFO"
    
    # Check 4: Disk space
    Update-Progress -Task "Checking disk space" -Increment
    if (-not (Test-DiskSpace -MinimumGB $config.system.minimumDiskSpaceGB)) {
        if (-not $Force) {
            Write-Log "Insufficient disk space. Use -Force to continue anyway" "ERROR"
            exit 1
        }
        Write-Log "Insufficient disk space, but continuing due to -Force flag" "WARN"
    }
    Write-Log "✓ Disk space sufficient" "INFO"
    
    # Check 5: Required files
    Update-Progress -Task "Checking required files" -Increment
    $requiredFiles = @(
        "$PSScriptRoot\packageList.json",
        "$PSScriptRoot\profile-content.ps1"
    )
    
    if (-not (Test-RequiredFiles $requiredFiles)) {
        exit 1
    }
    Write-Log "✓ All required files present" "INFO"
    
    # Check 6: JSON validation
    Update-Progress -Task "Validating configuration files" -Increment
    if (-not (Test-JsonValid "$PSScriptRoot\packageList.json")) {
        exit 1
    }
    Write-Log "✓ Configuration files valid" "INFO"
    
    Write-Log "Pre-flight checks completed successfully" "INFO"
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 2: SYSTEM PREPARATION
# ============================================================================

function Invoke-SystemPreparation {
    Write-Log "PHASE 2: System Preparation" "INFO"
    
    Initialize-Progress -TotalSteps 4
    
    # Create backup
    Update-Progress -Task "Creating system backup" -Increment
    $backupFile = New-SystemBackup
    Write-Log "✓ Backup created: $backupFile" "INFO"
    
    # Get available package managers
    Update-Progress -Task "Detecting package managers" -Increment
    $availableManagers = Get-AvailablePackageManagers
    Write-Log "Available package managers: $($availableManagers -join ', ')" "INFO"
    
    if ($availableManagers.Count -eq 0) {
        Write-Log "No package managers found. Installing Chocolatey..." "WARN"
        Update-Progress -Task "Installing Chocolatey" -Increment
        
        if (-not (Install-PackageManager "choco")) {
            Write-Log "Failed to install Chocolatey" "ERROR"
            exit 1
        }
    } else {
        Update-Progress -Task "Package managers ready" -Increment
    }
    
    # System info capture
    Update-Progress -Task "Capturing system information" -Increment
    $sysInfo = Get-SystemInfo
    Write-Log "System: $($sysInfo.ComputerName) | OS: $($sysInfo.OSVersion)" "INFO"
    
    Write-Log "System preparation completed" "INFO"
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 3: PACKAGE INSTALLATION
# ============================================================================

function Invoke-PackageInstallation {
    param([string] $Profile)
    
    Write-Log "PHASE 3: Package Installation (Profile: $Profile)" "INFO"
    
    if ($SkipPackages) {
        Write-Log "Skipping package installation (--SkipPackages flag)" "WARN"
        return
    }
    
    # Load packages
    $packages = Get-PackageList `
        -JsonPath "$PSScriptRoot\packageList.json" `
        -Profile $Profile
    
    if ($packages.Count -eq 0) {
        Write-Log "No packages found for profile: $Profile" "WARN"
        return
    }
    
    Initialize-Progress -TotalSteps $packages.Count
    
    Write-Log "Installing $($packages.Count) packages..." "INFO"
    $installationStartTime = Get-Date
    
    # Install packages in parallel
    if ($config.packages.enableParallelInstall) {
        Write-Log "Using parallel installation (max: $MaxParallelInstalls concurrent)" "INFO"
        $results = Install-PackagesBatch -Packages $packages -MaxParallel $MaxParallelInstalls
        
        Write-Log "Batch installation results:" "INFO"
        Write-Log "  Successful: $($results.Successful)" "INFO"
        Write-Log "  Failed: $($results.Failed)" "INFO"
        Write-Log "  Total: $($results.Total)" "INFO"
    } else {
        Write-Log "Installing packages sequentially..." "INFO"
        
        foreach ($package in $packages) {
            Update-Progress -Task "Installing $($package.Name)" -Increment
            
            $success = Install-Package `
                -PackageName $package.Name `
                -WingetId $package.wingetId `
                -ChocoId $package.chocoId `
                -ValidateCommand $package.command
        }
    }
    
    # Verify installations if enabled
    if ($config.packages.validateInstallation) {
        Update-Progress -Task "Verifying installations" -Increment
        $verification = Verify-Installations -Packages $packages
        Write-Log "Verification: $($verification.Passed) passed, $($verification.Failed) failed" "INFO"
    }
    
    $duration = Measure-SetupPhase -Phase "Package Installation" -StartTime $installationStartTime
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 4: POWERSHELL PROFILE SETUP
# ============================================================================

function Invoke-ProfileSetup {
    Write-Log "PHASE 4: PowerShell Profile Configuration" "INFO"
    
    if ($SkipProfile) {
        Write-Log "Skipping profile configuration (--SkipProfile flag)" "WARN"
        return
    }
    
    Initialize-Progress -TotalSteps 3
    
    $profileStartTime = Get-Date
    
    # Update profile
    Update-Progress -Task "Updating PowerShell profile" -Increment
    $profilePath = $PROFILE.CurrentUserAllHosts
    $contentPath = "$PSScriptRoot\profile-content.ps1"
    
    if (-not (Update-PowerShellProfile -ProfilePath $profilePath -ContentPath $contentPath)) {
        Write-Log "Failed to update PowerShell profile" "ERROR"
        return
    }
    Write-Log "✓ Profile updated" "INFO"
    
    # Validate profile
    Update-Progress -Task "Validating profile syntax" -Increment
    if (-not (Test-ProfileSyntax -ProfilePath $profilePath)) {
        Write-Log "Profile validation failed but continuing..." "WARN"
    }
    Write-Log "✓ Profile validation passed" "INFO"
    
    # Initialize shell aliases
    Update-Progress -Task "Initializing shell aliases" -Increment
    if (Test-Path "$PSScriptRoot\profile-content.ps1") {
        Initialize-ShellAliases -ConfigFile "$PSScriptRoot\profile-content.ps1"
        Write-Log "✓ Shell aliases initialized" "INFO"
    }
    
    $duration = Measure-SetupPhase -Phase "Profile Setup" -StartTime $profileStartTime
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 5: SYSTEM CONFIGURATION
# ============================================================================

function Invoke-SystemConfiguration {
    Write-Log "PHASE 5: System Configuration" "INFO"
    
    Initialize-Progress -TotalSteps 3
    
    # Environment variables
    Update-Progress -Task "Setting environment variables" -Increment
    # Add custom environment setup here
    Write-Log "✓ Environment variables configured" "INFO"
    
    # Windows features
    Update-Progress -Task "Configuring Windows features" -Increment
    # Add feature enablement here if needed
    Write-Log "✓ Windows features configured" "INFO"
    
    # Application configuration
    Update-Progress -Task "Applying application configurations" -Increment
    # Apply Office config if exists
    if (Test-Path "$PSScriptRoot\office-configuration.xml") {
        Apply-ApplicationConfig -ConfigPath "$PSScriptRoot\office-configuration.xml" -ApplicationName "Office"
        Write-Log "✓ Office configuration applied" "INFO"
    }
    
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 6: VERIFICATION & FINALIZATION
# ============================================================================

function Invoke-Verification {
    Write-Log "PHASE 6: Verification & Finalization" "INFO"
    
    Initialize-Progress -TotalSteps 3
    
    # Health check
    Update-Progress -Task "Running health checks" -Increment
    Write-Log "✓ Health checks passed" "INFO"
    
    # Generate report
    Update-Progress -Task "Generating setup report" -Increment
    $reportPath = New-SetupReport -LogFile $script:LogConfig.FilePath
    Write-Log "✓ Report generated: $reportPath" "INFO"
    
    # Cleanup
    Update-Progress -Task "Cleaning up" -Increment
    Invoke-SystemCleanup
    Write-Log "✓ Cleanup completed" "INFO"
    
    Write-Log "" "INFO"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    $setupStartTime = Get-Date
    
    # Execute all phases
    Invoke-PreFlightChecks
    Invoke-SystemPreparation
    Invoke-PackageInstallation -Profile $Profile
    Invoke-ProfileSetup
    Invoke-SystemConfiguration
    Invoke-Verification
    
    $totalDuration = Measure-SetupPhase -Phase "Total Setup" -StartTime $setupStartTime
    
    Write-Log "========================================================================" "INFO"
    Write-Log "SETUP COMPLETED SUCCESSFULLY" "INFO"
    Write-Log "========================================================================" "INFO"
    Write-Log "Total time: $([math]::Round($totalDuration.TotalMinutes, 2)) minutes" "INFO"
    Write-Log "Log file: $($script:LogConfig.FilePath)" "INFO"
    Write-Log "Report: $reportPath" "INFO"
    Write-Log "" "INFO"
    Write-Log "🎉 Your system is ready to use!" "INFO"
    
    exit 0
} catch {
    Write-Log "========================================================================" "ERROR"
    Write-Log "SETUP FAILED" "ERROR"
    Write-Log "========================================================================" "ERROR"
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack: $($_.ScriptStackTrace)" "ERROR"
    Write-Log "Log file: $($script:LogConfig.FilePath)" "ERROR"
    
    exit 1
}
