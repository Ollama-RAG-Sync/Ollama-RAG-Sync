param (
    [Parameter(Mandatory = $true)]
    [string]$FolderPath,

    [Parameter(Mandatory = $false)]
    [string]$InstallPath = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "User"),
    
    [Parameter(Mandatory = $false)]
    [string]$CollectionName,

    [Parameter(Mandatory = $false)]
    [string]$Description
)

# Validate InstallPath
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-Log "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable." -Level "ERROR"
    exit 1
}

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedModulePath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedModulePath -Force

$DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath

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
$collection = Get-CollectionByName -Name $CollectionName -InstallPath $InstallPath

if ($null -eq $collection) {
    $collection = New-Collection -Name $CollectionName -Description $Description -SourceFolder $FolderPath -InstallPath $InstallPath -DatabasePath $DatabasePath
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

# Get files excluding specified folders
$files = Get-ChildItem -Path $FolderPath -Recurse -File 

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
