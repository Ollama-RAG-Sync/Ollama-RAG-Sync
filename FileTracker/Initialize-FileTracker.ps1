<#
.SYNOPSIS
    Initializes a SQLite database to track file modifications in a specified folder.
.DESCRIPTION
    This script creates a SQLite database and populates it with information about files
    in the specified folder (recursively). For each file, it stores the path, last modification date,
    and sets the "Dirty" flag to false.
.PARAMETER FolderPath
    The path to the folder to monitor for file changes.
.PARAMETER DatabasePath
    The path where the SQLite database will be created. If not specified, a "FileTracker.db" file
    will be created in a ".ai" subfolder within the FolderPath.
.PARAMETER OmitFolders
    An array of folder names to exclude from file tracking. By default, the ".ai" folder is excluded.
.EXAMPLE
    .\Initialize-FileTracker.ps1 -FolderPath "D:\MyDocuments" -DatabasePath "D:\MyDocuments\FileTracker.db"
.EXAMPLE
    .\Initialize-FileTracker.ps1 -FolderPath "D:\MyDocuments"
    # This will create the database at "D:\MyDocuments\.ai\FileTracker.db"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$FolderPath,
    
    [Parameter(Mandatory = $false)]
    [string]$DatabasePath,

    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(".ai")
)

# If DatabasePath is not provided, set it to a file inside .ai subfolder in FolderPath
if (-not $DatabasePath) {
    $aiFolder = Join-Path -Path $FolderPath -ChildPath ".ai"
    
    # Create .ai folder if it doesn't exist
    if (-not (Test-Path -Path $aiFolder)) {
        New-Item -Path $aiFolder -ItemType Directory | Out-Null
        Write-Host "Created .ai folder at $aiFolder" -ForegroundColor Yellow
    }
    
    $DatabasePath = Join-Path -Path $aiFolder -ChildPath "FileTracker.db"
    Write-Host "DatabasePath set to $DatabasePath" -ForegroundColor Cyan
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
    # Create database directory if it doesn't exist
    $databaseDir = Split-Path -Path $DatabasePath -Parent
    if (-not (Test-Path -Path $databaseDir)) {
        New-Item -Path $databaseDir -ItemType Directory | Out-Null
    }


    # Set SQLitePCLRaw provider
    [SQLitePCL.raw]::SetProvider([SQLitePCL.SQLite3Provider_e_sqlite3]::new())
    
    # Create connection to SQLite database
    $connectionString = "Data Source=$DatabasePath;"
    $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection($connectionString)
    $connection.Open()
    
    # Create command object
    $command = $connection.CreateCommand()
    
    # Create table if not exists
    $command.CommandText = @"
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    FilePath TEXT UNIQUE,
    LastModified TEXT,
    Dirty INTEGER,
    Deleted INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_FilePath ON files(FilePath);
DELETE FROM files; -- Clear existing data
"@
    $null = $command.ExecuteNonQuery()
    
    # Initialize the counter for progress reporting
    $filesProcessed = 0
    
    Write-Host "Excluding folders: $($OmitFolders -join ', ')" -ForegroundColor Yellow
    
    # Get files excluding specified folders
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
    Write-Host "Found $totalFiles files" 

    # Prepare insert statement
    $null = $insertCommand = $connection.CreateCommand()
    $null = $insertCommand.CommandText = "INSERT OR IGNORE INTO files (FilePath, LastModified, Dirty, Deleted) VALUES (@FilePath, @LastModified, @Dirty, 0)"
    $null = $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", [System.Data.DbType]::String)))
    $null = $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", [System.Data.DbType]::String)))
    $null = $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Dirty", [System.Data.DbType]::Int32)))
    
    # Process the filtered files
    $files | ForEach-Object {
        $filePath = $_.FullName
        $lastModified = $_.LastWriteTime.ToString("o") # ISO 8601 format
        
        # Set parameters
        $null = $insertCommand.Parameters["@FilePath"].Value = $filePath
        $null = $insertCommand.Parameters["@LastModified"].Value = $lastModified
        $null = $insertCommand.Parameters["@Dirty"].Value = 1 # true - mark new files as dirty
        
        # Insert record
        $insertCommand.ExecuteNonQuery() | Out-Null
        
        # Update progress
        $filesProcessed++
        Write-Progress -Activity "Initializing File Tracker Database" -Status "Processing files" -PercentComplete (($filesProcessed / $totalFiles) * 100)
    }
    
    Write-Progress -Activity "Initializing File Tracker Database" -Completed
    Write-Host "Database initialized with $filesProcessed files."
}
catch {
    Write-Error "Error initializing database: $_"
}
finally {
    Write-Host "Finished initializing database"

    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
