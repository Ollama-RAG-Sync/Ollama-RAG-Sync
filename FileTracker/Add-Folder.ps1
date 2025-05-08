<#
.SYNOPSIS
    Adds a folder to FileTracker for monitoring, enabling tracking for all file system events.
.DESCRIPTION
    This script creates a new collection in the FileTracker database based on the provided folder path.
    It adds all files from the folder (recursively) and automatically starts a background job
    to watch the collection for all file changes (create, delete, modify, rename) including subdirectories.
.PARAMETER FolderPath
    The path to the folder to add and monitor.
.PARAMETER InstallPath
    The installation path of the Ollama-RAG-Sync project, used to locate shared modules and the database.
.PARAMETER CollectionName
    Optional: The name for the collection. If not provided, the folder's name will be used.
.PARAMETER Description
    Optional: A description for the collection.
.PARAMETER OmitFolders
    Optional: An array of folder names to exclude from file tracking. Defaults can be set within the script.
.PARAMETER WatchInterval
    Optional: The interval in seconds for the file watcher to check for changes. Defaults to 15 seconds.
.PARAMETER DatabasePath
    Optional: The path where the SQLite database is located. If not specified, the default path based on InstallPath will be used.
.EXAMPLE
    .\Add-Folder.ps1 -FolderPath "D:\MyImportantDocs" -InstallPath "C:\Path\To\Ollama-RAG-Sync"
    # Adds the folder, names the collection "MyImportantDocs", and starts watching all events.
.EXAMPLE
    .\Add-Folder.ps1 -FolderPath "D:\Projects\Source" -InstallPath "C:\Path\To\Ollama-RAG-Sync" -CollectionName "ProjectSource" -OmitFolders @(".git", "node_modules", "bin", "obj")
    # Adds the folder with a custom name, excludes specific subfolders, and starts watching all events.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$FolderPath,

    [Parameter(Mandatory = $true)]
    [string]$InstallPath,

    [Parameter(Mandatory = $false)]
    [string]$CollectionName,

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [string[]]$OmitFolders = @(".ai", ".git"), # Default excluded folders

    [Parameter(Mandatory = $false)]
    [int]$WatchInterval = 15,

    [Parameter(Mandatory = $false)]
    [string]$DatabasePath # Optional override
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

# Determine Collection Name if not provided
if (-not $CollectionName) {
    $CollectionName = (Get-Item -Path $FolderPath).Name
    Write-Host "Using folder name as Collection Name: '$CollectionName'" -ForegroundColor Cyan
}

# Ensure the database is initialized
$initScript = Join-Path -Path $scriptParentPath -ChildPath "Initialize-Database.ps1"
& $initScript -InstallPath $InstallPath

# Create a new collection
Write-Host "Creating collection '$CollectionName'..." -ForegroundColor Cyan
# Note: IncludeExtensions is not specified, meaning all files are included by default in New-Collection logic (assuming it handles null/empty)
$collection = Get-CollectionByName -Name $CollectionName -InstallPath $InstallPath
if ($null -eq $collection) {
    $collection = New-Collection -Name $CollectionName -Description $Description -SourceFolder $FolderPath -ExcludeFolders ($OmitFolders -join ',') -InstallPath $InstallPath -DatabasePath $DatabasePath
} else {
    Write-Host "Creating new collection..." -ForegroundColor Green
}

if (-not $collection) {
    Write-Error "Failed to create collection. Check previous errors."
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

    # Check against each OmitFolder pattern
    foreach ($folderPattern in $OmitFolders) {
        # Simple check: does the path contain the folder name surrounded by path separators?
        # More robust checks might be needed depending on desired behavior (e.g., regex, anchoring)
        if ($filePath -like "*\$folderPattern\*") {
            $exclude = $true
            break
        }
        # Check if the folder is at the root of the collection path (less common case, but possible)
        if ($filePath.StartsWith("$FolderPath\$folderPattern\")) {
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

    # Add file to collection, mark as dirty for initial processing
    $result = Add-FileToCollection -CollectionId $collection.id -FilePath $filePath -Dirty $true -DatabasePath $DatabasePath -InstallPath $InstallPath

    if ($result) {
        $status = if ($result.updated) { "Updated" } else { "Added" }
        Write-Verbose "$status file: $filePath"
    }
    else {
        Write-Warning "Failed to add file: $filePath"
    }

    # Update progress
    $filesProcessed++
    Write-Progress -Activity "Adding files to collection '$CollectionName'" -Status "Processing file $filesProcessed of $totalFiles" -PercentComplete (($filesProcessed / $totalFiles) * 100)
}

Write-Progress -Activity "Adding files to collection '$CollectionName'" -Completed
Write-Host "Collection '$CollectionName' added with $filesProcessed files." -ForegroundColor Green
Write-Host "All files have been marked as 'dirty' for initial processing." -ForegroundColor Cyan
Write-Host "Folder '$FolderPath' added as collection '$CollectionName'." -ForegroundColor Green
Write-Host "FileTracker service will pick up this collection for monitoring based on saved settings." -ForegroundColor Cyan
Write-Host "Ensure the main FileTracker watcher process is running." -ForegroundColor Yellow
