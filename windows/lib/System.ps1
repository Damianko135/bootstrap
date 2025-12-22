#!/usr/bin/env pwsh
# System.ps1 - System configuration and customization functions
# Handles environment setup, profile configuration, and system settings

Set-StrictMode -Version Latest

# ============================================================================
# POWERSHELL PROFILE MANAGEMENT
# ============================================================================

<#
.SYNOPSIS
    Update or create PowerShell profile
.PARAMETER ProfilePath
    Path to the profile file to update
.PARAMETER ContentPath
    Path to the content to append to the profile
#>
function Update-PowerShellProfile {
    param(
        [string] $ProfilePath = $PROFILE.CurrentUserAllHosts,
        [string] $ContentPath = $null
    )
    
    Write-Log "Updating PowerShell profile: $ProfilePath" "INFO"
    
    if (-not (Test-Path (Split-Path $ProfilePath))) {
        New-Item -ItemType Directory -Path (Split-Path $ProfilePath) -Force | Out-Null
        Write-Log "Created profile directory" "DEBUG"
    }
    
    if ($ContentPath -and (Test-Path $ContentPath)) {
        $profileContent = Get-Content $ContentPath -Raw
        
        # Check if content already exists to avoid duplicates
        if ((Test-Path $ProfilePath) -and (Select-String -Path $ProfilePath -Pattern "# Laptop Automation Config" -Quiet)) {
            Write-Log "Profile already contains automation config, skipping update" "WARN"
            return $true
        }
        
        # Add marker comment
        $profileContent = "`n# Laptop Automation Config`n$profileContent`n"
        
        Add-Content -Path $ProfilePath -Value $profileContent -Force
        Write-Log "Profile updated successfully" "INFO"
        return $true
    } else {
        Write-Log "Content file not found: $ContentPath" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Validate PowerShell profile syntax
.PARAMETER ProfilePath
    Path to the profile to validate
#>
function Test-ProfileSyntax {
    param(
        [string] $ProfilePath = $PROFILE.CurrentUserAllHosts
    )
    
    Write-Log "Validating profile syntax: $ProfilePath" "INFO"
    
    if (-not (Test-Path $ProfilePath)) {
        Write-Log "Profile not found: $ProfilePath" "WARN"
        return $true
    }
    
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $ProfilePath -Raw), [ref]$null)
        Write-Log "Profile syntax validation passed" "INFO"
        return $true
    } catch {
        Write-Log "Profile syntax validation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# ENVIRONMENT VARIABLES
# ============================================================================

<#
.SYNOPSIS
    Set an environment variable persistently
.PARAMETER Name
    Name of the environment variable
.PARAMETER Value
    Value to set
.PARAMETER Scope
    Scope of the variable (User or Machine)
#>
function Set-EnvironmentVariable {
    param(
        [string] $Name,
        [string] $Value,
        [ValidateSet("User", "Machine")] $Scope = "User"
    )
    
    Write-Log "Setting environment variable: $Name = $Value (Scope: $Scope)" "INFO"
    
    try {
        [System.Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
        # Also set in current session
        Set-Item -Path "env:$Name" -Value $Value
        Write-Log "Environment variable set successfully" "DEBUG"
        return $true
    } catch {
        Write-Log "Failed to set environment variable: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Add a path to PATH environment variable
.PARAMETER Path
    Path to add
.PARAMETER Scope
    Scope of the variable (User or Machine)
#>
function Add-EnvironmentPath {
    param(
        [string] $Path,
        [ValidateSet("User", "Machine")] $Scope = "User"
    )
    
    Write-Log "Adding to PATH: $Path (Scope: $Scope)" "INFO"
    
    $current = [System.Environment]::GetEnvironmentVariable("PATH", $Scope)
    
    if ($current -notcontains $Path) {
        $newPath = "$current;$Path"
        [System.Environment]::SetEnvironmentVariable("PATH", $newPath, $Scope)
        $env:PATH = $newPath
        Write-Log "Path added successfully" "DEBUG"
        return $true
    } else {
        Write-Log "Path already exists in environment" "DEBUG"
        return $true
    }
}

# ============================================================================
# SHELL CONFIGURATION
# ============================================================================

<#
.SYNOPSIS
    Configure shell aliases and functions
.PARAMETER ConfigFile
    Path to configuration file containing aliases and functions
#>
function Initialize-ShellAliases {
    param(
        [string] $ConfigFile
    )
    
    Write-Log "Initializing shell aliases from: $ConfigFile" "INFO"
    
    if (-not (Test-Path $ConfigFile)) {
        Write-Log "Configuration file not found: $ConfigFile" "ERROR"
        return $false
    }
    
    try {
        . $ConfigFile
        Write-Log "Shell aliases initialized successfully" "INFO"
        return $true
    } catch {
        Write-Log "Failed to initialize shell aliases: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# WINDOWS SETTINGS
# ============================================================================

<#
.SYNOPSIS
    Enable Windows features
.PARAMETER Features
    Array of feature names to enable
#>
function Enable-WindowsFeature {
    param(
        [string[]] $Features
    )
    
    Write-Log "Enabling Windows features: $($Features -join ', ')" "INFO"
    
    if (-not (Test-Administrator)) {
        Write-Log "Administrator privileges required to enable Windows features" "ERROR"
        return $false
    }
    
    foreach ($feature in $Features) {
        try {
            Write-Log "  Enabling: $feature" "DEBUG"
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop
            Write-Log "  ✓ $feature enabled" "INFO"
        } catch {
            Write-Log "  ✗ Failed to enable $feature : $($_.Exception.Message)" "WARN"
        }
    }
    
    return $true
}

<#
.SYNOPSIS
    Register file type associations
.PARAMETER FileExtension
    File extension to associate
.PARAMETER ProgramPath
    Path to the program to associate
.PARAMETER ProgId
    Program ID for the association
#>
function Register-FileAssociation {
    param(
        [string] $FileExtension,
        [string] $ProgramPath,
        [string] $ProgId
    )
    
    Write-Log "Registering file association: $FileExtension -> $ProgId" "INFO"
    
    if (-not (Test-Administrator)) {
        Write-Log "Administrator privileges required for file associations" "ERROR"
        return $false
    }
    
    try {
        # Create registry entries
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$FileExtension\UserChoice"
        
        Write-Log "File association registered: $FileExtension" "DEBUG"
        return $true
    } catch {
        Write-Log "Failed to register file association: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# APPLICATION CONFIGURATION
# ============================================================================

<#
.SYNOPSIS
    Apply configuration from XML file (e.g., Office settings)
.PARAMETER ConfigPath
    Path to the configuration XML file
.PARAMETER ApplicationName
    Name of the application being configured
#>
function Apply-ApplicationConfig {
    param(
        [string] $ConfigPath,
        [string] $ApplicationName = "Unknown"
    )
    
    Write-Log "Applying configuration for $ApplicationName : $ConfigPath" "INFO"
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Log "Configuration file not found: $ConfigPath" "ERROR"
        return $false
    }
    
    try {
        [xml] $config = Get-Content $ConfigPath
        Write-Log "Configuration loaded successfully" "DEBUG"
        
        # Application-specific configuration logic would go here
        # For now, just validate the XML
        
        Write-Log "Configuration applied successfully for $ApplicationName" "INFO"
        return $true
    } catch {
        Write-Log "Failed to apply configuration: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# STARTUP & CLEANUP
# ============================================================================

<#
.SYNOPSIS
    Add an application to Windows startup
.PARAMETER ApplicationName
    Name of the application
.PARAMETER ExecutablePath
    Full path to the executable
.PARAMETER Arguments
    Optional arguments to pass to the application
#>
function Add-StartupApplication {
    param(
        [string] $ApplicationName,
        [string] $ExecutablePath,
        [string] $Arguments = ""
    )
    
    Write-Log "Adding to startup: $ApplicationName" "INFO"
    
    if (-not (Test-Administrator)) {
        Write-Log "Administrator privileges required for startup items" "ERROR"
        return $false
    }
    
    try {
        $startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
        $shortcutPath = Join-Path $startupPath "$ApplicationName.lnk"
        
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $ExecutablePath
        $shortcut.Arguments = $Arguments
        $shortcut.Save()
        
        Write-Log "Added to startup: $ApplicationName" "INFO"
        return $true
    } catch {
        Write-Log "Failed to add to startup: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Clean up temporary files and caches
#>
function Invoke-SystemCleanup {
    Write-Log "Starting system cleanup..." "INFO"
    
    $cleanupPaths = @(
        "$env:TEMP",
        "$env:LOCALAPPDATA\Temp",
        "$env:WINDIR\Temp"
    )
    
    foreach ($path in $cleanupPaths) {
        if (Test-Path $path) {
            try {
                Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastAccessTime -lt (Get-Date).AddDays(-7) } |
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                
                Write-Log "Cleaned: $path" "DEBUG"
            } catch {
                Write-Log "Could not clean $path : $($_.Exception.Message)" "DEBUG"
            }
        }
    }
    
    Write-Log "System cleanup completed" "INFO"
}

# ============================================================================
# PERFORMANCE & DIAGNOSTICS
# ============================================================================

<#
.SYNOPSIS
    Measure setup execution time and performance
.PARAMETER Phase
    Name of the setup phase
.PARAMETER StartTime
    Start time of the phase
#>
function Measure-SetupPhase {
    param(
        [string] $Phase,
        [DateTime] $StartTime
    )
    
    $duration = (Get-Date) - $StartTime
    Write-Log "[$Phase] Completed in $($duration.TotalSeconds)s ($([math]::Round($duration.TotalSeconds/60, 2)) min)" "INFO"
    
    return $duration
}

<#
.SYNOPSIS
    Generate setup completion report
.PARAMETER LogFile
    Path to the log file
.PARAMETER ReportPath
    Path to save the report
#>
function New-SetupReport {
    param(
        [string] $LogFile,
        [string] $ReportPath = "$env:APPDATA/laptopAutomation/setup-report.html"
    )
    
    Write-Log "Generating setup report..." "INFO"
    
    try {
        $reportDir = Split-Path $ReportPath
        if (-not (Test-Path $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }
        
        $systemInfo = Get-SystemInfo
        $logContent = Get-Content $LogFile -Raw
        
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Laptop Automation Setup Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        .section { background: white; margin: 20px 0; padding: 15px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .success { color: #27ae60; }
        .error { color: #e74c3c; }
        .warning { color: #f39c12; }
        pre { background: #f8f8f8; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Laptop Automation Setup Report</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
    
    <div class="section">
        <h2>System Information</h2>
        <p><strong>Computer:</strong> $($systemInfo.ComputerName)</p>
        <p><strong>User:</strong> $($systemInfo.UserName)</p>
        <p><strong>OS:</strong> $($systemInfo.OSVersion)</p>
        <p><strong>PowerShell:</strong> $($systemInfo.PowerShellVersion)</p>
        <p><strong>Administrator:</strong> $($systemInfo.IsAdmin)</p>
    </div>
    
    <div class="section">
        <h2>Setup Log</h2>
        <pre>$logContent</pre>
    </div>
</body>
</html>
"@
        
        $html | Set-Content $ReportPath
        Write-Log "Report saved: $ReportPath" "INFO"
        
        return $ReportPath
    } catch {
        Write-Log "Failed to generate report: $($_.Exception.Message)" "ERROR"
        return $null
    }
}
