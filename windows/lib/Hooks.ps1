#!/usr/bin/env pwsh
# Hooks.ps1 - Plugin/hook system for custom setup scripts
# Allows extending setup with user-defined pre/post-installation hooks

Set-StrictMode -Version Latest

# ============================================================================
# HOOK SYSTEM
# ============================================================================

$script:HookConfig = @{
    Directory = $null
    Hooks = @{
        PreSetup = @()
        PostSetup = @()
        PrePackageInstall = @()
        PostPackageInstall = @()
        PreValidation = @()
        PostValidation = @()
    }
}

<#
.SYNOPSIS
    Initialize the hook system
.PARAMETER HookDirectory
    Directory to search for hook files
#>
function Initialize-HookSystem {
    param(
        [string] $HookDirectory = "$PSScriptRoot\..\hooks"
    )
    
    $script:HookConfig.Directory = $HookDirectory
    
    if (-not (Test-Path $HookDirectory)) {
        Write-Log "Hook directory not found: $HookDirectory (hooks are optional)" "DEBUG"
        return
    }
    
    Write-Log "Initializing hook system from: $HookDirectory" "DEBUG"
    
    # Load all hook files
    $hookFiles = Get-ChildItem $HookDirectory -Filter "*.ps1" -ErrorAction SilentlyContinue
    
    foreach ($hookFile in $hookFiles) {
        try {
            . $hookFile.FullName
            Write-Log "Loaded hook file: $($hookFile.Name)" "DEBUG"
        } catch {
            Write-Log "Failed to load hook file $($hookFile.Name): $($_.Exception.Message)" "WARN"
        }
    }
}

<#
.SYNOPSIS
    Register a hook function
.PARAMETER HookName
    Name of the hook (PreSetup, PostSetup, PrePackageInstall, PostPackageInstall, etc.)
.PARAMETER ScriptBlock
    ScriptBlock or function name to execute
.PARAMETER Priority
    Execution priority (lower = earlier)
#>
function Register-Hook {
    param(
        [ValidateSet("PreSetup", "PostSetup", "PrePackageInstall", "PostPackageInstall", "PreValidation", "PostValidation")] [string] $HookName,
        [ScriptBlock] $ScriptBlock,
        [int] $Priority = 100
    )
    
    if (-not $script:HookConfig.Hooks[$HookName]) {
        Write-Log "Invalid hook name: $HookName" "ERROR"
        return $false
    }
    
    $script:HookConfig.Hooks[$HookName] += @{
        ScriptBlock = $ScriptBlock
        Priority = $Priority
        RegisteredAt = Get-Date
    }
    
    Write-Log "Hook registered: $HookName (Priority: $Priority)" "DEBUG"
    return $true
}

<#
.SYNOPSIS
    Execute all registered hooks for a specific point
.PARAMETER HookName
    Name of the hook point to execute
.PARAMETER Parameters
    Hashtable of parameters to pass to hooks
#>
function Invoke-Hooks {
    param(
        [ValidateSet("PreSetup", "PostSetup", "PrePackageInstall", "PostPackageInstall", "PreValidation", "PostValidation")] [string] $HookName,
        [hashtable] $Parameters = @{}
    )
    
    if (-not $script:HookConfig.Hooks[$HookName]) {
        Write-Log "Invalid hook name: $HookName" "ERROR"
        return $false
    }
    
    $hooks = $script:HookConfig.Hooks[$HookName] | Sort-Object -Property Priority
    
    if ($hooks.Count -eq 0) {
        Write-Log "No hooks registered for: $HookName" "DEBUG"
        return $true
    }
    
    Write-Log "Executing $($hooks.Count) hook(s) for: $HookName" "INFO"
    
    $allSuccess = $true
    
    foreach ($hook in $hooks) {
        try {
            Write-Log "  Executing hook (priority: $($hook.Priority))..." "DEBUG"
            
            $result = & $hook.ScriptBlock @Parameters
            
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
                Write-Log "  ⚠ Hook exited with code: $LASTEXITCODE" "WARN"
                $allSuccess = $false
            } else {
                Write-Log "  ✓ Hook execution successful" "DEBUG"
            }
        } catch {
            Write-Log "  ✗ Hook execution failed: $($_.Exception.Message)" "ERROR"
            $allSuccess = $false
        }
    }
    
    return $allSuccess
}

<#
.SYNOPSIS
    Get list of registered hooks
#>
function Get-RegisteredHooks {
    param([string] $HookName = $null)
    
    if ($HookName) {
        if ($script:HookConfig.Hooks[$HookName]) {
            return $script:HookConfig.Hooks[$HookName]
        }
        return @()
    }
    
    return $script:HookConfig.Hooks
}

<#
.SYNOPSIS
    Clear all hooks (useful for testing)
#>
function Clear-AllHooks {
    $script:HookConfig.Hooks = @{
        PreSetup = @()
        PostSetup = @()
        PrePackageInstall = @()
        PostPackageInstall = @()
        PreValidation = @()
        PostValidation = @()
    }
    
    Write-Log "All hooks cleared" "DEBUG"
}

# ============================================================================
# HOOK HELPERS
# ============================================================================

<#
.SYNOPSIS
    Helper to execute a custom script file as a hook
#>
function Invoke-HookScript {
    param(
        [string] $ScriptPath,
        [hashtable] $Parameters = @{}
    )
    
    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Hook script not found: $ScriptPath" "ERROR"
        return $false
    }
    
    try {
        Write-Log "Executing hook script: $ScriptPath" "INFO"
        & $ScriptPath @Parameters
        return $true
    } catch {
        Write-Log "Hook script execution failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Helper to execute a PowerShell command as a hook
#>
function Invoke-HookCommand {
    param(
        [string] $Command,
        [hashtable] $Parameters = @{}
    )
    
    try {
        Write-Log "Executing hook command: $Command" "INFO"
        Invoke-Expression $Command
        return $true
    } catch {
        Write-Log "Hook command execution failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Create a hook template for users
#>
function New-HookTemplate {
    param(
        [string] $TemplateName = "custom-setup",
        [string] $OutputPath = $null
    )
    
    if (-not $OutputPath) {
        $OutputPath = "$($script:HookConfig.Directory)\$TemplateName.ps1"
    }
    
    $template = @'
#!/usr/bin/env pwsh
# Custom Setup Hook
# This file is automatically loaded by the hook system
# Add your custom setup logic here

# Example: Register hooks
# Register-Hook -HookName "PostSetup" -ScriptBlock {
#     Write-Log "Running custom post-setup hook" "INFO"
#     # Your custom logic here
# } -Priority 50

# Example: Install additional packages
function Invoke-CustomPackageInstallation {
    param(
        [array] $ExtraPackages
    )
    
    Write-Log "Installing custom packages..." "INFO"
    foreach ($package in $ExtraPackages) {
        Write-Log "Installing: $($package.Name)" "INFO"
        # Your installation logic
    }
}

# Example: Configure custom environment
function Configure-CustomEnvironment {
    Write-Log "Configuring custom environment..." "INFO"
    
    # Set custom environment variables
    # [System.Environment]::SetEnvironmentVariable("CUSTOM_VAR", "value", "User")
    
    # Modify PowerShell profile
    # Add-Content -Path $PROFILE -Value "# Custom configuration"
}

Write-Log "Custom setup hook loaded" "INFO"
'@
    
    try {
        $template | Set-Content $OutputPath -Force
        Write-Log "Hook template created: $OutputPath" "INFO"
        return $OutputPath
    } catch {
        Write-Log "Failed to create hook template: $($_.Exception.Message)" "ERROR"
        return $null
    }
}
