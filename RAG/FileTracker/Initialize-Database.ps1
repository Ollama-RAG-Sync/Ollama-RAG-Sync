<#
.SYNOPSIS
    Initializes the FileTracker database with collection support.
.DESCRIPTION
    This script creates the SQLite database for FileTracker with tables to support collections
    and their associated files. Each collection is a set of files that can be processed together.
.PARAMETER DatabasePath
    The path where the SQLite database will be created. If not specified, it will use the default path
    in the user's AppData folder.
.EXAMPLE
    .\Initialize-CollectionDatabase.ps1
    # This will create the database at the default location
.EXAMPLE
    .\Initialize-CollectionDatabase.ps1 -DatabasePath "D:\Data\FileTracker.db"
    # This will create the database at the specified path
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$InstallPath = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "User")
)

# Validate InstallPath
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-Error "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable."
    exit 1
}

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedModulePath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedModulePath -Force -Global

# Determine Database Path
$DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
Write-Host "Initializing database at: $DatabasePath" -ForegroundColor Cyan

# Ensure the directory for the database exists
$dbDirectory = Split-Path -Path $DatabasePath -Parent
if (-not (Test-Path -Path $dbDirectory)) {
    New-Item -Path $dbDirectory -ItemType Directory -Force | Out-Null
}

# Create the file if it doesn't exist (Get-DatabaseConnection will handle opening/creating)
if (-not (Test-Path -Path $DatabasePath)) {
    New-Item -Path $DatabasePath -ItemType File | Out-Null
    Write-Host "Database file created."
}

# Create/Open the database and initialize tables
try {
    # Get connection - this also ensures SQLite environment is initialized
    $connection = Get-DatabaseConnection -DatabasePath $DatabasePath -InstallPath $InstallPath
    
    # Create command object
    $command = $connection.CreateCommand()
    
    # Create collections table if not exists
    $command.CommandText = @"
CREATE TABLE IF NOT EXISTS collections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    source_folder TEXT NOT NULL,
    include_extensions TEXT,
    exclude_folders TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
"@
    $null = $command.ExecuteNonQuery()
    Write-Host "Created collections table" -ForegroundColor Green
    
    # Create files table if not exists - now with collection_id and OriginalUrl
    $command.CommandText = @"
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    FilePath TEXT NOT NULL,
    OriginalUrl TEXT,
    LastModified TEXT NOT NULL,
    Dirty INTEGER DEFAULT 1,
    Deleted INTEGER DEFAULT 0,
    collection_id INTEGER NOT NULL,
    FOREIGN KEY (collection_id) REFERENCES collections(id),
    UNIQUE(FilePath, collection_id)
);
CREATE INDEX IF NOT EXISTS idx_FilePath ON files(FilePath);
CREATE INDEX IF NOT EXISTS idx_collection_id ON files(collection_id);
"@
    $null = $command.ExecuteNonQuery()
    Write-Host "Created files table with collection support" -ForegroundColor Green
    
    # Create settings table if not exists
    $command.CommandText = @"
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT NOT NULL
);
"@
    $null = $command.ExecuteNonQuery()
    Write-Host "Created settings table" -ForegroundColor Green
    
    # Set schema version
    $schemaVersionCommand = $connection.CreateCommand()
    $schemaVersionCommand.CommandText = "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES ('schema_version', '1.0', @UpdatedAt)"
    $null = $schemaVersionCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", [DateTime]::UtcNow.ToString("o"))))
    $null = $schemaVersionCommand.ExecuteNonQuery()
    
    Write-Host "Database initialized successfully at $DatabasePath" -ForegroundColor Green
}
catch {
    Write-Error "Error initializing database: $_"
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
