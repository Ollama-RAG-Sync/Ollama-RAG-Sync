# Process-AllFiles.ps1
# This script processes all files in a directory by:
# 1. Calling Update-FileTracker.ps1 to scan for changes
# 2. Marking all files as dirty
# 3. Processing all files using a processing script
# 4. Clearing the dirty flag on all files

param(
    [Parameter(Mandatory=$true)]
    [string]$DirectoryPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [string]$ProcessorScript,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$ProcessorScriptParams = @{},
    
    [Parameter(Mandatory=$false)]
    [string[]]$OmitFolders = @(".ai")
)

# Get the current script path
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$fileTrackerPath = Join-Path -Path $scriptPath -ChildPath "..\FileTracker"

# Step 1: Call Update-FileTracker.ps1 to identify files and update the DB
Write-Host "Step 1: Updating file tracker database..." -ForegroundColor Cyan
$updateTrackerPath = Join-Path -Path $fileTrackerPath -ChildPath "Update-FileTracker.ps1"
& $updateTrackerPath -FolderPath $DirectoryPath -OmitFolders $OmitFolders 

# Step 2: Mark all files as dirty
Write-Host "Step 2: Marking all files as dirty..." -ForegroundColor Cyan
$markDirtyPath = Join-Path -Path $fileTrackerPath -ChildPath "Mark-FileAsDirty.ps1"
& $markDirtyPath -All -FolderPath $DirectoryPath

# Step 3: Process all dirty files
Write-Host "Step 3: Processing all files..." -ForegroundColor Cyan
$processDirtyPath = Join-Path -Path $scriptPath -ChildPath "Process-DirtyFiles.ps1"

# Set up parameters for Process-DirtyFiles.ps1
$processDirtyParams = @{
    DirectoryPath = $DirectoryPath
    OllamaUrl = $OllamaUrl
    EmbeddingModel = $EmbeddingModel
}

# Add ProcessorScript parameter if specified
if ($ProcessorScript) {
    $processDirtyParams.Add("ProcessorScript", $ProcessorScript)
    
    # Add any additional processor script parameters
    if ($ProcessorScriptParams -and $ProcessorScriptParams.Count -gt 0) {
        $processDirtyParams.Add("ProcessorScriptParams", $ProcessorScriptParams)
    }
}

# Process all dirty files
& $processDirtyPath @processDirtyParams

# Step 4: Clear the dirty flag on all files
Write-Host "Step 4: Clearing dirty flag on all processed files..." -ForegroundColor Cyan
$markProcessedPath = Join-Path -Path $fileTrackerPath -ChildPath "Mark-FileAsProcessed.ps1"
& $markProcessedPath -All -FolderPath $DirectoryPath

Write-Host "Process-AllFiles completed successfully." -ForegroundColor Green
