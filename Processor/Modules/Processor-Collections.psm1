# Processor-Files.psm1
# Contains functions for processing collection files

function Process-CollectionFile {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$FileInfo,
        
        [Parameter(Mandatory=$true)]
        [string]$HandlerScript,
        
        # VectorDbPath parameter removed
        
        [Parameter(Mandatory=$true)]
        [string]$TempDir,
        
        [Parameter(Mandatory=$true)]
        [string]$OllamaUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$EmbeddingModel,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory=$true)]
        [bool]$UseChunking,
        
        [Parameter(Mandatory=$true)]
        [int]$ChunkSize,
        
        [Parameter(Mandatory=$true)]
        [int]$ChunkOverlap,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$HandlerScriptParams = @{},
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    $filePath = $FileInfo.FilePath
    $fileId = $FileInfo.Id
    $collectionId = $FileInfo.CollectionId
    $collectionName = $FileInfo.CollectionName
    
    & $WriteLog "Processing file: $filePath (ID: $fileId) in collection: $collectionName"
    
    # Check if file exists
    if (-not (Test-Path -Path $filePath)) {
        & $WriteLog "File no longer exists: $filePath" -Level "WARNING"
        
        # Simply mark the file as processed
        $success = $true
        return $success
    }
    
    # Prepare parameters for the processor script
    $scriptParams = @{
        FilePath = $filePath
        # VectorDbPath assignment removed
        OllamaUrl = $OllamaUrl
        EmbeddingModel = $EmbeddingModel
        TempDir = $TempDir
        ScriptPath = $ScriptPath
        CollectionName = $collectionName
        FileId = $fileId
        CollectionId = $collectionId
        UseChunking = $UseChunking
        ChunkSize = $ChunkSize
        ChunkOverlap = $ChunkOverlap
    }
    
    # Add any additional parameters passed to the processor script
    foreach ($key in $HandlerScriptParams.Keys) {
        $scriptParams[$key] = $HandlerScriptParams[$key]
    }
    
    try {
        # Check if processor script exists
        if (-not (Test-Path -Path $HandlerScript)) {
            & $WriteLog "Processor script not found: $HandlerScript" -Level "ERROR"
            return $false
        }
        
        & $WriteLog "Using processor script: $HandlerScript"
        
        # Execute the processor script
        & $HandlerScript @scriptParams
        
        & $WriteLog "Processor script completed for: $filePath"
        return $true
    }
    catch {
        & $WriteLog "Error executing processor script: $_" -Level "ERROR"
        return $false
    }
}

function Process-Collection {
    param (
        [Parameter(Mandatory=$false)]
        [int]$CollectionId,
        
        [Parameter(Mandatory=$true)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        # VectorDbPath parameter removed
        
        [Parameter(Mandatory=$true)]
        [string]$TempDir,
        
        [Parameter(Mandatory=$true)]
        [string]$OllamaUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$EmbeddingModel,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory=$true)]
        [bool]$UseChunking,
        
        [Parameter(Mandatory=$true)]
        [int]$ChunkSize,
        
        [Parameter(Mandatory=$true)]
        [int]$ChunkOverlap,
        
        [Parameter(Mandatory=$false)]
        [string]$CustomProcessorScript,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$CustomProcessorParams = @{},
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionDirtyFiles,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionDeletedFiles,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionProcessor,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$MarkFileAsProcessed
    )
    
    # If CollectionId is provided, log both name and ID
    if ($CollectionId) {
        & $WriteLog "Processing collection: $CollectionName (ID: $CollectionId)"
    } else {
        & $WriteLog "Processing collection: $CollectionName"
    }
    
    # Get dirty files from the collection (using either ID or Name)
    if ($CollectionId) {
        $dirtyFiles = & $GetCollectionDirtyFiles -CollectionId $CollectionId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } else {
        $dirtyFiles = & $GetCollectionDirtyFiles -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    }
    
    # Get deleted files from the collection (using either ID or Name)
    if ($CollectionId) {
        $deletedFiles = & $GetCollectionDeletedFiles -CollectionId $CollectionId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } else {
        $deletedFiles = & $GetCollectionDeletedFiles -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    }
    
    $totalFilesToProcess = 0
    if ($dirtyFiles) { $totalFilesToProcess += $dirtyFiles.Count }
    if ($deletedFiles) { $totalFilesToProcess += $deletedFiles.Count }
    
    if ($totalFilesToProcess -eq 0) {
        & $WriteLog "No files to process found in collection: $CollectionName"
        return @{
            success = $true
            message = "No files to process found in collection"
            processed = 0
            errors = 0
        }
    }
    
    if ($dirtyFiles) {
        & $WriteLog "Found $($dirtyFiles.Count) dirty files to process in collection: $CollectionName"
    }
    
    if ($deletedFiles) {
        & $WriteLog "Found $($deletedFiles.Count) deleted files to process in collection: $CollectionName"
    }
    
    # Get processor script from database if custom not provided
    $processorScript = $CustomProcessorScript
    $processorParams = $CustomProcessorParams
    
    if (-not $processorScript) {
        $collectionProcessor = & $GetCollectionProcessor -CollectionName $CollectionName -DatabasePath $DatabasePath -WriteLog $WriteLog
        
        if ($collectionProcessor) {
            $processorScript = $collectionProcessor.ProcessorScript
            $processorParams = $collectionProcessor.ProcessorParams
            & $WriteLog "Using processor script from database: $processorScript"
        }
        else {
            # If no custom or database processor, use the default
            $processorScript = Join-Path -Path $ScriptPath -ChildPath "Update-LocalChromaDb.ps1"
            & $WriteLog "No custom processor found, using default: $processorScript"
        }
    }
    
    # Process each file
    $processed = 0
    $errors = 0
    
    # Process dirty files
    if ($dirtyFiles) {
        foreach ($file in $dirtyFiles) {
            # Add collection name to file info (not included in API response)
            $file | Add-Member -MemberType NoteProperty -Name "CollectionName" -Value $CollectionName
            
            # VectorDbPath argument removed from call
            $success = Process-CollectionFile -FileInfo $file -HandlerScript $processorScript -HandlerScriptParams $processorParams `
                -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel `
                -ScriptPath $ScriptPath -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap -WriteLog $WriteLog
            
            if ($success) {
                # Mark file as processed (using either ID or Name)
                if ($CollectionId) {
                    $markResult = & $MarkFileAsProcessed -CollectionId $CollectionId -FileId $file.Id -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                } else {
                    $markResult = & $MarkFileAsProcessed -CollectionName $CollectionName -FileId $file.Id -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                }
                
                if ($markResult) {
                    $processed++
                    & $WriteLog "Successfully processed and marked as processed: $($file.FilePath)"
                }
                else {
                    $errors++
                    & $WriteLog "File was processed but could not be marked as processed: $($file.FilePath)" -Level "ERROR"
                }
            }
            else {
                $errors++
                & $WriteLog "Failed to process file: $($file.FilePath)" -Level "ERROR"
            }
        }
    }
    
    # Process deleted files
    if ($deletedFiles) {
        foreach ($file in $deletedFiles) {
            # Add collection name to file info (not included in API response)
            $file | Add-Member -MemberType NoteProperty -Name "CollectionName" -Value $CollectionName
            
            # For deleted files, treating as non-existent to remove from DB
            # so it will be removed from the Chroma DB
            # VectorDbPath argument removed from call
            $success = Process-CollectionFile -FileInfo $file -HandlerScript $processorScript -HandlerScriptParams $processorParams `
                -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel `
                -ScriptPath $ScriptPath -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap -WriteLog $WriteLog
            
            if ($success) {
                # Mark file as processed (this will typically remove it from the FileTracker database)
                if ($CollectionId) {
                    $markResult = & $MarkFileAsProcessed -CollectionId $CollectionId -FileId $file.Id -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                } else {
                    $markResult = & $MarkFileAsProcessed -CollectionName $CollectionName -FileId $file.Id -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                }
                
                if ($markResult) {
                    $processed++
                    & $WriteLog "Successfully processed deleted file and marked as processed: $($file.FilePath)"
                }
                else {
                    $errors++
                    & $WriteLog "Deleted file was processed but could not be marked as processed: $($file.FilePath)" -Level "ERROR"
                }
            }
            else {
                $errors++
                & $WriteLog "Failed to process deleted file: $($file.FilePath)" -Level "ERROR"
            }
        }
    }
    
    & $WriteLog "Collection processing completed. Processed: $processed, Errors: $errors"
    
    return @{
        success = $true
        message = "Collection processing completed"
        processed = $processed
        errors = $errors
    }
}

Export-ModuleMember -Function Process-CollectionFile, Process-Collection
