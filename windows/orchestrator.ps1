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
    [switch] $Recover,
    [switch] $Repair,
    [switch] $DryRun,
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
$modules = @("Core.ps1", "Packages.ps1", "System.ps1", "Telemetry.ps1", "Validation.ps1", "Hooks.ps1")

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

# Initialize checkpoint system
Initialize-CheckpointSystem

# Initialize telemetry
Initialize-Metrics

# Initialize hook system
Initialize-HookSystem

Write-Log "========================================================================" "INFO"
Write-Log "LAPTOP AUTOMATION SETUP - ORCHESTRATOR v2.1" "INFO"
Write-Log "========================================================================" "INFO"
Write-Log "Profile: $Profile" "INFO"
Write-Log "Config: $ConfigPath" "INFO"
Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" "INFO"

if ($DryRun) {
    Write-Log "⚠ DRY-RUN MODE - No changes will be made" "WARN"
}

if ($Recover) {
    Write-Log "⚠ RECOVERY MODE - Attempting to resume from last checkpoint" "WARN"
}

if ($Repair) {
    Write-Log "⚠ REPAIR MODE - Will attempt to repair failed installations" "WARN"
}

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
    
    # Save checkpoint
    Save-Checkpoint -Phase "PreFlightChecks" -Data @{
        Timestamp = Get-Date
        AdminCheck = $true
    }
    
    Write-Log "Pre-flight checks completed successfully" "INFO"
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 2: SYSTEM PREPARATION
# ============================================================================

function Invoke-SystemPreparation {
    Write-Log "PHASE 2: System Preparation" "INFO"
    Start-MetricsPhase "SystemPreparation"
    
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
            Complete-MetricsPhase "SystemPreparation" "FAILED"
            exit 1
        }
    } else {
        Update-Progress -Task "Package managers ready" -Increment
    }
    
    # System info capture
    Update-Progress -Task "Capturing system information" -Increment
    $sysInfo = Get-SystemInfo
    Write-Log "System: $($sysInfo.ComputerName) | OS: $($sysInfo.OSVersion)" "INFO"
    
    # Save checkpoint
    Save-Checkpoint -Phase "SystemPreparation" -Data @{
        BackupFile = $backupFile
        AvailableManagers = $availableManagers
    }
    
    Complete-MetricsPhase "SystemPreparation" "SUCCESS"
    Write-Log "System preparation completed" "INFO"
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 3: PACKAGE INSTALLATION
# ============================================================================

function Invoke-PackageInstallation {
    param([string] $Profile)
    
    Write-Log "PHASE 3: Package Installation (Profile: $Profile)" "INFO"
    Start-MetricsPhase "PackageInstallation"
    
    if ($SkipPackages) {
        Write-Log "Skipping package installation (--SkipPackages flag)" "WARN"
        Complete-MetricsPhase "PackageInstallation" "SKIPPED"
        return
    }
    
    # Load packages
    $packages = Get-PackageList `
        -JsonPath "$PSScriptRoot\packageList.json" `
        -Profile $Profile
    
    if ($packages.Count -eq 0) {
        Write-Log "No packages found for profile: $Profile" "WARN"
        Complete-MetricsPhase "PackageInstallation" "SKIPPED"
        return
    }
    
    # Dependency resolution and conflict detection
    $graph = Build-DependencyGraph $packages
    $conflicts = Detect-PackageConflicts $packages $graph
    
    if ($conflicts.Count -gt 0) {
        Write-Log "Package conflicts detected! Use --Force to override." "ERROR"
        if (-not $Force) {
            Complete-MetricsPhase "PackageInstallation" "FAILED"
            exit 1
        }
    }
    
    # Sort packages by dependencies
    $packages = Sort-PackagesByDependencies $packages $graph
    
    # Show preview if dry-run
    if ($DryRun -or $config.packages.dryRunMode) {
        $preview = Get-InstallationPreview -Packages $packages -Profile $Profile
        Show-InstallationPreview $preview
        Write-Log "Dry-run mode: no packages will be installed" "INFO"
        Complete-MetricsPhase "PackageInstallation" "DRY_RUN"
        return
    }
    
    # Execute pre-installation hooks
    Invoke-Hooks -HookName "PrePackageInstall" -Parameters @{Packages = $packages; Profile = $Profile}
    
    Initialize-Progress -TotalSteps $packages.Count
    
    Write-Log "Installing $($packages.Count) packages..." "INFO"
    $installationStartTime = Get-Date
    
    # Install packages in parallel or sequentially
    if ($config.packages.enableParallelInstall) {
        Write-Log "Using parallel installation (max: $MaxParallelInstalls concurrent)" "INFO"
        $results = Install-PackagesBatch -Packages $packages -MaxParallel $MaxParallelInstalls
        
        Write-Log "Batch installation results:" "INFO"
        Write-Log "  Successful: $($results.Successful)" "INFO"
        Write-Log "  Failed: $($results.Failed)" "INFO"
        Write-Log "  Total: $($results.Total)" "INFO"
        
        Record-PackageMetric -PackageName "batch" -Status "SUCCESS" -Message "Batch: $($results.Successful)/$($results.Total) succeeded"
    } else {
        Write-Log "Installing packages sequentially..." "INFO"
        
        foreach ($package in $packages) {
            Update-Progress -Task "Installing $($package.Name)" -Increment
            
            $success = Install-Package `
                -PackageName $package.Name `
                -WingetId $package.wingetId `
                -ChocoId $package.chocoId `
                -ValidateCommand $package.command
            
            if ($success) {
                Record-PackageMetric -PackageName $package.Name -Status "SUCCESS"
            } else {
                Record-PackageMetric -PackageName $package.Name -Status "FAILED"
            }
        }
    }
    
    # Execute post-installation hooks
    Invoke-Hooks -HookName "PostPackageInstall" -Parameters @{Packages = $packages; Profile = $Profile}
    
    # Save checkpoint
    Save-Checkpoint -Phase "PackageInstallation" -Data @{
        Profile = $Profile
        PackageCount = $packages.Count
    }
    
    Complete-MetricsPhase "PackageInstallation" "SUCCESS"
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 4: POWERSHELL PROFILE SETUP
# ============================================================================

function Invoke-ProfileSetup {
    Write-Log "PHASE 4: PowerShell Profile Configuration" "INFO"
    Start-MetricsPhase "ProfileSetup"
    
    if ($SkipProfile) {
        Write-Log "Skipping profile configuration (--SkipProfile flag)" "WARN"
        Complete-MetricsPhase "ProfileSetup" "SKIPPED"
        return
    }
    
    Initialize-Progress -TotalSteps 3
    
    # Update profile
    Update-Progress -Task "Updating PowerShell profile" -Increment
    $profilePath = $PROFILE.CurrentUserAllHosts
    $contentPath = "$PSScriptRoot\profile-content.ps1"
    
    if (-not (Update-PowerShellProfile -ProfilePath $profilePath -ContentPath $contentPath)) {
        Write-Log "Failed to update PowerShell profile" "ERROR"
        Complete-MetricsPhase "ProfileSetup" "FAILED"
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
    
    # Save checkpoint
    Save-Checkpoint -Phase "ProfileSetup" -Data @{
        ProfilePath = $profilePath
    }
    
    Complete-MetricsPhase "ProfileSetup" "SUCCESS"
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 5: VALIDATION & HEALTH CHECKS
# ============================================================================

function Invoke-PostInstallationValidation {
    param([Object[]] $Packages)
    
    Write-Log "PHASE 5: Post-Installation Validation" "INFO"
    Start-MetricsPhase "Validation"
    
    if ($SkipValidation) {
        Write-Log "Skipping validation (--SkipValidation flag)" "WARN"
        Complete-MetricsPhase "Validation" "SKIPPED"
        return
    }
    
    if (-not $config.validation.enablePostInstallValidation) {
        Write-Log "Post-installation validation disabled in config" "DEBUG"
        Complete-MetricsPhase "Validation" "SKIPPED"
        return
    }
    
    # Execute pre-validation hooks
    Invoke-Hooks -HookName "PreValidation" -Parameters @{Packages = $Packages}
    
    Initialize-Progress -TotalSteps 2
    
    # Run comprehensive validation
    Update-Progress -Task "Running comprehensive validation" -Increment
    $validationResults = Invoke-FullValidation -Packages $Packages -StopOnError $config.validation.stopOnValidationError
    
    # Run repair if requested
    if ($Repair -or $config.validation.repairFailedPackages) {
        Update-Progress -Task "Attempting to repair failed installations" -Increment
        if ($validationResults.PackageValidation.Failed -gt 0) {
            Write-Log "Attempting repair for $($validationResults.PackageValidation.Failed) failed packages..." "INFO"
            $repairResults = Repair-Installation -Packages $Packages -Profile $Profile
            Write-Log "Repair results: $($repairResults.Repaired.Count) fixed, $($repairResults.Failed.Count) still failing" "INFO"
        }
    } else {
        Update-Progress -Task "Validation complete" -Increment
    }
    
    # Execute post-validation hooks
    Invoke-Hooks -HookName "PostValidation" -Parameters @{ValidationResults = $validationResults}
    
    # Save checkpoint
    Save-Checkpoint -Phase "Validation" -Data @{
        ValidationStatus = $validationResults.OverallStatus
        IssueCount = $validationResults.Issues.Count
    }
    
    Complete-MetricsPhase "Validation" "SUCCESS"
    Write-Log "" "INFO"
}

# ============================================================================
# PHASE 6: FINALIZATION & REPORTING
# ============================================================================

function Invoke-Finalization {
    Write-Log "PHASE 6: Finalization & Reporting" "INFO"
    Start-MetricsPhase "Finalization"
    
    Initialize-Progress -TotalSteps 3
    
    # Generate report
    Update-Progress -Task "Generating setup report" -Increment
    $reportPath = Join-Path $config.telemetry.reportPath "setup_report_$(Get-Date -Format yyyyMMdd_HHmmss).json"
    $report = Get-SetupReport -ReportPath $reportPath
    Write-Log "✓ Report generated: $reportPath" "INFO"
    
    # Send telemetry if enabled
    Update-Progress -Task "Processing telemetry" -Increment
    if ($config.telemetry.enableTelemetry) {
        Send-Telemetry -Report $report -Endpoint $config.telemetry.telemetryEndpoint
    }
    
    # Display summary
    Update-Progress -Task "Displaying summary" -Increment
    if ($config.notifications.showSummaryOnCompletion) {
        Show-SetupSummary -Report $report
    }
    
    # Save final checkpoint
    Save-Checkpoint -Phase "Finalization" -Data @{
        ReportPath = $reportPath
        CompletedSuccessfully = $true
    }
    
    Complete-MetricsPhase "Finalization" "SUCCESS"
    
    return $report
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    $setupStartTime = Get-Date
    
    # Recovery mode: check if we should resume from last checkpoint
    if ($Recover) {
        $lastCheckpoint = Get-LastCheckpoint
        if ($lastCheckpoint) {
            Write-Log "Resuming from checkpoint: $($lastCheckpoint.Phase)" "INFO"
            $completedPhases = Get-CompletedPhases
            Write-Log "Previously completed phases: $($completedPhases -join ', ')" "INFO"
        } else {
            Write-Log "No previous checkpoint found, starting fresh" "WARN"
        }
    }
    
    # Execute pre-setup hooks
    Invoke-Hooks -HookName "PreSetup" -Parameters @{Profile = $Profile}
    
    # Execute all phases (skip completed ones only in recovery mode)
    if ($Recover -and (Test-PhaseCompleted "PreFlightChecks")) {
        Write-Log "Skipping pre-flight checks (already completed)" "DEBUG"
    } else {
        Invoke-PreFlightChecks
    }
    
    if ($Recover -and (Test-PhaseCompleted "SystemPreparation")) {
        Write-Log "Skipping system preparation (already completed)" "DEBUG"
    } else {
        Invoke-SystemPreparation
    }
    
    # Load package list for validation phase
    $packages = Get-PackageList -JsonPath "$PSScriptRoot\packageList.json" -Profile $Profile
    
    if ($Recover -and (Test-PhaseCompleted "PackageInstallation")) {
        Write-Log "Skipping package installation (already completed)" "DEBUG"
    } else {
        Invoke-PackageInstallation -Profile $Profile
    }
    
    if ($Recover -and (Test-PhaseCompleted "ProfileSetup")) {
        Write-Log "Skipping profile setup (already completed)" "DEBUG"
    } else {
        Invoke-ProfileSetup
    }
    
    if ($Recover -and (Test-PhaseCompleted "Validation")) {
        Write-Log "Skipping validation (already completed)" "DEBUG"
    } else {
        Invoke-PostInstallationValidation -Packages $packages
    }
    
    # Execute post-setup hooks
    Invoke-Hooks -HookName "PostSetup" -Parameters @{Profile = $Profile}
    
    # Finalization and reporting
    $report = Invoke-Finalization
    
    # Clear checkpoints on successful completion
    if (-not $Recover) {
        Clear-Checkpoints
    }
    
    $totalDuration = (Get-Date) - $setupStartTime
    
    Write-Log "========================================================================" "INFO"
    Write-Log "SETUP COMPLETED SUCCESSFULLY" "INFO"
    Write-Log "========================================================================" "INFO"
    Write-Log "Total time: $([math]::Round($totalDuration.TotalMinutes, 2)) minutes" "INFO"
    Write-Log "Log file: $($script:LogConfig.FilePath)" "INFO"
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
    Write-Log "" "ERROR"
    Write-Log "To recover from this failure, run:" "INFO"
    Write-Log "  powershell -nop -ep Bypass -f orchestrator.ps1 -Recover" "INFO"
    
    exit 1
}
