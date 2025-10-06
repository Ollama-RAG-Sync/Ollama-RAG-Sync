<#
.SYNOPSIS
    Stops all running file system watchers for collections in the FileTracker database.
.DESCRIPTION
    This script stops all FileSystemWatcher background jobs that are currently monitoring 
    collections. It can gracefully stop all watchers or force them to stop immediately.
.PARAMETER InstallPath
    The path to the installation directory containing the database and assemblies.
.PARAMETER Force
    If specified, forces all watchers to stop immediately without waiting for graceful shutdown.
.EXAMPLE
    .\Stop-AllWatchers.ps1 -InstallPath "C:\FileTracker"
    Stops all running collection watchers gracefully.
.EXAMPLE
    .\Stop-AllWatchers.ps1 -InstallPath "C:\FileTracker" -Force
    Forcefully stops all running collection watchers immediately.
.NOTES
    Use Get-FileTrackerStatus to see which watchers are currently running before stopping them.
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$InstallPath = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "User"),
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Validate InstallPath
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-Error "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable."
    exit 1
}

try {
    # Find all watcher jobs (they follow the naming pattern "Watch_Collection_<ID>")
    $watcherJobs = Get-Job | Where-Object { $_.Name -match '^Watch_Collection_\d+$' }
    
    if ($watcherJobs.Count -eq 0) {
        Write-Host "No active collection watchers found." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Found $($watcherJobs.Count) active watcher(s)." -ForegroundColor Cyan
    Write-Host ""
    
    $stoppedCount = 0
    $failedCount = 0
    $results = @()
    
    foreach ($job in $watcherJobs) {
        # Extract collection ID from job name
        if ($job.Name -match 'Watch_Collection_(\d+)') {
            $collectionId = $matches[1]
        }
        else {
            $collectionId = "Unknown"
        }
        
        Write-Host "Stopping watcher: $($job.Name) (Job ID: $($job.Id), Collection ID: $collectionId)" -ForegroundColor Cyan
        Write-Host "  State: $($job.State)" -ForegroundColor Gray
        
        try {
            if ($job.State -ne 'Running') {
                Write-Warning "  Job is not running (State: $($job.State)). Cleaning up..."
                Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
                Write-Host "  Cleaned up job." -ForegroundColor Green
                $stoppedCount++
                $results += @{
                    jobName = $job.Name
                    jobId = $job.Id
                    collectionId = $collectionId
                    status = "Cleaned up"
                    initialState = $job.State
                }
                continue
            }
            
            # Stop the job
            if ($Force) {
                Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
            else {
                # Try graceful stop first
                Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
                
                # Wait up to 5 seconds for graceful shutdown
                $timeout = 5
                $elapsed = 0
                while ($elapsed -lt $timeout) {
                    $currentJob = Get-Job -Id $job.Id -ErrorAction SilentlyContinue
                    if (-not $currentJob -or $currentJob.State -ne 'Running') {
                        break
                    }
                    Start-Sleep -Seconds 1
                    $elapsed++
                }
                
                # Check if still running
                $currentJob = Get-Job -Id $job.Id -ErrorAction SilentlyContinue
                if ($currentJob -and $currentJob.State -eq 'Running') {
                    Write-Warning "  Job did not stop gracefully. Forcing stop..."
                    Stop-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
            }
            
            # Remove the job
            Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
            
            Write-Host "  Stopped successfully." -ForegroundColor Green
            $stoppedCount++
            $results += @{
                jobName = $job.Name
                jobId = $job.Id
                collectionId = $collectionId
                status = "Stopped"
                initialState = "Running"
            }
        }
        catch {
            Write-Warning "  Error stopping job: $_"
            $failedCount++
            $results += @{
                jobName = $job.Name
                jobId = $job.Id
                collectionId = $collectionId
                status = "Failed"
                error = $_.Exception.Message
            }
        }
        
        Write-Host ""
    }
    
    # Display summary
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "Summary:" -ForegroundColor Green
    Write-Host "  Total watchers found: $($watcherJobs.Count)" -ForegroundColor Cyan
    Write-Host "  Successfully stopped: $stoppedCount" -ForegroundColor Green
    Write-Host "  Failed: $failedCount" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Display detailed results
    if ($results.Count -gt 0) {
        Write-Host "Detailed Results:" -ForegroundColor Cyan
        $results | ForEach-Object {
            $statusColor = switch ($_.status) {
                "Stopped" { "Green" }
                "Cleaned up" { "Green" }
                "Failed" { "Red" }
                default { "Gray" }
            }
            
            Write-Host "  [$($_.status)] $($_.jobName) (Job ID: $($_.jobId), Collection ID: $($_.collectionId))" -ForegroundColor $statusColor
            if ($_.error) {
                Write-Host "    Error: $($_.error)" -ForegroundColor Red
            }
        }
        Write-Host ""
    }
    
    if ($stoppedCount -gt 0) {
        Write-Host "All watchers have been stopped." -ForegroundColor Green
        Write-Host "You can restart them using Start-AllWatchers or Start-CollectionWatcher." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Error stopping watchers: $_"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
