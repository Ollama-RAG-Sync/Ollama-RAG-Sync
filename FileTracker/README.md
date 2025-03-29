# FileTracker Module

A PowerShell module for tracking file changes in collections and processing them.

## Overview

The FileTracker module helps you create and manage collections of files and track changes to them. It supports:

- Creating collections of files from specified folders
- Monitoring collections for file changes (create/modify/delete/rename)
- Marking files as "dirty" (needing processing) when changes are detected
- Managing collections through a REST API

## Key Scripts

### Collection Management

- **Initialize-Collections.ps1**: Create a new collection and add files from a specified folder
- **Initialize-CollectionDatabase.ps1**: Set up the SQLite database for collection tracking
- **Update-Collection.ps1**: Scan a collection's source folder for changes and update the database

### File Watching

- **Watch-FileTracker.ps1**: Monitor a directory for file changes and update the database
- **Start-CollectionWatch.ps1**: Start, stop, or restart file watching for an existing collection
- **Start-AllCollectionWatchers.ps1**: Automatically start watchers for all collections with enabled watch settings

### API and Services

- **Start-FileTracker.ps1**: Start the REST API server for FileTracker
- **Install-FileTracker.ps1**: Install the required dependencies

## Using File Watchers

### Creating a Collection with File Watching

```powershell
# Create a collection and start watching it for file changes
.\Initialize-Collections.ps1 -CollectionName "Documentation" -FolderPath "D:\Docs" -Watch

# Specify which types of changes to monitor
.\Initialize-Collections.ps1 -CollectionName "CodeProject" -FolderPath "D:\Projects\App" -Watch -WatchCreated -WatchModified

# Control watching behavior
.\Initialize-Collections.ps1 -CollectionName "Reports" -FolderPath "D:\Reports" -Watch -IncludeSubdirectories -ProcessInterval 30
```

### Managing Watchers for Existing Collections

```powershell
# Start watching an existing collection
.\Start-CollectionWatch.ps1 -CollectionId 1 -Action Start

# Stop watching a collection
.\Start-CollectionWatch.ps1 -CollectionName "Documentation" -Action Stop

# Restart watching with different settings
.\Start-CollectionWatch.ps1 -CollectionId 2 -Action Restart -WatchCreated -WatchModified -ProcessInterval 30
```

### Managing All Collection Watchers

```powershell
# Start all collection watchers that are enabled
.\Start-AllCollectionWatchers.ps1

# Force restart of all watchers (even if already running)
.\Start-AllCollectionWatchers.ps1 -Force
```

### Checking Watcher Status

```powershell
# Check all running watch jobs
Get-Job -Name "Watch_Collection_*"

# Stop all watch jobs
Stop-Job -Name "Watch_Collection_*"
Remove-Job -Name "Watch_Collection_*"
```

## Watch Settings

When configuring file watchers, you can control:

- **WatchCreated**: Monitor for new files created in the directory
- **WatchModified**: Monitor for existing files being modified
- **WatchDeleted**: Monitor for files being deleted
- **WatchRenamed**: Monitor for files being renamed
- **IncludeSubdirectories**: Include subdirectories in monitoring
- **ProcessInterval**: Minimum time (in seconds) between registering duplicate events
- **OmitFolders**: Specify folder names to exclude from monitoring

File watch settings are stored in the SQLite database and persist between system restarts.
