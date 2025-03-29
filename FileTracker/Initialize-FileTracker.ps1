<#
.SYNOPSIS
    Initializes the FileTracker database and creates a collection for a specified folder.
.DESCRIPTION
    This script creates or updates the centralized FileTracker database and adds a collection
    for the specified folder. It then populates the collection with information about files
    in the folder (recursively), marking them for processing.
.PARAMETER FolderPath
    The path to the folder to monitor for file changes.
.PARAMETER CollectionName
    The name to use for the collection. If not specified, it will use the folder name.
.PARAMETER Description
    Optional description for the collection.
.PARAMETER DatabasePath
    The path where the SQLite database will be created. If not specified, it will use the default path
    in the user's AppData folder.
.PARAMETER OmitFolders
    An array of folder names to exclude from file tracking. By default, the ".ai" folder is excluded.
.EXAMPLE
    .\Initialize-FileTracker.ps1 -FolderPath "D:\MyDocuments" -CollectionName "My Documents"
.EXAMPLE
    .\Initialize-FileTracker.ps1 -FolderPath "D:\MyDocuments" -OmitFolders @(".ai", ".git", "node_modules")
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$FolderPath,
    
    [Parameter(Mandatory = $false)]
    [string]$CollectionName,
    
    [Parameter(Mandatory = $false)]
    [string]$Description,
    
    [Parameter(Mandatory = $false)]
    [string]$DatabasePath,

    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(".ai")
)

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedPath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedPath -Force

# If DatabasePath is not provided, use the default path
if (-not $DatabasePath) {
    $DatabasePath = Get-DefaultDatabasePath
    Write-Host "Using default database path: $DatabasePath" -ForegroundColor Cyan
}

# If CollectionName is not provided, use the folder name
if (-not $CollectionName) {
    $CollectionName = Split-Path -Path $FolderPath -Leaf
    Write-Host "Using folder name as collection name: $CollectionName" -ForegroundColor Cyan
}

# Check if SQLite assemblies exist
$sqliteAssemblyPath = "$env:APPDATA\FileTracker\libs\Microsoft.Data.Sqlite.dll"
$sqliteAssemblyPath2 = "$env:APPDATA\FileTracker\libs\SQLitePCLRaw.core.dll"
$sqliteAssemblyPath3 = "$env:APPDATA\FileTracker\libs\SQLitePCLRaw.provider.e_sqlite3.dll"

# Load SQLite assembly
try {
    Add-Type -Path $sqliteAssemblyPath
    Add-Type -Path $sqliteAssemblyPath2
    Add-Type -Path $sqliteAssemblyPath3
}
catch {
    Write-Error "Error loading SQLite assemblies: $_"
    Write-Host "Please make sure you've run Install-FileTracker.ps1 first." -ForegroundColor Red
    exit 1
}

# Initialize the centralized collection database if it doesn't exist
try {
    # Make sure collection database is initialized
    $initDbScript = Join-Path -Path $scriptParentPath -ChildPath "Initialize-CollectionDatabase.ps1"
    & $initDbScript -DatabasePath $DatabasePath
    
    # Get or create the collection
    $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
    
    # Check if collection exists
    $checkCommand = $connection.CreateCommand()
    $checkCommand.CommandText = "SELECT id FROM collections WHERE name = @Name"
    $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Name", $CollectionName)))
    
    $collectionId = $checkCommand.ExecuteScalar()
    
    if (-not $collectionId) {
        # Create new collection
        $collection = New-Collection -Name $CollectionName -Description $Description -DatabasePath $DatabasePath
        $collectionId = $collection.id
        Write-Host "Created new collection '$CollectionName' with ID $collectionId" -ForegroundColor Green
    }
    else {
        Write-Host "Using existing collection '$CollectionName' with ID $collectionId" -ForegroundColor Cyan
    }
    
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
    Write-Host "Found $totalFiles files to process" -ForegroundColor Cyan
    
    # Begin transaction for better performance
    $transaction = $connection.BeginTransaction()
    
    # Prepare insert statement
    $insertCommand = $connection.CreateCommand()
    $insertCommand.CommandText = "INSERT OR REPLACE INTO files (FilePath, LastModified, Dirty, Deleted, collection_id) VALUES (@FilePath, @LastModified, @Dirty, 0, @CollectionId)"
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", [DBNull]::Value)))
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", [DBNull]::Value)))
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Dirty", 1))) # Mark all files as dirty initially
    $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
    
    # Process the filtered files
    $files | ForEach-Object {
        $filePath = $_.FullName
        $lastModified = $_.LastWriteTime.ToString("o") # ISO 8601 format
        
        # Set parameters
        $insertCommand.Parameters["@FilePath"].Value = $filePath
        $insertCommand.Parameters["@LastModified"].Value = $lastModified
        
        # Insert record
        $insertCommand.ExecuteNonQuery() | Out-Null
        
        # Update progress
        $filesProcessed++
        Write-Progress -Activity "Initializing File Tracker" -Status "Processing files" -PercentComplete (($filesProcessed / $totalFiles) * 100)
    }
    
    # Commit transaction
    $transaction.Commit()
    
    Write-Progress -Activity "Initializing File Tracker" -Completed
    Write-Host "Collection initialized with $filesProcessed files marked for processing." -ForegroundColor Green
}
catch {
    if ($transaction) {
        $transaction.Rollback()
    }
    Write-Error "Error initializing file tracker: $_"
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
    
    Write-Host "Finished initializing file tracker for folder: $FolderPath" -ForegroundColor Green
}
