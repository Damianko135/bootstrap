@{
    RootModule        = 'functions.ps1'
    ModuleVersion     = '1.0.0'
    GUID              = '12345678-1234-1234-1234-123456789012'
    Author            = 'Damian Korver'
    CompanyName       = 'Laptop Automation'
    Description       = 'Shared functions for Windows Laptop Automation'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Write-LogEntry',
        'Test-Administrator',
        'Test-PackageManagerAvailable'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
