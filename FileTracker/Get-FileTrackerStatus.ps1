<#
.SYNOPSIS
    Gets the current status of the FileTracker system, including collections, files, and watchers.
.DESCRIPTION
    This script retrieves comprehensive information about the current state of the FileTracker system,
    including all collections, their files (dirty, processed, and deleted), and running file watchers.
.PARAMETER InstallPath
    The path to the installation directory.
.OUTPUTS
    Returns a PowerShell object containing status information about collections, files, and watchers.
#>
param (
    [Parameter(Mandatory=$false)]
    [string]$InstallPath = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "User")
)

# Validate InstallPath
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-Error "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable."
    exit 1
}

# Import required modules
Import-Module -Name "$PSScriptRoot\FileTracker-Shared.psm1" -Force
Import-Module -Name "$PSScriptRoot\Database-Shared.psm1" -Force

# Determine Database Path
$DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
Write-Verbose "Using database path: $DatabasePath"

try {
    # Get all collections (pass InstallPath)
    $collections = Get-Collections -DatabasePath $DatabasePath -InstallPath $InstallPath
    
    # Initialize status variables
    $totalFiles = 0
    $dirtyFiles = 0
    $processedFiles = 0
    $deletedFiles = 0
    $watchersInfo = @()
    $collectionsWithStats = @()
    
    # Process each collection
    foreach ($collection in $collections) {
        # Get files in this collection (pass InstallPath)
        $allFiles = Get-CollectionFiles -CollectionId $collection.id -DatabasePath $DatabasePath -InstallPath $InstallPath
        $dirty = Get-CollectionFiles -CollectionId $collection.id -DirtyOnly -DatabasePath $DatabasePath -InstallPath $InstallPath
        $processed = Get-CollectionFiles -CollectionId $collection.id -ProcessedOnly -DatabasePath $DatabasePath -InstallPath $InstallPath
        $deleted = Get-CollectionFiles -CollectionId $collection.id -DeletedOnly -DatabasePath $DatabasePath -InstallPath $InstallPath
        
        # Update counters
        $totalFiles += $allFiles.Count # Assuming $allFiles is an array or collection
        $dirtyFiles += $dirty.Count
        $processedFiles += $processed.Count
        $deletedFiles += $deleted.Count
        
        # Check if the collection has an active watcher
        $watcherInfo = $null
        $watchJob = Get-Job -Name "Watch_Collection_$($collection.id)" -ErrorAction SilentlyContinue
        
        if ($watchJob) {
            $watcherInfo = @{
                jobId = $watchJob.Id
                jobName = $watchJob.Name
                state = $watchJob.State
                hasMoreData = $watchJob.HasMoreData
                location = $watchJob.Location
                command = $watchJob.Command
                startTime = $watchJob.PSBeginTime
                runningTimeMinutes = ([DateTime]::Now - $watchJob.PSBeginTime).TotalMinutes
            }
            
            $watchersInfo += $watcherInfo
        }
        
        # Add collection with enhanced stats
        $collectionsWithStats += @{
            id = $collection.id
            name = $collection.name
            description = $collection.description
            source_folder = $collection.source_folder
            include_extensions = $collection.include_extensions
            exclude_folders = $collection.exclude_folders
            created_at = $collection.created_at
            updated_at = $collection.updated_at
            files = @{
                total = $allFiles.Count
                dirty = $dirty.Count
                processed = $processed.Count
                deleted = $deleted.Count
            }
            watcher = $watcherInfo
            isBeingWatched = ($watchJob -ne $null)
        }
    }
    
    # Return comprehensive status
    return @{
        initialized = $true
        databasePath = $DatabasePath
        collections = $collectionsWithStats
        watchers = $watchersInfo
        summary = @{
            totalCollections = $collections.Count
            totalFiles = $totalFiles
            dirtyFiles = $dirtyFiles
            processedFiles = $processedFiles
            deletedFiles = $deletedFiles
            activeWatchers = $watchersInfo.Count
            collectionWatchPercentage = if ($collections.Count -gt 0) { 
                [math]::Round(($watchersInfo.Count / $collections.Count) * 100, 2) 
            } else { 
                0 
            }
            processingProgress = if ($totalFiles -gt 0) { 
                [math]::Round(($processedFiles / $totalFiles) * 100, 2) 
            } else { 
                100 
            }
            lastUpdated = [DateTime]::Now.ToString("o")
        }
    }
}
catch {
    return @{
        initialized = $false
        error = "Error getting FileTracker status: $_, $($_.ScriptStackTrace)"
        collections = @()
        watchers = @()
        summary = @{
            totalCollections = 0
            totalFiles = 0
            dirtyFiles = 0
            processedFiles = 0
            deletedFiles = 0
            activeWatchers = 0
        }
    }
}
