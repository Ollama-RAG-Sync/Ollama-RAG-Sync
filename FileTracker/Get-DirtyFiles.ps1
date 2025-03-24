<#
.SYNOPSIS
    Lists files marked for processing in the SQLite database.
.DESCRIPTION
    This script queries the SQLite database and returns a list of files that are marked
    for processing (ToProcess = true). These represent newly created or modified files
    that have not yet been processed.
.PARAMETER FolderPath
    The path to the monitored folder. If specified instead of DatabasePath, the script will
    automatically compute the database path as [FolderPath]\.ai\FileTracker.db.
.PARAMETER DatabasePath
    The path to the SQLite database. Either this or FolderPath must be specified.
.PARAMETER AsObject
    If specified, returns PowerShell objects instead of formatted output.
.EXAMPLE
    .\Get-FilesToProcess.ps1 -FolderPath "D:\MyDocuments"
    # Lists files to process using the database at "D:\MyDocuments\.ai\FileTracker.db"
.EXAMPLE
    .\Get-FilesToProcess.ps1 -DatabasePath "D:\FileTracker\.ai\FileTracker.db"
    # Lists files to process using the specified database path
.EXAMPLE
    .\Get-FilesToProcess.ps1 -FolderPath "D:\MyDocuments" -AsObject | ForEach-Object { $_.FilePath }
    # Returns just the file paths as strings
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$FolderPath,
    
    [Parameter(Mandatory = $false)]
    [string]$DatabasePath,
    
    [Parameter(Mandatory = $false)]
    [switch]$AsObject,
    
    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(".ai")
)

# If DatabasePath is not provided but FolderPath is, compute the DatabasePath
if (-not $DatabasePath -and $FolderPath) {
    $aiFolder = Join-Path -Path $FolderPath -ChildPath ".ai"
    $DatabasePath = Join-Path -Path $aiFolder -ChildPath "FileTracker.db"
    Write-Host "Using computed DatabasePath: $DatabasePath" -ForegroundColor Cyan
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

# Validate that we have a DatabasePath
if (-not $DatabasePath) {
    Write-Error "Either DatabasePath or FolderPath must be specified."
    exit 1
}

$sqliteAssemblyPath = "$FolderPath\.ai\libs\Microsoft.Data.Sqlite.dll"
$sqliteAssemblyPath2 = "$FolderPath\.ai\libs\SQLitePCLRaw.core.dll"
$sqliteAssemblyPath3 = "$FolderPath\.ai\libs\SQLitePCLRaw.provider.e_sqlite3.dll"

# Load SQLite assembly
Add-Type -Path $sqliteAssemblyPath
Add-Type -Path $sqliteAssemblyPath2
Add-Type -Path $sqliteAssemblyPath3

# Create/Open the database
try {
    
    # Set SQLitePCLRaw provider
    [SQLitePCL.raw]::SetProvider([SQLitePCL.SQLite3Provider_e_sqlite3]::new())
    
    # Create connection to SQLite database
    $connectionString = "Data Source=$DatabasePath"
    $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection($connectionString)
    $connection.Open()
    
    # Create command to count files to process
    $countCommand = $connection.CreateCommand()
    $countCommand.CommandText = "SELECT COUNT(*) FROM files WHERE Dirty = 1"
    $filesToProcessCount = $countCommand.ExecuteScalar()
    
    if ($filesToProcessCount -eq 0) {
        Write-Host "No files found that need processing." -ForegroundColor Yellow
        exit 0
    }
    
    # Create a results array
    $results = @()
    
    # Query for files marked for processing
    $selectCommand = $connection.CreateCommand()
    $selectCommand.CommandText = "SELECT FilePath, LastModified FROM files WHERE Dirty = 1"
    $reader = $selectCommand.ExecuteReader()
    
    # Process files
    while ($reader.Read()) {
        $filePath = $reader["FilePath"]
        $lastModified = [DateTime]::Parse($reader["LastModified"])
        
        # Skip files in omitted folders if FolderPath is provided
        if ($FolderPath -and $OmitFolders.Count -gt 0) {
            $isOmitted = Test-PathInOmittedFolders -Path $filePath -OmitFolders $OmitFolders -BaseDirectory $FolderPath
            if ($isOmitted) {
                Write-Verbose "Skipping file in omitted folder: $filePath"
                continue
            }
        }
        
        $fileInfo = [PSCustomObject]@{
            FilePath = $filePath
            LastModified = $lastModified
            ToProcess = $true
        }
        
        $results += $fileInfo
        
        # If not returning objects, print info to console
        if (-not $AsObject) {
            Write-Host "Dirty files: $filePath" -ForegroundColor Green
            Write-Host "  Last Modified: $lastModified" -ForegroundColor Gray
            Write-Host ""
        }
    }
    
    # Close the reader
    $reader.Close()
    
    if (-not $AsObject) {
        Write-Host "Found $($results.Count) files to process." -ForegroundColor Cyan
        
        if ($OmitFolders.Count -gt 0 -and $FolderPath) {
            Write-Host "Note: Files in omitted folders were excluded: {$($OmitFolders -join ', ')}" -ForegroundColor Yellow
        }
    } else {
        # Return objects if AsObject switch is used
        return $results
    }
}
catch {
    Write-Error "Error querying database: $_"
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
