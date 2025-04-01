<#
.SYNOPSIS
    Starts, stops, or restarts file watching for an existing collection.
.DESCRIPTION
    This script manages file watching for an existing collection in the FileTracker database.
    It can start a new watch job, stop an existing one, or restart watching with updated parameters.
.PARAMETER CollectionId
    The ID of the collection to manage watching for.
.PARAMETER CollectionName
    The name of the collection to manage watching for. Either CollectionId or CollectionName must be specified.
.PARAMETER Action
    The action to perform: Start, Stop, or Restart. Default is Start.
.PARAMETER WatchCreated
    If true, monitor for created files. Default is true.
.PARAMETER WatchModified
    If true, monitor for modified files. Default is true.
.PARAMETER WatchDeleted
    If true, monitor for deleted files. Default is true.
.PARAMETER WatchRenamed
    If true, monitor for renamed files. Default is true.
.PARAMETER IncludeSubdirectories
    If true, include subdirectories in file monitoring. Default is true.
.PARAMETER ProcessInterval
    The interval in seconds between checking for duplicate events. Default is 15.
.PARAMETER OmitFolders
    An array of folder names to exclude from file tracking. By default, ".ai" and ".git" folders are excluded.
.PARAMETER DatabasePath
    The path where the SQLite database is located. If not specified, the default database path will be used.
.EXAMPLE
    .\Start-CollectionWatch.ps1 -CollectionId 1 -Action Start
    # Starts watching for collection with ID 1 using default settings
.EXAMPLE
    .\Start-CollectionWatch.ps1 -CollectionName "Documentation" -Action Stop
    # Stops watching for the collection named "Documentation"
.EXAMPLE
    .\Start-CollectionWatch.ps1 -CollectionId 2 -Action Restart -WatchCreated -WatchModified -ProcessInterval 30
    # Restarts watching for collection with ID 2, only monitoring for created and modified files, checking every 30 seconds
#>

param (
    [Parameter(Mandatory = $false)]
    [int]$CollectionId,
    
    [Parameter(Mandatory = $false)]
    [string]$CollectionName,
    
    [Parameter(Mandatory = $false)]
    [string]$Action = "Start",
    
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
    [int]$ProcessInterval = 15,
    
    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(),

    [Parameter(Mandatory = $true)]
    [string]$InstallPath
)

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedPath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedPath -Force
$sqliteAssemblyPath = "$InstallPath\Microsoft.Data.Sqlite.dll"
$sqliteAssemblyPath2 = "$InstallPath\SQLitePCLRaw.core.dll"
$sqliteAssemblyPath3 = "$InstallPath\SQLitePCLRaw.provider.e_sqlite3.dll"

# Load SQLite assembly
Add-Type -Path $sqliteAssemblyPath
Add-Type -Path $sqliteAssemblyPath2
Add-Type -Path $sqliteAssemblyPath3

$DatabasePath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"

# Get collection by name if needed
if ($CollectionName) {
    $collections = Get-Collections -DatabasePath $DatabasePath
    $collection = $collections | Where-Object { $_.name -eq $CollectionName }
    
    if (-not $collection) {
        Write-Error "Collection with name '$CollectionName' not found."
        exit 1
    }
    
    $CollectionId = $collection.id
    Write-Host "Found collection '$CollectionName' with ID: $CollectionId" -ForegroundColor Green
}

# Get collection details
$collection = Get-Collection -Id $CollectionId -DatabasePath $DatabasePath
if (-not $collection) {
    Write-Error "Collection with ID $CollectionId not found."
    exit 1
}

# Functions for managing watch settings and jobs
function Get-WatchSettings {
    param (
        [int]$CollectionId,
        [string]$DatabasePath
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Generate a unique key for this collection's watch settings
        $watchKey = "collection_${CollectionId}_watch"
        
        # Get settings
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT value FROM settings WHERE key = @Key"
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Key", $watchKey)))
        
        $settings = $command.ExecuteScalar()
        
        $connection.Close()
        $connection.Dispose()
        
        if ($settings) {
            return ConvertFrom-Json $settings
        }
        
        return $null
    }
    catch {
        Write-Error "Error getting watch settings: $_"
        return $null
    }
}

function Save-WatchSettings {
    param (
        [int]$CollectionId,
        [PSCustomObject]$Settings,
        [string]$DatabasePath
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Generate a unique key for this collection's watch settings
        $watchKey = "collection_${CollectionId}_watch"
        
        # Convert to JSON
        $settingsJson = ConvertTo-Json $Settings -Compress
        
        # Store in database
        $command = $connection.CreateCommand()
        $command.CommandText = "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (@Key, @Value, @UpdatedAt)"
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Key", $watchKey)))
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Value", $settingsJson)))
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", [DateTime]::UtcNow.ToString("o"))))
        $command.ExecuteNonQuery()
        
        $connection.Close()
        $connection.Dispose()
        
        return $true
    }
    catch {
        Write-Error "Error saving watch settings: $_"
        return $false
    }
}

function Start-WatchJob {
    param (
        [int]$CollectionId,
        [string]$FolderPath,
        [bool]$WatchCreated,
        [bool]$WatchModified,
        [bool]$WatchDeleted,
        [bool]$WatchRenamed,
        [bool]$IncludeSubdirectories,
        [int]$ProcessInterval,
        [string[]]$OmitFolders,
        [string]$FileFilter = "*.*",
        [string]$DatabasePath
    )
    
    # Get the path to the Watch-FileTracker.ps1 script
    $watchScriptPath = Join-Path -Path $scriptParentPath -ChildPath "Watch-FileTracker.ps1"
    
    # Build watch parameters
    $watchParams = @{
        DirectoryToWatch = $FolderPath
        WatchCreated = $WatchCreated
        WatchModified = $WatchModified
        WatchDeleted = $WatchDeleted
        WatchRenamed = $WatchRenamed
        IncludeSubdirectories = $IncludeSubdirectories
        ProcessInterval = $ProcessInterval
        OmitFolders = $OmitFolders
    }
    
    if ($FileFilter -ne "*.*") {
        $watchParams["FileFilter"] = $FileFilter
    }
    
    # Start the job
    $job = Start-Job -Name "Watch_Collection_$CollectionId" -ScriptBlock {
        param($scriptPath, $params)
        & $scriptPath @params
    } -ArgumentList $watchScriptPath, $watchParams
    
    return $job
}

function Stop-WatchJob {
    param (
        [int]$CollectionId
    )
    
    $watchJob = Get-Job -Name "Watch_Collection_$CollectionId" -ErrorAction SilentlyContinue
    
    if ($watchJob) {
        Stop-Job -Id $watchJob.Id
        Remove-Job -Id $watchJob.Id
        return $true
    }
    
    return $false
}

# Main script logic
try {
    # Check for existing watch job
    $watchJob = Get-Job -Name "Watch_Collection_$CollectionId" -ErrorAction SilentlyContinue
    $isWatching = $null -ne $watchJob
    
    # Get existing watch settings if available
    $existingSettings = Get-WatchSettings -CollectionId $CollectionId -DatabasePath $DatabasePath
    
    # Determine FileFilter based on collection's include_extensions
    $fileFilter = "*.*"
    if ($collection.include_extensions) {
        $includeExtensions = $collection.include_extensions -split "," | ForEach-Object { $_.Trim() }
        $fileFilterPatterns = $includeExtensions | ForEach-Object { "*$_" }
        $fileFilter = $fileFilterPatterns -join ", "
    }
    
    # Handle different actions
    switch ($Action) {
        "Stop" {
            if ($isWatching) {
                Write-Host "Stopping file watch job for collection '$($collection.name)'..." -ForegroundColor Cyan
                $stopped = Stop-WatchJob -CollectionId $CollectionId
                
                if ($stopped) {
                    # Update settings in database to show watch is disabled
                    if ($existingSettings) {
                        $existingSettings.enabled = $false
                        Save-WatchSettings -CollectionId $CollectionId -Settings $existingSettings -DatabasePath $DatabasePath
                    }
                    
                    Write-Host "File watching stopped for collection '$($collection.name)'." -ForegroundColor Green
                }
                else {
                    Write-Warning "Failed to stop watch job for collection."
                }
            }
            else {
                Write-Host "Collection '$($collection.name)' is not currently being watched." -ForegroundColor Yellow
            }
        }
        
        "Restart" {
            # Stop existing job if running
            if ($isWatching) {
                Write-Host "Stopping existing file watch job for collection '$($collection.name)'..." -ForegroundColor Cyan
                $stopped = Stop-WatchJob -CollectionId $CollectionId
                
                if (-not $stopped) {
                    Write-Warning "Failed to stop existing watch job for collection."
                }
            }
            
            # Fall through to Start case to start a new job
        }
        
        "Start" {
            if ($isWatching -and $Action -eq "Start") {
                Write-Host "Collection '$($collection.name)' is already being watched. Use -Action Restart to restart watching." -ForegroundColor Yellow
                break
            }
            
            # Create new watch settings
            $watchSettings = @{
                enabled = $true
                watchCreated = [bool]$WatchCreated
                watchModified = [bool]$WatchModified
                watchDeleted = [bool]$WatchDeleted
                watchRenamed = [bool]$WatchRenamed
                includeSubdirectories = [bool]$IncludeSubdirectories
                processInterval = $ProcessInterval
                omitFolders = $OmitFolders
            }

            # Save settings to database
            $saved = Save-WatchSettings -CollectionId $CollectionId -Settings $watchSettings -DatabasePath $DatabasePath
            
            if (-not $saved) {
                Write-Error "Failed to save watch settings to database."
                exit 1
            }
            
            Write-Host "Starting file watcher for collection '$($collection.name)'..." -ForegroundColor Cyan
            
            # Start the watch job
            $job = Start-WatchJob -CollectionId $CollectionId `
                                 -FolderPath $collection.source_folder `
                                 -WatchCreated $watchSettings.watchCreated `
                                 -WatchModified $watchSettings.watchModified `
                                 -WatchDeleted $watchSettings.watchDeleted `
                                 -WatchRenamed $watchSettings.watchRenamed `
                                 -IncludeSubdirectories $watchSettings.includeSubdirectories `
                                 -ProcessInterval $watchSettings.processInterval `
                                 -OmitFolders $watchSettings.omitFolders `
                                 -FileFilter $fileFilter `
                                 -DatabasePath $DatabasePath
            
            Write-Host "File watcher job started with ID: $($job.Id)" -ForegroundColor Green
            Write-Host "Monitoring for file changes: " -NoNewline
            
            $watchTypes = @()
            if ($watchSettings.watchCreated) { $watchTypes += "Created" }
            if ($watchSettings.watchModified) { $watchTypes += "Modified" }
            if ($watchSettings.watchDeleted) { $watchTypes += "Deleted" }
            if ($watchSettings.watchRenamed) { $watchTypes += "Renamed" }
            
            Write-Host ($watchTypes -join ", ") -ForegroundColor Yellow
            
            if ($watchSettings.includeSubdirectories) {
                Write-Host "Including subdirectories in monitoring." -ForegroundColor Cyan
            }
            
            Write-Host "Using process interval: $($watchSettings.processInterval) seconds" -ForegroundColor Cyan
            Write-Host "Excluding folders: $($watchSettings.omitFolders -join ', ')" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Error "Error managing collection watch: $_"
    exit 1
}
