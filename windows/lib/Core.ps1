#!/usr/bin/env pwsh
# Core.ps1 - Core utility functions for laptop automation
# Provides logging, validation, and system utilities

Set-StrictMode -Version Latest

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

$script:LogConfig = @{
    Level = "INFO"
    Directory = $null
    FilePath = $null
    ConsoleOnly = $false
}

<#
.SYNOPSIS
    Initialize logging system with file and console output
.PARAMETER LogDirectory
    Directory to store log files
.PARAMETER Level
    Minimum log level (DEBUG, INFO, WARN, ERROR)
#>
function Initialize-Logging {
    param(
        [string] $LogDirectory = "$env:TEMP/laptopAutomation",
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")] $Level = "INFO"
    )
    
    $script:LogConfig.Level = $Level
    $script:LogConfig.Directory = $LogDirectory
    
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogConfig.FilePath = Join-Path $LogDirectory "automation_$timestamp.log"
    
    Write-Log "Logging initialized - Level: $Level, File: $($script:LogConfig.FilePath)" "INFO"
}

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")] $Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] [$Level] $Message"
    
    # Map log levels to colors
    $colors = @{
        "DEBUG" = "DarkGray"
        "INFO"  = "White"
        "WARN"  = "Yellow"
        "ERROR" = "Red"
    }
    
    Write-Host $formatted -ForegroundColor $colors[$Level]
    
    # Write to file if configured
    if ($script:LogConfig.FilePath) {
        Add-Content -Path $script:LogConfig.FilePath -Value $formatted
    }
}

# ============================================================================
# PROGRESS TRACKING
# ============================================================================

$script:ProgressState = @{
    TotalSteps = 0
    CurrentStep = 0
    CurrentTask = ""
}

function Initialize-Progress {
    param(
        [int] $TotalSteps
    )
    
    $script:ProgressState.TotalSteps = $TotalSteps
    $script:ProgressState.CurrentStep = 0
}

function Update-Progress {
    param(
        [string] $Task,
        [switch] $Increment
    )
    
    if ($Increment) {
        $script:ProgressState.CurrentStep++
    }
    
    $script:ProgressState.CurrentTask = $Task
    $percent = [math]::Min(($script:ProgressState.CurrentStep / $script:ProgressState.TotalSteps) * 100, 100)
    
    Write-Progress -Activity "System Setup" -Status $Task -PercentComplete $percent -CurrentOperation "Step $($script:ProgressState.CurrentStep)/$($script:ProgressState.TotalSteps)"
    Write-Log "[$($script:ProgressState.CurrentStep)/$($script:ProgressState.TotalSteps)] $Task" "INFO"
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PowerShellVersion {
    param([version] $RequiredVersion = "5.1")
    
    $currentVersion = $PSVersionTable.PSVersion
    
    if ($currentVersion -lt $RequiredVersion) {
        Write-Log "PowerShell version $currentVersion is below required $RequiredVersion" "ERROR"
        return $false
    }
    
    return $true
}

function Test-InternetConnection {
    param(
        [string[]] $DnsServers = @("8.8.8.8", "1.1.1.1"),
        [int] $TimeoutSeconds = 5
    )
    
    Write-Log "Testing internet connectivity..." "DEBUG"
    
    foreach ($dnsServer in $DnsServers) {
        try {
            $result = Test-Connection -ComputerName $dnsServer -Count 1 -Quiet -TimeoutSeconds $TimeoutSeconds
            if ($result) {
                Write-Log "Internet connection verified via $dnsServer" "DEBUG"
                return $true
            }
        } catch {
            Write-Log "Failed to reach $dnsServer : $($_.Exception.Message)" "DEBUG"
        }
    }
    
    return $false
}

function Test-DiskSpace {
    param(
        [int] $MinimumGB = 50
    )
    
    $drive = Get-Item "C:\"
    $freeSpaceGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 2)
    
    Write-Log "Disk space available: ${freeSpaceGB}GB (minimum: ${MinimumGB}GB)" "INFO"
    
    if ($freeSpaceGB -lt $MinimumGB) {
        Write-Log "Insufficient disk space. Required: ${MinimumGB}GB, Available: ${freeSpaceGB}GB" "WARN"
        return $false
    }
    
    return $true
}

function Test-RequiredFiles {
    param(
        [string[]] $Files
    )
    
    $missingFiles = @()
    
    foreach ($file in $Files) {
        if (-not (Test-Path $file)) {
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-Log "Missing required files: $($missingFiles -join ', ')" "ERROR"
        return $false
    }
    
    return $true
}

# ============================================================================
# JSON VALIDATION
# ============================================================================

function Test-JsonValid {
    param(
        [string] $FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Log "JSON file not found: $FilePath" "ERROR"
        return $false
    }
    
    try {
        $content = Get-Content $FilePath -Raw
        $null = ConvertFrom-Json $content
        Write-Log "JSON validation passed: $FilePath" "DEBUG"
        return $true
    } catch {
        Write-Log "JSON validation failed: $FilePath - $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-JsonContent {
    param(
        [string] $FilePath
    )
    
    if (-not (Test-JsonValid $FilePath)) {
        return $null
    }
    
    try {
        $content = Get-Content $FilePath -Raw
        return ConvertFrom-Json $content
    } catch {
        Write-Log "Failed to parse JSON: $FilePath - $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# ============================================================================
# BACKUP & RECOVERY
# ============================================================================

function New-SystemBackup {
    param(
        [string] $BackupPath = "$env:APPDATA/laptopAutomation/backups"
    )
    
    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = Join-Path $BackupPath "backup_$timestamp.json"
    
    $backupData = @{
        Timestamp = Get-Date
        WindowsVersion = (Get-WmiObject -Class Win32_OperatingSystem).Caption
        InstalledPackages = @()
    }
    
    # Get installed packages from winget if available
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            $packages = winget list --accept-source-agreements | Select-Object -Skip 1 | ConvertFrom-Csv
            $backupData.InstalledPackages = $packages
        } catch {
            Write-Log "Could not backup installed packages: $($_.Exception.Message)" "WARN"
        }
    }
    
    $backupData | ConvertTo-Json | Set-Content $backupFile
    Write-Log "Backup created: $backupFile" "INFO"
    
    return $backupFile
}

# ============================================================================
# PACKAGE MANAGER DETECTION
# ============================================================================

function Get-AvailablePackageManagers {
    $managers = @()
    
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $managers += "winget"
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $managers += "choco"
    }
    if (Get-Command apt -ErrorAction SilentlyContinue) {
        $managers += "apt"
    }
    
    return $managers
}

function Install-PackageManager {
    param(
        [ValidateSet("winget", "choco")] $Manager
    )
    
    Write-Log "Installing $Manager..." "INFO"
    
    switch ($Manager) {
        "choco" {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        }
        "winget" {
            Write-Log "winget requires Windows 11 or Windows 10 21H2+. Please install manually or upgrade Windows." "WARN"
            return $false
        }
    }
    
    return $true
}

# ============================================================================
# SYSTEM UTILITIES
# ============================================================================

function Invoke-WithRetry {
    param(
        [ScriptBlock] $ScriptBlock,
        [int] $MaxAttempts = 3,
        [int] $DelaySeconds = 5
    )
    
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Log "Attempt $attempt of $MaxAttempts..." "DEBUG"
            return & $ScriptBlock
        } catch {
            if ($attempt -lt $MaxAttempts) {
                Write-Log "Attempt $attempt failed: $($_.Exception.Message). Retrying in ${DelaySeconds}s..." "WARN"
                Start-Sleep -Seconds $DelaySeconds
            } else {
                Write-Log "All $MaxAttempts attempts failed: $($_.Exception.Message)" "ERROR"
                throw
            }
        }
    }
}

function Test-CommandExists {
    param([string] $Command)
    
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-SystemInfo {
    $info = @{
        Timestamp = Get-Date
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        OSVersion = [System.Environment]::OSVersion.VersionString
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        IsAdmin = Test-Administrator
    }
    
    return $info
}
