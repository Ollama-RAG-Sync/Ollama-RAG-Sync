<#
.SYNOPSIS
    Stops a running file system watcher for a specific collection.
.DESCRIPTION
    This script stops a FileSystemWatcher background job that is monitoring a collection's source folder.
    It gracefully stops the watcher and removes the background job.
.PARAMETER CollectionId
    The ID of the collection whose watcher should be stopped.
.PARAMETER CollectionName
    The name of the collection whose watcher should be stopped (alternative to CollectionId).
.PARAMETER InstallPath
    The path to the installation directory containing the database and assemblies.
.PARAMETER DatabasePath
    Optional override for the database path.
.PARAMETER Force
    If specified, forces the watcher to stop immediately without waiting for graceful shutdown.
.EXAMPLE
    .\Stop-CollectionWatcher.ps1 -CollectionName "Documents" -InstallPath "C:\FileTracker"
    Stops the watcher for the "Documents" collection.
.EXAMPLE
    .\Stop-CollectionWatcher.ps1 -CollectionId 1 -InstallPath "C:\FileTracker" -Force
    Forcefully stops the watcher for collection with ID 1.
.NOTES
    Use Get-FileTrackerStatus to see which watchers are currently running.
#>

[CmdletBinding(DefaultParameterSetName = "ByName")]
param (
    [Parameter(Mandatory = $true, ParameterSetName = "ById")]
    [int]$CollectionId,
    
    [Parameter(Mandatory = $true, ParameterSetName = "ByName")]
    [string]$CollectionName,
    
    [Parameter(Mandatory = $false)]
    [string]$InstallPath = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "User"),
    
    [Parameter(Mandatory = $false)]
    [string]$DatabasePath,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
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

try {
    # Get collection information
    if ($PSCmdlet.ParameterSetName -eq "ByName") {
        $collection = Get-CollectionByName -Name $CollectionName -DatabasePath $DatabasePath -InstallPath $InstallPath
        if (-not $collection) {
            Write-Error "Collection '$CollectionName' not found."
            exit 1
        }
        $CollectionId = $collection.id
    }
    else {
        $collection = Get-Collection -Id $CollectionId -DatabasePath $DatabasePath -InstallPath $InstallPath
        if (-not $collection) {
            Write-Error "Collection with ID $CollectionId not found."
            exit 1
        }
    }
    
    Write-Host "Collection: $($collection.name) (ID: $CollectionId)" -ForegroundColor Cyan
    
    # Check if a watcher is running for this collection
    $job = Get-Job -Name "Watch_Collection_$CollectionId" -ErrorAction SilentlyContinue
    
    if (-not $job) {
        Write-Warning "No watcher is currently running for collection '$($collection.name)' (ID: $CollectionId)."
        exit 0
    }
    
    Write-Host "Found running watcher:" -ForegroundColor Yellow
    Write-Host "  Job ID: $($job.Id)" -ForegroundColor Gray
    Write-Host "  Job State: $($job.State)" -ForegroundColor Gray
    Write-Host "  Started: $($job.PSBeginTime)" -ForegroundColor Gray
    
    if ($job.State -ne 'Running') {
        Write-Warning "Watcher job is in '$($job.State)' state, not running. Cleaning up..."
        Remove-Job -Id $job.Id -Force
        Write-Host "Watcher job removed." -ForegroundColor Green
        exit 0
    }
    
    # Stop the watcher
    Write-Host "Stopping watcher..." -ForegroundColor Yellow
    
    if ($Force) {
        Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
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
            Write-Warning "Watcher did not stop gracefully. Forcing stop..."
            Stop-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
    
    # Remove the job
    Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
    
    Write-Host "Watcher stopped successfully!" -ForegroundColor Green
    Write-Host "Collection '$($collection.name)' (ID: $CollectionId) is no longer being watched." -ForegroundColor Green
}
catch {
    Write-Error "Error stopping collection watcher: $_"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
