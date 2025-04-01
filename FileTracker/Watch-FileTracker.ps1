# File Tracker Watcher Script
# This script monitors a specified directory for file changes and updates a SQLite database for file processing

param (
    [Parameter(Mandatory = $true)]
    [string]$DirectoryToWatch,
    
    [Parameter(Mandatory = $false)]
    [string]$FileFilter = "*.*",

    [Parameter(Mandatory = $false)]
    [switch]$WatchCreated = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$WatchModified = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$WatchDeleted = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$WatchRenamed = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeSubdirectories = $false,

    [Parameter(Mandatory = $false)]
    [switch]$ProcessExistingFiles = $false,
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "",

    [Parameter(Mandatory = $false)]
    [int]$ProcessInterval = 15,
    
    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(),
    
    [Parameter(Mandatory = $false)]
    [int]$CollectionId,
    
    [Parameter(Mandatory = $false)]
    [string]$InstallPath
)

# Ensure the directory exists
if (-not (Test-Path -Path $DirectoryToWatch)) {
    Write-Error "Directory $DirectoryToWatch does not exist."
    exit 1
}

# Setup logging
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage
    
    if ($LogPath -ne "") {
        Add-Content -Path $LogPath -Value $logMessage
    }
}

# Import shared modules
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

$fileTrackerDir = Join-Path -Path $InstallPath -ChildPath "FileTracker"
$databasePath = Join-Path -Path $fileTrackerDir -ChildPath "Collection_$CollectionId.db"

# Import shared module for file tracking functions
$sharedModulePath = Join-Path -Path $scriptParentPath -ChildPath "FileTracker-Shared.psm1"
Import-Module -Name $sharedModulePath -Force

# Add type for SQLite handling - based on Initialize-FileProcessingTracker.ps1
$sqliteAssemblyPath = Join-Path -Path $InstallPath -ChildPath "Microsoft.Data.Sqlite.dll"
$sqliteAssemblyPath2 = Join-Path -Path $InstallPath -ChildPath "SQLitePCLRaw.core.dll"
$sqliteAssemblyPath3 = Join-Path -Path $InstallPath -ChildPath "SQLitePCLRaw.provider.e_sqlite3.dll"

try {
    # Load SQLite assemblies
    Add-Type -Path $sqliteAssemblyPath
    Add-Type -Path $sqliteAssemblyPath2
    Add-Type -Path $sqliteAssemblyPath3
}
catch {
    Write-Error "Failed to load SQLite assemblies: $_"
    exit 1
}

# Function to check if database exists and is initialized
function Test-DatabaseInitialized {
    param (
        [string]$DatabasePath,
        [switch]$IsCollectionMode
    )
    
    if (-not (Test-Path -Path $DatabasePath)) {
        return $false
    }
    
    try {
        # Set SQLitePCLRaw provider
        [SQLitePCL.raw]::SetProvider([SQLitePCL.SQLite3Provider_e_sqlite3]::new())
        
        # Create connection to SQLite database
        $connectionString = "Data Source=$DatabasePath"
        $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection($connectionString)
        $connection.Open()
        
        # Test if the files table exists
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='files'"
        $result = $command.ExecuteScalar()
        
        # In collection mode, also check for the collections table
        if ($IsCollectionMode) {
            $collectionCommand = $connection.CreateCommand()
            $collectionCommand.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='collections'"
            $collectionResult = $collectionCommand.ExecuteScalar()
            
            return ($result -eq "files" -and $collectionResult -eq "collections")
        }
        
        return $result -eq "files"
    }
    catch {
        Write-Error "Error checking database: $_"
        return $false
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

# Function to update or add file to processing database
function Update-FileInDatabase {
    param (
        [string]$FilePath,
        [string]$ChangeType,
        [string]$DatabasePath,
        [int]$CollectionId = $null
    )
    
    try {
        # Set SQLitePCLRaw provider
        [SQLitePCL.raw]::SetProvider([SQLitePCL.SQLite3Provider_e_sqlite3]::new())
        
        # Create connection to SQLite database
        $connectionString = "Data Source=$DatabasePath"
        $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection($connectionString)
        $connection.Open()
        
        $transaction = $connection.BeginTransaction()
        
        # Determine if we're in collection mode
        $isCollectionMode = $null -ne $CollectionId
        $currentTime = [DateTime]::Now.ToString("o")
        
        if ($isCollectionMode) {
            # Collection mode - check if the file exists in the collection
            $checkCommand = $connection.CreateCommand()
            $checkCommand.CommandText = "SELECT COUNT(*) FROM files WHERE FilePath = @FilePath AND collection_id = @CollectionId"
            $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
            $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
            $fileExists = $checkCommand.ExecuteScalar() -gt 0
            
            if ($ChangeType -eq "Deleted") {
                if ($fileExists) {
                    # Mark file as deleted and dirty
                    $updateCommand = $connection.CreateCommand()
                    $updateCommand.CommandText = "UPDATE files SET Dirty = 1, Deleted = 1 WHERE FilePath = @FilePath AND collection_id = @CollectionId"
                    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
                    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
                    $updateCommand.ExecuteNonQuery()
                    Write-Log "File marked as to delete and to process in collection $CollectionId - $FilePath"
                }
                else {
                    # File not in database, add it
                    $insertCommand = $connection.CreateCommand()
                    $insertCommand.CommandText = "INSERT INTO files (FilePath, LastModified, Dirty, Deleted, collection_id) VALUES (@FilePath, @LastModified, 1, 1, @CollectionId)"
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", $currentTime)))
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
                    $insertCommand.ExecuteNonQuery()
                    Write-Log "Added deleted file to collection $CollectionId database (to delete and to process) - $FilePath"
                }
            }
            else {
                # For Created, Modified, Renamed - mark as to process or add to database
                if ($fileExists) {
                    # Update last modified and mark to process
                    $updateCommand = $connection.CreateCommand()
                    $updateCommand.CommandText = "UPDATE files SET LastModified = @LastModified, Dirty = 1, Deleted = 0 WHERE FilePath = @FilePath AND collection_id = @CollectionId"
                    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
                    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", $currentTime)))
                    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
                    $updateCommand.ExecuteNonQuery()
                    Write-Log "File marked as to process in collection $CollectionId - $FilePath"
                }
                else {
                    # Add new file to database
                    $insertCommand = $connection.CreateCommand()
                    $insertCommand.CommandText = "INSERT INTO files (FilePath, LastModified, Dirty, Deleted, collection_id) VALUES (@FilePath, @LastModified, 1, 0, @CollectionId)"
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", $currentTime)))
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
                    $insertCommand.ExecuteNonQuery()
                    Write-Log "Added new file to collection $CollectionId database (to process) - $FilePath"
                }
            }
        } 
        else {
            # Legacy mode (no collection) - check if the file exists in the database
            $checkCommand = $connection.CreateCommand()
            $checkCommand.CommandText = "SELECT COUNT(*) FROM files WHERE FilePath = @FilePath"
            $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
            $fileExists = $checkCommand.ExecuteScalar() -gt 0
            
            if ($ChangeType -eq "Deleted") {
                if ($fileExists) {
                    # Mark file as deleted and to process
                    $updateCommand = $connection.CreateCommand()
                    $updateCommand.CommandText = "UPDATE files SET Dirty = 1, Deleted = 1 WHERE FilePath = @FilePath"
                    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
                    $updateCommand.ExecuteNonQuery()
                    Write-Log "File marked as to delete and to process - $FilePath"
                }
                else {
                    # File not in database, add it
                    $insertCommand = $connection.CreateCommand()
                    $insertCommand.CommandText = "INSERT INTO files (FilePath, LastModified, Dirty, Deleted) VALUES (@FilePath, @LastModified, 1, 1)"
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", $currentTime)))
                    $insertCommand.ExecuteNonQuery()
                    Write-Log "Added deleted file to database (to delete and to process) - $FilePath"
                }
            }
            else {
                # For Created, Modified, Renamed - just mark as to process or add to database
                if ($fileExists) {
                    # Update last modified and mark to process
                    $updateCommand = $connection.CreateCommand()
                    $updateCommand.CommandText = "UPDATE files SET LastModified = @LastModified, Dirty = 1, Deleted = 0 WHERE FilePath = @FilePath"
                    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
                    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", $currentTime)))
                    $updateCommand.ExecuteNonQuery()
                    Write-Log "File marked as to process - $FilePath"
                }
                else {
                    # Add new file to database
                    $insertCommand = $connection.CreateCommand()
                    $insertCommand.CommandText = "INSERT INTO files (FilePath, LastModified, Dirty, Deleted) VALUES (@FilePath, @LastModified, 1, 0)"
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
                    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", $currentTime)))
                    $insertCommand.ExecuteNonQuery()
                    Write-Log "Added new file to database (to process) - $FilePath"
                }
            }
        }
        
        $transaction.Commit()
        return $true
    }
    catch {
        if ($transaction) {
            $transaction.Rollback()
        }
        Write-Error "Error updating database: $_"
        return $false
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

# Check if database is initialized
$isCollectionMode = $null -ne $CollectionId

# Conditional parameters based on collection mode
$dbCheckParams = @{
    DatabasePath = $DatabasePath
}
if ($isCollectionMode) {
    $dbCheckParams['IsCollectionMode'] = $true
}

if (-not (Test-DatabaseInitialized @dbCheckParams)) {
    if ($isCollectionMode) {
        Write-Log "Collection database not initialized. Please run Initialize-CollectionDatabase.ps1 first." -Level "ERROR"
    } else {
        Write-Log "Database not initialized. Please run Initialize-FileProcessingTracker.ps1 first." -Level "ERROR"
    }
    exit 1
}

# If in collection mode, validate the collection exists
if ($isCollectionMode) {
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT COUNT(*) FROM collections WHERE id = @CollectionId"
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
        $collectionExists = $command.ExecuteScalar() -gt 0
        $connection.Close()
        
        if (-not $collectionExists) {
            Write-Log "Collection with ID $CollectionId not found in database $DatabasePath" -Level "ERROR"
            exit 1
        }
    }
    catch {
        Write-Error "Error validating collection: $_"
        exit 1
    }
}

Write-Log "Starting directory watcher for $DirectoryToWatch"
Write-Log "Watching for file changes matching $FileFilter"
Write-Log "Press Ctrl+C to stop the watcher."

# Create a FileSystemWatcher to monitor the directory
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $DirectoryToWatch
$watcher.Filter = $FileFilter
$watcher.IncludeSubdirectories = $IncludeSubdirectories
$watcher.EnableRaisingEvents = $true

# Collection to store event handlers
$eventHandlers = @()
$recentEvents = @{}

# Function to check if path is in omitted folders
function Test-PathInOmittedFolders {
    param (
        [string]$Path,
        [string[]]$OmitFolders,
        [string]$BaseDirectory
    )
    
    if ($OmitFolders.Count -eq 0) {
        return $false
    }
    
    $relativePath = $Path
    if ($Path.StartsWith($BaseDirectory)) {
        $relativePath = $Path.Substring($BaseDirectory.Length).TrimStart('\', '/')
    }
    
    foreach ($folder in $OmitFolders) {
        # Normalize folder path
        $folderPath = $folder.Replace('/', '\').TrimEnd('\')
        
        # Check if the path starts with the omitted folder
        if ($relativePath.StartsWith($folderPath + '\') -or $relativePath -eq $folderPath) {
            return $true
        }
    }
    
    return $false
}

$scriptBlock = {
    try {
        $path = $Event.SourceEventArgs.FullPath
        $changeType = $Event.SourceEventArgs.ChangeType
        $events = $Event.MessageData.RecentEvents
        $interval = $Event.MessageData.ProcessInterval
        $dbPath = $Event.MessageData.DatabasePath
        $updateFileFunc = $Event.MessageData.UpdateFileFunction
        $omitFolders = $Event.MessageData.OmitFolders
        $baseDir = $Event.MessageData.BaseDirectory
        $testOmitFunc = $Event.MessageData.TestOmitFunction
        $collectionId = $Event.MessageData.CollectionId

        $eventKey = "$changeType|$path"
        $isDuplicate = $false
        if ($events.ContainsKey($eventKey)) {
            $lastTime = $events[$eventKey]
            $timeDiff = (Get-Date) - $lastTime
            if ($timeDiff.TotalSeconds -lt $interval) {
                $isDuplicate = $true
            }
        }
        
        # Check if the file is in an omitted folder
        $isOmitted = & $testOmitFunc -Path $path -OmitFolders $omitFolders -BaseDirectory $baseDir
        
        if ($isOmitted) {
            Write-Host "Skipping file in omitted folder: $path" -ForegroundColor Yellow
            return
        }

        if ($isDuplicate -eq $false) {
            $collectionInfo = if ($collectionId) { " in collection $collectionId" } else { "" }
            Write-Host "Processing event: $changeType for $path$collectionInfo"
            
            # Handle the event based on change type
            $result = & $updateFileFunc -FilePath $path -ChangeType $changeType -DatabasePath $dbPath -CollectionId $collectionId
            if ($result) {
                Write-Host "Successfully updated database for: $path ($changeType)$collectionInfo"
            }
            else {
                Write-Host "Failed to update database for: $path ($changeType)$collectionInfo" -ForegroundColor Red
            }
            $events[$eventKey] = Get-Date
        }
        else {
            Write-Host "Duplicate event detected: $eventKey" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error in event handler: $_" -ForegroundColor Red
    }
}

$data = @{
    RecentEvents = $recentEvents
    ProcessInterval = $ProcessInterval
    DatabasePath = $DatabasePath
    UpdateFileFunction = ${function:Update-FileInDatabase}
    OmitFolders = $OmitFolders
    BaseDirectory = $DirectoryToWatch
    TestOmitFunction = ${function:Test-PathInOmittedFolders}
    CollectionId = $CollectionId
}

if ($WatchCreated) {
    $onCreated = Register-ObjectEvent -InputObject $watcher -EventName Created -Action $scriptBlock -MessageData $data
    $eventHandlers += $onCreated
    Write-Log "Watching for Created events."
}

if ($WatchModified) {
    $onChanged = Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $scriptBlock -MessageData $data
    $eventHandlers += $onChanged
    Write-Log "Watching for Modified events."
}

if ($WatchDeleted) {
    $onDeleted = Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $scriptBlock -MessageData $data
    $eventHandlers += $onDeleted
    Write-Log "Watching for Deleted events."
}

if ($WatchRenamed) {
    $onRenamed = Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $scriptBlock -MessageData $data
    $eventHandlers += $onRenamed
    Write-Log "Watching for Renamed events."
}

# Keep the script running until Ctrl+C is pressed
try {
    Write-Log "Watcher started successfully. Waiting for events..."
    Write-Log "Using database: $DatabasePath"

    # Display collection info if in collection mode
    if ($CollectionId) {
        Write-Host "Monitoring for collection ID: $CollectionId" -ForegroundColor Cyan
        Write-Log "Monitoring for collection ID: $CollectionId"
    }
    
    # Create a summary of what's being watched
    $watchEvents = @()
    if ($WatchCreated) { $watchEvents += "Created" }
    if ($WatchModified) { $watchEvents += "Modified" }
    if ($WatchDeleted) { $watchEvents += "Deleted" }
    if ($WatchRenamed) { $watchEvents += "Renamed" }
    
    Write-Log "Monitoring for events: {$($watchEvents -join ', ')}"
    if ($IncludeSubdirectories) {
        Write-Log "Including subdirectories in watch"
    }
    
    if ($OmitFolders.Count -gt 0) {
        Write-Log "Omitting folders: {$($OmitFolders -join ', ')}"
    }
    
    while ($true) { Start-Sleep -Seconds 1 }
} 
finally {
    # Clean up event handlers when the script is stopped
    foreach ($handler in $eventHandlers) {
        Unregister-Event -SourceIdentifier $handler.Name
    }
    $watcher.Dispose()
    Write-Log "Watcher stopped."
}
