# ProcessDirtyFiles.ps1
# Identifies dirty files and processes them - converting PDFs to markdown and adding text files to Chroma DB
# Also handles removed files by deleting them from the Chroma DB

#Requires -Version 7.0

param(
    [Parameter(Mandatory=$true)]
    [string]$DirectoryPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [string]$TextFileExtensions = ".txt,.md,.html,.csv,.json",
    
    [Parameter(Mandatory=$false)]
    [string]$PDFFileExtension = ".pdf",
    
    [Parameter(Mandatory=$false)]
    [string]$ProcessorScript,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$ProcessorScriptParams = @{},
    
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


# Import required functions
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$fileTrackerModule = Join-Path -Path $scriptPath -ChildPath "..\FileTracker\FileTracker-Shared.psm1"
$VectorDbPath = Join-Path -Path $DirectoryPath -ChildPath ".ai\Vectors"
if (Test-Path $fileTrackerModule) {
    Import-Module $fileTrackerModule -Force
}
else {
    Write-Error "FileTracker module not found at: $fileTrackerModule"
    exit 1
}

# Ensure temp directory exists
$TempDir = Join-Path -Path $DirectoryPath -ChildPath ".ai\temp"
if (-not (Test-Path -Path $TempDir)) {
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
}

# Initialize log file
$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "ProcessDirtyFiles_$logDate.log"
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
        Write-Host $logMessage
    }
    elseif ($Level -eq "WARNING") {
        Write-Host $logMessage
    }
    elseif ($Verbose -or $Level -eq "INFO") {
        Write-Host $logMessage
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
    Write-Log "Processing dirty file: $filePath"
    
    # Check if file exists
    if (-not (Test-Path -Path $filePath)) {
        Write-Log "File no longer exists, removing from Chroma DB: $filePath" -Level "WARNING"
        Remove-FromChromaDB -FilePath $filePath
        return
    }
    
    # If a custom processor script is provided, use it
    if ($ProcessorScript) {
        try {
            if (-not (Test-Path -Path $ProcessorScript)) {
                Write-Log "Custom processor script not found: $ProcessorScript" -Level "ERROR"
                return
            }
            
            Write-Log "Using custom processor script: $ProcessorScript"
            
            # Prepare parameters for the processor script
            $scriptParams = @{
                FilePath = $filePath
                VectorDbPath = $VectorDbPath
                OllamaUrl = $OllamaUrl
                EmbeddingModel = $EmbeddingModel
                TempDir = $TempDir
                ScriptPath = $scriptPath
            }
            
            # Add any additional parameters passed to the processor script
            foreach ($key in $ProcessorScriptParams.Keys) {
                $scriptParams[$key] = $ProcessorScriptParams[$key]
            }
            
            # Execute the custom processor script
            & $ProcessorScript @scriptParams
            
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
    
    # Mark the file as processed in the tracker
    try {
        $markProcessedScript = Join-Path -Path $scriptPath -ChildPath "..\FileTracker\Mark-FileAsProcessed.ps1"
        & $markProcessedScript -FolderPath $FolderPath -FilePath $filePath
        Write-Log "Marked file as processed: $filePath"
    }
    catch {
        Write-Log "Error marking file as processed: $_" -Level "ERROR"
    }
}

function Remove-FromChromaDB {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        # Create a temporary Python script to delete the document from ChromaDB
        $docId = [System.IO.Path]::GetFileName($FilePath)
        Write-Log "Removing document from ChromaDB: $docId"
        
        $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

        $pythonCode = @"
import sys
import chromadb
from chromadb.config import Settings

try:
    # Setup ChromaDB client
    chroma_client = chromadb.PersistentClient(path='$($VectorDbPath.Replace("\", "\\"))', settings=Settings(anonymized_telemetry=False))
    
    # Get collections
    document_collection = chroma_client.get_or_create_collection(name="document_collection")
    chunks_collection = chroma_client.get_or_create_collection(name="document_chunks_collection")
    
    # Remove any existing entries for this file from document_collection
    try:
        # Try deleting by file path in metadata
        document_collection.delete(where={"source": "$($FilePath.Replace("\", "\\"))"})
        print(f"Deleted document with source: $($FilePath.Replace("\", "\\"))")
    except Exception as e:
        print(f"Error when trying to delete by metadata in document_collection: {str(e)}")
        
    try:
        # Also try deleting by ID
        doc_id = "$docId"
        existing_ids = document_collection.get(ids=[doc_id])
        if existing_ids["ids"]:
            document_collection.delete(ids=[doc_id])
            print(f"Deleted document with ID: {doc_id}")
    except Exception as e:
        print(f"Error when trying to delete by ID in document_collection: {str(e)}")
    
    # Remove any existing chunks for this file from chunks_collection
    try:
        # Try deleting by file path in metadata
        chunks_collection.delete(where={"source": "$($FilePath.Replace("\", "\\"))"})
        print(f"Deleted chunks with source: $($FilePath.Replace("\", "\\"))")
    except Exception as e:
        print(f"Error when trying to delete chunks by metadata: {str(e)}")
    
    # Check for chunks with IDs starting with doc_id
    try:
        base_id = "$docId"
        # This is a bit of a hack since Chroma doesn't support startswith queries directly
        # We'll just try to get all IDs and filter them manually
        all_ids = chunks_collection.get()["ids"]
        chunk_ids = [id for id in all_ids if id.startswith(f"{base_id}_chunk_")]
        
        if chunk_ids:
            chunks_collection.delete(ids=chunk_ids)
            print(f"Deleted {len(chunk_ids)} chunks with IDs starting with {base_id}_chunk_")
    except Exception as e:
        print(f"Error when trying to delete chunks by ID: {str(e)}")
    
    print("Document removal complete")
    sys.exit(0)
except Exception as e:
    print(f"Error removing document from ChromaDB: {str(e)}")
    sys.exit(1)
"@

        $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
        
        # Execute the Python script
        $results = python $tempPythonScript 2>&1
        foreach ($line in $results) {
            Write-Log $line
        }
        
        # Clean up
        $null = Remove-Item -Path $tempPythonScript -Force
        
        Write-Log "Successfully removed document from ChromaDB: $docId"
    }
    catch {
        Write-Log "Error removing document from ChromaDB: $_" -Level "ERROR"
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
function Process-DirtyFilesBatch {
    param(
        [string]$DirectoryPath
    )
    
    try {
        Write-Log "Starting dirty files processing for folder: $DirectoryPath"
        
        # Check if folder exists
        if (-not (Test-Path -Path $DirectoryPath)) {
            Write-Log "Folder does not exist: $DirectoryPath" -Level "ERROR"
            return $false
        }
        
        # Get list of dirty files
        Write-Log "Fetching list of dirty files..."
        $getDirtyFilesScript = Join-Path -Path $scriptPath -ChildPath "..\FileTracker\Get-DirtyFiles.ps1"
        $dirtyFiles = & $getDirtyFilesScript -FolderPath $DirectoryPath -AsObject
        
        if (-not $dirtyFiles -or $dirtyFiles.Count -eq 0) {
            Write-Log "No dirty files found."
            return $true
        }
        
        Write-Log "Found $($dirtyFiles.Count) dirty files to process."
        
        # Process each dirty file
        foreach ($file in $dirtyFiles) {
            Process-DirtyFile -FileInfo $file
            
            # Check for stop file after each file in case we need to abort mid-batch
            if (Test-StopFile -StopFilePath $StopFilePath) {
                return $false
            }
        }
        
        Write-Log "Completed processing all dirty files."
        
        # Clean up temporary files older than 24 hours
        if (Test-Path -Path $TempDir) {
            $oldFiles = Get-ChildItem -Path $TempDir -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-24) }
            if ($oldFiles) {
                Write-Log "Cleaning up $($oldFiles.Count) temporary files older than 24 hours..."
                $oldFiles | Remove-Item -Force | Out-Null
            }
        }
        
        # Make sure all dirty flags are cleared
        try {
            Write-Log "Ensuring all dirty flags are cleared..."
            $processedFiles = $dirtyFiles | ForEach-Object { $_.FilePath }
            
            if ($processedFiles -and $processedFiles.Count -gt 0) {
                Write-Log "Clearing dirty flags for $($processedFiles.Count) processed files."
                
                foreach ($filePath in $processedFiles) {
                    if (Test-Path -Path $filePath) {
                        $markProcessedScript = Join-Path -Path $scriptPath -ChildPath "..\FileTracker\Mark-FileAsProcessed.ps1"
                        & $markProcessedScript -FolderPath $DirectoryPath -FilePath $filePath
                        Write-Log "Final clear dirty flag for: $filePath"
                    }
                }
                
                Write-Log "All dirty flags have been cleared."
            }
            else {
                Write-Log "No files to clear dirty flags for."
            }
        }
        catch {
            Write-Log "Error clearing dirty flags: $_" -Level "ERROR"
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
        Write-Log "Starting continuous processing mode. Polling every $ProcessInterval minutes."
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
            $success = Process-DirtyFilesBatch -DirectoryPath $DirectoryPath
            
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
                $nextRun = (Get-Date).AddMinutes($PollingInterval)
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
        $success = Process-DirtyFilesBatch -DirectoryPath $DirectoryPath
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
