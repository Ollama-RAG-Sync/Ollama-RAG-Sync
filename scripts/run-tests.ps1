# run-tests.ps1
# Script to run all tests in the project

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("All", "Unit", "Integration", "E2E", "PowerShell", "DotNet")]
    [string]$TestType = "All",
    
    [Parameter(Mandatory=$false)]
    [switch]$GenerateCoverage,
    
    [Parameter(Mandatory=$false)]
    [switch]$Detailed
)

# Ensure we're in the project root
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Ollama-RAG-Sync Test Runner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Function to run PowerShell tests
function Invoke-PowerShellTests {
    param(
        [string]$Tag
    )
    
    Write-Host "Running PowerShell Tests..." -ForegroundColor Yellow
    Write-Host ""
    
    # Check if Pester is installed
    $pesterModule = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge '5.0.0' }
    if (-not $pesterModule) {
        Write-Host "Installing Pester module..." -ForegroundColor Yellow
        Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser -SkipPublisherCheck
    }
    
    Import-Module Pester -MinimumVersion 5.0.0
    
    $ragPath = Join-Path $projectRoot "RAG"
    
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $ragPath
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = if ($Detailed) { "Detailed" } else { "Normal" }
    
    if ($Tag) {
        $pesterConfig.Filter.Tag = $Tag
    }
    
    if ($GenerateCoverage) {
        $pesterConfig.CodeCoverage.Enabled = $true
        $pesterConfig.CodeCoverage.Path = @(
            "$ragPath\**\*.psm1",
            "$ragPath\**\*.ps1"
        )
        $pesterConfig.CodeCoverage.OutputPath = Join-Path $projectRoot "coverage\powershell-coverage.xml"
    }
    
    $result = Invoke-Pester -Configuration $pesterConfig
    
    return $result
}

# Function to run .NET tests
function Invoke-DotNetTests {
    Write-Host "Running .NET Tests..." -ForegroundColor Yellow
    Write-Host ""
    
    $mcpTestPath = Join-Path $projectRoot "MCP\Ollama-RAG-Sync.Tests"
    
    if (-not (Test-Path $mcpTestPath)) {
        Write-Warning "MCP test project not found at: $mcpTestPath"
        return $null
    }
    
    Push-Location $mcpTestPath
    
    try {
        if ($GenerateCoverage) {
            dotnet test --configuration Release --collect:"XPlat Code Coverage" --logger "console;verbosity=detailed"
        } else {
            $verbosity = if ($Detailed) { "detailed" } else { "normal" }
            dotnet test --configuration Release --logger "console;verbosity=$verbosity"
        }
        
        $exitCode = $LASTEXITCODE
        
        Pop-Location
        
        return @{ ExitCode = $exitCode }
    }
    catch {
        Pop-Location
        throw
    }
}

# Main execution
$results = @{}

try {
    switch ($TestType) {
        "All" {
            Write-Host "Running all tests..." -ForegroundColor Green
            Write-Host ""
            
            # Run PowerShell tests
            $results.PowerShell = Invoke-PowerShellTests
            
            Write-Host ""
            Write-Host "----------------------------------------" -ForegroundColor Cyan
            Write-Host ""
            
            # Run .NET tests
            $results.DotNet = Invoke-DotNetTests
        }
        "Unit" {
            Write-Host "Running unit tests only..." -ForegroundColor Green
            $results.PowerShell = Invoke-PowerShellTests -Tag "Unit"
        }
        "Integration" {
            Write-Host "Running integration tests only..." -ForegroundColor Green
            $results.PowerShell = Invoke-PowerShellTests -Tag "Integration"
        }
        "E2E" {
            Write-Host "Running end-to-end tests only..." -ForegroundColor Green
            $results.PowerShell = Invoke-PowerShellTests -Tag "E2E"
        }
        "PowerShell" {
            Write-Host "Running PowerShell tests only..." -ForegroundColor Green
            $results.PowerShell = Invoke-PowerShellTests
        }
        "DotNet" {
            Write-Host "Running .NET tests only..." -ForegroundColor Green
            $results.DotNet = Invoke-DotNetTests
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Test Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $overallSuccess = $true
    
    if ($results.PowerShell) {
        Write-Host "PowerShell Tests:" -ForegroundColor Yellow
        Write-Host "  Total:   $($results.PowerShell.TotalCount)" -ForegroundColor White
        Write-Host "  Passed:  $($results.PowerShell.PassedCount)" -ForegroundColor Green
        Write-Host "  Failed:  $($results.PowerShell.FailedCount)" -ForegroundColor $(if ($results.PowerShell.FailedCount -gt 0) { "Red" } else { "Green" })
        Write-Host "  Skipped: $($results.PowerShell.SkippedCount)" -ForegroundColor Yellow
        Write-Host ""
        
        if ($results.PowerShell.FailedCount -gt 0) {
            $overallSuccess = $false
        }
    }
    
    if ($results.DotNet) {
        Write-Host ".NET Tests:" -ForegroundColor Yellow
        if ($results.DotNet.ExitCode -eq 0) {
            Write-Host "  Status: PASSED" -ForegroundColor Green
        } else {
            Write-Host "  Status: FAILED" -ForegroundColor Red
            $overallSuccess = $false
        }
        Write-Host ""
    }
    
    if ($GenerateCoverage) {
        Write-Host "Coverage reports generated in:" -ForegroundColor Cyan
        Write-Host "  coverage/" -ForegroundColor White
        Write-Host ""
    }
    
    if ($overallSuccess) {
        Write-Host "All tests passed!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "Some tests failed!" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "Error running tests: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
