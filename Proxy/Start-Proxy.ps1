# Start-RAGProxy.ps1
# REST API proxy that provides /api/chat endpoint
# Uses Vectors subsystem for vector search to find relevant context
# Forwards enhanced prompts to Ollama REST API

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility

param (
    [Parameter(Mandatory=$false)]
    [string]$ListenAddress = "localhost",
    
    [Parameter(Mandatory=$true)]
    [int]$Port,
    
    [Parameter(Mandatory=$true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaBaseUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$VectorsApiUrl = "http://localhost:8082",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [decimal]$RelevanceThreshold = 0.75,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxContextDocs = 5,
    
    [Parameter(Mandatory=$false)]
    [string]$QueryMode = "both", # Options: "chunks", "documents", "both"
    
    [Parameter(Mandatory=$false)]
    [double]$ChunkWeight = 0.6,
    
    [Parameter(Mandatory=$false)]
    [double]$DocumentWeight = 0.4,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseHttps,
    
    [Parameter(Mandatory=$false)]
    [switch]$ContextOnlyMode
)

# Set up logging
$vectorDbPath = Join-Path -Path $InstallPath -ChildPath "Vectors"
$TempDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $TempDir)) 
{ 
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null 
}

$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "FileTracker_$logDate.log"
$logFilePath = Join-Path -Path $TempDir -ChildPath "$logFileName"


function Close-ProcessOnPort {
    $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue

    if ($connection) {
        # Get the process ID (PID) of the process using the port
        $ppid = $connection.OwningProcess
    
        # Get process details to identify what is being killed
        $process = Get-Process -Id $ppid
    
        # Inform the user which process is being terminated
        Write-Host "Killing process '$($process.ProcessName)' with PID $pid listening on port 8081."
    
        # Attempt to forcefully terminate the process
        try {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            Write-Host "Process killed successfully."
        } catch {
            Write-Host "Failed to kill process: $_"
        }
    }
}

function Write-ApiLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor = "Black"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console
    if ($Level -eq "ERROR") {
        Write-Host $logMessage
    }
    elseif ($Level -eq "WARNING") {
        Write-Host $logMessage
    }
    else {
        Write-Host $logMessage
    }
    
    # Write to log file
    Add-Content -Path $logFilePath -Value $logMessage
}

# Check if Ollama is running
Write-ApiLog -Message "Checking if Ollama is running at $OllamaBaseUrl..." -Level "INFO"
try {
    $ollamaStatus = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/tags" -Method Get -ErrorAction Stop
    Write-ApiLog -Message "Ollama is running." -Level "INFO"
    
    # Check if embedding model is available
    $modelFound = $false
    foreach ($model in $ollamaStatus.models) {
        if ($model.name -eq $EmbeddingModel) {
            $modelFound = $true
            break
        }
    }
    
    if (-not $modelFound) {
        Write-ApiLog -Message "WARNING: Embedding model '$EmbeddingModel' not found in Ollama." -Level "WARNING"
        Write-ApiLog -Message "Available models: $($ollamaStatus.models.name -join ', ')" -Level "INFO"
    }
}
catch {
    Write-ApiLog -Message "Ollama is not running or not accessible at $OllamaBaseUrl" -Level "ERROR"
    Write-ApiLog -Message "Please ensure Ollama is running before proceeding." -Level "ERROR"
    Write-ApiLog -Message "You can download Ollama from https://ollama.ai/" -Level "INFO"
    exit 1
}

# Check if Vectors API is running
Write-ApiLog -Message "Checking if Vectors API is running at $VectorsApiUrl..." -Level "INFO"
try {
    $vectorsStatus = Invoke-RestMethod -Uri "$VectorsApiUrl/status" -Method Get -ErrorAction Stop
    Write-ApiLog -Message "Vectors API is running." -Level "INFO"
}
catch {
    Write-ApiLog -Message "Vectors API is not running or not accessible at $VectorsApiUrl" -Level "ERROR"
    Write-ApiLog -Message "Please ensure Vectors API is running before proceeding." -Level "ERROR"
    Write-ApiLog -Message "You can start it with: .\Vectors\Start-VectorsAPI.ps1" -Level "INFO"
    exit 1
}

# Function to query Vectors API for relevant documents
function Get-RelevantDocuments {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxResults = $MaxContextDocs,
        
        [Parameter(Mandatory=$false)]
        [double]$Threshold = $RelevanceThreshold,
        
        [Parameter(Mandatory=$false)]
        [string]$Mode = $QueryMode,
        
        [Parameter(Mandatory=$false)]
        [double]$ChkWeight = $ChunkWeight,
        
        [Parameter(Mandatory=$false)]
        [double]$DocWeight = $DocumentWeight
    )
    
    try {
        Write-ApiLog -Message "Querying Vectors API for: $Query" -Level "INFO"
        
        # Prepare the request body
        $body = @{
            query = $Query
            max_results = $MaxResults
            threshold = $Threshold
        }
        
        $results = @()
        $combinedResults = @()
        
        # Handle different query modes
        if ($Mode -eq "chunks" -or $Mode -eq "both") {
            # Query for chunks
            try {
                $endpoint = "$VectorsApiUrl/api/search/chunks"
                $chunkResponse = Invoke-RestMethod -Uri $endpoint -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop
                
                if ($chunkResponse.success -and $chunkResponse.results) {
                    Write-ApiLog -Message "Found $($chunkResponse.count) matching chunks." -Level "INFO"
                    
                    # Apply weight to chunk results if in "both" mode
                    if ($Mode -eq "both") {
                        foreach ($result in $chunkResponse.results) {
                            $result.similarity = $result.similarity * $ChkWeight
                            $result.source_type = "chunk"
                            $combinedResults += $result
                        }
                    } else {
                        $results = $chunkResponse.results
                    }
                }
            }
            catch {
                Write-ApiLog -Message "Error querying chunks: $_" -Level "ERROR"
            }
        }
        
        if ($Mode -eq "documents" -or $Mode -eq "both") {
            # Query for documents
            try {
                $endpoint = "$VectorsApiUrl/api/search/documents"
                $docResponse = Invoke-RestMethod -Uri $endpoint -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop
                
                if ($docResponse.success -and $docResponse.results) {
                    Write-ApiLog -Message "Found $($docResponse.count) matching documents." -Level "INFO"
                    
                    # Apply weight to document results if in "both" mode
                    if ($Mode -eq "both") {
                        foreach ($result in $docResponse.results) {
                            $result.similarity = $result.similarity * $DocWeight
                            $result.source_type = "document"
                            $combinedResults += $result
                        }
                    } else {
                        $results = $docResponse.results
                    }
                }
            }
            catch {
                Write-ApiLog -Message "Error querying documents: $_" -Level "ERROR"
            }
        }
        
        # If in "both" mode, combine and sort results
        if ($Mode -eq "both") {
            # Sort by similarity (descending)
            $results = $combinedResults | Sort-Object -Property similarity -Descending | Select-Object -First $MaxResults
        }
        
        # Filter by threshold
        $filteredResults = $results | Where-Object { $_.similarity -ge $Threshold }
        
        return @{
            success = $true
            results = $filteredResults
            count = $filteredResults.Count
        }
    }
    catch {
        Write-ApiLog -Message "Exception querying Vectors API: $_" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
            results = @()
        }
    }
}

# Function to prepare context from relevant documents
function Format-RelevantContextForOllama {
    param (
        [Parameter(Mandatory=$true)]
        [object]$Documents
    )
    
    $contextText = "I'll help answer your questions based on the following information:`n`n"
    
    foreach ($doc in $Documents) {
        $source = $doc.metadata.source
        $fileName = Split-Path -Path $source -Leaf
        $lineRange = if ($doc.metadata.line_range) { $doc.metadata.line_range } else { "N/A" }
        
        $contextText += "---`n"
        $contextText += "Source: $fileName"
        if ($lineRange -ne "N/A") {
            $contextText += " (lines $lineRange)"
        }
        $contextText += "`n"
        $contextText += "Content:`n$($doc.document)`n`n"
    }
    
    return $contextText
}

# Function to get list of available models from Ollama
function Get-OllamaModels {
    param (
        [Parameter(Mandatory=$false)]
        [bool]$IncludeDetails = $false
    )
    
    try {
        $endpoint = "$OllamaBaseUrl/api/tags"
        $response = Invoke-RestMethod -Uri $endpoint -Method Get -ErrorAction Stop
        
        $models = @()
        foreach ($model in $response.models) {
            if ($IncludeDetails) {
                $models += $model
            } else {
                $models += $model.name
            }
        }
        
        return @{
            success = $true
            models = $models
            count = $models.Count
        }
    }
    catch {
        Write-ApiLog -Message "Exception getting models from Ollama: $_" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
            models = @()
        }
    }
}

# Function to get vector database statistics
function Get-VectorDbStats {
    try {
        $endpoint = "$VectorsApiUrl/status"
        $response = Invoke-RestMethod -Uri $endpoint -Method Get -ErrorAction Stop
        
        return @{
            success = $true
            stats = $response
        }
    }
    catch {
        Write-ApiLog -Message "Exception getting vector database stats: $_" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
        }
    }
}

# Function to send chat to Ollama
function Send-ChatToOllama {
    param (
        [Parameter(Mandatory=$true)]
        [object[]]$Messages,
        
        [Parameter(Mandatory=$true)]
        [string]$Model,
        
        [Parameter(Mandatory=$false)]
        [object]$Context = $null,
        
        [Parameter(Mandatory=$false)]
        [double]$Temperature = 0.7,
        
        [Parameter(Mandatory=$false)]
        [int]$NumCtx = 40000
    )
    
    try {
        $endpoint = "$OllamaBaseUrl/api/chat"
        
        $body = @{
            model = $Model
            messages = $Messages
            temperature = $Temperature
            num_ctx = $NumCtx
        }
        
        if ($null -ne $Context) {
            $body.context = $Context
        }
        
        $jsonBody = $body | ConvertTo-Json -Depth 10
        $response = Invoke-RestMethod -Uri $endpoint -Method Post -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
        
        return @{
            success = $true
            result = $response
        }
    }
    catch {
        Write-ApiLog -Message "Exception sending chat to Ollama: $_" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
        }
    }
}

# Set up HTTP listener
$listener = New-Object System.Net.HttpListener
if ($UseHttps) {
    $prefix = "https://$($ListenAddress):$Port/"
    
    # Note: HTTPS requires a valid certificate to be bound to the port
    Write-ApiLog -Message "HTTPS requires a certificate to be bound to port $Port" -Level "WARNING"
    Write-ApiLog -Message "You may need to run: netsh http add sslcert ipport=0.0.0.0:$Port certhash=THUMBPRINT appid={GUID}" -Level "INFO"
}
else {
    $prefix = "http://$($ListenAddress):$Port/"
}

$listener.Prefixes.Add($prefix)

try {
    # Start the listener
    $listener.Start()
    
Write-ApiLog -Message "API proxy started at $prefix" -Level "INFO"
Write-ApiLog -Message "Vector database path: $vectorDbPath" -Level "INFO"
Write-ApiLog -Message "Vectors API URL: $VectorsApiUrl" -Level "INFO"
Write-ApiLog -Message "Ollama URL: $OllamaBaseUrl" -Level "INFO"
Write-ApiLog -Message "Embedding model: $EmbeddingModel" -Level "INFO"
Write-ApiLog -Message "Relevance threshold: $RelevanceThreshold" -Level "INFO"
Write-ApiLog -Message "Max context documents: $MaxContextDocs" -Level "INFO"
Write-ApiLog -Message "Query mode: $QueryMode" -Level "INFO"
Write-ApiLog -Message "Chunk weight: $ChunkWeight" -Level "INFO"
Write-ApiLog -Message "Document weight: $DocumentWeight" -Level "INFO"
Write-ApiLog -Message "Default temperature: 0.7" -Level "INFO"
Write-ApiLog -Message "Default context window: 40000" -Level "INFO"
if ($ContextOnlyMode) {
    Write-ApiLog -Message "Running in Context-only Mode - LLM will be instructed to use ONLY information from provided context" -Level "WARNING"
}
Write-ApiLog -Message "Press Ctrl+C to stop the server" -Level "INFO"
    
    # Handle requests in a loop
    while ($listener.IsListening) {
        $context = $null
        try {
            # Get request context
            $context = $listener.GetContext()
            
            # Get request and response objects
            $request = $context.Request
            $response = $context.Response
            
            # Parse URL to extract route
            $route = $request.Url.LocalPath
            $method = $request.HttpMethod
            
            Write-ApiLog -Message "Received $method request for $route" -Level "INFO"
            
            # Set default content type to JSON
            $response.ContentType = "application/json"
            
            # Parse request body if needed
            $requestBody = $null
            if ($request.HasEntityBody) {
                $reader = New-Object System.IO.StreamReader $request.InputStream
                $requestBody = $reader.ReadToEnd()
                $reader.Close()
                
                # Try to parse JSON body
                try {
                    $requestBody = $requestBody | ConvertFrom-Json
                }
                catch {
                    # Leave as string if not valid JSON
                }
            }
            
            # Handle based on route and method
            $responseBody = $null
            $statusCode = 200
            
            switch ($route) {
                # --- Health check and API info ---
                "/" {
                    if ($method -eq "GET") {
                        $responseBody = @{
                            status = "ok"
                            message = "API proxy running"
                            contextOnlyMode = $ContextOnlyMode.IsPresent
                            routes = @(
                "/api/chat - POST: Chat with context augmentation" + $(if ($ContextOnlyMode) { " (Context-only Mode active - returns only relevant context)" } else { "" })
                "/api/search - POST: Search for relevant documents"
                "/api/models - GET: Get list of available models"
                "/api/stats - GET: Get statistics about vector database"
                "/api/synchronize - POST: Synchronize dirty files from FileTracker to Vectors"
                "/status - GET: Get API proxy status (includes Context-only Mode status)"
                            )
                        }
                    }
                    else {
                        $statusCode = 405
                        $responseBody = @{
                            error = "Method not allowed"
                            message = "Use GET for this endpoint"
                        }
                    }
                }
                
                # --- Models endpoint ---
                "/api/models" {
                    if ($method -eq "GET") {
                        # Extract parameters
                        $includeDetails = $request.QueryString["include_details"] -eq "true"
                        
                        # Get models
                        $modelsResult = Get-OllamaModels -IncludeDetails $includeDetails
                        
                        if ($modelsResult.success) {
                            $responseBody = @{
                                models = $modelsResult.models
                                count = $modelsResult.count
                            }
                        }
                        else {
                            $statusCode = 500
                            $responseBody = @{
                                error = "Models error"
                                message = $modelsResult.error
                            }
                        }
                    }
                    else {
                        $statusCode = 405
                        $responseBody = @{
                            error = "Method not allowed"
                            message = "Use GET for this endpoint"
                        }
                    }
                }
                
                # --- Vector DB Stats endpoint ---
                "/api/stats" {
                    if ($method -eq "GET") {
                        # Get collection statistics
                        $statsResult = Get-VectorDbStats
                        
                        if ($statsResult.success) {
                            $responseBody = @{
                                success = $true
                                stats = $statsResult.stats
                            }
                        }
                        else {
                            $statusCode = 500
                            $responseBody = @{
                                error = "Vector database stats error"
                                message = $statsResult.error
                            }
                        }
                    }
                    else {
                        $statusCode = 405
                        $responseBody = @{
                            error = "Method not allowed"
                            message = "Use GET for this endpoint"
                        }
                    }
                }
                
                # --- Status endpoint ---
                "/status" {
                    if ($method -eq "GET") {
                        $responseBody = @{
                            status = "ok"
                            vectorDbPath = $vectorDbPath
                            vectorsApiUrl = $VectorsApiUrl
                            ollamaUrl = $OllamaBaseUrl
                            embeddingModel = $EmbeddingModel
                            relevanceThreshold = $RelevanceThreshold
                            maxContextDocs = $MaxContextDocs
                            defaultTemperature = 0.7
                            defaultNumCtx = 40000
                            contextOnlyMode = $ContextOnlyMode.IsPresent
                        }
                    }
                    else {
                        $statusCode = 405
                        $responseBody = @{
                            error = "Method not allowed"
                            message = "Use GET for this endpoint"
                        }
                    }
                }
                
                # --- Search endpoint ---
                "/api/search" {
                    if ($method -eq "POST") {
                        # Validate required parameters
                        if ($null -eq $requestBody -or $null -eq $requestBody.query) {
                            $statusCode = 400
                            $responseBody = @{
                                error = "Bad request"
                                message = "Required parameter missing: query"
                            }
                        }
                        else {
                            # Extract parameters
                            $query = $requestBody.query
                            $maxResults = if ($null -ne $requestBody.max_results) { $requestBody.max_results } else { $MaxContextDocs }
                            $threshold = if ($null -ne $requestBody.threshold) { $requestBody.threshold } else { $RelevanceThreshold }
                            
                            # Get relevant documents
                            $searchResult = Get-RelevantDocuments -Query $query -MaxResults $maxResults -Threshold $threshold
                            
                            if ($searchResult.success) {
                                $responseBody = @{
                                    success = $true
                                    query = $query
                                    results = $searchResult.results
                                    count = $searchResult.count
                                }
                            }
                            else {
                                $statusCode = 500
                                $responseBody = @{
                                    error = "Search error"
                                    message = $searchResult.error
                                }
                            }
                        }
                    }
                    else {
                        $statusCode = 405
                        $responseBody = @{
                            error = "Method not allowed"
                            message = "Use POST for this endpoint"
                        }
                    }
                }
                
                # --- Synchronize endpoint ---
                "/api/synchronize" {
                    if ($method -eq "POST") {
                        # Validate required parameters
                        if ($null -eq $requestBody -or [string]::IsNullOrEmpty($requestBody.collection_name)) {
                            $statusCode = 400
                            $responseBody = @{
                                error = "Bad request"
                                message = "Required parameter missing: collection_name"
                            }
                        }
                        else {
                            try {
                                # Extract parameters
                                $collectionName = $requestBody.collection_name
                                $fileTrackerApiUrl = if ($null -ne $requestBody.filetracker_api_url) { $requestBody.filetracker_api_url } else { "http://localhost:8080" }
                                $vectorsApiUrl = if ($null -ne $requestBody.vectors_api_url) { $requestBody.vectors_api_url } else { "http://localhost:8082" }
                                $chunkSize = if ($null -ne $requestBody.chunk_size) { $requestBody.chunk_size } else { 1000 }
                                $chunkOverlap = if ($null -ne $requestBody.chunk_overlap) { $requestBody.chunk_overlap } else { 200 }
                                $continuous = if ($null -ne $requestBody.continuous) { $requestBody.continuous } else { $false }
                                
                                # Get the processor path
                                $processorPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "Processor"
                                $synchronizeScript = Join-Path -Path $processorPath -ChildPath "Synchronize-Collection.ps1"
                                
                                Write-ApiLog -Message "Calling Synchronize-Collection script for collection: $collectionName" -Level "INFO"
                                
                                # Build parameter set
                                $params = @{
                                    CollectionName = $collectionName
                                    FileTrackerApiUrl = $fileTrackerApiUrl
                                    VectorsApiUrl = $vectorsApiUrl
                                    ChunkSize = $chunkSize
                                    ChunkOverlap = $chunkOverlap
                                }
                                
                                if ($continuous) {
                                    $params.Continuous = $true
                                }
                                
                                # Call the script asynchronously
                                $job = Start-Job -ScriptBlock {
                                    param($script, $parameters)
                                    & $script @parameters
                                } -ArgumentList $synchronizeScript, $params
                                
                                # Wait a moment to let the job start
                                Start-Sleep -Seconds 1
                                
                                # Check if the job started successfully
                                $jobState = $job.State
                                
                                if ($jobState -eq "Running") {
                                    $responseBody = @{
                                        success = $true
                                        message = "Synchronization started for collection: $collectionName"
                                        job_id = $job.Id
                                        collection_name = $collectionName
                                        continuous = $continuous
                                    }
                                }
                                else {
                                    $statusCode = 500
                                    $responseBody = @{
                                        success = $false
                                        error = "Failed to start synchronization job"
                                        job_state = $jobState
                                        collection_name = $collectionName
                                    }
                                }
                            }
                            catch {
                                $statusCode = 500
                                $responseBody = @{
                                    success = $false
                                    error = "Error starting synchronization"
                                    message = $_.ToString()
                                }
                            }
                        }
                    }
                    else {
                        $statusCode = 405
                        $responseBody = @{
                            error = "Method not allowed"
                            message = "Use POST for this endpoint"
                        }
                    }
                }
                
                # --- Chat endpoint ---
                "/api/chat" {
                    if ($method -eq "POST") {
                        # Validate required parameters
                        if ($null -eq $requestBody -or $null -eq $requestBody.messages) {
                            $statusCode = 400
                            $responseBody = @{
                                error = "Bad request"
                                message = "Required parameter missing: messages"
                            }
                        }
                        else {
                            # Extract parameters
                            $messages = $requestBody.messages
                            $model = if ($null -ne $requestBody.model) { $requestBody.model } else { "llama3" }
                            $maxResults = if ($null -ne $requestBody.max_context_docs) { $requestBody.max_context_docs } else { $MaxContextDocs }
                            $threshold = if ($null -ne $requestBody.threshold) { $requestBody.threshold } else { $RelevanceThreshold }
                            $enhanceContext = if ($null -ne $requestBody.enhance_context) { $requestBody.enhance_context } else { $true }
                            $temperature = if ($null -ne $requestBody.temperature) { $requestBody.temperature } else { 0.7 }
                            $numCtx = if ($null -ne $requestBody.num_ctx) { $requestBody.num_ctx } else { 40000 }
                            
                            # Get the latest user message for context search
                            $latestUserMessage = $null
                            for ($i = $messages.Count - 1; $i -ge 0; $i--) {
                                if ($messages[$i].role -eq "user") {
                                    $latestUserMessage = $messages[$i].content
                                    break
                                }
                            }
                            
                            # Get relevant documents if we should enhance context
                            $contextDocuments = @()
                            $rawOllamaContext = $null
                            
                            if ($enhanceContext -and $null -ne $latestUserMessage) {
                                # Get query mode from request or use default
                                $queryMode = if ($null -ne $requestBody.query_mode) { $requestBody.query_mode } else { $QueryMode }
                                $chunkWeight = if ($null -ne $requestBody.chunk_weight) { $requestBody.chunk_weight } else { $ChunkWeight }
                                $documentWeight = if ($null -ne $requestBody.document_weight) { $requestBody.document_weight } else { $DocumentWeight }
                                
                                Write-ApiLog -Message "Using query mode: $queryMode with weights - chunks: $chunkWeight, documents: $documentWeight" -Level "INFO"
                                
                                $searchResult = Get-RelevantDocuments -Query $latestUserMessage -MaxResults $maxResults -Threshold $threshold -Mode $queryMode -ChkWeight $chunkWeight -DocWeight $documentWeight
                                
                                if ($searchResult.success -and $searchResult.count -gt 0) {
                                    Write-ApiLog -Message "Found documents to add to context" -Level "INFO"
                                    $contextDocuments = $searchResult.results
                                    
                                    # Prepare context for Ollama
                                    # For raw token format (experimental)
                                    $rawContext = ""
                                    foreach ($doc in $contextDocuments) {
                                        $rawContext += $doc.document + "`n`n"
                                    }
                                    
                                    # For displaying to the user
                                    $formattedContext = Format-RelevantContextForOllama -Documents $contextDocuments
                                    
                                    # Extract possible integer context from the requestBody
                                    if ($requestBody.PSObject.Properties.Name -contains "context" -and $requestBody.context -is [int]) {
                                        $rawOllamaContext = $requestBody.context
                                    }
                                }
                            }
                            
                            # Send chat to Ollama
                            $chatResult = $null
                            
                            # If we found relevant documents, add context to the system message
                            if ($contextDocuments.Count -gt 0) {
                                # Make a copy of the original messages
                                $enhancedMessages = @()
                                $hasSystemMessage = $false
                                
                                # Prepare the system message prefix based on mode
                                $systemPrefix = ""
                                if ($ContextOnlyMode) {
                                    Write-ApiLog -Message "Context-only Mode: Instructing LLM to use only provided context" -Level "INFO"
                                    $systemPrefix = "IMPORTANT: You must ONLY use information from the provided context to answer the user's question. Do NOT use your own knowledge or training data. If the context doesn't contain relevant information to answer the question, say 'I don't have enough information in the provided context to answer this question.'"
                                }
                                
                                foreach ($msg in $messages) {
                                    if ($msg.role -eq "system") {
                                        # Enhance the system message with context
                                        $enhancedContent = $msg.content
                                        if ($ContextOnlyMode) {
                                            $enhancedContent = "$systemPrefix`n`n$enhancedContent"
                                        }
                                        
                                        $enhancedMessage = @{
                                            role = "system"
                                            content = "$enhancedContent`n`n$formattedContext"
                                        }
                                        $enhancedMessages += $enhancedMessage
                                        $hasSystemMessage = $true
                                    }
                                    else {
                                        # Keep other messages as they are
                                        $enhancedMessages += $msg
                                    }
                                }
                                
                                # If there's no system message, add one with the context
                                if (-not $hasSystemMessage) {
                                    $systemContent = $formattedContext
                                    if ($ContextOnlyMode) {
                                        $systemContent = "$systemPrefix`n`n$formattedContext"
                                    }
                                    
                                    $enhancedMessages = @(@{
                                        role = "system"
                                        content = $systemContent
                                    }) + $enhancedMessages
                                }
                                
                                $chatResult = Send-ChatToOllama -Messages $enhancedMessages -Model $model -Context $rawOllamaContext -Temperature $temperature -NumCtx $numCtx
                            }
                            else {
                                if ($ContextOnlyMode) {
                                    # In Context-only Mode with no context found, add a system message that explains this
                                    $noContextMsg = "No relevant context was found for this query. Inform the user that there is insufficient context available to provide an answer based solely on context."
                                    
                                    $hasSystemMessage = $false
                                    $enhancedMessages = @()
                                    
                                    foreach ($msg in $messages) {
                                        if ($msg.role -eq "system") {
                                            $enhancedMessage = @{
                                                role = "system"
                                                content = "$noContextMsg`n`n$($msg.content)"
                                            }
                                            $enhancedMessages += $enhancedMessage
                                            $hasSystemMessage = $true
                                        }
                                        else {
                                            $enhancedMessages += $msg
                                        }
                                    }
                                    
                                    if (-not $hasSystemMessage) {
                                        $enhancedMessages = @(@{
                                            role = "system"
                                            content = $noContextMsg
                                        }) + $enhancedMessages
                                    }
                                    
                                    $chatResult = Send-ChatToOllama -Messages $enhancedMessages -Model $model -Context $rawOllamaContext -Temperature $temperature -NumCtx $numCtx
                                }
                                else {
                                    $chatResult = Send-ChatToOllama -Messages $messages -Model $model -Context $rawOllamaContext -Temperature $temperature -NumCtx $numCtx
                                }
                            }
                            
                            if ($chatResult.success) {
                                # Add some metadata about the context to the response
                                $responseBody = $chatResult.result
                                $responseBody | Add-Member -MemberType NoteProperty -Name "context_count" -Value $contextDocuments.Count
                                
                                if ($contextDocuments.Count -gt 0) {
                                    # Add simplified context information
                                    $simplifiedContext = @()
                                    foreach ($doc in $contextDocuments) {
                                        $simplifiedContext += @{
                                            source = Split-Path -Path $doc.metadata.source -Leaf
                                            line_range = $doc.metadata.line_range
                                            similarity = $doc.similarity
                                        }
                                    }
                                    $responseBody | Add-Member -MemberType NoteProperty -Name "context_info" -Value $simplifiedContext
                                }
                            }
                            else {
                                $statusCode = 500
                                $responseBody = @{
                                    error = "Chat error"
                                    message = $chatResult.error
                                }
                            }
                        }
                    }
                    else {
                        $statusCode = 405
                        $responseBody = @{
                            error = "Method not allowed"
                            message = "Use POST for this endpoint"
                        }
                    }
                }
                
                # --- Handle unknown routes ---
                default {
                    $statusCode = 404
                    $responseBody = @{
                        error = "Route not found"
                        message = "The requested resource does not exist: $route"
                    }
                }
            }
            
            # Convert response to JSON
            $jsonResponse = $responseBody | ConvertTo-Json -Depth 10
            
            # Set status code
            $response.StatusCode = $statusCode
            
            # Write response
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.OutputStream.Close()
            
        }
        catch {
            Write-ApiLog -Message "Error handling request: $_" -Level "ERROR"
            
            # Try to send error response if context is available
            if ($null -ne $context -and $null -ne $response) {
                try {
                    $response.StatusCode = 500
                    $response.ContentType = "application/json"
                    
                    $errorJson = @{
                        error = "Internal server error"
                        message = $_.ToString()
                    } | ConvertTo-Json
                    
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorJson)
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.OutputStream.Close()
                }
                catch {
                    # Ignore errors in error handling
                }
            }
        }
        
    }
}
catch {
    Write-ApiLog -Message "Fatal error in API proxy server: $_" -Level "ERROR"
}
finally {
    $context.Response.Close()
    # --- Cleanup ---
    # This block ALWAYS executes, even on Ctrl+C or errors
    Write-Host "Executing finally block for cleanup..."

    # Check if the listener object was successfully created and is still running
    if ($listener -ne $null) {
         Write-Host "Listener object exists."
        if ($listener.IsListening) {
            Write-Host "Listener is listening. Stopping listener..."
            # Stop the listener from accepting new connections
            $listener.Stop()
            Write-Host "Listener stopped."
        } else {
            Write-Host "Listener was not listening (or already stopped)."
        }
        # Close and release resources (calls Stop() implicitly if still listening, then Dispose())
        Write-Host "Closing/Disposing listener..."
        $listener.Close() # Close calls Dispose()
        Write-Host "Listener closed and disposed."
    } else {
        Write-Host "Listener object was not created or was null."
    }

    Write-Host "Cleanup finished."
}