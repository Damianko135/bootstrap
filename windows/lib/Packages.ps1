#!/usr/bin/env pwsh
# Packages.ps1 - Package installation management with parallel execution
# Handles installation via multiple package managers with validation

Set-StrictMode -Version Latest

# ============================================================================
# PACKAGE INSTALLATION
# ============================================================================

<#
.SYNOPSIS
    Install a package using the specified or best available package manager
.PARAMETER PackageName
    Name of the package to install
.PARAMETER WingetId
    Winget package identifier
.PARAMETER ChocoId
    Chocolatey package identifier
.PARAMETER PackageManager
    Force specific package manager (winget, choco)
#>
function Install-Package {
    param(
        [string] $PackageName,
        [string] $WingetId,
        [string] $ChocoId,
        [string] $PackageManager = $null,
        [string] $ValidateCommand = $null,
        [int] $TimeoutSeconds = 300
    )
    
    Write-Log "Installing package: $PackageName" "INFO"
    
    # Determine which package manager to use
    $manager = $PackageManager
    if (-not $manager) {
        if (Test-CommandExists "winget") {
            $manager = "winget"
        } elseif (Test-CommandExists "choco") {
            $manager = "choco"
        } else {
            Write-Log "No suitable package manager found for $PackageName" "ERROR"
            return $false
        }
    }
    
    try {
        $startTime = Get-Date
        
        switch ($manager) {
            "winget" {
                if (-not $WingetId) {
                    Write-Log "Winget ID not available for $PackageName, trying Chocolatey..." "WARN"
                    return Install-Package -PackageName $PackageName -ChocoId $ChocoId -PackageManager "choco"
                }
                
                Write-Log "  Using winget: $WingetId" "DEBUG"
                winget install -e --id $WingetId --accept-source-agreements --accept-package-agreements -q
            }
            "choco" {
                if (-not $ChocoId) {
                    Write-Log "Chocolatey ID not available for $PackageName, trying winget..." "WARN"
                    return Install-Package -PackageName $PackageName -WingetId $WingetId -PackageManager "winget"
                }
                
                Write-Log "  Using choco: $ChocoId" "DEBUG"
                choco install $ChocoId -y -q
            }
            default {
                Write-Log "Unknown package manager: $manager" "ERROR"
                return $false
            }
        }
        
        $duration = (Get-Date) - $startTime
        Write-Log "Installation of $PackageName completed in $($duration.TotalSeconds)s" "INFO"
        
        # Validate installation if command provided
        if ($ValidateCommand) {
            Start-Sleep -Seconds 2  # Give time for PATH to update
            
            if (Test-CommandExists $ValidateCommand) {
                Write-Log "  ✓ Validation passed for $PackageName" "INFO"
                return $true
            } else {
                Write-Log "  ✗ Validation failed for $PackageName - command '$ValidateCommand' not found" "WARN"
            }
        }
        
        return $true
    } catch {
        Write-Log "Installation of $PackageName failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Install multiple packages in parallel for faster execution
.PARAMETER Packages
    Array of package objects with Name, WingetId, ChocoId properties
.PARAMETER MaxParallel
    Maximum number of parallel installations (default: 3)
#>
function Install-PackagesBatch {
    param(
        [Object[]] $Packages,
        [int] $MaxParallel = 3
    )
    
    Write-Log "Installing $($Packages.Count) packages (max parallel: $MaxParallel)" "INFO"
    
    $jobs = @()
    $results = @{}
    
    # Start parallel jobs
    foreach ($package in $Packages) {
        # Wait if we've hit the parallel limit
        while ((Get-Job -State Running).Count -ge $MaxParallel) {
            Start-Sleep -Milliseconds 500
        }
        
        $job = Start-Job -ScriptBlock {
            param($pkg)
            # Re-source the logging functions in the job context
            $package = $pkg
            
            try {
                $output = ""
                $success = $true
                
                # Attempt installation
                & winget install -e --id $package.WingetId --accept-source-agreements -q 2>&1 | Out-Null
                
                return @{
                    Package = $package.Name
                    Success = $success
                    Message = "Installation completed"
                }
            } catch {
                return @{
                    Package = $package.Name
                    Success = $false
                    Message = "Installation failed: $($_.Exception.Message)"
                }
            }
        } -ArgumentList $package
        
        $jobs += @{
            Job = $job
            Package = $package.Name
        }
    }
    
    # Wait for all jobs to complete and collect results
    $successCount = 0
    $failureCount = 0
    
    foreach ($jobInfo in $jobs) {
        $result = Receive-Job -Job $jobInfo.Job -Wait
        
        if ($result.Success) {
            Write-Log "✓ $($jobInfo.Package) - $($result.Message)" "INFO"
            $successCount++
        } else {
            Write-Log "✗ $($jobInfo.Package) - $($result.Message)" "ERROR"
            $failureCount++
        }
        
        Remove-Job -Job $jobInfo.Job
    }
    
    Write-Log "Batch installation summary: $successCount successful, $failureCount failed" "INFO"
    
    return @{
        Successful = $successCount
        Failed = $failureCount
        Total = $Packages.Count
    }
}

<#
.SYNOPSIS
    Load packages from JSON file and filter by profile
.PARAMETER JsonPath
    Path to the packages JSON file
.PARAMETER Profile
    Installation profile (minimal, standard, complete, gaming, custom)
.PARAMETER Exclude
    Array of package names to exclude
#>
function Get-PackageList {
    param(
        [string] $JsonPath,
        [string] $Profile = "standard",
        [string[]] $Exclude = @()
    )
    
    Write-Log "Loading package list from: $JsonPath (Profile: $Profile)" "INFO"
    
    $packages = Get-JsonContent $JsonPath
    
    if (-not $packages) {
        Write-Log "Failed to load packages from $JsonPath" "ERROR"
        return @()
    }
    
    # Filter based on profile
    $filtered = $packages | Where-Object {
        $_.Profile -eq $Profile -or $_.Profile -eq "all" -or -not $_.Profile
    }
    
    # Apply exclusions
    if ($Exclude.Count -gt 0) {
        $filtered = $filtered | Where-Object { $_.Name -notin $Exclude }
    }
    
    Write-Log "Loaded $($filtered.Count) packages for profile '$Profile'" "INFO"
    
    return $filtered
}

<#
.SYNOPSIS
    Verify that installed packages are functional
.PARAMETER Packages
    Array of package objects to verify
#>
function Verify-Installations {
    param(
        [Object[]] $Packages
    )
    
    Write-Log "Verifying installations..." "INFO"
    
    $successCount = 0
    $failureCount = 0
    
    foreach ($package in $Packages) {
        if ($package.command) {
            if (Test-CommandExists $package.command) {
                Write-Log "  ✓ $($package.Name) verified" "INFO"
                $successCount++
            } else {
                Write-Log "  ✗ $($package.Name) - command '$($package.command)' not found" "WARN"
                $failureCount++
            }
        }
    }
    
    Write-Log "Verification complete: $successCount passed, $failureCount failed" "INFO"
    
    return @{
        Passed = $successCount
        Failed = $failureCount
    }
}

<#
.SYNOPSIS
    Get installation status of a package
.PARAMETER PackageName
    Name of the package to check
#>
function Get-PackageStatus {
    param(
        [string] $PackageName
    )
    
    # Check via winget
    if (Test-CommandExists "winget") {
        try {
            $output = winget list --accept-source-agreements 2>$null | Select-String $PackageName
            if ($output) {
                return @{
                    Installed = $true
                    Manager = "winget"
                    Details = $output
                }
            }
        } catch {
            Write-Log "Could not query winget for $PackageName" "DEBUG"
        }
    }
    
    # Check via choco
    if (Test-CommandExists "choco") {
        try {
            $output = choco list $PackageName 2>$null | Select-String $PackageName
            if ($output) {
                return @{
                    Installed = $true
                    Manager = "choco"
                    Details = $output
                }
            }
        } catch {
            Write-Log "Could not query choco for $PackageName" "DEBUG"
        }
    }
    
    return @{
        Installed = $false
        Manager = $null
        Details = $null
    }
}

<#
.SYNOPSIS
    Uninstall a package
.PARAMETER PackageName
    Name of the package to uninstall
#>
function Uninstall-Package {
    param(
        [string] $PackageName
    )
    
    Write-Log "Uninstalling package: $PackageName" "INFO"
    
    try {
        if (Test-CommandExists "winget") {
            winget uninstall -e --name $PackageName -q 2>$null
        } elseif (Test-CommandExists "choco") {
            choco uninstall $PackageName -y -q 2>$null
        } else {
            Write-Log "No package manager available for uninstall" "ERROR"
            return $false
        }
        
        Write-Log "Uninstalled: $PackageName" "INFO"
        return $true
    } catch {
        Write-Log "Failed to uninstall $PackageName : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# DEPENDENCY RESOLUTION
# ============================================================================

<#
.SYNOPSIS
    Build a dependency graph from package list
.PARAMETER Packages
    Array of package objects
#>
function Build-DependencyGraph {
    param([Object[]] $Packages)
    
    Write-Log "Building dependency graph..." "INFO"
    
    $graph = @{}
    
    foreach ($package in $Packages) {
        $graph[$package.Name] = @{
            Package = $package
            Dependencies = $package.Dependencies -split "," | Where-Object { $_ } | ForEach-Object { $_.Trim() }
            Conflicts = $package.Conflicts -split "," | Where-Object { $_ } | ForEach-Object { $_.Trim() }
        }
    }
    
    Write-Log "Dependency graph built with $($graph.Count) packages" "DEBUG"
    return $graph
}

<#
.SYNOPSIS
    Resolve dependencies for a package
.PARAMETER PackageName
    Name of the package to resolve
.PARAMETER Graph
    Dependency graph from Build-DependencyGraph
.PARAMETER Resolved
    Internal parameter for recursion tracking
#>
function Resolve-PackageDependencies {
    param(
        [string] $PackageName,
        [hashtable] $Graph,
        [System.Collections.Generic.HashSet[string]] $Resolved = $null
    )
    
    if ($null -eq $Resolved) {
        $Resolved = New-Object System.Collections.Generic.HashSet[string]
    }
    
    if ($Resolved.Contains($PackageName)) {
        return $Resolved
    }
    
    if (-not $Graph[$PackageName]) {
        Write-Log "Package not found in graph: $PackageName" "WARN"
        return $Resolved
    }
    
    $Resolved.Add($PackageName) | Out-Null
    
    foreach ($dependency in $Graph[$PackageName].Dependencies) {
        if ($Graph[$dependency]) {
            Resolve-PackageDependencies -PackageName $dependency -Graph $Graph -Resolved $Resolved
        } else {
            Write-Log "Dependency not found: $dependency (required by $PackageName)" "WARN"
        }
    }
    
    return $Resolved
}

<#
.SYNOPSIS
    Detect conflicts between selected packages
.PARAMETER Packages
    Array of package objects to check
.PARAMETER Graph
    Dependency graph from Build-DependencyGraph
#>
function Detect-PackageConflicts {
    param(
        [Object[]] $Packages,
        [hashtable] $Graph = $null
    )
    
    Write-Log "Detecting package conflicts..." "INFO"
    
    if (-not $Graph) {
        $Graph = Build-DependencyGraph $Packages
    }
    
    $conflicts = @()
    $packageNames = $Packages | Select-Object -ExpandProperty Name
    
    foreach ($package in $Packages) {
        if (-not $Graph[$package.Name]) {
            continue
        }
        
        foreach ($conflict in $Graph[$package.Name].Conflicts) {
            if ($packageNames -contains $conflict) {
                $conflicts += @{
                    Package1 = $package.Name
                    Package2 = $conflict
                    Severity = "ERROR"
                }
                Write-Log "✗ Conflict detected: $($package.Name) conflicts with $conflict" "ERROR"
            }
        }
    }
    
    if ($conflicts.Count -eq 0) {
        Write-Log "No package conflicts detected" "INFO"
    } else {
        Write-Log "$($conflicts.Count) conflict(s) detected" "WARN"
    }
    
    return $conflicts
}

<#
.SYNOPSIS
    Order packages for installation based on dependencies
.PARAMETER Packages
    Array of package objects
.PARAMETER Graph
    Dependency graph from Build-DependencyGraph
#>
function Sort-PackagesByDependencies {
    param(
        [Object[]] $Packages,
        [hashtable] $Graph = $null
    )
    
    Write-Log "Sorting packages by dependencies..." "INFO"
    
    if (-not $Graph) {
        $Graph = Build-DependencyGraph $Packages
    }
    
    $sorted = @()
    $processed = New-Object System.Collections.Generic.HashSet[string]
    
    function Add-PackageWithDependencies {
        param([string] $PackageName)
        
        if ($processed.Contains($PackageName)) {
            return
        }
        
        if ($Graph[$PackageName]) {
            foreach ($dep in $Graph[$PackageName].Dependencies) {
                Add-PackageWithDependencies $dep
            }
        }
        
        $pkg = $Packages | Where-Object { $_.Name -eq $PackageName } | Select-Object -First 1
        if ($pkg) {
            $sorted += $pkg
            $processed.Add($PackageName) | Out-Null
        }
    }
    
    foreach ($package in $Packages) {
        Add-PackageWithDependencies $package.Name
    }
    
    Write-Log "Packages sorted by dependencies" "DEBUG"
    return $sorted
}

# ============================================================================
# DRY-RUN & PREVIEW MODE
# ============================================================================

<#
.SYNOPSIS
    Preview what will be installed without actually installing
.PARAMETER Packages
    Array of package objects to preview
.PARAMETER Profile
    Installation profile name
#>
function Get-InstallationPreview {
    param(
        [Object[]] $Packages,
        [string] $Profile = "standard"
    )
    
    Write-Log "Generating installation preview for profile: $Profile" "INFO"
    
    $graph = Build-DependencyGraph $Packages
    $conflicts = Detect-PackageConflicts $Packages $graph
    $sorted = Sort-PackagesByDependencies $Packages $graph
    
    $preview = @{
        Profile = $Profile
        TotalPackages = $Packages.Count
        PackageList = $sorted | Select-Object @{Name="Name"; Expression={$_.Name}}, @{Name="Manager"; Expression={if ($_.WingetId) {"winget"} else {"choco"}}}, @{Name="Category"; Expression={$_.Category}}
        Dependencies = @()
        Conflicts = $conflicts
        ConflictCount = $conflicts.Count
        EstimatedInstallTime = $sorted.Count * 30  # Rough estimate: 30s per package
    }
    
    # Build dependency summary
    foreach ($package in $sorted) {
        if ($graph[$package.Name].Dependencies.Count -gt 0) {
            $preview.Dependencies += @{
                Package = $package.Name
                DependsOn = $graph[$package.Name].Dependencies
            }
        }
    }
    
    return $preview
}

<#
.SYNOPSIS
    Display installation preview in human-readable format
#>
function Show-InstallationPreview {
    param([hashtable] $Preview)
    
    Write-Host "`nInstallation Preview" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host "Profile: $($Preview.Profile)" -ForegroundColor Yellow
    Write-Host "Total packages: $($Preview.TotalPackages)" -ForegroundColor White
    Write-Host "Estimated time: $(($Preview.EstimatedInstallTime / 60) | [math]::Round) minutes" -ForegroundColor White
    
    if ($Preview.ConflictCount -gt 0) {
        Write-Host "`n⚠ WARNING: $($Preview.ConflictCount) conflict(s) detected!" -ForegroundColor Red
        foreach ($conflict in $Preview.Conflicts) {
            Write-Host "  - $($conflict.Package1) conflicts with $($conflict.Package2)" -ForegroundColor Red
        }
    }
    
    Write-Host "`nPackages to install (in order):" -ForegroundColor Yellow
    $Preview.PackageList | ForEach-Object { 
        Write-Host "  $($_.Name) [$($_.Manager)] ($($_.Category))" -ForegroundColor White
    }
    
    if ($Preview.Dependencies.Count -gt 0) {
        Write-Host "`nDependency graph:" -ForegroundColor Yellow
        foreach ($dep in $Preview.Dependencies) {
            Write-Host "  $($dep.Package) depends on: $($dep.DependsOn -join ', ')" -ForegroundColor Gray
        }
    }
    
    Write-Host "`n" -ForegroundColor White
}

