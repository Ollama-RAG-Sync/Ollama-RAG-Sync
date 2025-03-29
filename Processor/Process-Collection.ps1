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
        # Create a temporary Python script to add the document to ChromaDB
        $docId = [System.IO.Path]::GetFileName($FilePath)
        Write-Log "Adding document to ChromaDB: $docId"
        
        $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"
        
        $pythonCode = @"
import sys
import os
import chromadb
from chromadb.config import Settings

try:
    # Setup ChromaDB client
    chroma_client = chromadb.PersistentClient(path='$($VectorDbPath.Replace("\", "\\"))', settings=Settings(anonymized_telemetry=False))
    
    # Get or create collections
    document_collection = chroma_client.get_or_create_collection(name="document_collection")
    chunks_collection = chroma_client.get_or_create_collection(name="document_chunks_collection")
    
    # Remove any existing entries for this file
    try:
        document_collection.delete(where={"source": "$($FilePath.Replace("\", "\\"))"})
    except Exception as e:
        print(f"Note: Could not delete by metadata: {str(e)}")
    
    try:
        doc_id = "$docId"
        existing_ids = document_collection.get(ids=[doc_id])
        if existing_ids["ids"]:
            document_collection.delete(ids=[doc_id])
    except Exception as e:
        print(f"Note: Could not delete by ID: {str(e)}")
    
    # Add document metadata
    document_metadata = {
        "source": "$($FilePath.Replace("\", "\\"))",
        "filename": os.path.basename("$($FilePath.Replace("\", "\\"))"),
        "collection_name": "$CollectionName"
    }
    
    # Store full document content
    full_content = """$($Content.Replace('"', '\"').Replace('"""', '\"""'))"""
    
    document_collection.add(
        ids=[doc_id],
        documents=[full_content],
        metadatas=[document_metadata]
    )
    
    # If chunking is enabled
    if $($UseChunking.ToString().ToLower()):
        # Remove any existing chunks
        try:
            chunks_collection.delete(where={"source": "$($FilePath.Replace("\", "\\"))"})
        except Exception as e:
            print(f"Note: Could not delete chunks by metadata: {str(e)}")
        
        # Simple chunking approach
        chunk_size = $ChunkSize
        chunk_overlap = $ChunkOverlap
        
        words = full_content.split()
        chunks = []
        chunk_ids = []
        chunk_metadatas = []
        
        for i in range(0, len(words), chunk_size - chunk_overlap):
            if i > 0:
                start_idx = i - chunk_overlap
            else:
                start_idx = i
                
            end_idx = min(i + chunk_size, len(words))
            chunk = " ".join(words[start_idx:end_idx])
            
            chunk_id = f"{doc_id}_chunk_{len(chunks)}"
            chunk_metadata = document_metadata.copy()
            chunk_metadata["chunk_id"] = len(chunks)
            chunk_metadata["chunk_start"] = start_idx
            chunk_metadata["chunk_end"] = end_idx
            
            chunks.append(chunk)
            chunk_ids.append(chunk_id)
            chunk_metadatas.append(chunk_metadata)
            
            if end_idx >= len(words):
                break
        
        # Add chunks to collection
        if chunks:
            chunks_collection.add(
                ids=chunk_ids,
                documents=chunks,
                metadatas=chunk_metadatas
            )
            print(f"Added {len(chunks)} chunks to ChromaDB")
    
    print("Document successfully added to ChromaDB")
    sys.exit(0)
except Exception as e:
    print(f"Error adding document to ChromaDB: {str(e)}")
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
        
        Write-Log "Successfully added document to ChromaDB: $docId"
    }
    catch {
        Write-Log "Error adding document to ChromaDB: $_" -Level "ERROR"
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
