# Processor-HTTP.psm1
# Contains HTTP server functions for the processor REST API using Pode

#Requires -Modules Pode

function Start-ProcessorHttpServer {
    param (
        [Parameter(Mandatory=$false)]
        [string]$ListenAddress = "localhost",
        
        [Parameter(Mandatory=$false)]
        [int]$Port = 10005,
        
        [Parameter(Mandatory=$true)]
        [string]$ApiPath,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$TempDir,
        
        [Parameter(Mandatory=$true)]
        [string]$OllamaUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$EmbeddingModel,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath, # Path to the Processor directory
        
        [Parameter(Mandatory=$true)]
        [bool]$UseChunking,
        
        [Parameter(Mandatory=$true)]
        [int]$ChunkSize,
        
        [Parameter(Mandatory=$true)]
        [int]$ChunkOverlap,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollections,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionDirtyFiles,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionDeletedFiles,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionProcessor,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$SetCollectionProcessor,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$RemoveCollectionProcessor,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetProcessorScriptsCount,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$ProcessCollection,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$MarkFileAsProcessed,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetFileDetails
    )
    
    try {
        & $using:WriteLog "Starting Processor REST API server using Pode..."
        & $using:WriteLog "FileTracker API URL: $FileTrackerBaseUrl"
        & $using:WriteLog "Database Path: $DatabasePath"

        Start-PodeServer -Threads 4 {
            Add-PodeEndpoint -Address $ListenAddress -Port $Port -Protocol Http
            # Middleware & OpenAPI Setup
            Enable-PodeOpenApi -Title "Processor API" -Version "1.0.0" -Description "API for managing and triggering file processing tasks" -ErrorAction Stop

            # --- API Routes ---

            # GET /api/status
            Add-PodeRoute -Method Get -Path "$($using:ApiPath)/status" -ScriptBlock {
                try {
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    $processorScriptsCount = & $using:GetProcessorScriptsCount -DatabasePath $using:DatabasePath -WriteLog $using:WriteLog
                    
                    $statusData = @{
                        collections = if ($null -ne $collections) { $collections.Count } else { 0 }
                        processor_scripts = $processorScriptsCount
                        running_since = (Get-PodeServer).StartedAt.ToString("yyyy-MM-dd HH:mm:ss")
                        version = "1.0.0" # Consider making this dynamic later
                    }
                    
                    Write-PodeJsonResponse -Value @{ success = $true; status = $statusData }
                } catch {
                    & $using:WriteLog "Error in GET /status: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } 

            # GET /api/collections
            Add-PodeRoute -Method Get -Path "$($using:ApiPath)/collections" -ScriptBlock {
                try {
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    
                    if ($collections -ne $null) {
                        foreach ($collection in $collections) {
                            $processor = & $using:GetCollectionProcessor -CollectionName $collection.name -DatabasePath $using:DatabasePath -WriteLog $using:WriteLog
                            if ($processor) {
                                $collection | Add-Member -MemberType NoteProperty -Name "has_processor" -Value $true
                                $collection | Add-Member -MemberType NoteProperty -Name "processor_script" -Value $processor.HandlerScript
                            } else {
                                $collection | Add-Member -MemberType NoteProperty -Name "has_processor" -Value $false
                            }
                        }
                        Write-PodeJsonResponse -Value @{ success = $true; collections = $collections; count = $collections.Count }
                    } else {
                        Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Failed to fetch collections from FileTracker" }
                    }
                } catch {
                    & $using:WriteLog "Error in GET /collections: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } 

            # GET /api/collections/{id}/processor
            Add-PodeRoute -Method Get -Path "$($using:ApiPath)/collections/:collectionId/processor" -ScriptBlock {
                try {
                    $collectionId = [int]$WebEvent.Parameters['collectionId']
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                    
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    $collectionName = $collection.name
                    $processor = & $using:GetCollectionProcessor -CollectionName $collectionName -DatabasePath $using:DatabasePath -WriteLog $using:WriteLog
                    
                    if ($processor) {
                        Write-PodeJsonResponse -Value @{ success = $true; processor = $processor }
                    } else {
                        Write-PodeJsonResponse -StatusCode 404 -Value @{ success = $false; error = "No processor found for collection" }
                    }
                } catch {
                    & $using:WriteLog "Error in GET /collections/$($WebEvent.Parameters['collectionId'])/processor: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } -OpenApi @{
                Summary = "Get collection processor"
                Description = "Retrieves the configured processor script and parameters for a specific collection."
                Parameters = @( @{ Name = "collectionId"; In = "path"; Required = $true; Schema = @{ type = "integer" } } )
                Responses = @{
                    "200" = @{ Description = "Processor details"; Content = @{ "application/json" = @{ Schema = @{ type = "object" } } } }
                    "404" = @{ Description = "Collection or processor not found" }
                    "500" = @{ Description = "Internal Server Error" }
                }
            }

            # PUT /api/collections/{id}/processor
            Add-PodeRoute -Method Put -Path "$($using:ApiPath)/collections/:collectionId/processor" -ScriptBlock {
                try {
                    $collectionId = [int]$WebEvent.Parameters['collectionId']
                    $data = $WebEvent.Data
                    
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    if (-not $data -or -not $data.processor_script) { Set-PodeResponseStatus -Code 400; Write-PodeJsonResponse -Value @{ success = $false; error = "Missing required field: processor_script" }; return }
                    
                    $collectionName = $collection.name
                    $processorScript = $data.processor_script
                    $processorParams = if ($data.processor_params) { $data.processor_params } else { @{} }
                    
                    $success = & $using:SetCollectionProcessor -CollectionId $collectionId -CollectionName $collectionName `
                        -HandlerScript $processorScript -HandlerParams $processorParams -DatabasePath $using:DatabasePath -WriteLog $using:WriteLog
                    
                    if ($success) {
                        Write-PodeJsonResponse -Value @{ success = $true; message = "Processor set successfully"; collection_id = $collectionId; collection_name = $collectionName; processor_script = $processorScript }
                    } else {
                        Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Failed to set processor" }
                    }
                } catch {
                    & $using:WriteLog "Error in PUT /collections/$($WebEvent.Parameters['collectionId'])/processor: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            }

            # DELETE /api/collections/{id}/processor
            Add-PodeRoute -Method Delete -Path "$($using:ApiPath)/collections/:collectionId/processor" -ScriptBlock {
                try {
                    $collectionId = [int]$WebEvent.Parameters['collectionId']
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    $collectionName = $collection.name
                    $success = & $using:RemoveCollectionProcessor -CollectionName $collectionName -DatabasePath $using:DatabasePath -WriteLog $using:WriteLog
                    
                    if ($success) {
                        Write-PodeJsonResponse -Value @{ success = $true; message = "Processor removed successfully"; collection_id = $collectionId; collection_name = $collectionName }
                    } else {
                        Write-PodeJsonResponse -StatusCode 404 -Value @{ success = $false; error = "No processor found for collection or failed to remove" }
                    }
                } catch {
                    & $using:WriteLog "Error in DELETE /collections/$($WebEvent.Parameters['collectionId'])/processor: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } -OpenApi @{
                Summary = "Remove collection processor"
                Description = "Removes the custom processor configuration for a specific collection."
                Parameters = @( @{ Name = "collectionId"; In = "path"; Required = $true; Schema = @{ type = "integer" } } )
                Responses = @{
                    "200" = @{ Description = "Processor removed successfully" }
                    "404" = @{ Description = "Collection or processor not found" }
                    "500" = @{ Description = "Internal Server Error" }
                }
            }

            # POST /api/collections/{id}/process
            Add-PodeRoute -Method Post -Path "$($using:ApiPath)/collections/:collectionId/process" -ScriptBlock {
                try {
                    $collectionId = [int]$WebEvent.Parameters['collectionId']
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    $collectionName = $collection.name
                    $data = $WebEvent.Data
                    $customProcessorScript = if ($data.processor_script) { $data.processor_script } else { $null }
                    $customProcessorParams = if ($data.processor_params) { $data.processor_params } else { @{} }
                    
                    # Process the collection (Note: This runs synchronously in the route)
                    $result = & $using:ProcessCollection -CollectionId $collectionId -CollectionName $collectionName `
                        -FileTrackerBaseUrl $using:FileTrackerBaseUrl -DatabasePath $using:DatabasePath `
                        -TempDir $using:TempDir -OllamaUrl $using:OllamaUrl -EmbeddingModel $using:EmbeddingModel -ScriptPath $using:ScriptPath `
                        -UseChunking $using:UseChunking -ChunkSize $using:ChunkSize -ChunkOverlap $using:ChunkOverlap `
                        -CustomProcessorScript $customProcessorScript -CustomProcessorParams $customProcessorParams `
                        -WriteLog $using:WriteLog -GetCollectionDirtyFiles $using:GetCollectionDirtyFiles `
                        -GetCollectionDeletedFiles $using:GetCollectionDeletedFiles `
                        -GetCollectionProcessor $using:GetCollectionProcessor -MarkFileAsProcessed $using:MarkFileAsProcessed
                    
                    Write-PodeJsonResponse -Value @{ success = $true; message = $result.message; collection_id = $collectionId; collection_name = $collectionName; processed_files = $result.processed; errors = $result.errors }
                    
                } catch {
                    & $using:WriteLog "Error in POST /collections/$($WebEvent.Parameters['collectionId'])/process: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            }

            # POST /api/collections/name/{name}/process
            Add-PodeRoute -Method Post -Path "$($using:ApiPath)/collections/name/:collectionName/process" -ScriptBlock {
                 try {
                    $collectionName = $WebEvent.Parameters['collectionName']
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    $collection = $collections | Where-Object { $_.name -eq $collectionName }
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    $collectionId = $collection.id # Get ID for consistency if needed later
                    $data = $WebEvent.Data
                    $customProcessorScript = if ($data.processor_script) { $data.processor_script } else { $null }
                    $customProcessorParams = if ($data.processor_params) { $data.processor_params } else { @{} }
                    
                    # Process the collection (Note: This runs synchronously in the route)
                    $result = & $using:ProcessCollection -CollectionName $collectionName `
                        -FileTrackerBaseUrl $using:FileTrackerBaseUrl -DatabasePath $using:DatabasePath `
                        -TempDir $using:TempDir -OllamaUrl $using:OllamaUrl -EmbeddingModel $using:EmbeddingModel -ScriptPath $using:ScriptPath `
                        -UseChunking $using:UseChunking -ChunkSize $using:ChunkSize -ChunkOverlap $using:ChunkOverlap `
                        -CustomProcessorScript $customProcessorScript -CustomProcessorParams $customProcessorParams `
                        -WriteLog $using:WriteLog -GetCollectionDirtyFiles $using:GetCollectionDirtyFiles `
                        -GetCollectionDeletedFiles $using:GetCollectionDeletedFiles `
                        -GetCollectionProcessor $using:GetCollectionProcessor -MarkFileAsProcessed $using:MarkFileAsProcessed
                    
                    Write-PodeJsonResponse -Value @{ success = $true; message = $result.message; collection_name = $collectionName; processed_files = $result.processed; errors = $result.errors }
                    
                } catch {
                    & $using:WriteLog "Error in POST /collections/name/$($WebEvent.Parameters['collectionName'])/process: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            }

            # POST /api/process
            Add-PodeRoute -Method Post -Path "$($using:ApiPath)/process" -ScriptBlock {
                try {
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    if (-not $collections -or $collections.Count -eq 0) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "No collections found" }; return }
                    
                    $totalProcessed = 0
                    $totalErrors = 0
                    $collectionResults = @()
                    
                    foreach ($collection in $collections) {
                        $collectionName = $collection.name
                        $collectionId = $collection.id
                        & $using:WriteLog "Processing collection: $collectionName (ID: $collectionId)"
                        
                        # Process the collection (Note: This runs synchronously in the route)
                        $result = & $using:ProcessCollection -CollectionId $collectionId -CollectionName $collectionName `
                            -FileTrackerBaseUrl $using:FileTrackerBaseUrl -DatabasePath $using:DatabasePath `
                            -TempDir $using:TempDir -OllamaUrl $using:OllamaUrl -EmbeddingModel $using:EmbeddingModel -ScriptPath $using:ScriptPath `
                            -UseChunking $using:UseChunking -ChunkSize $using:ChunkSize -ChunkOverlap $using:ChunkOverlap -WriteLog $using:WriteLog `
                            -GetCollectionDirtyFiles $using:GetCollectionDirtyFiles `
                            -GetCollectionDeletedFiles $using:GetCollectionDeletedFiles `
                            -GetCollectionProcessor $using:GetCollectionProcessor -MarkFileAsProcessed $using:MarkFileAsProcessed
                        
                        $totalProcessed += $result.processed
                        $totalErrors += $result.errors
                        $collectionResults += @{ collection_id = $collectionId; collection_name = $collectionName; processed_files = $result.processed; errors = $result.errors }
                    }
                    
                    Write-PodeJsonResponse -Value @{ success = $true; message = "Processing completed for all collections"; total_processed = $totalProcessed; total_errors = $totalErrors; collections = $collectionResults }
                    
                } catch {
                    & $using:WriteLog "Error in POST /process: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } 

            # POST /api/files/{id}/process
            Add-PodeRoute -Method Post -Path "$($using:ApiPath)/files/:fileId/process" -ScriptBlock {
                try {
                    $fileId = [int]$WebEvent.Parameters['fileId']
                    $data = $WebEvent.Data
                    
                    if (-not $data -or (-not $data.collection_id -and -not $data.collection_name)) { Set-PodeResponseStatus -Code 400; Write-PodeJsonResponse -Value @{ success = $false; error = "Either collection_id or collection_name must be provided" }; return }
                    
                    $collectionId = $data.collection_id
                    $collectionName = $data.collection_name
                    $collections = & $using:GetCollections -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    $collection = $null
                    
                    if ($collectionId) {
                        $collection = $collections | Where-Object { $_.id -eq $collectionId }
                        if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection with ID $collectionId not found" }; return }
                        $collectionName = $collection.name
                    } elseif ($collectionName) {
                        $collection = $collections | Where-Object { $_.name -eq $collectionName }
                        if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection with name '$collectionName' not found" }; return }
                        $collectionId = $collection.id
                    }
                    
                    $file = & $using:GetFileDetails -CollectionId $collectionId -FileId $fileId -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                    if (-not $file) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "File not found in collection" }; return }
                    
                    $file | Add-Member -MemberType NoteProperty -Name "CollectionName" -Value $collectionName
                    
                    $processorScript = if ($data.processor_script) { $data.processor_script } else { $null }
                    $processorParams = if ($data.processor_params) { $data.processor_params } else { @{} }
                    
                    if (-not $processorScript) {
                        $collectionProcessor = & $using:GetCollectionProcessor -CollectionName $collectionName -DatabasePath $using:DatabasePath -WriteLog $using:WriteLog
                        if ($collectionProcessor) {
                            $processorScript = $collectionProcessor.HandlerScript
                            $processorParams = $collectionProcessor.HandlerParams
                        } else {
                            $processorScript = Join-Path -Path $using:ScriptPath -ChildPath "Handlers\Update-LocalChromaDb.ps1" # Default processor
                        }
                    }
                    
                    # Import the file processing module locally (needed if running in separate runspace/thread)
                    $processorFilesModule = Join-Path -Path $using:ScriptPath -ChildPath "Modules\Processor-Files.psm1"
                    Import-Module $processorFilesModule -Force
                    
                    $success = Process-CollectionFile -FileInfo $file -HandlerScript $processorScript `
                        -HandlerScriptParams $processorParams -TempDir $using:TempDir `
                        -OllamaUrl $using:OllamaUrl -EmbeddingModel $using:EmbeddingModel -ScriptPath $using:ScriptPath `
                        -UseChunking $using:UseChunking -ChunkSize $using:ChunkSize -ChunkOverlap $using:ChunkOverlap -WriteLog $using:WriteLog
                    
                    if ($success) {
                        $markResult = & $using:MarkFileAsProcessed -CollectionId $collectionId -FileId $fileId -FileTrackerBaseUrl $using:FileTrackerBaseUrl -WriteLog $using:WriteLog
                        if ($markResult) {
                            Write-PodeJsonResponse -Value @{ success = $true; message = "File processed and marked successfully"; file_id = $fileId; file_path = $file.FilePath; collection_id = $collectionId; collection_name = $collectionName }
                        } else {
                            Set-PodeResponseStatus -Code 500
                            Write-PodeJsonResponse -Value @{ success = $false; error = "File processed but failed to mark as processed" }
                        }
                    } else {
                        Set-PodeResponseStatus -Code 500
                        Write-PodeJsonResponse -Value @{ success = $false; error = "Failed to process file" }
                    }
                    
                } catch {
                    & $using:WriteLog "Error in POST /files/$($WebEvent.Parameters['fileId'])/process: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            }
        }

        & $using:WriteLog "Processor REST API server running at http://localhost:$Port"
        & $using:WriteLog "Press Ctrl+C to stop the server."

    } catch {
        & $using:WriteLog "Fatal error starting Pode server: $_" -Level "ERROR"
        & $using:WriteLog "$($_.ScriptStackTrace)" -Level "ERROR"
        throw $_ # Rethrow to allow Start-Processor.ps1 to catch it
    }
}

Export-ModuleMember -Function Start-ProcessorHttpServer
