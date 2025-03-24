# Start-RAGProxy.ps1
# REST API proxy that provides /api/chat endpoint
# Uses ChromaDB for vector search to find relevant context
# Forwards enhanced prompts to Ollama REST API

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility

param (
    [Parameter(Mandatory=$false)]
    [string]$ListenAddress = "localhost",
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 8081,
    
    [Parameter(Mandatory=$true)]
    [string]$DirectoryPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaBaseUrl = "http://localhost:11434",
    
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
$pythonHelperPath = Join-Path -Path $PSScriptRoot -ChildPath "ragProxy.py"
$aiFolder = Join-Path -Path $DirectoryPath -ChildPath ".ai"
$vectorDbPath = Join-Path -Path $aiFolder -ChildPath "Vectors"
$LogPath = Join-Path -Path $aiFolder -ChildPath "temp\RAGProxy.log"

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
    Add-Content -Path $LogPath -Value $logMessage
}

# Check if Python is installed
try {
    $pythonVersion = pwsh.exe --version
    Write-ApiLog -Message "Found Python: $pythonVersion"
}
catch {
    Write-ApiLog -Message "Python not found. Please install Python 3.8+ to use this script. $_" -Level "ERROR"
    exit 1
}

# Check if vector database path exists
if (-not (Test-Path -Path $vectorDbPath)) {
    Write-ApiLog -Message "Vector database path does not exist: $vectorDbPath" -Level "WARNING"
    Write-ApiLog -Message "Creating directory: $vectorDbPath" -Level "INFO"
    New-Item -Path $vectorDbPath -ItemType Directory -Force | Out-Null
    
    Write-ApiLog -Message "WARNING: Vector database is empty. You should run CreateChromaEmbeddings.ps1 to populate it." -Level "WARNING"
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

# Function to query ChromaDB for relevant documents
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
        $pythonCmd = "python.exe ""$pythonHelperPath"" query ""$Query"" ""$vectorDbPath"" ""$EmbeddingModel"" ""$OllamaBaseUrl"" $MaxResults $Threshold ""$Mode"" $ChkWeight $DocWeight"
        $resultJson = Invoke-Expression $pythonCmd
        $result = $resultJson | ConvertFrom-Json
        
        if ($result.PSObject.Properties.Name -contains "error") {
            Write-ApiLog -Message "Error querying ChromaDB: $($result.error)" -Level "ERROR"
            return @{
                success = $false
                error = $result.error
                results = @()
            }
        }
        
        return @{
            success = $true
            results = $result.results
            count = $result.count
        }
    }
    catch {
        Write-ApiLog -Message "Exception querying ChromaDB: $_" -Level "ERROR"
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
        $lineRange = $doc.metadata.line_range
        
        $contextText += "---`n"
        $contextText += "Source: $fileName (lines $lineRange)`n"
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
        $pythonCmd = "python.exe ""$pythonHelperPath"" models ""$OllamaBaseUrl"" ""$IncludeDetails"""
        $resultJson = Invoke-Expression $pythonCmd
        $result = $resultJson | ConvertFrom-Json
        
        if ($result.PSObject.Properties.Name -contains "error") {
            Write-ApiLog -Message "Error getting models from Ollama: $($result.error)" -Level "ERROR"
            return @{
                success = $false
                error = $result.error
                models = @()
            }
        }
        
        return @{
            success = $true
            models = $result.models
            count = $result.count
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

# Function to get ChromaDB collection statistics
function Get-ChromaDbStats {
    try {
        $pythonCmd = "python.exe ""$pythonHelperPath"" stats ""$vectorDbPath"""
        $resultJson = Invoke-Expression $pythonCmd
        $result = $resultJson | ConvertFrom-Json
        
        if ($result.PSObject.Properties.Name -contains "error") {
            Write-ApiLog -Message "Error getting ChromaDB stats: $($result.error)" -Level "ERROR"
            return @{
                success = $false
                error = $result.error
            }
        }
        
        return @{
            success = $true
            stats = $result
        }
    }
    catch {
        Write-ApiLog -Message "Exception getting ChromaDB stats: $_" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
        }
    }
}

# Function to send enhanced prompt to Ollama
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
        # Create temporary directory if it doesn't exist
        $tempDir = Join-Path -Path $aiFolder -ChildPath "temp"
        if (-not (Test-Path -Path $tempDir)) {
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        }
        
        # Create temporary files for messages and context JSON
        $messagesJsonFile = Join-Path -Path $tempDir -ChildPath "messages_$([Guid]::NewGuid().ToString()).json"
        $contextJsonFile = if ($null -ne $Context) { Join-Path -Path $tempDir -ChildPath "context_$([Guid]::NewGuid().ToString()).json" } else { "null" }
        
        # Convert messages to JSON and save to temp file
        $messagesJson = ConvertTo-Json $Messages -Depth 10
        Set-Content -Path $messagesJsonFile -Value $messagesJson -Encoding UTF8
        
        # Convert context to JSON and save to temp file if it exists
        if ($null -ne $Context) {
            $contextJson = $Context | ConvertTo-Json -Depth 10
            Set-Content -Path $contextJsonFile -Value $contextJson -Encoding UTF8
        }

        # Include vector database parameters to allow document name retrieval
        $pythonCmd = "python.exe ""$pythonHelperPath"" chat ""$messagesJsonFile"" ""$Model"" ""$contextJsonFile"" ""$OllamaBaseUrl"" ""$Temperature"" ""$NumCtx"" ""$vectorDbPath"" ""$EmbeddingModel"" ""$MaxContextDocs"" ""$RelevanceThreshold"""
        $resultJson = Invoke-Expression $pythonCmd
        $result = $resultJson | ConvertFrom-Json
        
        # Clean up the temp files
        if (Test-Path -Path $messagesJsonFile) {
            Remove-Item -Path $messagesJsonFile -Force
        }
        
        if ($null -ne $Context -and (Test-Path -Path $contextJsonFile)) {
            Remove-Item -Path $contextJsonFile -Force
        }
        
        if ($result.PSObject.Properties.Name -contains "error") {
            Write-ApiLog -Message "Error sending chat to Ollama : $($result.error)" -Level "ERROR"
            return @{
                success = $false
                error = $result.error
            }
        }
        
        return @{
            success = $true
            result = $result
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
                "/api/stats - GET: Get statistics about ChromaDB collections"
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
                
                # --- ChromaDB Stats endpoint ---
                "/api/stats" {
                    if ($method -eq "GET") {
                        # Get collection statistics
                        $statsResult = Get-ChromaDbStats
                        
                        if ($statsResult.success) {
                            $responseBody = @{
                                success = $true
                                stats = $statsResult.stats
                            }
                        }
                        else {
                            $statusCode = 500
                            $responseBody = @{
                                error = "ChromaDB stats error"
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
                
                # Add document names from the Python response if they exist
                if ($responseBody.PSObject.Properties.Name -contains "document_names") {
                    Write-ApiLog -Message "Found document names in response: $($responseBody.document_names -join ', ')" -Level "INFO"
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
    # Clean up
    if ($null -ne $listener -and $listener.IsListening) {
        $listener.Stop()
        $listener.Close()
    }
    
    Write-ApiLog -Message "API proxy server stopped" -Level "INFO"
}
