# Processor-HTTP.psm1
# Contains HTTP server functions for the processor REST API

function Get-RequestBody {
    param (
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerRequest]$Request,
        
        [Parameter(Mandatory=$false)]
        [switch]$AsObject = $false,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        if ($Request.HasEntityBody) {
            $bodyReader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
            $bodyContent = $bodyReader.ReadToEnd()
            
            if ($AsObject -and $bodyContent) {
                try {
                    return $bodyContent | ConvertFrom-Json
                }
                catch {
                    & $WriteLog "Failed to parse request body as JSON: $_" -Level "ERROR"
                    return $null
                }
            }
            
            return $bodyContent
        }
    }
    catch {
        & $WriteLog "Error reading request body: $_" -Level "ERROR"
    }
    
    return $null
}

function Send-Response {
    param (
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory=$false)]
        [int]$StatusCode = 200,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Body,
        
        [Parameter(Mandatory=$false)]
        [string]$ContentType = "application/json",
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = $ContentType
        
        # Add CORS headers
        $Response.Headers.Add("Access-Control-Allow-Origin", "*")
        $Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        $Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        
        $jsonResponse = $Body | ConvertTo-Json -Depth 10
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
        
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.OutputStream.Close()
    }
    catch {
        & $WriteLog "Error sending response: $_" -Level "ERROR"
    }
}

function Send-ErrorResponse {
    param (
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerResponse]$Response,
        
        [Parameter(Mandatory=$false)]
        [int]$StatusCode = 400,
        
        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage = "Bad Request",
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    $errorBody = @{
        success = $false
        error = $ErrorMessage
    }
    
    Send-Response -Response $Response -StatusCode $StatusCode -Body $errorBody -WriteLog $WriteLog
}

function Start-ProcessorHttpServer {
    param (
        [Parameter(Mandatory=$true)]
        [int]$Port,
        
        [Parameter(Mandatory=$true)]
        [string]$ApiPath,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$VectorDbPath,
        
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
        # Define base URL for the API
        $baseUrl = "http://localhost:$Port$ApiPath"
        
        # Initialize the HTTP listener
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://localhost:$Port/")
        $listener.Start()
        
        & $WriteLog "HTTP server started at http://localhost:$Port/"
        & $WriteLog "API endpoints available at $baseUrl"
        
        # Main request handling loop
        while ($listener.IsListening) {
            # Wait for a request
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $urlPath = $request.Url.AbsolutePath
            $method = $request.HttpMethod
            
            # Log the request
            & $WriteLog "$method $urlPath" -Level "INFO"
            
            # Handle CORS preflight requests
            if ($method -eq "OPTIONS") {
                Send-Response -Response $response -StatusCode 200 -Body @{ success = $true } -WriteLog $WriteLog
                continue
            }
            
            try {
                # Process API requests
                if ($urlPath.StartsWith($ApiPath)) {
                    # Extract the endpoint part of the URL (after the API path)
                    $endpoint = $urlPath.Substring($ApiPath.Length).TrimStart('/')
                    
                    # Route the request to the appropriate handler
                    switch -Regex ($endpoint) {
                        # GET /status - Get processor status
                        "^status$" {
                            if ($method -eq "GET") {
                                # Get all collections
                                $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                
                                $statusData = @{
                                    collections = $collections.Count
                                    processor_scripts = 0
                                    running_since = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                    version = "1.0.0"
                                }
                                
                                # Get processor scripts count
                                $statusData.processor_scripts = & $GetProcessorScriptsCount -DatabasePath $DatabasePath -WriteLog $WriteLog
                                
                                $body = @{
                                    success = $true
                                    status = $statusData
                                }
                                
                                Send-Response -Response $response -Body $body -WriteLog $WriteLog
                            }
                            else {
                                Send-ErrorResponse -Response $response -StatusCode 405 -ErrorMessage "Method Not Allowed" -WriteLog $WriteLog
                            }
                            break
                        }
                        
                        # GET /collections - Get all collections
                        "^collections$" {
                            if ($method -eq "GET") {
                                $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                
                                if ($collections -ne $null) {
                                    # Add processor info to each collection
                                    foreach ($collection in $collections) {
                                        $processor = & $GetCollectionProcessor -CollectionName $collection.name -DatabasePath $DatabasePath -WriteLog $WriteLog
                                        
                                        if ($processor) {
                                            $collection | Add-Member -MemberType NoteProperty -Name "has_processor" -Value $true
                                            $collection | Add-Member -MemberType NoteProperty -Name "processor_script" -Value $processor.HandlerScript
                                        }
                                        else {
                                            $collection | Add-Member -MemberType NoteProperty -Name "has_processor" -Value $false
                                        }
                                    }
                                    
                                    $body = @{
                                        success = $true
                                        collections = $collections
                                        count = $collections.Count
                                    }
                                    
                                    Send-Response -Response $response -Body $body -WriteLog $WriteLog
                                }
                                else {
                                    Send-ErrorResponse -Response $response -StatusCode 500 -ErrorMessage "Failed to fetch collections from FileTracker" -WriteLog $WriteLog
                                }
                            }
                            else {
                                Send-ErrorResponse -Response $response -StatusCode 405 -ErrorMessage "Method Not Allowed" -WriteLog $WriteLog
                            }
                            break
                        }
                        
                        # GET /collections/{id}/processor - Get collection processor
                        # PUT /collections/{id}/processor - Set collection processor
                        # DELETE /collections/{id}/processor - Remove collection processor
                        "^collections/(\d+)/processor$" {
                            $collectionId = [int]$Matches[1]
                            
                            # Get collection details to verify it exists and get the name
                            $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                            $collection = $collections | Where-Object { $_.id -eq $collectionId }
                            
                            if (-not $collection) {
                                Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "Collection not found" -WriteLog $WriteLog
                                break
                            }
                            
                            $collectionName = $collection.name
                            
                            if ($method -eq "GET") {
                                $processor = & $GetCollectionProcessor -CollectionName $collectionName -DatabasePath $DatabasePath -WriteLog $WriteLog
                                
                                if ($processor) {
                                    $body = @{
                                        success = $true
                                        processor = $processor
                                    }
                                    
                                    Send-Response -Response $response -Body $body -WriteLog $WriteLog
                                }
                                else {
                                    Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "No processor found for collection" -WriteLog $WriteLog
                                }
                            }
                            elseif ($method -eq "PUT") {
                                $requestBody = Get-RequestBody -Request $request -AsObject -WriteLog $WriteLog
                                
                                if (-not $requestBody -or -not $requestBody.processor_script) {
                                    Send-ErrorResponse -Response $response -StatusCode 400 -ErrorMessage "Missing required field: processor_script" -WriteLog $WriteLog
                                    break
                                }
                                
                                $processorScript = $requestBody.processor_script
                                $processorParams = if ($requestBody.processor_params) { $requestBody.processor_params } else { @{} }
                                
                                $success = & $SetCollectionProcessor -CollectionId $collectionId -CollectionName $collectionName `
                                    -HandlerScript $processorScript -HandlerParams $processorParams -DatabasePath $DatabasePath -WriteLog $WriteLog
                                
                                if ($success) {
                                    $body = @{
                                        success = $true
                                        message = "Processor set successfully"
                                        collection_id = $collectionId
                                        collection_name = $collectionName
                                        processor_script = $processorScript
                                    }
                                    
                                    Send-Response -Response $response -Body $body -WriteLog $WriteLog
                                }
                                else {
                                    Send-ErrorResponse -Response $response -StatusCode 500 -ErrorMessage "Failed to set processor" -WriteLog $WriteLog
                                }
                            }
                            elseif ($method -eq "DELETE") {
                                $success = & $RemoveCollectionProcessor -CollectionName $collectionName -DatabasePath $DatabasePath -WriteLog $WriteLog
                                
                                if ($success) {
                                    $body = @{
                                        success = $true
                                        message = "Processor removed successfully"
                                        collection_id = $collectionId
                                        collection_name = $collectionName
                                    }
                                    
                                    Send-Response -Response $response -Body $body -WriteLog $WriteLog
                                }
                                else {
                                    Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "No processor found for collection" -WriteLog $WriteLog
                                }
                            }
                            else {
                                Send-ErrorResponse -Response $response -StatusCode 405 -ErrorMessage "Method Not Allowed" -WriteLog $WriteLog
                            }
                            break
                        }
                        
                        # POST /collections/{id}/process - Process all dirty files in a collection
                        "^collections/(\d+)/process$" {
                            $collectionId = [int]$Matches[1]
                            
                            if ($method -eq "POST") {
                                # Get collection details
                                $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                $collection = $collections | Where-Object { $_.id -eq $collectionId }
                                
                                if (-not $collection) {
                                    Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "Collection not found" -WriteLog $WriteLog
                                    break
                                }
                                
                                $collectionName = $collection.name
                                
                                # Check for custom processor in request
                                $requestBody = Get-RequestBody -Request $request -AsObject -WriteLog $WriteLog
                                $customProcessorScript = if ($requestBody.processor_script) { $requestBody.processor_script } else { $null }
                                $customProcessorParams = if ($requestBody.processor_params) { $requestBody.processor_params } else { @{} }
                                
                                # Create script blocks for API calls from inside ProcessCollection
                                $getCollectionDirtyFilesBlock = $GetCollectionDirtyFiles
                                $getCollectionDeletedFilesBlock = $GetCollectionDeletedFiles
                                $getCollectionProcessorBlock = $GetCollectionProcessor
                                $markFileAsProcessedBlock = $MarkFileAsProcessed
                                
                                # Process the collection
                                $result = & $ProcessCollection -CollectionId $collectionId -CollectionName $collectionName `
                                    -FileTrackerBaseUrl $FileTrackerBaseUrl -DatabasePath $DatabasePath -VectorDbPath $VectorDbPath `
                                    -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath `
                                    -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap `
                                    -CustomProcessorScript $customProcessorScript -CustomProcessorParams $customProcessorParams `
                                    -WriteLog $WriteLog -GetCollectionDirtyFiles $getCollectionDirtyFilesBlock `
                                    -GetCollectionDeletedFiles $getCollectionDeletedFilesBlock `
                                    -GetCollectionProcessor $getCollectionProcessorBlock -MarkFileAsProcessed $markFileAsProcessedBlock
                                
                                $body = @{
                                    success = $true
                                    message = $result.message
                                    collection_id = $collectionId
                                    collection_name = $collectionName
                                    processed_files = $result.processed
                                    errors = $result.errors
                                }
                                
                                Send-Response -Response $response -Body $body -WriteLog $WriteLog
                            }
                            else {
                                Send-ErrorResponse -Response $response -StatusCode 405 -ErrorMessage "Method Not Allowed" -WriteLog $WriteLog
                            }
                            break
                        }
                        
                        # POST /collections/name/{name}/process - Process all dirty files in a collection by name
                        "^collections/name/([^/]+)/process$" {
                            $collectionName = $Matches[1]
                            
                            if ($method -eq "POST") {
                                # Get collection details
                                $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                $collection = $collections | Where-Object { $_.name -eq $collectionName }
                                
                                if (-not $collection) {
                                    Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "Collection not found" -WriteLog $WriteLog
                                    break
                                }
                                
                                # Check for custom processor in request
                                $requestBody = Get-RequestBody -Request $request -AsObject -WriteLog $WriteLog
                                $customProcessorScript = if ($requestBody.processor_script) { $requestBody.processor_script } else { $null }
                                $customProcessorParams = if ($requestBody.processor_params) { $requestBody.processor_params } else { @{} }
                                
                                # Create script blocks for API calls from inside ProcessCollection
                                $getCollectionDirtyFilesBlock = $GetCollectionDirtyFiles
                                $getCollectionDeletedFilesBlock = $GetCollectionDeletedFiles
                                $getCollectionProcessorBlock = $GetCollectionProcessor
                                $markFileAsProcessedBlock = $MarkFileAsProcessed
                                
                                # Process the collection
                                $result = & $ProcessCollection -CollectionName $collectionName `
                                    -FileTrackerBaseUrl $FileTrackerBaseUrl -DatabasePath $DatabasePath -VectorDbPath $VectorDbPath `
                                    -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath `
                                    -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap `
                                    -CustomProcessorScript $customProcessorScript -CustomProcessorParams $customProcessorParams `
                                    -WriteLog $WriteLog -GetCollectionDirtyFiles $getCollectionDirtyFilesBlock `
                                    -GetCollectionDeletedFiles $getCollectionDeletedFilesBlock `
                                    -GetCollectionProcessor $getCollectionProcessorBlock -MarkFileAsProcessed $markFileAsProcessedBlock
                                
                                $body = @{
                                    success = $true
                                    message = $result.message
                                    collection_name = $collectionName
                                    processed_files = $result.processed
                                    errors = $result.errors
                                }
                                
                                Send-Response -Response $response -Body $body -WriteLog $WriteLog
                            }
                            else {
                                Send-ErrorResponse -Response $response -StatusCode 405 -ErrorMessage "Method Not Allowed" -WriteLog $WriteLog
                            }
                            break
                        }
                        
                        # POST /process - Process all dirty and deleted files in all collections
                        "^process$" {
                            if ($method -eq "POST") {
                                # Get all collections
                                $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                
                                if (-not $collections -or $collections.Count -eq 0) {
                                    Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "No collections found" -WriteLog $WriteLog
                                    break
                                }
                                
                                $totalProcessed = 0
                                $totalErrors = 0
                                $collectionResults = @()
                                
                                # Create script blocks for API calls from inside ProcessCollection
                                $getCollectionDirtyFilesBlock = $GetCollectionDirtyFiles
                                $getCollectionDeletedFilesBlock = $GetCollectionDeletedFiles
                                $getCollectionProcessorBlock = $GetCollectionProcessor
                                $markFileAsProcessedBlock = $MarkFileAsProcessed
                                
                                # Process each collection
                                foreach ($collection in $collections) {
                                    $collectionName = $collection.name
                                    $collectionId = $collection.id
                                    
                                    & $WriteLog "Processing collection: $collectionName (ID: $collectionId)"
                                    
                                    # Process the collection
                                    $result = & $ProcessCollection -CollectionId $collectionId -CollectionName $collectionName `
                                        -FileTrackerBaseUrl $FileTrackerBaseUrl -DatabasePath $DatabasePath -VectorDbPath $VectorDbPath `
                                        -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath `
                                        -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap -WriteLog $WriteLog `
                                        -GetCollectionDirtyFiles $getCollectionDirtyFilesBlock `
                                        -GetCollectionDeletedFiles $getCollectionDeletedFilesBlock `
                                        -GetCollectionProcessor $getCollectionProcessorBlock -MarkFileAsProcessed $markFileAsProcessedBlock
                                    
                                    $totalProcessed += $result.processed
                                    $totalErrors += $result.errors
                                    
                                    $collectionResults += @{
                                        collection_id = $collectionId
                                        collection_name = $collectionName
                                        processed_files = $result.processed
                                        errors = $result.errors
                                    }
                                }
                                
                                $body = @{
                                    success = $true
                                    message = "Processing completed for all collections"
                                    total_processed = $totalProcessed
                                    total_errors = $totalErrors
                                    collections = $collectionResults
                                }
                                
                                Send-Response -Response $response -Body $body -WriteLog $WriteLog
                            }
                            else {
                                Send-ErrorResponse -Response $response -StatusCode 405 -ErrorMessage "Method Not Allowed" -WriteLog $WriteLog
                            }
                            break
                        }
                        
                        # POST /files/{id}/process - Process a single file by ID
                        "^files/(\d+)/process$" {
                            $fileId = [int]$Matches[1]
                            
                            if ($method -eq "POST") {
                                $requestBody = Get-RequestBody -Request $request -AsObject -WriteLog $WriteLog
                                
                                # Allow request to specify either collection_id or collection_name
                                if (-not $requestBody -or (-not $requestBody.collection_id -and -not $requestBody.collection_name)) {
                                    Send-ErrorResponse -Response $response -StatusCode 400 -ErrorMessage "Either collection_id or collection_name must be provided" -WriteLog $WriteLog
                                    break
                                }
                                
                                # Determine collection ID and name
                                $collectionId = $requestBody.collection_id
                                $collectionName = $requestBody.collection_name
                                $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                
                                if ($collectionId) {
                                    # If collection_id provided, use it to get collection
                                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                                    
                                    if (-not $collection) {
                                        Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "Collection with ID $collectionId not found" -WriteLog $WriteLog
                                        break
                                    }
                                    
                                    $collectionName = $collection.name
                                } elseif ($collectionName) {
                                    # If collection_name provided, use it to get collection
                                    $collection = $collections | Where-Object { $_.name -eq $collectionName }
                                    
                                    if (-not $collection) {
                                        Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "Collection with name '$collectionName' not found" -WriteLog $WriteLog
                                        break
                                    }
                                    
                                    $collectionId = $collection.id
                                }
                                
                                # Get file details from FileTracker
                                try {
                                    $file = & $GetFileDetails -CollectionId $collectionId -FileId $fileId `
                                        -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                    
                                    if (-not $file) {
                                        Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "File not found in collection" -WriteLog $WriteLog
                                        break
                                    }
                                    
                                    # Add collection name to file info
                                    $file | Add-Member -MemberType NoteProperty -Name "CollectionName" -Value $collectionName
                                    
                                    # Get processor script from database or request
                                    $processorScript = if ($requestBody.processor_script) { $requestBody.processor_script } else { $null }
                                    $processorParams = if ($requestBody.processor_params) { $requestBody.processor_params } else { @{} }
                                    
                                    if (-not $processorScript) {
                                        $collectionProcessor = & $GetCollectionProcessor -CollectionName $collectionName `
                                            -DatabasePath $DatabasePath -WriteLog $WriteLog
                                        
                                        if ($collectionProcessor) {
                                    $processorScript = $collectionProcessor.HandlerScript
                                    $processorParams = $collectionProcessor.HandlerParams
                                        }
                                        else {
                                            # Use default processor if no custom processor found
                                            $processorScript = Join-Path -Path $ScriptPath -ChildPath "Update-LocalChromaDb.ps1"
                                        }
                                    }
                                    
                                    # Import the file processing module locally
                                    $processorFilesModule = Join-Path -Path $PSScriptRoot -ChildPath "Processor-Files.psm1"
                                    $processorFilesModule = Resolve-Path $processorFilesModule
                                    Import-Module $processorFilesModule -Force
                                    
                                    # Process the file
                                    $success = Process-CollectionFile -FileInfo $file -HandlerScript $processorScript `
                                        -HandlerScriptParams $processorParams -VectorDbPath $VectorDbPath -TempDir $TempDir `
                                        -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath `
                                        -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap -WriteLog $WriteLog
                                    
                                    if ($success) {
                                        # Mark file as processed using either ID or name
                                        if ($collectionId) {
                                            $markResult = & $MarkFileAsProcessed -CollectionId $collectionId -FileId $fileId `
                                                -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                        } else {
                                            $markResult = & $MarkFileAsProcessed -CollectionName $collectionName -FileId $fileId `
                                                -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                                        }
                                        
                                        if ($markResult) {
                                            $body = @{
                                                success = $true
                                                message = "File processed and marked as processed successfully"
                                                file_id = $fileId
                                                file_path = $file.FilePath
                                                collection_id = $collectionId
                                                collection_name = $collectionName
                                            }
                                            
                                            Send-Response -Response $response -Body $body -WriteLog $WriteLog
                                        }
                                        else {
                                            Send-ErrorResponse -Response $response -StatusCode 500 -ErrorMessage "File was processed but could not be marked as processed" -WriteLog $WriteLog
                                        }
                                    }
                                    else {
                                        Send-ErrorResponse -Response $response -StatusCode 500 -ErrorMessage "Failed to process file" -WriteLog $WriteLog
                                    }
                                }
                                catch {
                                    & $WriteLog "Error processing file: $_" -Level "ERROR"
                                    Send-ErrorResponse -Response $response -StatusCode 500 -ErrorMessage "Error processing file: $_" -WriteLog $WriteLog
                                }
                            }
                            else {
                                Send-ErrorResponse -Response $response -StatusCode 405 -ErrorMessage "Method Not Allowed" -WriteLog $WriteLog
                            }
                            break
                        }
                        
                        default {
                            Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "Endpoint not found" -WriteLog $WriteLog
                            break
                        }
                    }
                }
                else {
                    Send-ErrorResponse -Response $response -StatusCode 404 -ErrorMessage "API endpoint not found" -WriteLog $WriteLog
                }
            }
            catch {
                & $WriteLog "Error processing request: $_" -Level "ERROR"
                Send-ErrorResponse -Response $response -StatusCode 500 -ErrorMessage "Internal Server Error: $_" -WriteLog $WriteLog
            }
        }
    }
    catch {
        & $WriteLog "Error starting HTTP server: $_" -Level "ERROR"
        throw $_
    }
    finally {
        if ($listener -and $listener.IsListening) {
            $listener.Stop()
            $listener.Close()
            & $WriteLog "HTTP server stopped." -Level "WARNING"
        }
    }
}

Export-ModuleMember -Function Get-RequestBody, Send-Response, Send-ErrorResponse, Start-ProcessorHttpServer
