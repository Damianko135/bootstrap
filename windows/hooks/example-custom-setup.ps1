#!/usr/bin/env pwsh
# example-custom-setup.ps1
# This is an example hook file showing how to extend the setup
# Copy and rename this file to customize your setup
# The hook system will automatically load all *.ps1 files in the hooks directory

Write-Log "Custom setup hook loaded" "INFO"

# ============================================================================
# EXAMPLE 1: Custom pre-setup hook
# ============================================================================
Register-Hook -HookName "PreSetup" -ScriptBlock {
    param($Profile)
    Write-Log "Custom pre-setup hook executing for profile: $Profile" "INFO"
    # Add your custom pre-setup logic here
    # Examples:
    # - Check for third-party software
    # - Validate custom requirements
    # - Set up custom variables
} -Priority 10

# ============================================================================
# EXAMPLE 2: Custom post-setup hook
# ============================================================================
Register-Hook -HookName "PostSetup" -ScriptBlock {
    param($Profile)
    Write-Log "Custom post-setup hook executing for profile: $Profile" "INFO"
    # Add your custom post-setup logic here
    # Examples:
    # - Configure third-party tools
    # - Download custom files
    # - Apply custom settings
} -Priority 90

# ============================================================================
# EXAMPLE 3: Custom pre-package installation
# ============================================================================
Register-Hook -HookName "PrePackageInstall" -ScriptBlock {
    param($Packages, $Profile)
    Write-Log "Installing $($Packages.Count) packages from profile: $Profile" "INFO"
    # Add custom pre-installation logic here
    # Examples:
    # - Warn about incompatibilities
    # - Prepare custom repositories
} -Priority 50

# ============================================================================
# EXAMPLE 4: Custom function that can be called
# ============================================================================
function Install-CustomApplications {
    <#
    .SYNOPSIS
        Install custom applications not in the standard package list
    #>
    param(
        [string[]] $Applications = @("CustomApp1", "CustomApp2")
    )
    
    Write-Log "Installing custom applications: $($Applications -join ', ')" "INFO"
    
    foreach ($app in $Applications) {
        Write-Log "Custom installation logic for: $app" "INFO"
        # Add your custom installation logic here
    }
}

# ============================================================================
# EXAMPLE 5: Custom environment configuration
# ============================================================================
function Configure-CustomEnvironment {
    Write-Log "Configuring custom environment variables..." "INFO"
    
    # Example: Set custom environment variable
    # [System.Environment]::SetEnvironmentVariable("MY_CUSTOM_VAR", "value", "User")
    
    # Example: Add custom path
    # Add-EnvironmentPath -Path "C:\MyCustomTools" -Scope "User"
    
    Write-Log "Custom environment configuration complete" "INFO"
}

# ============================================================================
# EXAMPLE 6: Custom PowerShell profile additions
# ============================================================================
function Add-CustomProfileConfig {
    Write-Log "Adding custom PowerShell profile configuration..." "INFO"
    
    $customConfig = @"
    
# Custom Configuration Added by Hook
# Add your custom aliases, functions, and profile settings here

# Example: Custom alias
# Set-Alias -Name ll -Value Get-ChildItem -Force

# Example: Custom function
# function Test-MyFunction {
#     Write-Host "This is a custom function"
# }

"@
    
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        Add-Content -Path $profilePath -Value $customConfig -Force
        Write-Log "Custom profile configuration added" "INFO"
    }
}

Write-Log "Custom setup hook initialized with example hooks" "DEBUG"
