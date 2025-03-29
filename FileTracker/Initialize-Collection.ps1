<#
.SYNOPSIS
    Initializes a collection in the FileTracker database with files from a specified folder.
.DESCRIPTION
    This script creates a new collection in the FileTracker database and adds all files from
    the specified folder (recursively). Each file is marked as dirty for initial processing.
.PARAMETER CollectionName
    The name of the collection to create.
.PARAMETER FolderPath
    The path to the folder containing files to add to the collection.
.PARAMETER Description
    An optional description for the collection.
.PARAMETER IncludeExtensions
    An array of file extensions to include in file tracking. If not specified, all files will be included.
    Example: @(".docx", ".pdf", ".txt")
.PARAMETER OmitFolders
    An array of folder names to exclude from file tracking. By default, ".ai" and ".git" folders are excluded.
.PARAMETER DatabasePath
    The path where the SQLite database is located. If not specified, the default database path will be used.
.PARAMETER Watch
    If specified, start a background job to watch the collection for file changes (create/delete/modify/rename).
.PARAMETER WatchCreated
    If specified with -Watch, monitor for created files. Default is true if -Watch is specified.
.PARAMETER WatchModified
    If specified with -Watch, monitor for modified files. Default is true if -Watch is specified.
.PARAMETER WatchDeleted
    If specified with -Watch, monitor for deleted files. Default is true if -Watch is specified.
.PARAMETER WatchRenamed
    If specified with -Watch, monitor for renamed files. Default is true if -Watch is specified.
.PARAMETER IncludeSubdirectories
    If specified with -Watch, include subdirectories in file monitoring. Default is true if -Watch is specified.
.EXAMPLE
    .\Initialize-Collections.ps1 -CollectionName "Documentation" -FolderPath "D:\MyDocuments"
    # This will create a collection named "Documentation" with all files from D:\MyDocuments
.EXAMPLE
    .\Initialize-Collections.ps1 -CollectionName "Projects" -FolderPath "D:\Projects" -Description "Software project documentation" -OmitFolders @(".ai", ".git", "bin", "obj")
    # This will create a collection with the specified description and exclude additional folders from tracking
.EXAMPLE
    .\Initialize-Collections.ps1 -CollectionName "Documents" -FolderPath "D:\Files" -IncludeExtensions @(".docx", ".pdf", ".txt")
    # This will create a collection that only includes files with the specified extensions
.EXAMPLE
    .\Initialize-Collections.ps1 -CollectionName "CodeProject" -FolderPath "D:\Projects\MyApp" -Watch
    # This will create a collection and start a background job to monitor for file changes
.EXAMPLE
    .\Initialize-Collections.ps1 -CollectionName "Reports" -FolderPath "D:\Reports" -Watch -WatchCreated -WatchModified -IncludeSubdirectories
    # This will create a collection with a file watcher that only monitors for created and modified files in all subdirectories
.EXAMPLE
    .\Initialize-Collections.ps1 -CollectionName "ApiDocs" -FolderPath "D:\Docs\API" -Watch -ProcessInterval 30 -OmitFolders @(".ai", ".git", "node_modules")
    # This will create a collection with a file watcher that checks for changes every 30 seconds and excludes specific folders
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$CollectionName,
    
    [Parameter(Mandatory = $true)]
    [string]$FolderPath,
    
    [Parameter(Mandatory = $false)]
    [string]$Description,
    
    [Parameter(Mandatory = $false)]
    [string[]]$IncludeExtensions,
    
    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(),
    
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$Watch,
    
    [Parameter(Mandatory = $false)]
    [switch]$WatchCreated = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$WatchModified = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$WatchDeleted = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$WatchRenamed = $true,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeSubdirectories = $true,
    
    [Parameter(Mandatory = $false)]
    [int]$ProcessInterval = 15
)
$DatabasePath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedPath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedPath -Force

# If DatabasePath is not provided, use the default path
if (-not $DatabasePath) {
    $DatabasePath = Get-DefaultDatabasePath
    Write-Host "Using default database path: $DatabasePath" -ForegroundColor Cyan
}

# Check if the folder exists
if (-not (Test-Path -Path $FolderPath -PathType Container)) {
    Write-Error "Folder not found: $FolderPath"
    exit 1
}

# Ensure the database is initialized
$initScript = Join-Path -Path $scriptParentPath -ChildPath "Initialize-Database.ps1"
& $initScript -InstallPath $InstallPath

# Create a new collection
Write-Host "Creating collection '$CollectionName'..." -ForegroundColor Cyan
$collection = New-Collection -Name $CollectionName -Description $Description -InstallPath $InstallPath -SourceFolder $FolderPath

if (-not $collection) {
    Write-Error "Failed to create collection."
    exit 1
}

Write-Host "Collection created with ID: $($collection.id)" -ForegroundColor Green

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
Write-Host "Found $totalFiles files to add to collection"

# Process the filtered files
$files | ForEach-Object {
    $filePath = $_.FullName
    
    # Add file to collection
    $result = Add-FileToCollection -CollectionId $collection.id -FilePath $filePath -Dirty $true -DatabasePath $DatabasePath
    
    if ($result) {
        $status = if ($result.updated) { "Updated" } else { "Added" }
        Write-Verbose "$status file: $filePath"
    }
    else {
        Write-Warning "Failed to add file: $filePath"
    }
    
    # Update progress
    $filesProcessed++
    Write-Progress -Activity "Adding files to collection" -Status "Processing files" -PercentComplete (($filesProcessed / $totalFiles) * 100)
}

Write-Progress -Activity "Adding files to collection" -Completed
Write-Host "Collection initialized with $filesProcessed files." -ForegroundColor Green
Write-Host "All files have been marked as 'dirty' for initial processing." -ForegroundColor Cyan

# Check if watch is enabled
if ($Watch) {
    Write-Host "Starting file watcher for collection '$CollectionName'..." -ForegroundColor Cyan
    
    # Store watch settings in database
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Generate a unique key for this collection's watch settings
        $watchKey = "collection_${collection.id}_watch"
        
        # Create JSON settings object
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
        
        # Convert to JSON
        $watchSettingsJson = ConvertTo-Json $watchSettings -Compress
        
        # Store in database
        $command = $connection.CreateCommand()
        $command.CommandText = "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (@Key, @Value, @UpdatedAt)"
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Key", $watchKey)))
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Value", $watchSettingsJson)))
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", [DateTime]::UtcNow.ToString("o"))))
        $command.ExecuteNonQuery()
        
        $connection.Close()
        $connection.Dispose()
        
        Write-Host "Watch settings stored in database." -ForegroundColor Green
    }
    catch {
        Write-Error "Error storing watch settings: $_"
    }
    
    # Start the watch job
    try {
        # Get the path to the Watch-FileTracker.ps1 script
        $watchScriptPath = Join-Path -Path $scriptParentPath -ChildPath "Watch-FileTracker.ps1"
        
        # Build watch parameters
        $watchParams = @{
            DirectoryToWatch = $FolderPath
            WatchCreated = [bool]$WatchCreated
            WatchModified = [bool]$WatchModified
            WatchDeleted = [bool]$WatchDeleted
            WatchRenamed = [bool]$WatchRenamed
            IncludeSubdirectories = [bool]$IncludeSubdirectories
            ProcessInterval = $ProcessInterval
            OmitFolders = $OmitFolders
        }
        
        # If include extensions specified, format them for file filter
        if ($IncludeExtensions) {
            # Format as a filter pattern like *.ext1, *.ext2, etc.
            $fileFilterPatterns = $IncludeExtensions | ForEach-Object { "*$_" }
            $fileFilter = $fileFilterPatterns -join ", "
            $watchParams["FileFilter"] = $fileFilter
        }
        
        # Start the job
        $job = Start-Job -Name "Watch_Collection_$($collection.id)" -ScriptBlock {
            param($scriptPath, $params)
            & $scriptPath @params
        } -ArgumentList $watchScriptPath, $watchParams
        
        Write-Host "File watcher job started with ID: $($job.Id)" -ForegroundColor Green
        Write-Host "Monitoring for file changes: " -NoNewline
        
        $watchTypes = @()
        if ($WatchCreated) { $watchTypes += "Created" }
        if ($WatchModified) { $watchTypes += "Modified" }
        if ($WatchDeleted) { $watchTypes += "Deleted" }
        if ($WatchRenamed) { $watchTypes += "Renamed" }
        
        Write-Host ($watchTypes -join ", ") -ForegroundColor Yellow
        
        if ($IncludeSubdirectories) {
            Write-Host "Including subdirectories in monitoring." -ForegroundColor Cyan
        }
    }
    catch {
        Write-Error "Error starting watch job: $_"
    }
}
