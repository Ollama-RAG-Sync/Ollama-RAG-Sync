# Get-FileTrackerStatus

This script retrieves and displays comprehensive information about the current state of the FileTracker system, including collections, files, and active watchers.

## Overview

The `Get-FileTrackerStatus.ps1` script provides a detailed status report of the FileTracker system, showing:

- Summary of all collections, files, and file processing progress
- Details of each collection, including its files and watcher status
- Information about active watchers and their running times

## Usage

### Basic Usage

```powershell
# Get status using the default database path
.\Get-FileTrackerStatus.ps1

# Get status for a specific database
.\Get-FileTrackerStatus.ps1 -DatabasePath "C:\AppData\FileTracker\FileTracker.db"
```

### Using in Scripts

```powershell
# Import the module
Import-Module -Name ".\FileTracker\Get-FileTrackerStatus.ps1" -Force

# Get the status object for further processing
$status = Get-FileTrackerStatus
Write-Host "Processing progress: $($status.summary.processingProgress)%"

# Get only collections with dirty files that need processing
$collectionsNeedingProcessing = $status.collections | Where-Object { $_.files.dirty -gt 0 }
foreach ($collection in $collectionsNeedingProcessing) {
    Write-Host "Collection '$($collection.name)' has $($collection.files.dirty) files that need processing"
}
```

## Output

### Console Output

When run directly from the console, the script produces a formatted display with color-coding:

```
======= FileTracker Status =======
Database: C:\Users\username\AppData\Roaming\FileTracker\FileTracker.db

--- Summary ---
Collections        : 3
Total Files        : 124
Files to Process   : 15
Processed Files    : 109
Deleted Files      : 2
Active Watchers    : 2
Processing Progress: 87.9%
Last Updated       : 2025-03-30T17:15:23.4567890Z

--- Collections ---
[1] Documentation - Watching
  Source: D:\Docs
  Files: Total: 42, To Process: 5, Processed: 37, Deleted: 0
  Watcher: Running for 152.3 minutes (JobId: 3)

[2] CodeProject - Watching
  Source: D:\Projects\App
  Files: Total: 78, To Process: 10, Processed: 68, Deleted: 0
  Watcher: Running for 78.5 minutes (JobId: 4)

[3] Reports - Not Watching
  Source: D:\Reports
  Files: Total: 4, To Process: 0, Processed: 4, Deleted: 2
  Watcher: Not active

--- Active Watchers ---
Job: Watch_Collection_1 (ID: 3)
  State: Running
  Started: 03/30/2025 15:12:05
  Running for: 152.3 minutes

Job: Watch_Collection_2 (ID: 4)
  State: Running
  Started: 03/30/2025 16:25:48
  Running for: 78.5 minutes
```

### Object Output

When used in scripts, the function returns a PowerShell object with this structure:

```powershell
$status = @{
    initialized = $true
    databasePath = "path/to/database.db"
    collections = @(
        @{
            id = 1
            name = "Collection Name"
            description = "Description"
            source_folder = "D:\path\to\source"
            include_extensions = ".txt,.md,.pdf"
            exclude_folders = ".git,node_modules"
            created_at = "2025-03-01T12:00:00.0000000Z"
            updated_at = "2025-03-30T14:30:00.0000000Z"
            files = @{
                total = 42
                dirty = 5
                processed = 37
                deleted = 0
            }
            watcher = @{
                jobId = 3
                jobName = "Watch_Collection_1"
                state = "Running"
                hasMoreData = $true
                location = ""
                command = "..."
                startTime = "03/30/2025 15:12:05"
                runningTimeMinutes = 152.3
            }
            isBeingWatched = $true
        }
        # Additional collections...
    )
    watchers = @(
        @{
            jobId = 3
            jobName = "Watch_Collection_1"
            state = "Running"
            hasMoreData = $true
            location = ""
            command = "..."
            startTime = "03/30/2025 15:12:05"
            runningTimeMinutes = 152.3
        }
        # Additional watchers...
    )
    summary = @{
        totalCollections = 3
        totalFiles = 124
        dirtyFiles = 15
        processedFiles = 109
        deletedFiles = 2
        activeWatchers = 2
        collectionWatchPercentage = 66.67
        processingProgress = 87.9
        lastUpdated = "2025-03-30T17:15:23.4567890Z"
    }
}
```

## Notes

- If the database doesn't exist or can't be accessed, the function will return an object with `initialized = $false` and an error message.
- The script can be used both interactively (with console output) and programmatically (returning an object).
- Collection watchers are identified by background jobs with names matching the pattern `Watch_Collection_[ID]`.
