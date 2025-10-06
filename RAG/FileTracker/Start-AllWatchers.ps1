<#
.SYNOPSIS
    Starts file system watchers for all collections in the FileTracker database.
.DESCRIPTION
    This script retrieves all collections from the FileTracker database and starts a 
    FileSystemWatcher background job for each one. This allows automatic tracking of 
    file changes across all collections.
.PARAMETER InstallPath
    The path to the installation directory containing the database and assemblies.
.PARAMETER DatabasePath
    Optional override for the database path.
.PARAMETER SkipRunning
    If specified, skips collections that already have a running watcher.
.EXAMPLE
    .\Start-AllWatchers.ps1 -InstallPath "C:\FileTracker"
    Starts watchers for all collections in the database.
.EXAMPLE
    .\Start-AllWatchers.ps1 -InstallPath "C:\FileTracker" -SkipRunning
    Starts watchers only for collections that don't already have one running.
.NOTES
    Use Get-FileTrackerStatus to see which watchers are currently running.
    Use Stop-AllWatchers to stop all running watchers.
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$InstallPath = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "User"),
    
    [Parameter(Mandatory = $false)]
    [string]$DatabasePath,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipRunning
)

# Validate InstallPath
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-Error "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable."
    exit 1
}

# Import required modules
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedModulePath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedModulePath -Force -Global

# Determine Database Path
if (-not $DatabasePath) {
    $DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
}

Write-Host "Using database path: $DatabasePath" -ForegroundColor Cyan

# Validate database exists
if (-not (Test-Path -Path $DatabasePath)) {
    Write-Error "Database not found at $DatabasePath. Please initialize it first using Initialize-Database.ps1"
    exit 1
}

try {
    # Get all collections
    $collections = Get-Collections -DatabasePath $DatabasePath -InstallPath $InstallPath
    
    if ($collections.Count -eq 0) {
        Write-Warning "No collections found in the database."
        Write-Host "Use Add-Folder.ps1 to create collections." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Found $($collections.Count) collection(s) in the database." -ForegroundColor Green
    Write-Host ""
    
    $startedCount = 0
    $skippedCount = 0
    $failedCount = 0
    $results = @()
    
    foreach ($collection in $collections) {
        Write-Host "Processing collection: $($collection.name) (ID: $($collection.id))" -ForegroundColor Cyan
        
        # Check if watcher is already running
        $existingJob = Get-Job -Name "Watch_Collection_$($collection.id)" -ErrorAction SilentlyContinue
        
        if ($existingJob -and $existingJob.State -eq 'Running') {
            if ($SkipRunning) {
                Write-Host "  Skipping - watcher already running (Job ID: $($existingJob.Id))" -ForegroundColor Yellow
                $skippedCount++
                $results += @{
                    collection = $collection.name
                    collectionId = $collection.id
                    status = "Skipped"
                    reason = "Already running"
                    jobId = $existingJob.Id
                }
                continue
            }
            else {
                Write-Host "  Warning: watcher already running (Job ID: $($existingJob.Id))" -ForegroundColor Yellow
                Write-Host "  Use -SkipRunning to skip collections with running watchers" -ForegroundColor Gray
                $skippedCount++
                $results += @{
                    collection = $collection.name
                    collectionId = $collection.id
                    status = "Skipped"
                    reason = "Already running"
                    jobId = $existingJob.Id
                }
                continue
            }
        }
        
        # Validate source folder exists
        if (-not (Test-Path -Path $collection.source_folder -PathType Container)) {
            Write-Warning "  Source folder does not exist: $($collection.source_folder)"
            Write-Warning "  Skipping this collection."
            $failedCount++
            $results += @{
                collection = $collection.name
                collectionId = $collection.id
                status = "Failed"
                reason = "Source folder does not exist"
                jobId = $null
            }
            continue
        }
        
        # Start the watcher
        try {
            $startWatcherScript = Join-Path -Path $scriptParentPath -ChildPath "Start-CollectionWatcher.ps1"
            
            # Call Start-CollectionWatcher.ps1 with appropriate parameters
            & $startWatcherScript -CollectionId $collection.id -InstallPath $InstallPath -DatabasePath $DatabasePath | Out-Null
            
            # Wait a moment to check if job started successfully
            Start-Sleep -Milliseconds 500
            
            $job = Get-Job -Name "Watch_Collection_$($collection.id)" -ErrorAction SilentlyContinue
            
            if ($job -and $job.State -eq 'Running') {
                Write-Host "  Started successfully (Job ID: $($job.Id))" -ForegroundColor Green
                $startedCount++
                $results += @{
                    collection = $collection.name
                    collectionId = $collection.id
                    status = "Started"
                    reason = $null
                    jobId = $job.Id
                }
            }
            else {
                Write-Warning "  Failed to start watcher"
                $failedCount++
                $results += @{
                    collection = $collection.name
                    collectionId = $collection.id
                    status = "Failed"
                    reason = "Job did not start"
                    jobId = $null
                }
            }
        }
        catch {
            Write-Warning "  Error starting watcher: $_"
            $failedCount++
            $results += @{
                collection = $collection.name
                collectionId = $collection.id
                status = "Failed"
                reason = $_.Exception.Message
                jobId = $null
            }
        }
        
        Write-Host ""
    }
    
    # Display summary
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "Summary:" -ForegroundColor Green
    Write-Host "  Total collections: $($collections.Count)" -ForegroundColor Cyan
    Write-Host "  Started: $startedCount" -ForegroundColor Green
    Write-Host "  Skipped: $skippedCount" -ForegroundColor Yellow
    Write-Host "  Failed: $failedCount" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Display detailed results table
    if ($results.Count -gt 0) {
        Write-Host "Detailed Results:" -ForegroundColor Cyan
        $results | ForEach-Object {
            $statusColor = switch ($_.status) {
                "Started" { "Green" }
                "Skipped" { "Yellow" }
                "Failed" { "Red" }
                default { "Gray" }
            }
            
            Write-Host "  [$($_.status)] $($_.collection) (ID: $($_.collectionId))" -ForegroundColor $statusColor
            if ($_.reason) {
                Write-Host "    Reason: $($_.reason)" -ForegroundColor Gray
            }
            if ($_.jobId) {
                Write-Host "    Job ID: $($_.jobId)" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
    
    # Show helpful commands
    if ($startedCount -gt 0) {
        Write-Host "Use the following commands to manage watchers:" -ForegroundColor Yellow
        Write-Host "  - View all watchers: Get-FileTrackerStatus -InstallPath '$InstallPath'" -ForegroundColor Gray
        Write-Host "  - Stop all watchers: Stop-AllWatchers -InstallPath '$InstallPath'" -ForegroundColor Gray
        Write-Host "  - Stop specific watcher: Stop-CollectionWatcher -CollectionId <ID> -InstallPath '$InstallPath'" -ForegroundColor Gray
    }
}
catch {
    Write-Error "Error starting watchers: $_"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
