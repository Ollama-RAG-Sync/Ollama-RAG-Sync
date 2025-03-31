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
    [Parameter(Mandatory = $true)]
    [string]$InstallPath
)

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedPath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedPath -Force

$DatabasePath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"

if (-not (Test-Path -Path $DatabasePath)) {
    New-Item -Path $DatabasePath -ItemType File
}

# Check if SQLite assemblies exist
$sqliteAssemblyPath = "$InstallPath\Microsoft.Data.Sqlite.dll"
$sqliteAssemblyPath2 = "$InstallPath\SQLitePCLRaw.core.dll"
$sqliteAssemblyPath3 = "$InstallPath\SQLitePCLRaw.provider.e_sqlite3.dll"

# Check if we need to copy SQLite assemblies
if (-not (Test-Path -Path $sqliteAssemblyPath)) {
    if (Test-Path -Path $sourceLibsDir) {
        # Copy SQLite DLLs from the source directory
        Copy-Item -Path "$InstallPath\Microsoft.Data.Sqlite.dll" -Destination $sqliteAssemblyPath -Force
        Copy-Item -Path "$InstallPath\SQLitePCLRaw.core.dll" -Destination $sqliteAssemblyPath2 -Force
        Copy-Item -Path "$InstallPath\SQLitePCLRaw.provider.e_sqlite3.dll" -Destination $sqliteAssemblyPath3 -Force
        
        Write-Host "Copied SQLite assemblies to $libsDir" -ForegroundColor Green
    }
    else {
        Write-Error "SQLite assemblies not found. Please install them first using Install-FileTracker.ps1"
        exit 1
    }
}

# Load SQLite assembly
try {
    Add-Type -Path $sqliteAssemblyPath
    Add-Type -Path $sqliteAssemblyPath2
    Add-Type -Path $sqliteAssemblyPath3
}
catch {
    Write-Error "Error loading SQLite assemblies: $_"
    exit 1
}

# Create/Open the database
try {
    # Set SQLitePCLRaw provider
    [SQLitePCL.raw]::SetProvider([SQLitePCL.SQLite3Provider_e_sqlite3]::new())
    
    # Create connection to SQLite database
    $connectionString = "Data Source=$DatabasePath"
    $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection($connectionString)
    $connection.Open()
    
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
    $command.ExecuteNonQuery()
    Write-Host "Created collections table" -ForegroundColor Green
    
    # Create files table if not exists - now with collection_id and OriginalUrl
    $command.CommandText = @"
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    FilePath TEXT NOT NULL,
    OriginalUrl TEXT,
    LastModified TEXT NOT NULL,
    Dirty INTEGER NOT NULL,
    Deleted INTEGER DEFAULT 0,
    collection_id INTEGER NOT NULL,
    FOREIGN KEY (collection_id) REFERENCES collections(id),
    UNIQUE(FilePath, collection_id)
);
CREATE INDEX IF NOT EXISTS idx_FilePath ON files(FilePath);
CREATE INDEX IF NOT EXISTS idx_collection_id ON files(collection_id);
"@
    $command.ExecuteNonQuery()
    Write-Host "Created files table with collection support" -ForegroundColor Green
    
    # Create settings table if not exists
    $command.CommandText = @"
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT NOT NULL
);
"@
    $command.ExecuteNonQuery()
    Write-Host "Created settings table" -ForegroundColor Green
    
    # Set schema version
    $schemaVersionCommand = $connection.CreateCommand()
    $schemaVersionCommand.CommandText = "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES ('schema_version', '1.0', @UpdatedAt)"
    $schemaVersionCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", [DateTime]::UtcNow.ToString("o"))))
    $schemaVersionCommand.ExecuteNonQuery()
    
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
