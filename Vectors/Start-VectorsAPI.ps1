# Start-VectorsAPI.ps1
# REST API server for Vectors subsystem using Pode
# Provides endpoints for adding, removing, and searching documents/chunks in the vector database

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility, Pode

param (
    [Parameter(Mandatory=$false)]
    [string]$ListenAddress = "localhost", # Pode uses this in Start-PodeServer -Endpoint
    
    [Parameter(Mandatory=$true)]
    [int]$Port,
    
    [Parameter(Mandatory=$false)]
    [string]$ChromaDbPath, # Will be determined based on InstallPath if not provided
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [int]$DefaultChunkSize = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$DefaultChunkOverlap = 200,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseHttps, # Pode handles HTTPS via Start-PodeServer -Endpoint options

    [Parameter(Mandatory=$true)]
    [string]$InstallPath
)

# Import Pode Module
Import-Module Pode -ErrorAction Stop

# Determine script path and import local modules/functions
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path -Path $scriptPath -ChildPath "Modules"
$functionsPath = Join-Path -Path $scriptPath -ChildPath "Functions"

# Set up logging
$TempDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $TempDir)) 
{ 
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null 
}

$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "Vectors_$logDate.log"
$logFilePath = Join-Path -Path $TempDir -ChildPath "$logFileName"

# Determine ChromaDB Path if not provided
if (-not $ChromaDbPath) {
    $ChromaDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db"
    Write-Host "ChromaDbPath not provided, using default: $ChromaDbPath" -ForegroundColor Cyan
}

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
    else {
        Write-Host $logMessage -ForegroundColor Green # Default to Green
    }
    
    # Write to log file
    Add-Content -Path $logFilePath -Value $logMessage
}

# --- Core Logic Functions (Keep original functions, they are called by routes) ---

# Function to add a document to the vector database
function Add-Document {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$false)]
        [int]$FileId = 0,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkSize = $using:DefaultChunkSize, # Use script-level default
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkOverlap = $using:DefaultChunkOverlap, # Use script-level default
        
        [Parameter(Mandatory=$false)]
        [string]$ContentType = "Text"
    )
    
    try {
        Write-Log "Adding document to vectors: $FilePath (ID: $FileId)"
        
        # Set parameters for Add-DocumentToVectors.ps1
        $params = @{
            FilePath = $FilePath
            # FileId is not used by Add-DocumentToVectors.ps1 but kept for logging/response
        }
        
        # Add optional parameters if provided and different from default
        if ($ChunkSize -ne $using:DefaultChunkSize) { $params.ChunkSize = $ChunkSize }
        if ($ChunkOverlap -ne $using:DefaultChunkOverlap) { $params.ChunkOverlap = $ChunkOverlap }
        
        # Pass global config
        $params.ChromaDbPath = $using:ChromaDbPath
        $params.OllamaUrl = $using:OllamaUrl
        $params.EmbeddingModel = $using:EmbeddingModel
        
        # Call Add-DocumentToVectors.ps1
        $addDocumentScript = Join-Path -Path $using:functionsPath -ChildPath "Add-DocumentToVectors.ps1"
        $result = & $addDocumentScript @params
        
        if ($result) {
            Write-Log "Successfully added document to vectors: $FilePath"
            return @{ success = $true; message = "Document added successfully"; filePath = $FilePath; fileId = $FileId }
        } else {
            Write-Log "Failed to add document to vectors: $FilePath" -Level "ERROR"
            return @{ success = $false; error = "Failed to add document to vectors"; filePath = $FilePath; fileId = $FileId }
        }
    }
    catch {
        Write-Log "Error adding document to vectors: $_" -Level "ERROR" # Removed ScriptStackTrace for brevity
        return @{ success = $false; error = $_.ToString(); filePath = $FilePath; fileId = $FileId }
    }
}

# Function to remove a document from the vector database
function Remove-Document {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false)]
        [int]$FileId = 0 # Kept for logging/response consistency
    )
    
    try {
        Write-Log "Removing document from vectors: $FilePath (ID: $FileId)"
        
        # Set parameters for Remove-DocumentFromVectors.ps1
        $params = @{
            FilePath = $FilePath
            ChromaDbPath = $using:ChromaDbPath
            OllamaUrl = $using:OllamaUrl
            EmbeddingModel = $using:EmbeddingModel
        }
        
        # Call Remove-DocumentFromVectors.ps1
        $removeDocumentScript = Join-Path -Path $using:functionsPath -ChildPath "Remove-DocumentFromVectors.ps1"
        $result = & $removeDocumentScript @params
        
        if ($result) {
            Write-Log "Successfully removed document from vectors: $FilePath"
            return @{ success = $true; message = "Document removed successfully"; filePath = $FilePath; fileId = $FileId }
        } else {
            Write-Log "Failed to remove document from vectors: $FilePath" -Level "ERROR"
            # Check if the error was 'not found' vs other failure
            if ($_.Exception.Message -like "*No vectors found for file*") {
                 return @{ success = $false; error = "Document not found in vectors"; filePath = $FilePath; fileId = $FileId; notFound = $true }
            } else {
                 return @{ success = $false; error = "Failed to remove document from vectors"; filePath = $FilePath; fileId = $FileId }
            }
        }
    }
    catch {
        Write-Log "Error removing document from vectors: $_" -Level "ERROR"
         if ($_.Exception.Message -like "*No vectors found for file*") {
             return @{ success = $false; error = "Document not found in vectors: $($_.Exception.Message)"; filePath = $FilePath; fileId = $FileId; notFound = $true }
         } else {
            return @{ success = $false; error = $_.ToString(); filePath = $FilePath; fileId = $FileId }
         }
    }
}

# Function to search for chunks by query
function Search-Chunks {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxResults = 10,
        
        [Parameter(Mandatory=$false)]
        [double]$MinScore = 0.0,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$WhereFilter = @{}
    )
    
    try {
        Write-Log "Searching chunks for query: $Query"
        
        # Set parameters for Get-ChunksByQuery.ps1
        $params = @{
            QueryText = $Query
            MaxResults = $MaxResults
            MinScore = $MinScore
            ChromaDbPath = $using:ChromaDbPath
            OllamaUrl = $using:OllamaUrl
            EmbeddingModel = $using:EmbeddingModel
        }
        
        if ($WhereFilter.Count -gt 0) { $params.WhereFilter = $WhereFilter }
        
        # Call Get-ChunksByQuery.ps1
        $searchScript = Join-Path -Path $using:functionsPath -ChildPath "Get-ChunksByQuery.ps1"
        $results = & $searchScript @params
        
        if ($results -and $results.Count -gt 0) {
            Write-Log "Found $($results.Count) matching chunks for query: $Query"
            return @{ success = $true; results = $results; count = $results.Count; query = $Query }
        } else {
            Write-Log "No matching chunks found for query: $Query" -Level "INFO"
            return @{ success = $true; results = @(); count = 0; query = $Query }
        }
    }
    catch {
        Write-Log "Error searching chunks: $_" -Level "ERROR"
        return @{ success = $false; error = $_.ToString(); results = @(); count = 0; query = $Query }
    }
}

# Function to search for documents by query
function Search-Documents {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxResults = 10,
        
        [Parameter(Mandatory=$false)]
        [double]$MinScore = 0.0,
        
        [Parameter(Mandatory=$false)]
        [bool]$ReturnSourceContent = $false,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$WhereFilter = @{}
    )
    
    try {
        Write-Log "Searching documents for query: $Query"
        
        # Set parameters for Get-DocumentsByQuery.ps1
        $params = @{
            QueryText = $Query
            MaxResults = $MaxResults
            MinScore = $MinScore
            ReturnSourceContent = $ReturnSourceContent
            ChromaDbPath = $using:ChromaDbPath
            OllamaUrl = $using:OllamaUrl
            EmbeddingModel = $using:EmbeddingModel
        }
        
        if ($WhereFilter.Count -gt 0) { $params.WhereFilter = $WhereFilter }
        
        # Call Get-DocumentsByQuery.ps1
        $searchScript = Join-Path -Path $using:functionsPath -ChildPath "Get-DocumentsByQuery.ps1"
        $results = & $searchScript @params
        
        if ($results -and $results.Count -gt 0) {
            Write-Log "Found $($results.Count) matching documents for query: $Query"
            return @{ success = $true; results = $results; count = $results.Count; query = $Query }
        } else {
            Write-Log "No matching documents found for query: $Query" -Level "INFO"
            return @{ success = $true; results = @(); count = 0; query = $Query }
        }
    }
    catch {
        Write-Log "Error searching documents: $_" -Level "ERROR"
        return @{ success = $false; error = $_.ToString(); results = @(); count = 0; query = $Query }
    }
}

# --- Start Pode Server ---
try {
    Write-Log "Starting Vectors API server using Pode..."
    Write-Log "ChromaDB Path: $ChromaDbPath"
    Write-Log "Ollama URL: $OllamaUrl"
    Write-Log "Embedding model: $EmbeddingModel"

    Start-PodeServer -Threads 4 {
        Add-PodeEndpoint -Address $ListenAddress -Port $Port -Protocol Http
        # Middleware & OpenAPI Setup
        Enable-PodeOpenApi -Title "Vectors API" -Version "1.0.0" -Description "API for managing and querying vector embeddings" -ErrorAction Stop

        # --- API Routes ---

        # GET / - Basic info
        Add-PodeRoute -Method Get -Path "/" -ScriptBlock {
            Write-PodeJsonResponse -Value @{
                status = "ok"
                message = "Vectors API server running"
                routes = @(
                    "/documents - POST: Add a document to vectors",
                    "/documents - DELETE: Remove a document from vectors (use filePath in body)",
                    "/api/search/chunks - POST: Search for relevant chunks",
                    "/api/search/documents - POST: Search for relevant documents",
                    "/status - GET: Get server status"
                )
            }
        } -OpenApi @{
            Summary = "API Information"
            Description = "Provides basic status and lists available routes."
            Responses = @{ "200" = @{ Description = "API status and routes" } }
        }

        # GET /status
        Add-PodeRoute -Method Get -Path "/status" -ScriptBlock {
             Write-PodeJsonResponse -Value @{
                status = "ok"
                chromaDbPath = $using:ChromaDbPath
                ollamaUrl = $using:OllamaUrl
                embeddingModel = $using:EmbeddingModel
                defaultChunkSize = $using:DefaultChunkSize
                defaultChunkOverlap = $using:DefaultChunkOverlap
            }
        } -OpenApi @{
            Summary = "Server Status"
            Description = "Returns the current configuration and status of the Vectors API server."
             Responses = @{ "200" = @{ Description = "Server configuration details" } }
        }

        # POST /documents - Add document
        Add-PodeRoute -Method Post -Path "/documents" -ScriptBlock {
            try {
                $data = $WebEvent.Data
                if ($null -eq $data -or [string]::IsNullOrEmpty($data.filePath)) {
                    Set-PodeResponseStatus -Code 400
                    Write-PodeJsonResponse -Value @{ success = $false; error = "Bad request: Required parameter missing: filePath" }; return
                }
                
                $filePath = $data.filePath
                $fileId = if ($null -ne $data.fileId) { $data.fileId } else { 0 }
                $chunkSize = if ($null -ne $data.chunkSize) { $data.chunkSize } else { $using:DefaultChunkSize }
                $chunkOverlap = if ($null -ne $data.chunkOverlap) { $data.chunkOverlap } else { $using:DefaultChunkOverlap }
                $contentType = if ($null -ne $data.contentType) { $data.contentType } else { "Text" }
                
                $result = Add-Document -FilePath $filePath -FileId $fileId -ChunkSize $chunkSize -ChunkOverlap $chunkOverlap -ContentType $contentType
                
                if ($result.success) {
                    Write-PodeJsonResponse -Value $result
                } else {
                    Set-PodeResponseStatus -Code 500
                    Write-PodeJsonResponse -Value $result
                }
            } catch {
                 Write-Log "Error in POST /documents: $_" -Level "ERROR"
                 Set-PodeResponseStatus -Code 500
                 Write-PodeJsonResponse -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        } -OpenApi @{
            Summary = "Add Document to Vectors"
            Description = "Processes a file, generates embeddings for its chunks, and stores them in the vector database."
            RequestBody = @{
                Required = $true
                Content = @{ "application/json" = @{ Schema = @{ 
                    type = "object"; 
                    properties = @{ 
                        filePath = @{ type = "string"; description = "Path to the file to process" }; 
                        fileId = @{ type = "integer"; description = "Optional ID associated with the file" }; 
                        chunkSize = @{ type = "integer"; description = "Chunk size (default: $($using:DefaultChunkSize))" }; 
                        chunkOverlap = @{ type = "integer"; description = "Chunk overlap (default: $($using:DefaultChunkOverlap))" };
                        contentType = @{ type = "string"; description = "Content type (e.g., Text, Markdown - currently informational)" } 
                    }; 
                    required = @("filePath") 
                } } }
            }
            Responses = @{
                "200" = @{ Description = "Document added successfully" }
                "400" = @{ Description = "Bad Request (missing filePath)" }
                "500" = @{ Description = "Internal Server Error during processing" }
            }
        }

        # DELETE /documents - Remove document (using body for filePath)
        Add-PodeRoute -Method Delete -Path "/documents" -ScriptBlock {
             try {
                $data = $WebEvent.Data
                if ($null -eq $data -or [string]::IsNullOrEmpty($data.filePath)) {
                    Set-PodeResponseStatus -Code 400
                    Write-PodeJsonResponse -Value @{ success = $false; error = "Bad request: Required parameter missing in body: filePath" }; return
                }

                $filePath = $data.filePath
                $fileId = if ($null -ne $data.fileId) { $data.fileId } else { 0 } # Optional fileId from body

                $result = Remove-Document -FilePath $filePath -FileId $fileId
                
                if ($result.success) {
                    Write-PodeJsonResponse -Value $result
                } elseif ($result.notFound) {
                     Set-PodeResponseStatus -Code 404
                     Write-PodeJsonResponse -Value $result
                } else {
                    Set-PodeResponseStatus -Code 500
                    Write-PodeJsonResponse -Value $result
                }
            } catch {
                 Write-Log "Error in DELETE /documents: $_" -Level "ERROR"
                 Set-PodeResponseStatus -Code 500
                 Write-PodeJsonResponse -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        } -OpenApi @{
            Summary = "Remove Document from Vectors"
            Description = "Removes all vector embeddings associated with a specific file path from the database."
             RequestBody = @{
                Required = $true
                Content = @{ "application/json" = @{ Schema = @{ 
                    type = "object"; 
                    properties = @{ 
                        filePath = @{ type = "string"; description = "Path of the file whose vectors should be removed" };
                        fileId = @{ type = "integer"; description = "Optional ID associated with the file (for response consistency)" }; 
                    }; 
                    required = @("filePath") 
                } } }
            }
            Responses = @{
                "200" = @{ Description = "Document vectors removed successfully" }
                "400" = @{ Description = "Bad Request (missing filePath in body)" }
                "404" = @{ Description = "Document not found in vector store" }
                "500" = @{ Description = "Internal Server Error during removal" }
            }
        }

        # POST /api/search/chunks
        Add-PodeRoute -Method Post -Path "/api/search/chunks" -ScriptBlock {
            try {
                $data = $WebEvent.Data
                if ($null -eq $data -or [string]::IsNullOrEmpty($data.query)) {
                    Set-PodeResponseStatus -Code 400
                    Write-PodeJsonResponse -Value @{ success = $false; error = "Bad request: Required parameter missing: query" }; return
                }
                
                $query = $data.query
                $maxResults = if ($null -ne $data.max_results) { $data.max_results } else { 10 }
                $threshold = if ($null -ne $data.threshold) { $data.threshold } else { 0.0 }
                $whereFilter = if ($null -ne $data.filter) { $data.filter } else { @{} }
                
                $result = Search-Chunks -Query $query -MaxResults $maxResults -MinScore $threshold -WhereFilter $whereFilter
                
                if ($result.success) {
                    Write-PodeJsonResponse -Value $result
                } else {
                    Set-PodeResponseStatus -Code 500
                    Write-PodeJsonResponse -Value $result
                }
            } catch {
                 Write-Log "Error in POST /api/search/chunks: $_" -Level "ERROR"
                 Set-PodeResponseStatus -Code 500
                 Write-PodeJsonResponse -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        } -OpenApi @{
            Summary = "Search Chunks"
            Description = "Searches for individual text chunks in the vector database based on semantic similarity to the query."
            RequestBody = @{
                Required = $true
                Content = @{ "application/json" = @{ Schema = @{ 
                    type = "object"; 
                    properties = @{ 
                        query = @{ type = "string"; description = "The search query text" }; 
                        max_results = @{ type = "integer"; description = "Maximum number of results to return (default: 10)" }; 
                        threshold = @{ type = "number"; format="double"; description = "Minimum similarity score (default: 0.0)" }; 
                        filter = @{ type = "object"; description = "Optional metadata filter (ChromaDB 'where' format)" } 
                    }; 
                    required = @("query") 
                } } }
            }
            Responses = @{
                "200" = @{ Description = "Search results (list of chunks)" }
                "400" = @{ Description = "Bad Request (missing query)" }
                "500" = @{ Description = "Internal Server Error during search" }
            }
        }

        # POST /api/search/documents
        Add-PodeRoute -Method Post -Path "/api/search/documents" -ScriptBlock {
             try {
                $data = $WebEvent.Data
                if ($null -eq $data -or [string]::IsNullOrEmpty($data.query)) {
                    Set-PodeResponseStatus -Code 400
                    Write-PodeJsonResponse -Value @{ success = $false; error = "Bad request: Required parameter missing: query" }; return
                }
                
                $query = $data.query
                $maxResults = if ($null -ne $data.max_results) { $data.max_results } else { 10 }
                $threshold = if ($null -ne $data.threshold) { $data.threshold } else { 0.0 }
                $returnContent = if ($null -ne $data.return_content) { $data.return_content } else { $false }
                $whereFilter = if ($null -ne $data.filter) { $data.filter } else { @{} }
                
                $result = Search-Documents -Query $query -MaxResults $maxResults -MinScore $threshold -ReturnSourceContent $returnContent -WhereFilter $whereFilter
                
                if ($result.success) {
                    Write-PodeJsonResponse -Value $result
                } else {
                    Set-PodeResponseStatus -Code 500
                    Write-PodeJsonResponse -Value $result
                }
            } catch {
                 Write-Log "Error in POST /api/search/documents: $_" -Level "ERROR"
                 Set-PodeResponseStatus -Code 500
                 Write-PodeJsonResponse -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        } -OpenApi @{
            Summary = "Search Documents"
            Description = "Searches for documents in the vector database based on semantic similarity, aggregating chunk scores."
             RequestBody = @{
                Required = $true
                Content = @{ "application/json" = @{ Schema = @{ 
                    type = "object"; 
                    properties = @{ 
                        query = @{ type = "string"; description = "The search query text" }; 
                        max_results = @{ type = "integer"; description = "Maximum number of documents to return (default: 10)" }; 
                        threshold = @{ type = "number"; format="double"; description = "Minimum aggregated similarity score (default: 0.0)" }; 
                        return_content = @{ type = "boolean"; description = "Whether to return the source content of the best matching chunk (default: false)" };
                        filter = @{ type = "object"; description = "Optional metadata filter (ChromaDB 'where' format)" } 
                    }; 
                    required = @("query") 
                } } }
            }
            Responses = @{
                "200" = @{ Description = "Search results (list of documents)" }
                "400" = @{ Description = "Bad Request (missing query)" }
                "500" = @{ Description = "Internal Server Error during search" }
            }
        }

        # Default route for 404
        Add-PodeRoute -Method * -Path * -ScriptBlock {
            Set-PodeResponseStatus -Code 404
            Write-PodeJsonResponse -Value @{ success = $false; error = "Endpoint not found: $($WebEvent.Request.Url.Path)" }
        }
    }

    Write-Log "Vectors API server running at $($endpointParams.Protocol)://$($endpointParams.Address):$($endpointParams.Port)"
    Write-Log "Swagger UI available at $($endpointParams.Protocol)://$($endpointParams.Address):$($endpointParams.Port)/swagger"
    Write-Log "Press Ctrl+C to stop the server."

} catch {
    Write-Log "Fatal error starting Pode server: $_" -Level "ERROR"
    Write-Log "$($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}

# Keep PowerShell session open until Ctrl+C
while ($true) { Start-Sleep -Seconds 1 }
