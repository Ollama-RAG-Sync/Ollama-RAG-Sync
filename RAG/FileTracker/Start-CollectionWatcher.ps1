<#
.SYNOPSIS
    Starts a file system watcher for a specific collection.
.DESCRIPTION
    This script starts a FileSystemWatcher that monitors the collection's source folder for file changes.
    When files are created, modified, deleted, or renamed, the watcher automatically marks them as dirty
    in the FileTracker database so they can be processed.
    
    The watcher runs as a background job and can monitor changes in real-time.
.PARAMETER CollectionId
    The ID of the collection to watch.
.PARAMETER CollectionName
    The name of the collection to watch (alternative to CollectionId).
.PARAMETER InstallPath
    The path to the installation directory containing the database and assemblies.
.PARAMETER DatabasePath
    Optional override for the database path.
.EXAMPLE
    .\Start-CollectionWatcher.ps1 -CollectionName "Documents" -InstallPath "C:\FileTracker"
    Starts watching the "Documents" collection for file changes.
.EXAMPLE
    .\Start-CollectionWatcher.ps1 -CollectionId 1 -InstallPath "C:\FileTracker"
    Starts watching the collection with ID 1 for file changes.
.NOTES
    The watcher runs as a background job. Use Get-FileTrackerStatus to see active watchers.
    Use Stop-CollectionWatcher to stop a running watcher.
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
    [string]$DatabasePath
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
    
    $sourceFolder = $collection.source_folder
    $includeExtensions = $collection.include_extensions
    $excludeFolders = $collection.exclude_folders
    
    # Validate source folder exists
    if (-not (Test-Path -Path $sourceFolder -PathType Container)) {
        Write-Error "Source folder does not exist: $sourceFolder"
        exit 1
    }
    
    Write-Host "Collection: $($collection.name) (ID: $CollectionId)" -ForegroundColor Green
    Write-Host "Source Folder: $sourceFolder" -ForegroundColor Cyan
    if ($includeExtensions) {
        Write-Host "Include Extensions: $includeExtensions" -ForegroundColor Cyan
    }
    if ($excludeFolders) {
        Write-Host "Exclude Folders: $excludeFolders" -ForegroundColor Cyan
    }
    
    # Check if a watcher is already running for this collection
    $existingJob = Get-Job -Name "Watch_Collection_$CollectionId" -ErrorAction SilentlyContinue
    if ($existingJob) {
        if ($existingJob.State -eq 'Running') {
            Write-Warning "A watcher is already running for collection '$($collection.name)' (ID: $CollectionId)."
            Write-Host "Job ID: $($existingJob.Id), State: $($existingJob.State)" -ForegroundColor Yellow
            Write-Host "Use Stop-CollectionWatcher to stop it first if you want to restart." -ForegroundColor Yellow
            exit 0
        }
        else {
            # Clean up old job
            Write-Host "Removing old watcher job (State: $($existingJob.State))..." -ForegroundColor Yellow
            Remove-Job -Id $existingJob.Id -Force
        }
    }
    
    # Parse exclude folders if provided
    $excludeFoldersList = @()
    if ($excludeFolders) {
        $excludeFoldersList = $excludeFolders -split ',' | ForEach-Object { $_.Trim() }
    }
    
    # Parse include extensions if provided
    $includeExtensionsList = @()
    if ($includeExtensions) {
        $includeExtensionsList = $includeExtensions -split ',' | ForEach-Object { $_.Trim() }
    }
    
    # Create the watcher script block
    $watcherScriptBlock = {
        param (
            $CollectionId,
            $CollectionName,
            $SourceFolder,
            $DatabasePath,
            $InstallPath,
            $ExcludeFolders,
            $IncludeExtensions,
            $DatabaseModulePath
        )
        
        # Import database module in the background job
        Import-Module -Name $DatabaseModulePath -Force -Global
        
        # Function to check if a file should be tracked
        function Test-ShouldTrackFile {
            param (
                [string]$FilePath,
                [string]$SourceFolder,
                [string[]]$ExcludeFolders,
                [string[]]$IncludeExtensions
            )
            
            # Check if file is in excluded folder
            if ($ExcludeFolders -and $ExcludeFolders.Count -gt 0) {
                $relativePath = $FilePath.Substring($SourceFolder.Length).TrimStart('\', '/')
                foreach ($folder in $ExcludeFolders) {
                    $folderPath = $folder.Replace('/', '\').TrimEnd('\')
                    if ($relativePath.StartsWith($folderPath + '\') -or $relativePath -eq $folderPath) {
                        return $false
                    }
                }
            }
            
            # Check if file has allowed extension
            if ($IncludeExtensions -and $IncludeExtensions.Count -gt 0) {
                $extension = [System.IO.Path]::GetExtension($FilePath)
                if ($extension -and $IncludeExtensions -notcontains $extension) {
                    return $false
                }
            }
            
            return $true
        }
        
        # Function to mark file as dirty
        function Set-FileDirty {
            param (
                [string]$FilePath,
                [int]$CollectionId,
                [string]$DatabasePath,
                [string]$InstallPath
            )
            
            try {
                # Get database connection
                $connection = Get-DatabaseConnection -DatabasePath $DatabasePath -InstallPath $InstallPath
                
                # Check if file exists in database
                $checkCommand = $connection.CreateCommand()
                $checkCommand.CommandText = "SELECT id, Deleted FROM files WHERE FilePath = @FilePath AND collection_id = @CollectionId"
                $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath))) | Out-Null
                $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId))) | Out-Null
                
                $reader = $checkCommand.ExecuteReader()
                
                if ($reader.Read()) {
                    # File exists, update it
                    $fileId = $reader.GetInt32(0)
                    $reader.Close()
                    
                    # Update file as dirty and not deleted if it exists on disk
                    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
                        $lastModified = (Get-Item -LiteralPath $FilePath).LastWriteTime.ToString("o")
                        $updateCommand = $connection.CreateCommand()
                        $updateCommand.CommandText = "UPDATE files SET LastModified = @LastModified, Dirty = 1, Deleted = 0 WHERE id = @Id"
                        $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", $lastModified))) | Out-Null
                        $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $fileId))) | Out-Null
                        $updateCommand.ExecuteNonQuery() | Out-Null
                        
                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Updated: $FilePath" -ForegroundColor Green
                    }
                }
                else {
                    $reader.Close()
                    
                    # File doesn't exist in database, add it if it exists on disk
                    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
                        $lastModified = (Get-Item -LiteralPath $FilePath).LastWriteTime.ToString("o")
                        $insertCommand = $connection.CreateCommand()
                        $insertCommand.CommandText = "INSERT INTO files (FilePath, OriginalUrl, LastModified, Dirty, Deleted, collection_id) VALUES (@FilePath, NULL, @LastModified, 1, 0, @CollectionId)"
                        $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath))) | Out-Null
                        $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", $lastModified))) | Out-Null
                        $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId))) | Out-Null
                        $insertCommand.ExecuteNonQuery() | Out-Null
                        
                        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Added: $FilePath" -ForegroundColor Cyan
                    }
                }
            }
            catch {
                Write-Warning "[$(Get-Date -Format 'HH:mm:ss')] Error updating file $FilePath : $_"
            }
            finally {
                if ($connection) {
                    $connection.Close()
                    $connection.Dispose()
                }
            }
        }
        
        # Function to mark file as deleted
        function Set-FileDeleted {
            param (
                [string]$FilePath,
                [int]$CollectionId,
                [string]$DatabasePath,
                [string]$InstallPath
            )
            
            try {
                # Get database connection
                $connection = Get-DatabaseConnection -DatabasePath $DatabasePath -InstallPath $InstallPath
                
                # Mark file as deleted
                $updateCommand = $connection.CreateCommand()
                $updateCommand.CommandText = "UPDATE files SET Deleted = 1 WHERE FilePath = @FilePath AND collection_id = @CollectionId"
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath))) | Out-Null
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId))) | Out-Null
                $rowsAffected = $updateCommand.ExecuteNonQuery()
                
                if ($rowsAffected -gt 0) {
                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Deleted: $FilePath" -ForegroundColor Magenta
                }
            }
            catch {
                Write-Warning "[$(Get-Date -Format 'HH:mm:ss')] Error marking file as deleted $FilePath : $_"
            }
            finally {
                if ($connection) {
                    $connection.Close()
                    $connection.Dispose()
                }
            }
        }
        
        Write-Host "==================================================" -ForegroundColor Yellow
        Write-Host "File Watcher Started for Collection: $CollectionName (ID: $CollectionId)" -ForegroundColor Green
        Write-Host "Watching: $SourceFolder" -ForegroundColor Cyan
        Write-Host "Press Ctrl+C or use Stop-CollectionWatcher to stop" -ForegroundColor Yellow
        Write-Host "==================================================" -ForegroundColor Yellow
        
        # Create FileSystemWatcher
        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $SourceFolder
        $watcher.IncludeSubdirectories = $true
        $watcher.EnableRaisingEvents = $true
        
        # Set filters for all file changes
        $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor 
                                [System.IO.NotifyFilters]::LastWrite -bor 
                                [System.IO.NotifyFilters]::CreationTime
        
        # Register event handlers
        $onCreated = Register-ObjectEvent -InputObject $watcher -EventName Created -Action {
            $filePath = $Event.SourceEventArgs.FullPath
            
            if (Test-ShouldTrackFile -FilePath $filePath -SourceFolder $SourceFolder -ExcludeFolders $ExcludeFolders -IncludeExtensions $IncludeExtensions) {
                # Small delay to ensure file is ready
                Start-Sleep -Milliseconds 100
                Set-FileDirty -FilePath $filePath -CollectionId $CollectionId -DatabasePath $DatabasePath -InstallPath $InstallPath
            }
        }
        
        $onChanged = Register-ObjectEvent -InputObject $watcher -EventName Changed -Action {
            $filePath = $Event.SourceEventArgs.FullPath
            
            if (Test-ShouldTrackFile -FilePath $filePath -SourceFolder $SourceFolder -ExcludeFolders $ExcludeFolders -IncludeExtensions $IncludeExtensions) {
                Set-FileDirty -FilePath $filePath -CollectionId $CollectionId -DatabasePath $DatabasePath -InstallPath $InstallPath
            }
        }
        
        $onDeleted = Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action {
            $filePath = $Event.SourceEventArgs.FullPath
            
            if (Test-ShouldTrackFile -FilePath $filePath -SourceFolder $SourceFolder -ExcludeFolders $ExcludeFolders -IncludeExtensions $IncludeExtensions) {
                Set-FileDeleted -FilePath $filePath -CollectionId $CollectionId -DatabasePath $DatabasePath -InstallPath $InstallPath
            }
        }
        
        $onRenamed = Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action {
            $oldPath = $Event.SourceEventArgs.OldFullPath
            $newPath = $Event.SourceEventArgs.FullPath
            
            # Mark old file as deleted
            if (Test-ShouldTrackFile -FilePath $oldPath -SourceFolder $SourceFolder -ExcludeFolders $ExcludeFolders -IncludeExtensions $IncludeExtensions) {
                Set-FileDeleted -FilePath $oldPath -CollectionId $CollectionId -DatabasePath $DatabasePath -InstallPath $InstallPath
            }
            
            # Add new file
            if (Test-ShouldTrackFile -FilePath $newPath -SourceFolder $SourceFolder -ExcludeFolders $ExcludeFolders -IncludeExtensions $IncludeExtensions) {
                Set-FileDirty -FilePath $newPath -CollectionId $CollectionId -DatabasePath $DatabasePath -InstallPath $InstallPath
            }
            
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Renamed: $oldPath -> $newPath" -ForegroundColor Yellow
        }
        
        # Keep the watcher running
        try {
            while ($true) {
                Start-Sleep -Seconds 1
            }
        }
        finally {
            # Clean up
            Unregister-Event -SourceIdentifier $onCreated.Name
            Unregister-Event -SourceIdentifier $onChanged.Name
            Unregister-Event -SourceIdentifier $onDeleted.Name
            Unregister-Event -SourceIdentifier $onRenamed.Name
            $watcher.Dispose()
            
            Write-Host "File Watcher Stopped for Collection: $CollectionName (ID: $CollectionId)" -ForegroundColor Red
        }
    }
    
    # Start the watcher as a background job
    $job = Start-Job -Name "Watch_Collection_$CollectionId" -ScriptBlock $watcherScriptBlock -ArgumentList @(
        $CollectionId,
        $collection.name,
        $sourceFolder,
        $DatabasePath,
        $InstallPath,
        $excludeFoldersList,
        $includeExtensionsList,
        $databaseSharedModulePath
    )
    
    # Wait a moment to check if job started successfully
    Start-Sleep -Seconds 2
    
    $jobStatus = Get-Job -Id $job.Id
    
    if ($jobStatus.State -eq 'Running') {
        Write-Host ""
        Write-Host "File watcher started successfully!" -ForegroundColor Green
        Write-Host "Job ID: $($job.Id)" -ForegroundColor Cyan
        Write-Host "Job Name: $($job.Name)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Use the following commands to manage the watcher:" -ForegroundColor Yellow
        Write-Host "  - View watcher output: Receive-Job -Id $($job.Id) -Keep" -ForegroundColor Gray
        Write-Host "  - Check watcher status: Get-Job -Id $($job.Id)" -ForegroundColor Gray
        Write-Host "  - Stop watcher: Stop-CollectionWatcher -CollectionId $CollectionId -InstallPath '$InstallPath'" -ForegroundColor Gray
        Write-Host "  - View all watchers: Get-FileTrackerStatus -InstallPath '$InstallPath'" -ForegroundColor Gray
    }
    else {
        Write-Error "Failed to start watcher. Job state: $($jobStatus.State)"
        if ($jobStatus.State -eq 'Failed') {
            Write-Error "Job error: $(Receive-Job -Id $job.Id 2>&1)"
        }
        exit 1
    }
}
catch {
    Write-Error "Error starting collection watcher: $_"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
