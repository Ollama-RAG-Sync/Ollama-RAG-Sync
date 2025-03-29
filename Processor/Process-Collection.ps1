# Process-CollectionDirtyFiles.ps1
# Identifies dirty files in a collection and processes them - converting PDFs to markdown and adding text files to Chroma DB
# Also handles removed files by deleting them from the Chroma DB

#Requires -Version 7.0

param(
    [Parameter(Mandatory=$true)]
    [string]$CollectionName,
    
    [Parameter(Mandatory=$false)]
    [string]$DatabasePath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [string]$TextFileExtensions = ".txt,.md,.html,.csv,.json",
    
    [Parameter(Mandatory=$false)]
    [string]$PDFFileExtension = ".pdf",
    
    [Parameter(Mandatory=$false)]
    [string]$HandlerScript,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$HandlerScriptParams = @{},
    
    [Parameter(Mandatory=$false)]
    [bool]$UseChunking = $true,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 200,
    
    [Parameter(Mandatory=$false)]
    [int]$ProcessInterval = 5,
    
    [Parameter(Mandatory=$false)]
    [switch]$Continuous = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$StopFilePath = ".stop_processing"
)

# Import required modules
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$databaseSharedModule = Join-Path -Path $scriptPath -ChildPath "..\FileTracker\Database-Shared.psm1"

Import-Module $databaseSharedModule -Force

# If DatabasePath is not provided, use the default path
if (-not $DatabasePath) {
    $DatabasePath = Get-DefaultDatabasePath
    Write-Host "Using default database path: $DatabasePath" -ForegroundColor Cyan
}

# Ensure temp directory exists
$appDataDir = Join-Path -Path $env:APPDATA -ChildPath "FileTracker"
$TempDir = Join-Path -Path $appDataDir -ChildPath "temp"
if (-not (Test-Path -Path $TempDir)) {
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
}

# Setup the Vector DB path
$VectorDbPath = Join-Path -Path $appDataDir -ChildPath "Vectors"
if (-not (Test-Path -Path $VectorDbPath)) {
    New-Item -Path $VectorDbPath -ItemType Directory -Force | Out-Null
}

# Initialize log file
$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "ProcessCollection_${CollectionName}_$logDate.log"
$logFilePath = Join-Path -Path $TempDir -ChildPath $logFileName

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with appropriate color
    if ($Level -eq "ERROR") {
        Write-Host $logMessage -ForegroundColor Red
    }
    elseif ($Level -eq "WARNING") {
        Write-Host $logMessage -ForegroundColor Yellow
    }
    elseif ($Verbose -or $Level -eq "INFO") {
        Write-Host $logMessage -ForegroundColor Green
    }
    
    # Write to log file
    Add-Content -Path $logFilePath -Value $logMessage
}

function Process-DirtyFile {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$FileInfo
    )

    $filePath = $FileInfo.FilePath
    $fileId = $FileInfo.Id
    $collectionId = $FileInfo.CollectionId
    
    Write-Log "Processing dirty file: $filePath (ID: $fileId) in collection: $CollectionName"
    
    # Check if file exists
    if (-not (Test-Path -Path $filePath)) {
        Write-Log "File no longer exists, removing from Chroma DB: $filePath" -Level "WARNING"
        Remove-FromChromaDB -FilePath $filePath
        return
    }
    
    # If a custom processor script is provided, use it
    if ($HandlerScript) {
        try {
            if (-not (Test-Path -Path $HandlerScript)) {
                Write-Log "Custom processor script not found: $HandlerScript" -Level "ERROR"
                return
            }
            
            Write-Log "Using custom processor script: $HandlerScript"
            
            # Prepare parameters for the processor script
            $scriptParams = @{
                FilePath = $filePath
                VectorDbPath = $VectorDbPath
                OllamaUrl = $OllamaUrl
                EmbeddingModel = $EmbeddingModel
                TempDir = $TempDir
                ScriptPath = $scriptPath
                CollectionName = $CollectionName
                FileId = $fileId
                CollectionId = $collectionId
            }
            
            # Add any additional parameters passed to the processor script
            foreach ($key in $HandlerScriptParams.Keys) {
                $scriptParams[$key] = $HandlerScriptParams[$key]
            }
            
            # Execute the custom processor script
            & $HandlerScript @scriptParams
            
            Write-Log "Custom processor script completed for: $filePath"
        }
        catch {
            Write-Log "Error in custom processor script: $_" -Level "ERROR"
        }
    }
    # Otherwise use the default processing logic
    else {
        # Get file extension
        $fileExtension = [System.IO.Path]::GetExtension($filePath).ToLower()
        
        # Split extension lists into arrays
        $textExtensions = $TextFileExtensions.Split(',') | ForEach-Object { $_.Trim().ToLower() }
        $pdfExtension = $PDFFileExtension.Trim().ToLower()
        
        # Process based on file type
        if ($fileExtension -eq $pdfExtension) {
            Write-Log "Processing PDF file: $filePath"
            Process-PDFFile -FilePath $filePath
        }
        elseif ($textExtensions -contains $fileExtension) {
            Write-Log "Processing text file: $filePath"
            Process-TextFile -FilePath $filePath
        }
        else {
            Write-Log "Unsupported file type ($fileExtension): $filePath" -Level "WARNING"
        }
    }
    
    # Mark the file as processed in the database
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        $updateCommand = $connection.CreateCommand()
        $updateCommand.CommandText = "UPDATE files SET Dirty = 0 WHERE id = @FileId"
        $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FileId", $fileId)))
        $updateCommand.ExecuteNonQuery()
        
        $connection.Close()
        $connection.Dispose()
        
        Write-Log "Marked file as processed: $filePath (ID: $fileId)"
    }
    catch {
        Write-Log "Error marking file as processed: $_" -Level "ERROR"
    }
}

function Process-PDFFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        Write-Log "PDF processing would occur here: $FilePath"
        # Placeholder for PDF processing - could call Convert-PDFToMarkdown.ps1 here
        # For now, just adding to ChromaDB as a placeholder
        Add-ToChromaDB -FilePath $FilePath -Content "PDF content would be processed here"
    }
    catch {
        Write-Log "Error processing PDF file: $_" -Level "ERROR"
    }
}

function Process-TextFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        # Read the file content
        $content = Get-Content -Path $FilePath -Raw
        if ([string]::IsNullOrEmpty($content)) {
            Write-Log "File is empty: $FilePath" -Level "WARNING"
            return
        }
        
        # Add to ChromaDB
        Add-ToChromaDB -FilePath $FilePath -Content $content
    }
    catch {
        Write-Log "Error processing text file: $_" -Level "ERROR"
    }
}

function Add-ToChromaDB {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$Content
    )
    
    try {
        # Save content to a temporary file if necessary
        $useOriginalFile = $false
        $tempFile = $null
        
        if ((Get-Content -Path $FilePath -Raw) -eq $Content) {
            # Content matches file, use the original file
            $useOriginalFile = $true
            $fileToAdd = $FilePath
        } else {
            # Content is different, use a temporary file
            $tempFile = [System.IO.Path]::GetTempFileName() + [System.IO.Path]::GetExtension($FilePath)
            $Content | Set-Content -Path $tempFile -Encoding utf8
            $fileToAdd = $tempFile
        }
        
        # Get the document ID
        $docId = [System.IO.Path]::GetFileName($FilePath)
        Write-Log "Adding document to vector store: $docId"
        
        # Use the Vectors subsystem to add the document
        $vectorsPath = Join-Path -Path $scriptPath -ChildPath "..\Vectors"
        $addDocumentScript = Join-Path -Path $vectorsPath -ChildPath "Functions\Add-DocumentToVectors.ps1"
        
        # Prepare parameters
        $params = @{
            FilePath = $fileToAdd
            ChromaDbPath = $VectorDbPath
        }
        
        if (-not [string]::IsNullOrEmpty($OllamaUrl)) {
            $params.OllamaUrl = $OllamaUrl
        }
        
        if (-not [string]::IsNullOrEmpty($EmbeddingModel)) {
            $params.EmbeddingModel = $EmbeddingModel
        }
        
        if ($ChunkSize -gt 0) {
            $params.ChunkSize = $ChunkSize
        }
        
        if ($ChunkOverlap -gt 0) {
            $params.ChunkOverlap = $ChunkOverlap
        }
        
        # Execute the script
        & $addDocumentScript @params
        
        # Clean up temporary file if created
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item -Path $tempFile -Force
        }
        
        Write-Log "Successfully added document to vector store: $docId"
        return $true
    }
    catch {
        Write-Log "Error adding document to vector store: $_" -Level "ERROR"
        return $false
    }
}

function Remove-FromChromaDB {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        # Get the document ID
        $docId = [System.IO.Path]::GetFileName($FilePath)
        Write-Log "Removing document from vector store: $docId"
        
        # Use the Vectors subsystem to remove the document
        $vectorsPath = Join-Path -Path $scriptPath -ChildPath "..\Vectors"
        $removeDocumentScript = Join-Path -Path $vectorsPath -ChildPath "Functions\Remove-DocumentFromVectors.ps1"
        
        # Prepare parameters
        $params = @{
            FilePath = $FilePath
            ChromaDbPath = $VectorDbPath
        }
        
        if (-not [string]::IsNullOrEmpty($OllamaUrl)) {
            $params.OllamaUrl = $OllamaUrl
        }
        
        if (-not [string]::IsNullOrEmpty($EmbeddingModel)) {
            $params.EmbeddingModel = $EmbeddingModel
        }
        
        # Execute the script
        & $removeDocumentScript @params
        
        Write-Log "Successfully removed document from vector store: $docId"
        return $true
    }
    catch {
        Write-Log "Error removing document from vector store: $_" -Level "ERROR"
        return $false
    }
}

# Function to check if a stop file exists
function Test-StopFile {
    param (
        [string]$StopFilePath
    )
    
    if (-not [string]::IsNullOrEmpty($StopFilePath) -and (Test-Path -Path $StopFilePath)) {
        Write-Log "Stop file detected at: $StopFilePath. Stopping processing." -Level "WARNING"
        return $true
    }
    
    return $false
}

# Function to process a single batch of dirty files
function Process-CollectionDirtyFilesBatch {
    param(
        [string]$CollectionName,
        [string]$DatabasePath
    )
    
    try {
        Write-Log "Starting dirty files processing for collection: $CollectionName"
        
        # Get list of dirty files from the collection
        Write-Log "Fetching list of dirty files from collection..."
        $getDirtyFilesScript = Join-Path -Path $scriptPath -ChildPath "..\FileTracker\Get-CollectionDirtyFiles.ps1"
        $dirtyFiles = & $getDirtyFilesScript -CollectionName $CollectionName -DatabasePath $DatabasePath -AsObject
        
        if (-not $dirtyFiles -or $dirtyFiles.Count -eq 0) {
            Write-Log "No dirty files found in collection."
            return $true
        }
        
        Write-Log "Found $($dirtyFiles.Count) dirty files to process in collection '$CollectionName'."
        
        # Process each dirty file
        foreach ($file in $dirtyFiles) {
            Process-DirtyFile -FileInfo $file
            
            # Check for stop file after each file in case we need to abort mid-batch
            if (Test-StopFile -StopFilePath $StopFilePath) {
                return $false
            }
        }
        
        Write-Log "Completed processing all dirty files in collection '$CollectionName'."
        
        # Clean up temporary files older than 24 hours
        if (Test-Path -Path $TempDir) {
            $oldFiles = Get-ChildItem -Path $TempDir -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-24) }
            if ($oldFiles) {
                Write-Log "Cleaning up $($oldFiles.Count) temporary files older than 24 hours..."
                $oldFiles | Remove-Item -Force | Out-Null
            }
        }
        
        return $true
    }
    catch {
        Write-Log "Error in processing batch: $_" -Level "ERROR"
        return $false
    }
}

# Main Process
try {
    # If running in continuous mode, set up a loop
    if ($Continuous) {
        Write-Log "Starting continuous processing mode for collection '$CollectionName'. Polling every $ProcessInterval minutes."
        Write-Log "To stop processing, create a stop file at: $StopFilePath" -Level "WARNING"
        
        $keepRunning = $true
        $iteration = 0
        
        while ($keepRunning) {
            $iteration++
            Write-Log "Starting iteration $iteration..."
            
            # Check for stop file at the beginning of each loop
            if (Test-StopFile -StopFilePath $StopFilePath) {
                $keepRunning = $false
                break
            }
            
            # Process the current batch of dirty files
            $success = Process-CollectionDirtyFilesBatch -CollectionName $CollectionName -DatabasePath $DatabasePath
            
            # Check if we should continue
            if (-not $success) {
                Write-Log "Batch processing failed or was interrupted. Checking whether to continue..." -Level "WARNING"
                
                if (Test-StopFile -StopFilePath $StopFilePath) {
                    $keepRunning = $false
                    break
                }
            }
            
            # If we're still running, wait for the next interval
            if ($keepRunning) {
                $nextRun = (Get-Date).AddMinutes($ProcessInterval)
                Write-Log "Next processing run scheduled at: $nextRun"
                
                # Sleep in smaller increments to check for stop file periodically
                $sleepIntervalSeconds = 30
                $totalSleepSeconds = $ProcessInterval * 60
                $sleepCount = [math]::Ceiling($totalSleepSeconds / $sleepIntervalSeconds)
                
                for ($i = 0; $i -lt $sleepCount; $i++) {
                    if (Test-StopFile -StopFilePath $StopFilePath) {
                        $keepRunning = $false
                        break
                    }
                    
                    # Calculate remaining sleep time
                    $remainingSeconds = $totalSleepSeconds - ($i * $sleepIntervalSeconds)
                    $sleepTime = [math]::Min($sleepIntervalSeconds, $remainingSeconds)
                    
                    if ($sleepTime -gt 0) {
                        Start-Sleep -Seconds $sleepTime
                    }
                }
            }
        }
        
        Write-Log "Continuous processing has been stopped."
    }
    # Otherwise, just run once
    else {
        $success = Process-CollectionDirtyFilesBatch -CollectionName $CollectionName -DatabasePath $DatabasePath
        if (-not $success) {
            exit 1
        }
    }
}
catch {
    Write-Log "Critical error in main process: $_" -Level "ERROR"
    exit 1
}

Write-Log "Script execution completed successfully."
Write-Log "Log file created at: $logFilePath"
