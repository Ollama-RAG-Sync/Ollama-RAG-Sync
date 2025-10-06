# File Watcher Feature

## Overview

The File Watcher feature provides automatic, real-time tracking of file changes in your FileTracker collections. When you enable a file watcher for a collection, the system monitors the collection's source folder and automatically marks files as "dirty" (needing processing) when they are created, modified, deleted, or renamed.

## How It Works

Each file watcher runs as a PowerShell background job that uses the .NET `FileSystemWatcher` class to monitor file system events. When a file change is detected:

1. **File Created/Modified**: The file is automatically added to the collection or marked as dirty in the FileTracker database
2. **File Deleted**: The file is marked as deleted in the database
3. **File Renamed**: The old file is marked as deleted and the new file is added as a new entry

The watcher respects your collection's configuration:
- **Include Extensions**: Only tracks files with specified extensions (if configured)
- **Exclude Folders**: Ignores files in excluded folders (e.g., `.git`, `node_modules`)

## Benefits

- **Real-time Synchronization**: No need to manually refresh collections after file changes
- **Automated Processing Pipeline**: Changed files are automatically queued for processing
- **Multiple Collections**: Run separate watchers for each collection with independent configurations
- **Low Overhead**: Watchers use minimal system resources and run in the background

## Getting Started

### Prerequisites

- FileTracker database must be initialized (using `Initialize-Database.ps1`)
- At least one collection must be created (using `Add-Folder.ps1`)
- `OLLAMA_RAG_INSTALL_PATH` environment variable should be set

### Starting a Watcher for a Single Collection

#### By Collection Name
```powershell
.\Start-CollectionWatcher.ps1 -CollectionName "Documents" -InstallPath "C:\FileTracker"
```

#### By Collection ID
```powershell
.\Start-CollectionWatcher.ps1 -CollectionId 1 -InstallPath "C:\FileTracker"
```

The script will:
- Validate that the collection exists
- Check if a watcher is already running
- Start a background job to monitor file changes
- Display the job ID and helpful management commands

### Starting Watchers for All Collections

To start watchers for all collections in the database:

```powershell
.\Start-AllWatchers.ps1 -InstallPath "C:\FileTracker"
```

#### Skip Collections with Running Watchers
```powershell
.\Start-AllWatchers.ps1 -InstallPath "C:\FileTracker" -SkipRunning
```

This command will:
- Iterate through all collections
- Start a watcher for each valid collection
- Skip collections that already have running watchers (with `-SkipRunning`)
- Provide a summary of started, skipped, and failed watchers

## Monitoring Watchers

### View All Active Watchers

Use `Get-FileTrackerStatus` to see comprehensive information about all collections and their watchers:

```powershell
.\Get-FileTrackerStatus.ps1 -InstallPath "C:\FileTracker"
```

This displays:
- **Collection Information**: ID, name, source folder, configuration
- **File Statistics**: Total, dirty, processed, and deleted file counts
- **Watcher Status**: Whether a watcher is running and its details
- **Summary Statistics**: Overall system health and progress

The output includes for each collection:
- `isBeingWatched`: Boolean indicating if a watcher is active
- `watcher`: Object containing job ID, state, start time, and running duration

### View Watcher Output

To see real-time output from a specific watcher job:

```powershell
# View output once (keeps it for future viewing)
Receive-Job -Id <JobId> -Keep

# View output and remove it
Receive-Job -Id <JobId>

# View output continuously (requires PowerShell 7+)
Receive-Job -Id <JobId> -Keep -Wait
```

### Check Watcher Job Status

```powershell
# View all background jobs
Get-Job

# View specific watcher job
Get-Job -Name "Watch_Collection_<CollectionId>"

# View job details
Get-Job -Id <JobId> | Format-List *
```

## Stopping Watchers

### Stop a Single Watcher

#### By Collection Name
```powershell
.\Stop-CollectionWatcher.ps1 -CollectionName "Documents" -InstallPath "C:\FileTracker"
```

#### By Collection ID
```powershell
.\Stop-CollectionWatcher.ps1 -CollectionId 1 -InstallPath "C:\FileTracker"
```

#### Force Stop (Immediate)
```powershell
.\Stop-CollectionWatcher.ps1 -CollectionId 1 -InstallPath "C:\FileTracker" -Force
```

### Stop All Watchers

To stop all running file watchers at once:

```powershell
# Graceful stop (default)
.\Stop-AllWatchers.ps1 -InstallPath "C:\FileTracker"

# Force stop (immediate)
.\Stop-AllWatchers.ps1 -InstallPath "C:\FileTracker" -Force
```

## Watcher Behavior Details

### Tracked Events

| Event Type | Action | Database Update |
|------------|--------|-----------------|
| **File Created** | New file added to collection | File inserted with `Dirty=1`, `Deleted=0` |
| **File Modified** | Existing file changed | `LastModified` updated, `Dirty=1`, `Deleted=0` |
| **File Deleted** | File removed from folder | `Deleted=1` (file remains in database) |
| **File Renamed** | File name changed | Old file: `Deleted=1`, New file: inserted with `Dirty=1` |

### File Filtering

Watchers apply the same filtering rules as the collection configuration:

1. **Include Extensions**: If specified, only files with matching extensions are tracked
   - Example: `.md,.txt,.pdf`
   - If not specified, all file types are tracked

2. **Exclude Folders**: Folders matching these patterns are ignored
   - Example: `.git,.ai,node_modules`
   - Applied recursively to all subdirectories

### Performance Considerations

- **Lightweight**: Watchers use minimal CPU and memory
- **Event Batching**: Multiple rapid changes to the same file are handled efficiently
- **Database Connections**: Each event opens and closes a database connection (prevents locking)
- **Non-blocking**: Watchers run in background jobs and don't block other operations

## Troubleshooting

### Watcher Won't Start

**Problem**: Error message "Watcher already running" or job fails to start

**Solutions**:
1. Check if a watcher is already running: `Get-FileTrackerStatus -InstallPath "C:\FileTracker"`
2. Stop the existing watcher: `Stop-CollectionWatcher -CollectionId <ID>`
3. Clean up failed jobs: `Get-Job | Where-Object {$_.State -eq 'Failed'} | Remove-Job`

### Source Folder Doesn't Exist

**Problem**: Error message "Source folder does not exist"

**Solutions**:
1. Verify the collection's source folder path is valid
2. Update the collection's source folder: Use `Update-Collection` (if available) or manually update the database
3. Ensure the folder hasn't been moved or deleted

### Files Not Being Tracked

**Problem**: File changes aren't reflected in the database

**Solutions**:
1. Verify the watcher is running: `Get-Job -Name "Watch_Collection_<ID>"`
2. Check watcher output for errors: `Receive-Job -Id <JobId> -Keep`
3. Ensure files match the collection's include/exclude rules
4. Check file permissions (watcher needs read access)

### High Memory Usage

**Problem**: Watcher job consuming excessive memory

**Solutions**:
1. Stop and restart the watcher: `Stop-CollectionWatcher` then `Start-CollectionWatcher`
2. Clear job output regularly: `Receive-Job -Id <JobId>` (without `-Keep`)
3. Reduce the number of files in the collection or split into multiple collections

### Watcher Stops Unexpectedly

**Problem**: Watcher job state changes to 'Failed' or 'Stopped'

**Solutions**:
1. Check job error output: `Receive-Job -Id <JobId>`
2. Verify database file isn't locked or corrupted
3. Check system permissions for the source folder
4. Review PowerShell execution policy settings

## Best Practices

### When to Use Watchers

✅ **Good Use Cases**:
- Active development folders with frequent changes
- Shared folders where multiple users make updates
- Long-running systems that need continuous synchronization
- Collections with large numbers of files that change frequently

❌ **Avoid Watchers For**:
- Static archives that rarely change (use manual refresh instead)
- Collections with extremely high file churn (thousands of changes per minute)
- Network drives with high latency (may cause delays)

### Managing Multiple Watchers

1. **Start All at System Boot**: Create a startup script that calls `Start-AllWatchers.ps1`
2. **Monitor Regularly**: Schedule periodic checks using `Get-FileTrackerStatus`
3. **Restart on Failure**: Implement error handling to auto-restart failed watchers
4. **Log Watcher Activity**: Redirect job output to log files for auditing

### Resource Management

- **Limit Concurrent Watchers**: While multiple watchers can run simultaneously, consider system resources
- **Clear Job Output**: Periodically clear job output to prevent memory buildup
- **Use Exclude Folders**: Exclude temporary folders, caches, and build outputs to reduce noise

## Integration with Processing Pipeline

File watchers integrate seamlessly with the FileTracker processing pipeline:

1. **Watcher Detects Change** → File marked as `Dirty=1`
2. **Process-Collection** → Retrieves dirty files and processes them
3. **After Processing** → Files marked as `Dirty=0` (processed)
4. **Repeat** → Watcher continues monitoring for new changes

Example workflow:
```powershell
# Start watcher for a collection
.\Start-CollectionWatcher.ps1 -CollectionName "Documents" -InstallPath "C:\FileTracker"

# In a separate terminal/script, process dirty files
.\Process-Collection.ps1 -CollectionName "Documents" -InstallPath "C:\FileTracker"

# Files changed after processing are automatically marked dirty again
# The watcher ensures the collection stays synchronized
```

## Scripts Reference

### Start-CollectionWatcher.ps1
Starts a file watcher for a specific collection.

**Parameters**:
- `-CollectionId`: Collection ID (integer)
- `-CollectionName`: Collection name (string)
- `-InstallPath`: Installation directory path
- `-DatabasePath`: Optional database path override

### Stop-CollectionWatcher.ps1
Stops a running file watcher for a collection.

**Parameters**:
- `-CollectionId`: Collection ID (integer)
- `-CollectionName`: Collection name (string)
- `-InstallPath`: Installation directory path
- `-DatabasePath`: Optional database path override
- `-Force`: Force immediate stop (switch)

### Start-AllWatchers.ps1
Starts watchers for all collections.

**Parameters**:
- `-InstallPath`: Installation directory path
- `-DatabasePath`: Optional database path override
- `-SkipRunning`: Skip collections with active watchers (switch)

### Stop-AllWatchers.ps1
Stops all running collection watchers.

**Parameters**:
- `-InstallPath`: Installation directory path
- `-Force`: Force immediate stop for all (switch)

### Get-FileTrackerStatus.ps1
Displays comprehensive status including watcher information.

**Parameters**:
- `-InstallPath`: Installation directory path

## Examples

### Example 1: Complete Workflow
```powershell
# Set environment variable (one-time setup)
[System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "C:\FileTracker", "User")

# Initialize database
.\Initialize-Database.ps1

# Create a collection
.\Add-Folder.ps1 -CollectionName "MyDocs" -FolderPath "C:\Documents" -IncludeExtensions ".md,.txt"

# Start watcher
.\Start-CollectionWatcher.ps1 -CollectionName "MyDocs"

# Check status
.\Get-FileTrackerStatus.ps1

# View watcher output
$job = Get-Job -Name "Watch_Collection_1"
Receive-Job -Id $job.Id -Keep

# Make changes to files in C:\Documents
# Watcher automatically marks them as dirty

# Stop watcher when done
.\Stop-CollectionWatcher.ps1 -CollectionName "MyDocs"
```

### Example 2: Multiple Collections
```powershell
# Create multiple collections
.\Add-Folder.ps1 -CollectionName "Projects" -FolderPath "C:\Projects" -ExcludeFolders "node_modules,.git"
.\Add-Folder.ps1 -CollectionName "Notes" -FolderPath "C:\Notes"
.\Add-Folder.ps1 -CollectionName "Research" -FolderPath "C:\Research" -IncludeExtensions ".pdf,.docx"

# Start all watchers
.\Start-AllWatchers.ps1

# Check overall status
.\Get-FileTrackerStatus.ps1

# Stop all watchers
.\Stop-AllWatchers.ps1
```

### Example 3: Monitoring and Maintenance
```powershell
# Schedule a task to monitor watchers every hour
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\FileTracker\CheckWatchers.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName "FileTrackerWatcherCheck" -Action $action -Trigger $trigger

# CheckWatchers.ps1 content:
# .\Get-FileTrackerStatus.ps1 | Out-File "C:\Logs\WatcherStatus.log" -Append
# # Add logic to restart failed watchers if needed
```

## FAQ

**Q: Do watchers persist across system reboots?**  
A: No, watchers are background jobs that stop when PowerShell exits. You need to restart them after a reboot. Consider creating a startup script.

**Q: Can I run watchers on network drives?**  
A: Yes, but performance may be slower and reliability depends on network stability. Local drives are recommended.

**Q: What happens if the database is locked?**  
A: The watcher will log an error for that specific file change but continue running. The file can be manually marked dirty or the watcher will catch subsequent changes.

**Q: Do watchers impact file processing performance?**  
A: No, watchers only update the database to mark files as dirty. Actual file processing happens separately via `Process-Collection.ps1`.

**Q: How many watchers can I run simultaneously?**  
A: There's no hard limit, but consider system resources. Most systems can handle 10-20 watchers without issues.

**Q: Can I pause a watcher?**  
A: PowerShell jobs don't support pause/resume. Stop the watcher and restart it when needed.

## Related Documentation

- **ARCHITECTURE.md**: Overall system architecture
- **MULTI_COLLECTION_STORAGE.md**: Collection management details
- **TESTING.md**: Testing file tracker functionality
- **FileTracker Scripts**: Individual script documentation (help comments)

## Support

For issues, questions, or contributions related to the file watcher feature:
1. Check the troubleshooting section above
2. Review script help: `Get-Help .\Start-CollectionWatcher.ps1 -Full`
3. Check job logs: `Receive-Job -Id <JobId> -Keep`
4. File an issue on GitHub with watcher output and error details
