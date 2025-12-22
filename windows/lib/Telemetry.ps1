#!/usr/bin/env pwsh
# Telemetry.ps1 - Health monitoring, metrics collection, and reporting
# Tracks installation success rates, performance, and system health

Set-StrictMode -Version Latest

# ============================================================================
# METRICS TRACKING
# ============================================================================

$script:Metrics = @{
    StartTime = $null
    EndTime = $null
    Phase = @{}
    Packages = @{
        Total = 0
        Successful = 0
        Failed = 0
        Skipped = 0
    }
    Errors = @()
    Warnings = @()
}

<#
.SYNOPSIS
    Initialize metrics collection
#>
function Initialize-Metrics {
    $script:Metrics.StartTime = Get-Date
    $script:Metrics.Phase = @{}
    $script:Metrics.Packages = @{
        Total = 0
        Successful = 0
        Failed = 0
        Skipped = 0
    }
    $script:Metrics.Errors = @()
    $script:Metrics.Warnings = @()
    
    Write-Log "Metrics collection initialized" "DEBUG"
}

<#
.SYNOPSIS
    Record the start of a phase
#>
function Start-MetricsPhase {
    param([string] $PhaseName)
    
    $script:Metrics.Phase[$PhaseName] = @{
        StartTime = Get-Date
        EndTime = $null
        Duration = $null
        Status = "IN_PROGRESS"
    }
    
    Write-Log "Phase metrics started: $PhaseName" "DEBUG"
}

<#
.SYNOPSIS
    Record the completion of a phase
#>
function Complete-MetricsPhase {
    param(
        [string] $PhaseName,
        [string] $Status = "SUCCESS"
    )
    
    if (-not $script:Metrics.Phase[$PhaseName]) {
        Write-Log "Phase metrics not found for: $PhaseName" "WARN"
        return
    }
    
    $script:Metrics.Phase[$PhaseName].EndTime = Get-Date
    $script:Metrics.Phase[$PhaseName].Duration = $script:Metrics.Phase[$PhaseName].EndTime - $script:Metrics.Phase[$PhaseName].StartTime
    $script:Metrics.Phase[$PhaseName].Status = $Status
    
    Write-Log "Phase metrics completed: $PhaseName ($(($script:Metrics.Phase[$PhaseName].Duration).TotalSeconds)s)" "DEBUG"
}

<#
.SYNOPSIS
    Record package installation metrics
#>
function Record-PackageMetric {
    param(
        [string] $PackageName,
        [ValidateSet("SUCCESS", "FAILED", "SKIPPED")] $Status,
        [string] $Message = ""
    )
    
    $script:Metrics.Packages.Total++
    
    switch ($Status) {
        "SUCCESS" { $script:Metrics.Packages.Successful++ }
        "FAILED" { $script:Metrics.Packages.Failed++ }
        "SKIPPED" { $script:Metrics.Packages.Skipped++ }
    }
    
    if ($Status -eq "FAILED") {
        $script:Metrics.Errors += @{
            Package = $PackageName
            Message = $Message
            Timestamp = Get-Date
        }
    }
}

<#
.SYNOPSIS
    Record a warning during setup
#>
function Record-Warning {
    param([string] $Message)
    
    $script:Metrics.Warnings += @{
        Message = $Message
        Timestamp = Get-Date
    }
}

# ============================================================================
# HEALTH MONITORING
# ============================================================================

<#
.SYNOPSIS
    Perform system health check and return status
#>
function Get-SystemHealth {
    Write-Log "Performing system health check..." "INFO"
    
    $health = @{
        Timestamp = Get-Date
        HealthStatus = "HEALTHY"
        Issues = @()
        Details = @{}
    }
    
    # Check disk space
    try {
        $drive = Get-Item "C:\"
        $freeSpaceGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 2)
        $health.Details.DiskSpaceGB = $freeSpaceGB
        
        if ($freeSpaceGB -lt 10) {
            $health.HealthStatus = "WARNING"
            $health.Issues += "Low disk space: ${freeSpaceGB}GB"
        }
    } catch {
        $health.Issues += "Failed to check disk space: $($_.Exception.Message)"
    }
    
    # Check system resources
    try {
        $cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples[0].CookedValue
        $health.Details.CPUUsagePercent = [math]::Round($cpuUsage, 2)
    } catch {
        Write-Log "Could not retrieve CPU metrics" "DEBUG"
    }
    
    try {
        $memory = Get-CimInstance -ClassName CIM_OperatingSystem
        $usedMemory = $memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory
        $memoryPercent = [math]::Round(($usedMemory / $memory.TotalVisibleMemorySize) * 100, 2)
        $health.Details.MemoryUsagePercent = $memoryPercent
        
        if ($memoryPercent -gt 90) {
            $health.HealthStatus = "WARNING"
            $health.Issues += "High memory usage: ${memoryPercent}%"
        }
    } catch {
        Write-Log "Could not retrieve memory metrics" "DEBUG"
    }
    
    # Check internet connectivity
    try {
        $connected = Test-InternetConnection
        $health.Details.InternetConnected = $connected
        
        if (-not $connected) {
            $health.HealthStatus = "WARNING"
            $health.Issues += "Internet connectivity lost"
        }
    } catch {
        Write-Log "Could not check internet connectivity" "DEBUG"
    }
    
    return $health
}

# ============================================================================
# REPORTING
# ============================================================================

<#
.SYNOPSIS
    Generate a comprehensive setup report
#>
function Get-SetupReport {
    param(
        [string] $ReportPath = $null
    )
    
    $script:Metrics.EndTime = Get-Date
    $totalDuration = $script:Metrics.EndTime - $script:Metrics.StartTime
    
    $report = @{
        GeneratedAt = Get-Date
        ExecutionDuration = $totalDuration.TotalSeconds
        DurationFormatted = "{0:hh\:mm\:ss}" -f $totalDuration
        Phases = $script:Metrics.Phase
        Packages = $script:Metrics.Packages
        PackageSuccessRate = if ($script:Metrics.Packages.Total -gt 0) { 
            [math]::Round(($script:Metrics.Packages.Successful / $script:Metrics.Packages.Total) * 100, 2) 
        } else { 
            0 
        }
        Errors = $script:Metrics.Errors
        ErrorCount = $script:Metrics.Errors.Count
        Warnings = $script:Metrics.Warnings
        WarningCount = $script:Metrics.Warnings.Count
        SystemHealth = Get-SystemHealth
    }
    
    if ($ReportPath) {
        try {
            $reportDir = Split-Path $ReportPath
            if (-not (Test-Path $reportDir)) {
                New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
            }
            
            $report | ConvertTo-Json -Depth 10 | Set-Content $ReportPath
            Write-Log "Report saved to: $ReportPath" "INFO"
        } catch {
            Write-Log "Failed to save report: $($_.Exception.Message)" "WARN"
        }
    }
    
    return $report
}

<#
.SYNOPSIS
    Display a formatted summary of the setup
#>
function Show-SetupSummary {
    param([hashtable] $Report)
    
    Write-Host "`n" -NoNewline
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "                      SETUP COMPLETION REPORT                          " -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    
    Write-Host "`nExecution Summary:" -ForegroundColor Yellow
    Write-Host "  Total Duration: $($Report.DurationFormatted)" -ForegroundColor White
    Write-Host "  Started:        $($Report.GeneratedAt.AddSeconds(-$Report.ExecutionDuration) | Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
    Write-Host "  Completed:      $($Report.GeneratedAt | Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
    
    Write-Host "`nPhase Results:" -ForegroundColor Yellow
    foreach ($phase in $Report.Phases.GetEnumerator()) {
        $statusColor = if ($phase.Value.Status -eq "SUCCESS") { "Green" } else { "Red" }
        Write-Host "  $($phase.Key): $($phase.Value.Status) ($(($phase.Value.Duration).TotalSeconds)s)" -ForegroundColor $statusColor
    }
    
    Write-Host "`nPackage Installation Results:" -ForegroundColor Yellow
    Write-Host "  Total:      $($Report.Packages.Total)" -ForegroundColor White
    Write-Host "  Successful: $($Report.Packages.Successful)" -ForegroundColor Green
    Write-Host "  Failed:     $($Report.Packages.Failed)" -ForegroundColor $(if ($Report.Packages.Failed -gt 0) { "Red" } else { "Green" })
    Write-Host "  Skipped:    $($Report.Packages.Skipped)" -ForegroundColor Gray
    Write-Host "  Success Rate: $($Report.PackageSuccessRate)%" -ForegroundColor White
    
    if ($Report.ErrorCount -gt 0) {
        Write-Host "`nErrors ($($Report.ErrorCount)):" -ForegroundColor Red
        foreach ($error in $Report.Errors | Select-Object -First 5) {
            Write-Host "  ✗ $($error.Package): $($error.Message)" -ForegroundColor Red
        }
        if ($Report.ErrorCount -gt 5) {
            Write-Host "  ... and $($Report.ErrorCount - 5) more errors" -ForegroundColor Red
        }
    }
    
    if ($Report.WarningCount -gt 0) {
        Write-Host "`nWarnings ($($Report.WarningCount)):" -ForegroundColor Yellow
        foreach ($warning in $Report.Warnings | Select-Object -First 5) {
            Write-Host "  ⚠ $($warning.Message)" -ForegroundColor Yellow
        }
        if ($Report.WarningCount -gt 5) {
            Write-Host "  ... and $($Report.WarningCount - 5) more warnings" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nSystem Health:" -ForegroundColor Yellow
    $healthColor = switch ($Report.SystemHealth.HealthStatus) {
        "HEALTHY" { "Green" }
        "WARNING" { "Yellow" }
        "CRITICAL" { "Red" }
        default { "White" }
    }
    Write-Host "  Status: $($Report.SystemHealth.HealthStatus)" -ForegroundColor $healthColor
    Write-Host "  Disk Space: $($Report.SystemHealth.Details.DiskSpaceGB)GB free" -ForegroundColor White
    if ($Report.SystemHealth.Details.MemoryUsagePercent) {
        Write-Host "  Memory Usage: $($Report.SystemHealth.Details.MemoryUsagePercent)%" -ForegroundColor White
    }
    
    Write-Host "`n========================================================================" -ForegroundColor Cyan
    Write-Host "For detailed logs, see: $($script:LogConfig.FilePath)" -ForegroundColor Gray
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "`n" -NoNewline
}

<#
.SYNOPSIS
    Send telemetry data to optional reporting endpoint (respecting privacy)
#>
function Send-Telemetry {
    param(
        [hashtable] $Report,
        [string] $Endpoint = $null,
        [switch] $DisableTracking
    )
    
    if ($DisableTracking) {
        Write-Log "Telemetry disabled via flag" "INFO"
        return $false
    }
    
    if (-not $Endpoint) {
        Write-Log "No telemetry endpoint configured" "DEBUG"
        return $false
    }
    
    try {
        # Anonymize report before sending
        $anonReport = @{
            Version = "2.0.0"
            Timestamp = $Report.GeneratedAt
            ExecutionDuration = $Report.ExecutionDuration
            PackageStats = $Report.Packages
            SuccessRate = $Report.PackageSuccessRate
            ErrorCount = $Report.ErrorCount
            WarningCount = $Report.WarningCount
            # Don't send detailed errors/package names
        }
        
        $json = ConvertTo-Json $anonReport
        
        Invoke-RestMethod -Uri $Endpoint `
            -Method POST `
            -Body $json `
            -ContentType "application/json" `
            -TimeoutSec 10 `
            -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "Telemetry sent successfully" "DEBUG"
        return $true
    } catch {
        Write-Log "Failed to send telemetry: $($_.Exception.Message)" "DEBUG"
        return $false
    }
}
