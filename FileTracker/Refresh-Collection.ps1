<#
.SYNOPSIS
    Updates the collection in the FileTracker database with information about modified or new files.
.DESCRIPTION
    This script scans the specified folder (recursively) for file changes and updates the collection in the SQLite database.
    If a file is new or modified since the last scan, it's marked as "dirty" for processing.
    Files that are in the collection but no longer in the folder are marked as deleted.
.PARAMETER CollectionName
    The name of the collection to update.
.PARAMETER FolderPath
    The path to the folder to scan for file changes.
.PARAMETER OmitFolders
    An array of folder names to exclude from file tracking. By default, ".ai" and ".git" folders are excluded.
.PARAMETER DatabasePath
    The path where the SQLite database is located. If not specified, the default database path will be used.
.EXAMPLE
    .\Update-Collection.ps1 -CollectionName "Documentation" -FolderPath "D:\MyDocuments"
.EXAMPLE
    .\Update-Collection.ps1 -CollectionName "Projects" -FolderPath "D:\Projects" -OmitFolders @(".ai", ".git", "bin", "obj")
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$CollectionName,
    
    [Parameter(Mandatory = $true)]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [string]$InstallPath, # Added mandatory InstallPath
    
    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(".git"),
    
    [Parameter(Mandatory = $false)]
    [string]$DatabasePath # Made optional override
)

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedModulePath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedModulePath -Force

# Determine Database Path
if (-not $DatabasePath) {
    $DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
    Write-Host "Using determined database path: $DatabasePath" -ForegroundColor Cyan
} else {
     Write-Host "Using provided database path: $DatabasePath" -ForegroundColor Cyan
}

# Check if the folder exists
if (-not (Test-Path -Path $FolderPath -PathType Container)) {
    Write-Error "Folder not found: $FolderPath"
    exit 1
}

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

try {
    # Get the connection to the database (pass InstallPath)
    $connection = Get-DatabaseConnection -DatabasePath $DatabasePath -InstallPath $InstallPath
    
    # Find the collection by name
    $collectionCommand = $connection.CreateCommand()
    $collectionCommand.CommandText = "SELECT id FROM collections WHERE name = @Name"
    $collectionCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Name", $CollectionName)))
    
    $collectionId = $collectionCommand.ExecuteScalar()
    
    if (-not $collectionId) {
        Write-Error "Collection '$CollectionName' not found. Please create it first using Initialize-Collections.ps1"
        exit 1
    }
    
    Write-Host "Updating collection: $CollectionName (ID: $collectionId)" -ForegroundColor Cyan
    
    # Create transaction for better performance
    $transaction = $connection.BeginTransaction()
    
    # Get all existing file paths from the database for faster lookups
    $existingFilePaths = @{}
    $existingFilesDetails = @{}
    
    $selectCommand = $connection.CreateCommand()
    $selectCommand.CommandText = "SELECT id, FilePath, LastModified FROM files WHERE collection_id = @CollectionId"
    $selectCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
    $reader = $selectCommand.ExecuteReader()
    
    while ($reader.Read()) {
        $id = $reader["id"]
        $path = $reader["FilePath"]
        $lastModified = [DateTime]::Parse($reader["LastModified"])
        
        $existingFilePaths[$path] = $true
        $existingFilesDetails[$path] = @{
            Id = $id
            LastModified = $lastModified
        }
    }
    $reader.Close()
    
    # Initialize counters for reporting
    $newFiles = 0
    $modifiedFiles = 0
    $unchangedFiles = 0
    $removedFiles = 0
    $filesProcessed = 0
    
    # Get total number of files for progress reporting
    $files = Get-ChildItem -Path $FolderPath -Recurse -File | Where-Object {
        $filePath = $_.FullName
        $exclude = $false
        
        foreach ($folder in $OmitFolders) {
            if ($filePath -like "*\$folder\*") {
                $exclude = $true
                break
            }
        }
        
        -not $exclude
    }
    
    $totalFiles = $files.Count
    Write-Host "Found $totalFiles files to process" -ForegroundColor Yellow
    
    # Track current files for detecting removed files
    $currentFilePaths = @{}
    
    # Prepare statements
    $updateCommand = $connection.CreateCommand()
    $updateCommand.CommandText = "UPDATE files SET LastModified = @LastModified, Dirty = 1, Deleted = 0 WHERE id = @Id"
    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", [DBNull]::Value)))
    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", [DBNull]::Value)))
    
    $insertCommand = $connection.CreateCommand()
    $insertCommand.CommandText = "INSERT INTO files (FilePath, OriginalUrl, LastModified, Dirty, Deleted, collection_id) VALUES (@FilePath, NULL, @LastModified, 1, 0, @CollectionId)"
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", [DBNull]::Value)))
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", [DBNull]::Value)))
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
    
    $markDeleteCommand = $connection.CreateCommand()
    $markDeleteCommand.CommandText = "UPDATE files SET Deleted = 1 WHERE id = @Id"
    $markDeleteCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", [DBNull]::Value)))
    
    # Process the filtered files
    $files | ForEach-Object {
        $filePath = $_.FullName
        $lastModified = $_.LastWriteTime
        $lastModifiedStr = $lastModified.ToString("o") # ISO 8601 format
        
        # Add to current files tracking
        $currentFilePaths[$filePath] = $true
        
        # Update progress
        $filesProcessed++
        Write-Progress -Activity "Updating Collection" -Status "Processing files" -PercentComplete (($filesProcessed / $totalFiles) * 100)
        
        # Check if file exists in the database
        if ($existingFilePaths.ContainsKey($filePath)) {
            # Get the existing file details
            $existingFile = $existingFilesDetails[$filePath]
            $existingLastModified = $existingFile.LastModified
            
            # Check if the file has been modified
            if ($lastModified -gt $existingLastModified) {
                # File has been modified, update it and set Dirty to true
                $updateCommand.Parameters["@LastModified"].Value = $lastModifiedStr
                $updateCommand.Parameters["@Id"].Value = $existingFile.Id
                $updateCommand.ExecuteNonQuery()
                $modifiedFiles++
                Write-Verbose "Modified file: $filePath"
            }
            else {
                $unchangedFiles++
            }
        }
        else {
            # New file, insert it and set Dirty to true
            $insertCommand.Parameters["@FilePath"].Value = $filePath
            $insertCommand.Parameters["@LastModified"].Value = $lastModifiedStr
            $insertCommand.ExecuteNonQuery()
            $newFiles++
            Write-Verbose "New file: $filePath"
        }
    }
    
    # Check for removed files (files in the database but not in the current scan)
    foreach ($existingFilePath in $existingFilePaths.Keys) {
        if (-not $currentFilePaths.ContainsKey($existingFilePath)) {
            # File is missing - mark as deleted
            $markDeleteCommand.Parameters["@Id"].Value = $existingFilesDetails[$existingFilePath].Id
            $markDeleteCommand.ExecuteNonQuery()
            $removedFiles++
            Write-Verbose "Marked as deleted: $existingFilePath"
        }
    }
    
    # Update the collection's updated_at timestamp
    $updateCollectionCommand = $connection.CreateCommand()
    $updateCollectionCommand.CommandText = "UPDATE collections SET updated_at = @UpdatedAt WHERE id = @Id"
    $updateCollectionCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", [DateTime]::UtcNow.ToString("o"))))
    $updateCollectionCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $collectionId)))
    $updateCollectionCommand.ExecuteNonQuery()
    
    # Commit transaction
    $transaction.Commit()
    
    Write-Progress -Activity "Updating Collection" -Completed
    
    # Report summary
    Write-Host "Collection Update Summary:" -ForegroundColor Green
    Write-Host "New files: $newFiles" -ForegroundColor Cyan
    Write-Host "Modified files: $modifiedFiles" -ForegroundColor Yellow
    Write-Host "Unchanged files: $unchangedFiles" -ForegroundColor Gray
    Write-Host "Missing files (marked as deleted): $removedFiles" -ForegroundColor Magenta
    
    if ($OmitFolders.Count -gt 0) {
        Write-Host "Omitted folders: {$($OmitFolders -join ', ')}" -ForegroundColor Yellow
    }
    
    # Report files to process
    $toDirtyCommand = $connection.CreateCommand()
    $toDirtyCommand.CommandText = "SELECT COUNT(*) FROM files WHERE Dirty = 1 AND collection_id = @CollectionId"
    $toDirtyCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
    $filesToProcessCount = $toDirtyCommand.ExecuteScalar()
    
    Write-Host "Files to process: $filesToProcessCount" -ForegroundColor Green
    
    if ($filesToProcessCount -gt 0 -and $filesToProcessCount -le 20) {
        Write-Host "Files marked as dirty:" -ForegroundColor Green
        
        $listProcessCommand = $connection.CreateCommand()
        $listProcessCommand.CommandText = "SELECT FilePath FROM files WHERE Dirty = 1 AND collection_id = @CollectionId"
        $listProcessCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
        $reader = $listProcessCommand.ExecuteReader()
        
        while ($reader.Read()) {
            Write-Host " - $($reader["FilePath"])" -ForegroundColor Cyan
        }
        $reader.Close()
    }
    
    # Report files marked for deletion
    $toDeleteCommand = $connection.CreateCommand()
    $toDeleteCommand.CommandText = "SELECT COUNT(*) FROM files WHERE Deleted = 1 AND collection_id = @CollectionId"
    $toDeleteCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
    $filesToDeleteCount = $toDeleteCommand.ExecuteScalar()
    
    if ($filesToDeleteCount -gt 0 -and $filesToDeleteCount -le 20) {
        Write-Host "Files marked as deleted (missing from folder): $filesToDeleteCount" -ForegroundColor Magenta
        
        $listDeleteCommand = $connection.CreateCommand()
        $listDeleteCommand.CommandText = "SELECT FilePath FROM files WHERE Deleted = 1 AND collection_id = @CollectionId"
        $listDeleteCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
        $reader = $listDeleteCommand.ExecuteReader()
        
        while ($reader.Read()) {
            Write-Host " - $($reader["FilePath"])" -ForegroundColor Magenta
        }
        $reader.Close()
    }
}
catch {
    if ($transaction) {
        $transaction.Rollback()
    }
    Write-Error "Error updating collection: $_"
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
