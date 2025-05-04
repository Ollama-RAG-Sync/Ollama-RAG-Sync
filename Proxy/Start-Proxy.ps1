# Start-Proxy.ps1 (Renamed from Start-RAGProxy.ps1 for consistency)
# REST API proxy using Pode that provides /api/chat endpoint
# Uses Vectors subsystem for vector search to find relevant context
# Forwards enhanced prompts to Ollama REST API

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility, Pode

param (
    [Parameter(Mandatory=$false)]
    [string]$ListenAddress = "localhost",
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 10000,
    
    [Parameter(Mandatory=$true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaBaseUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$VectorsApiUrl = "http://localhost:10001",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest", # Used for logging/status, not direct embedding here
    
    [Parameter(Mandatory=$false)]
    [decimal]$RelevanceThreshold = 0.75,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxContextDocs = 5,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("chunks", "documents", "both")]
    [string]$QueryMode = "both", 
    
    [Parameter(Mandatory=$false)]
    [double]$ChunkWeight = 0.6,
    
    [Parameter(Mandatory=$false)]
    [double]$DocumentWeight = 0.4,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseHttps,
    
    [Parameter(Mandatory=$false)]
    [switch]$ContextOnlyMode
)

# Import Pode Module
Import-Module Pode -ErrorAction Stop

# Set up logging
$vectorDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db" # Used for status display
$TempDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $TempDir)) 
{ 
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null 
}

$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "Proxy_$logDate.log" # Changed log file name
$logFilePath = Join-Path -Path $TempDir -ChildPath "$logFileName"

function Write-ApiLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
        # Removed ForegroundColor param, let Write-Host handle defaults based on level
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console
    if ($Level -eq "ERROR") {
        Write-Host $logMessage -ForegroundColor Red
    }
    elseif ($Level -eq "WARNING") {
        Write-Host $logMessage -ForegroundColor Yellow
    }
    else {
        Write-Host $logMessage -ForegroundColor Green # Default Green
    }
}

# --- Pre-flight Checks ---
Write-ApiLog -Message "Checking dependent services..." -Level "INFO"
$ollamaOk = $false
$vectorsOk = $false

# Check Ollama
try {
    $ollamaStatus = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
    Write-ApiLog -Message "Ollama connection successful ($OllamaBaseUrl)." -Level "INFO"
    $ollamaOk = $true
    # Check embedding model availability (informational)
    if (-not ($ollamaStatus.models.name -contains $EmbeddingModel)) {
        Write-ApiLog -Message "WARNING: Configured embedding model '$EmbeddingModel' not found in Ollama. Vector search might use a different model." -Level "WARNING"
    }
} catch {
    Write-ApiLog -Message "ERROR: Ollama is not running or not accessible at $OllamaBaseUrl. Please ensure it's running." -Level "ERROR"
}

# Check Vectors API
try {
    Invoke-RestMethod -Uri "$VectorsApiUrl/status" -Method Get -TimeoutSec 5 -ErrorAction Stop
    Write-ApiLog -Message "Vectors API connection successful ($VectorsApiUrl)." -Level "INFO"
    $vectorsOk = $true
} catch {
    Write-ApiLog -Message "ERROR: Vectors API is not running or not accessible at $VectorsApiUrl. Please ensure it's running." -Level "ERROR"
}

if (-not $ollamaOk -or -not $vectorsOk) {
    Write-ApiLog -Message "One or more dependent services are unavailable. Exiting." -Level "ERROR"
    exit 1
}
Write-ApiLog -Message "Dependent service checks passed." -Level "INFO"


# --- Core Logic Functions (Called by Routes) ---

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
    
    Write-ApiLog -Message "Querying Vectors API ($Mode mode) for: '$Query' (Max: $MaxResults, Threshold: $Threshold)" -Level "INFO"
    $combinedResults = @()
    $finalResults = @()
    $success = $true
    $errorMessage = $null

    try {
        $baseBody = @{ query = $Query; max_results = $MaxResults; threshold = 0 } # Threshold applied after combining/sorting

        # Query Chunks
        if ($Mode -eq "chunks" -or $Mode -eq "both") {
            try {
                $chunkResponse = Invoke-RestMethod -Uri "$VectorsApiUrl/api/search/chunks" -Method Post -Body ($baseBody | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
                if ($chunkResponse.success -and $chunkResponse.results) {
                    Write-ApiLog -Message "Found $($chunkResponse.count) matching chunks." -Level "DEBUG" # Changed level
                    $weight = if ($Mode -eq "both") { $ChkWeight } else { 1.0 }
                    foreach ($r in $chunkResponse.results) { 
                        $r.similarity = $r.similarity * $weight
                        $r.source_type = "chunk"
                        $combinedResults += $r 
                    }
                }
            } catch { Write-ApiLog -Message "Warning: Error querying chunks: $($_.Exception.Message)" -Level "WARNING" }
        }

        # Query Documents
        if ($Mode -eq "documents" -or $Mode -eq "both") {
             try {
                $docResponse = Invoke-RestMethod -Uri "$VectorsApiUrl/api/search/documents" -Method Post -Body ($baseBody | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
                if ($docResponse.success -and $docResponse.results) {
                    Write-ApiLog -Message "Found $($docResponse.count) matching documents." -Level "DEBUG" # Changed level
                    $weight = if ($Mode -eq "both") { $DocWeight } else { 1.0 }
                    foreach ($r in $docResponse.results) { 
                        $r.similarity = $r.similarity * $weight
                        $r.source_type = "document"
                        $combinedResults += $r 
                    }
                }
            } catch { Write-ApiLog -Message "Warning: Error querying documents: $($_.Exception.Message)" -Level "WARNING" }
        }

        # Combine, Sort, Filter, Limit
        if ($combinedResults.Count -gt 0) {
            $finalResults = $combinedResults | Sort-Object -Property similarity -Descending | Where-Object { $_.similarity -ge $Threshold } | Select-Object -First $MaxResults
        }

    } catch {
        $success = $false
        $errorMessage = $_.ToString()
    }
    
    return @{ success = $success; error = $errorMessage; results = $finalResults; count = $finalResults.Count }
}

function Format-RelevantContextForOllama {
    param ([Parameter(Mandatory=$true)] [object]$Documents)
    
    $contextText = "--- Context Start ---`n"
    foreach ($doc in $Documents) {
        $source = $doc.metadata.source
        $fileName = Split-Path -Path $source -Leaf
        $content = $doc.document
        $similarity = $doc.similarity
        $sourceType = $doc.source_type
        
        $contextText += "`nSource: $fileName (`nType: $sourceType, Similarity: $([math]::Round($similarity, 4)))`n"
        $contextText += "Content: $content`n"
    }
    $contextText += "`n--- Context End ---`n"
    return $contextText
}

function Get-OllamaModels {
    param (
        [Parameter(Mandatory=$false)]
        [bool]$IncludeDetails = $false,
        [Parameter(Mandatory=$false)]
        [string]$OllamaBaseUrl = $false)
    try {
        $response = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/tags" -Method Get -TimeoutSec 10 -ErrorAction Stop
        $models = $response.models 
        return @{ success = $true; models = $models; count = $models.Count }
    } catch {
        Write-ApiLog -Message "Exception getting models from Ollama: $_" -Level "ERROR"
        return @{ success = $false; error = $_.ToString(); models = @() }
    }
}

function Get-VectorDbStats {
     try {
        $response = Invoke-RestMethod -Uri "$($VectorsApiUrl)/status" -Method Get -TimeoutSec 10 -ErrorAction Stop
        # Assuming the /status endpoint returns the stats directly
        return @{ success = $true; stats = $response } 
    } catch {
        Write-ApiLog -Message "Exception getting vector database stats: $_" -Level "ERROR"
        return @{ success = $false; error = $_.ToString() }
    }
}

function Send-ChatToOllama {
    param (
        [Parameter(Mandatory=$true)] [object[]]$Messages,
        [Parameter(Mandatory=$true)] [string]$Model,
        [Parameter(Mandatory=$false)] [object]$Context = $null, # Ollama context object for conversation history
        [Parameter(Mandatory=$false)] [double]$Temperature = 0.7,
        [Parameter(Mandatory=$false)] [int]$NumCtx = 4096, # Default context window size,
        [Parameter(Mandatory=$false)] [string]$OllamaBaseUrl
    )
    try {
        $body = @{ model = $Model; messages = $Messages; stream = $false } # Stream false for single response
        if ($null -ne $Context) { $body.context = $Context }
        # Add optional parameters if they differ from Ollama defaults
        if ($Temperature -ne 0.8) { $body.options = @{ temperature = $Temperature } } # Ollama default is 0.8
        if ($NumCtx -ne 2048) { # Ollama default is 2048
             if ($body.options -eq $null) { $body.options = @{} }
             $body.options.num_ctx = $NumCtx 
        } 

        $jsonBody = $body | ConvertTo-Json -Depth 10
        # Use single quotes for the outer message string to simplify inner quote handling for -replace
        # Escape the literal $ in the regex pattern with a backtick
        Write-ApiLog -Message ('Sending request to Ollama: ' + ($jsonBody -replace '"password":".*?"', '"password":"***"')) -Level "DEBUG" # Log request without sensitive data if any
        
        $response = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/chat" -Method Post -Body $jsonBody -ContentType "application/json" -TimeoutSec 120 -ErrorAction Stop # Increased timeout
        
        return @{ success = $true; result = $response }
    } catch {
        Write-ApiLog -Message "Exception sending chat to Ollama: $_" -Level "ERROR"
        return @{ success = $false; error = $_.ToString() }
    }
}

# --- Start Pode Server ---
try {
    Write-ApiLog -Message "Starting RAG Proxy API server using Pode..."
    Write-ApiLog -Message "Ollama URL: $OllamaBaseUrl"
    Write-ApiLog -Message "Vectors API URL: $VectorsApiUrl"
    if ($ContextOnlyMode) { Write-ApiLog -Message "Running in Context-Only Mode" -Level "WARNING" }

    # Start the server without the -Endpoint parameter, as it's added above
    Start-PodeServer -Threads 4 {
        Add-PodeEndpoint -Address $ListenAddress -Port $Port -Protocol Http

        $ollamaUrl = $OllamaBaseUrl
        $vectorsApiUrl = $VectorsApiUrl
        $embeddingModel = $EmbeddingModel # Informational
        $relevanceThreshold = $RelevanceThreshold
        $maxContextDocs = $MaxContextDocs
        $queryMode = $QueryMode
        $chunkWeight = $ChunkWeight
        $documentWeight = $DocumentWeight
        $contextOnlyMode = $ContextOnlyMode.IsPresent

        # GET / - Basic info
        Add-PodeRoute -Method Get -Path "/" -ScriptBlock {
            Write-PodeJsonResponse -Value @{
                status = "ok"
                message = "RAG Proxy API running"
                contextOnlyMode = $using:contextOnlyMode
                routes = @(
                    "/api/chat - POST: Chat with context augmentation",
                    "/api/search - POST: Search for relevant documents/chunks",
                    "/api/models - GET: Get list of available Ollama models",
                    "/api/stats - GET: Get statistics about vector database via Vectors API",
                    "/status - GET: Get API proxy status"
                )
            }
        } 

        # GET /status
        Add-PodeRoute -Method Get -Path "/status" -ScriptBlock {
             Write-PodeJsonResponse -Value @{
                status = "ok"
                ollamaUrl = $using:ollamaUrl
                vectorsApiUrl = $using:vectorsApiUrl
                embeddingModel = $using:embeddingModel # Informational
                relevanceThreshold = $using:relevanceThreshold
                maxContextDocs = $using:maxContextDocs
                queryMode = $using:queryMode
                chunkWeight = $using:chunkWeight
                documentWeight = $using:documentWeight
                contextOnlyMode = $using:contextOnlyMode
            }
        }

        # GET /api/models
        Add-PodeRoute -Method Get -Path "/api/models" -ScriptBlock {
            try {
                $includeDetails = $WebEvent.Query['include_details'] -eq 'true'
                $modelsResult = Get-OllamaModels -IncludeDetails $includeDetails -OllamaBaseUrl $using:ollamaUrl
                if ($modelsResult.success) {
                    Write-PodeJsonResponse -Value @{ models = $modelsResult.models; count = $modelsResult.count }
                } else {
                    Write-PodeJsonResponse -StatusCode 502 -Value @{ success = $false; error = "Failed to retrieve models from Ollama"; details = $modelsResult.error }
                }
            } catch {
                 Write-ApiLog -Message "Error in GET /api/models: $_" -Level "ERROR"
                 Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }

        # GET /api/stats - Vector DB Stats
        Add-PodeRoute -Method Get -Path "/api/stats" -ScriptBlock {
            try {
                $statsResult = Get-VectorDbStats
                if ($statsResult.success) {
                    Write-PodeJsonResponse -Value @{ success = $true; stats = $statsResult.stats }
                } else {
                    Write-PodeJsonResponse -StatusCode 502 -Value @{ success = $false; error = "Failed to retrieve stats from Vectors API"; details = $statsResult.error }
                }
            } catch {
                 Write-ApiLog -Message "Error in GET /api/stats: $_" -Level "ERROR"
                 Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }

        # POST /api/search - Passthrough to Vectors API search
        Add-PodeRoute -Method Post -Path "/api/search" -ScriptBlock {
            try {
                $data = $WebEvent.Data
                if ($null -eq $data -or [string]::IsNullOrEmpty($data.query)) {
                    Write-PodeJsonResponse -StatusCode 400 -Value @{ success = $false; error = "Bad request: Required parameter missing: query" }; return
                }
                
                $query = $data.query
                $maxResults = if ($null -ne $data.max_results) { $data.max_results } else { $maxContextDocs }
                $threshold = if ($null -ne $data.threshold) { $data.threshold } else { $relevanceThreshold }
                $mode = if ($null -ne $data.mode) { $data.mode } else { $QueryMode }
                $chkWeight = if ($null -ne $data.chunk_weight) { $data.chunk_weight } else { $chunkWeight }
                $docWeight = if ($null -ne $data.document_weight) { $data.document_weight } else { $documentWeight }

                $searchResult = Get-RelevantDocuments -Query $query -MaxResults $maxResults -Threshold $threshold -Mode $mode -ChkWeight $chkWeight -DocWeight $docWeight
                
                if ($searchResult.success) {
                    Write-PodeJsonResponse -Value @{ success = $true; query = $query; results = $searchResult.results; count = $searchResult.count }
                } else {
                    Write-PodeJsonResponse -StatusCode 502 -Value @{ success = $false; error = "Search failed"; details = $searchResult.error }
                }
            } catch {
                 Write-ApiLog -Message "Error in POST /api/search: $_" -Level "ERROR"
                 Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        } 

        # POST /api/chat
        Add-PodeRoute -Method Post -Path "/api/chat" -ScriptBlock {
            try {
                $data = $WebEvent.Data
                if ($null -eq $data -or $null -eq $data.messages) {
                    Write-PodeJsonResponse -StatusCode 400 -Value @{ success = $false; error = "Bad request: Required parameter missing: messages" }; return
                }
                
                $messages = $data.messages
                $model = if ($null -ne $data.model) { $data.model } else { "llama3" } # Default model
                $maxResults = if ($null -ne $data.max_context_docs) { $data.max_context_docs } else { $using:maxContextDocs }
                $threshold = if ($null -ne $data.threshold) { $data.threshold } else { $using:relevanceThreshold }
                $enhanceContext = if ($null -ne $data.enhance_context) { $data.enhance_context } else { $true }
                $temperature = if ($null -ne $data.temperature) { $data.temperature } else { 0.7 }
                $numCtx = if ($null -ne $data.num_ctx) { $data.num_ctx } else { 4096 } # Default context window
                $ollamaContext = if ($null -ne $data.context) { $data.context } else { $null } # Pass through Ollama context if provided

                # Find latest user message for context search
                $latestUserMessage = ($messages | Where-Object { $_.role -eq 'user' } | Select-Object -Last 1).content
                
                $contextDocuments = @()
                $formattedContext = $null
                $searchPerformed = $false

                if ($enhanceContext -and $null -ne $latestUserMessage) {
                    $searchPerformed = $true
                    $qMode = if ($null -ne $data.query_mode) { $data.query_mode } else { $using:queryMode }
                    $chkWeight = if ($null -ne $data.chunk_weight) { $data.chunk_weight } else { $using:chunkWeight }
                    $docWeight = if ($null -ne $data.document_weight) { $data.document_weight } else { $using:documentWeight }
                    
                    $searchResult = Get-RelevantDocuments -Query $latestUserMessage -MaxResults $maxResults -Threshold $threshold -Mode $qMode -ChkWeight $chkWeight -DocWeight $docWeight
                    
                    if ($searchResult.success -and $searchResult.count -gt 0) {
                        Write-ApiLog -Message "Found $($searchResult.count) relevant documents for context." -Level "INFO"
                        $contextDocuments = $searchResult.results
                        $formattedContext = Format-RelevantContextForOllama -Documents $contextDocuments
                    } else {
                         Write-ApiLog -Message "No relevant documents found meeting threshold for context." -Level "INFO"
                         if (-not $searchResult.success) { 
                             Write-ApiLog -Message "Vector search failed: $($searchResult.error)" -Level "WARNING"
                         }
                    }
                }
                # Prepare messages for Ollama
                $ollamaMessages = @() + $messages # Create a mutable copy
                $systemMessageIndex = 0
                for ($i = 0; $i -lt $ollamaMessages.Count; $i++) {
                    if ($ollamaMessages[$i].role -eq 'system') {
                        $systemMessageIndex = $i
                        break
                    }
                }   

                if ($null -ne $formattedContext) {
                    # Inject context into system message or add a new one
                    $contextPrefix = if ($contextOnlyMode) {
                        "IMPORTANT: You must ONLY use information from the provided context below to answer the user's question. Do NOT use your own knowledge or training data. If the context doesn't contain relevant information, state that clearly."
                    } else {
                        "Use the following context to help answer the user's question:"
                    }
                    
                    $fullSystemContent = "$contextPrefix`n$formattedContext"

                    if ($systemMessageIndex -ge 0) {
                        $ollamaMessages[$systemMessageIndex].content = "$($ollamaMessages[$systemMessageIndex].content)`n`n$fullSystemContent"
                    } else {
                        $ollamaMessages = @(@{ role = 'system'; content = $fullSystemContent }) + $ollamaMessages
                    }
                } elseif ($contextOnlyMode -and $searchPerformed) {
                     # Context-Only mode, search was done, but nothing found
                     $noContextMsg = "IMPORTANT: No relevant context was found for the user's query. Inform the user that you cannot answer the question based *only* on the provided context, as required."
                     if ($systemMessageIndex -ge 0) {
                        $ollamaMessages[$systemMessageIndex].content = "$($ollamaMessages[$systemMessageIndex].content)`n`n$noContextMsg"
                    } else {
                        $ollamaMessages = @(@{ role = 'system'; content = $noContextMsg }) + $ollamaMessages
                    }
                }

                # Send to Ollama
                $chatResult = Send-ChatToOllama -OllamaBaseUrl $using:ollamaUrl -Messages $ollamaMessages -Model $model -Context $ollamaContext -Temperature $temperature -NumCtx $numCtx
                if ($chatResult.success) {
                    $responseBody = $chatResult.result
                    # Add context metadata to response
                    $responseBody | Add-Member -MemberType NoteProperty -Name "context_info" -Value @{
                        used = ($null -ne $formattedContext)
                        count = $contextDocuments.Count
                        documents = if ($contextDocuments.Count -gt 0) { 
                            $contextDocuments | ForEach-Object { @{ source = Split-Path -Path $_.metadata.source -Leaf; similarity = $_.similarity; type = $_.source_type } } 
                        } else { @() }
                    }
                    Write-PodeJsonResponse -Value $responseBody
                } else {
                    Write-PodeJsonResponse -StatusCode 502 -Value @{ success = $false; error = "Failed to get response from Ollama ($using:ollamaUrl)"; details = $chatResult.error }
                }

            } catch {
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                 
            }
        }
    }

    # Use subexpressions $(...) for robust variable interpolation within the string
    Write-ApiLog -Message "RAG Proxy API server running at $($protocol)://$($ListenAddress):$($Port)"
    Write-ApiLog -Message "Swagger UI available at $($protocol)://$($ListenAddress):$($Port)/swagger"
    Write-ApiLog -Message "Press Ctrl+C to stop the server."

} catch {
    Write-ApiLog -Message "Fatal error starting Pode server: $_" -Level "ERROR"
    Write-ApiLog "$($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}
