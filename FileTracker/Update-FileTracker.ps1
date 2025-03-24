<#
.SYNOPSIS
    Updates the SQLite database with information about modified or new files.
.DESCRIPTION
    This script scans the specified folder (recursively) for file changes and updates the SQLite database.
    If a file is new or modified since the last scan, its "Dirty" flag is set to true.
    Files that are in the database but no longer in the folder are marked with the "ToDelete" flag.
.PARAMETER FolderPath
    The path to the folder to scan for file changes.
.PARAMETER DatabasePath
    The path to the SQLite database.
.EXAMPLE
    .\Update-FileTracker.ps1 -FolderPath "D:\MyDocuments" 
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$FolderPath,
    
    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(".ai")
)

$aiFolder = Join-Path -Path $FolderPath -ChildPath ".ai"
    
# Create .ai folder if it doesn't exist
if (-not (Test-Path -Path $aiFolder)) {
    New-Item -Path $aiFolder -ItemType Directory | Out-Null
    Write-Host "Created .ai folder at $aiFolder" -ForegroundColor Yellow
}
    
$DatabasePath = Join-Path -Path $aiFolder -ChildPath "FileTracker.db"

# Check if SQLite assemblies exist, if not run the installer
$sqliteAssemblyPath = "$FolderPath\.ai\libs\Microsoft.Data.Sqlite.dll"
$sqliteAssemblyPath2 = "$FolderPath\.ai\libs\SQLitePCLRaw.core.dll"
$sqliteAssemblyPath3 = "$FolderPath\.ai\libs\SQLitePCLRaw.provider.e_sqlite3.dll"

# Load SQLite assembly
Add-Type -Path $sqliteAssemblyPath -Verbose
Add-Type -Path $sqliteAssemblyPath2 -Verbose
Add-Type -Path $sqliteAssemblyPath3 -Verbose

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

# Create/Open the database
try {
    # Create connection to SQLite database
    $connectionString = "Data Source=$DatabasePath"
    $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection($connectionString)
    $connection.Open()
    
    # Create transaction for better performance
    $transaction = $connection.BeginTransaction()
    
    # Get all existing file paths from the database for faster lookups
    $existingFilePaths = @{}
    $existingFilesDetails = @{}
    
    $selectCommand = $connection.CreateCommand()
    $selectCommand.CommandText = "SELECT id, FilePath, LastModified FROM files"
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
    $totalFiles = (Get-ChildItem -Path $FolderPath -Recurse -File).Count
    
    # Track current files for detecting removed files
    $currentFilePaths = @{}
    
    # Prepare statements
    $updateCommand = $connection.CreateCommand()
    $updateCommand.CommandText = "UPDATE files SET LastModified = @LastModified, Dirty = 1, Deleted = 0 WHERE id = @Id"
    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", [System.Data.DbType]::String)))
    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", [System.Data.DbType]::Int32)))
    
    $insertCommand = $connection.CreateCommand()
    $insertCommand.CommandText = "INSERT INTO files (FilePath, LastModified, Dirty, Deleted) VALUES (@FilePath, @LastModified, 1, 0)"
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", [System.Data.DbType]::String)))
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", [System.Data.DbType]::String)))
    
    $markDeleteCommand = $connection.CreateCommand()
    $markDeleteCommand.CommandText = "UPDATE files SET Deleted = 1 WHERE FilePath = @FilePath"
    $markDeleteCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", [System.Data.DbType]::String)))
    
    # Get all files recursively and update the database
    Get-ChildItem -Path $FolderPath -Recurse -File | ForEach-Object {
        $filePath = $_.FullName
        
        # Check if the file is in an omitted folder
        $isOmitted = Test-PathInOmittedFolders -Path $filePath -OmitFolders $OmitFolders -BaseDirectory $FolderPath
        
        if ($isOmitted) {
            Write-Verbose "Skipping file in omitted folder: $filePath"
            return
        }
        
        $lastModified = $_.LastWriteTime
        $lastModifiedStr = $lastModified.ToString("o") # ISO 8601 format
        
        # Add to current files tracking
        $currentFilePaths[$filePath] = $true
        
        # Update progress
        $filesProcessed++
        Write-Progress -Activity "Updating File Tracker Database" -Status "Processing files" -PercentComplete (($filesProcessed / $totalFiles) * 100)
        
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
        }
    }
    
    # Check for removed files (files in the database but not in the current scan)
    foreach ($existingFilePath in $existingFilePaths.Keys) {
        if (-not $currentFilePaths.ContainsKey($existingFilePath)) {
            # File is missing - mark as ToDelete
            $markDeleteCommand.Parameters["@FilePath"].Value = $existingFilePath
            $markDeleteCommand.ExecuteNonQuery()
            $removedFiles++
        }
    }
    
    # Commit transaction
    $transaction.Commit()
    
    Write-Progress -Activity "Updating File Tracker Database" -Completed
    
    # Report summary
    Write-Host "File Tracker Database Update Summary:" -ForegroundColor Green
    Write-Host "New files: $newFiles" -ForegroundColor Cyan
    Write-Host "Modified files: $modifiedFiles" -ForegroundColor Yellow
    Write-Host "Unchanged files: $unchangedFiles" -ForegroundColor Gray
    Write-Host "Missing files (marked as deleted): $removedFiles" -ForegroundColor Magenta
    
    if ($OmitFolders.Count -gt 0) {
        Write-Host "Omitted folders: {$($OmitFolders -join ', ')}" -ForegroundColor Yellow
    }
    
    # Report files to process
    $toDirtyCommand = $connection.CreateCommand()
    $toDirtyCommand.CommandText = "SELECT COUNT(*) FROM files WHERE Dirty = 1"
    $filesToProcessCount = $toDirtyCommand.ExecuteScalar()
    
    Write-Host "Files to process: $filesToProcessCount" -ForegroundColor Green
    
    if ($filesToProcessCount -gt 0) {
        Write-Host "Files marked as dirty:" -ForegroundColor Green
        
        $listProcessCommand = $connection.CreateCommand()
        $listProcessCommand.CommandText = "SELECT FilePath FROM files WHERE Dirty = 1"
        $reader = $listProcessCommand.ExecuteReader()
        
        while ($reader.Read()) {
            Write-Host " - $($reader["FilePath"])" -ForegroundColor Cyan
        }
        $reader.Close()
    }
    
    # Report files marked for deletion
    $toDeleteCommand = $connection.CreateCommand()
    $toDeleteCommand.CommandText = "SELECT COUNT(*) FROM files WHERE Deleted = 1"
    $filesToDeleteCount = $toDeleteCommand.ExecuteScalar()
    
    if ($filesToDeleteCount -gt 0) {
        Write-Host "Files marked as deleted (missing from folder): $filesToDeleteCount" -ForegroundColor Magenta
        
        $listDeleteCommand = $connection.CreateCommand()
        $listDeleteCommand.CommandText = "SELECT FilePath FROM files WHERE Deleted = 1"
        $reader = $listDeleteCommand.ExecuteReader()
        
        while ($reader.Read()) {
            Write-Host " - $($reader["FilePath"])" -ForegroundColor Magenta
        }
        $reader.Close()
    }
}
catch {
    Write-Error "Error updating database: $_"
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
