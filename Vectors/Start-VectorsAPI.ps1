# Start-VectorsAPI.ps1
# REST API server for Vectors subsystem using Pode
# Provides endpoints for adding, removing, and searching documents/chunks in the vector database

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility, Pode

param (
    [Parameter(Mandatory=$false)]
    [string]$ListenAddress = "localhost", # Pode uses this in Start-PodeServer -Endpoint
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 10001,

    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434", # Ollama API URL
    
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
 $chromaDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db"

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
}

# --- Core Logic Functions (Keep original functions, they are called by routes) ---

# Function to add a document to the vector database
function Add-Document {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string]$ChromaDbPath,

        [Parameter(Mandatory=$true)]
        [string]$OllamaUrl,

        [Parameter(Mandatory=$true)]
        [string]$EmbeddingModel,

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
        #if ($ChunkSize -ne $using:DefaultChunkSize) { $params.ChunkSize = $ChunkSize }
        #if ($ChunkOverlap -ne $using:DefaultChunkOverlap) { $params.ChunkOverlap = $ChunkOverlap }
        
        # Pass global config
        $params.ChromaDbPath = $ChromaDbPath
        $params.OllamaUrl = $OllamaUrl
        $params.EmbeddingModel = $EmbeddingModel

        $functionsPath = "Functions"
        
        Write-Host  "Functions Path =  $functionsPath"
        Write-Host  "ChromaDbPath =  $ChromaDbPath"
        Write-Host  "OllamaUrl =  $OllamaUrl"
        Write-Host  "EmbeddingModel = $EmbeddingModel"

        # Call Add-DocumentToVectors.ps1
        $addDocumentScript = Join-Path -Path $functionsPath -ChildPath "Add-DocumentToVectors.ps1"

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
        Write-Log "Error adding document to vectors: $_ $($_.ScriptStackTrace)" -Level "ERROR" # Removed ScriptStackTrace for brevity
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
            ChromaDbPath = $using:chromaDbPath
            OllamaUrl = $using:OllamaUrl
            EmbeddingModel = $using:EmbeddingModel
        }
        
        # Call Remove-DocumentFromVectors.ps1
        $removeDocumentScript = Join-Path -Path $FunctionsPath -ChildPath "Remove-DocumentFromVectors.ps1"
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
            ChromaDbPath = $using:chromaDbPath
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
        [hashtable]$WhereFilter = @{},

        [Parameter(Mandatory=$true)]
        [string]$ChromaDbPath,
        
        [Parameter(Mandatory=$true)]
        [string]$OllamaUrl,

        [Parameter(Mandatory=$true)]
        [string]$EmbeddingModel
    )
    
    try {
        Write-Log "Searching documents for query: $Query"
        
        # Set parameters for Get-DocumentsByQuery.ps1
        $params = @{
            QueryText = $Query
            MaxResults = $MaxResults
            MinScore = $MinScore
            ReturnSourceContent = $ReturnSourceContent
            ChromaDbPath = $ChromaDbPath
            OllamaUrl = $OllamaUrl
            EmbeddingModel = $EmbeddingModel
        }
        
        if (($WhereFilter -ne $null) -and ($WhereFilter.Count -gt 0)) { $params.WhereFilter = $WhereFilter }
        
        # Call Get-DocumentsByQuery.ps1
        $searchScript = Join-Path -Path ".\Functions" -ChildPath "Get-DocumentsByQuery.ps1"
        $results = & $searchScript @params

        if ($results -ne $null -and $results.Count -gt 0) {
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
    $scriptsPath = $PSScriptRoot
    $modulesPath = Join-Path -Path $scriptsPath -ChildPath "Modules"
    $functionsPath = Join-Path -Path $scriptsPath -ChildPath "Functions"
    
    Write-Log "Importing modules..."
    Import-Module "$modulesPath\Vectors-Core.psm1" -Force -Verbose
    Import-Module "$modulesPath\Vectors-Database.psm1" -Force -Verbose
    Import-Module "$modulesPath\Vectors-Embeddings.psm1" -Force -Verbose
   
    Write-Log "Starting Vectors API server using Pode..."
    Write-Log "ChromaDB Path: $ChromaDbPath"
    Write-Log "Ollama URL: $OllamaUrl"
    Write-Log "Embedding model: $EmbeddingModel"

    Start-PodeServer -Threads 4 {

        $chromaDbPath  = $ChromaDbPath
        $ollamaUrl = $OllamaUrl
        $embeddingModel = $EmbeddingModel

        New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging -Levels Error, Warning, Informational, Verbose

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
        } 

        # GET /status
        Add-PodeRoute -Method Get -Path "/status" -ScriptBlock {
             Write-PodeJsonResponse -Value @{
                status = "ok"
                chromaDbPath = $using:chromaDbPath
                ollamaUrl = $using:OllamaUrl
                embeddingModel = $using:EmbeddingModel
                defaultChunkSize = $using:DefaultChunkSize
                defaultChunkOverlap = $using:DefaultChunkOverlap
            }
        }
        # POST /documents - Add document
        Add-PodeRoute -Method Post -Path "/documents" -ScriptBlock {
            try {
                $data = $WebEvent.Data
                if ($null -eq $data -or [string]::IsNullOrEmpty($data.filePath)) {
                    Write-PodeJsonResponse -StatusCode 400 -Value @{ success = $false; error = "Bad request: Required parameter missing: filePath" }; return
                }
                
                $filePath = $data.filePath
                $fileId = if ($null -ne $data.fileId) { $data.fileId } else { 0 }
                $chunkSize = if ($null -ne $data.chunkSize) { $data.chunkSize } else { $using:DefaultChunkSize }
                $chunkOverlap = if ($null -ne $data.chunkOverlap) { $data.chunkOverlap } else { $using:DefaultChunkOverlap }
                $contentType = if ($null -ne $data.contentType) { $data.contentType } else { "Text" }

                $chromaDbPath  = $using:chromaDbPath
                $ollamaUrl = $using:OllamaUrl
                $embeddingModel = $using:EmbeddingModel

                $result = Add-Document -ChromaDbPath $chromaDbPath -OllamaUrl $ollamaUrl -Embedding $embeddingModel -FilePath $filePath -FileId $fileId -ChunkSize $chunkSize -ChunkOverlap $chunkOverlap -ContentType $contentType
                
                if ($result.success) {
                    Write-PodeJsonResponse -Value $result
                } else {
                    Write-PodeJsonResponse -StatusCode 500 -Value $result
                }
            } catch {
                 Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
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
                     Write-PodeJsonResponse -StatusCode 404 -Value $result
                } else {
                    Write-PodeJsonResponse -StatusCode 500 -Value $result
                }
            } catch {
                 Write-Log "Error in DELETE /documents: $_" -Level "ERROR"
                 Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
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
                 Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }

        # POST /api/search/documents
        Add-PodeRoute -Method Post -Path "/api/search/documents" -ScriptBlock {
             try {
                $data = $WebEvent.Data
                if ($null -eq $data -or [string]::IsNullOrEmpty($data.query)) {
                    Write-PodeJsonResponse -StatusCode 400 -Value @{ success = $false; error = "Bad request: Required parameter missing: query" }; return
                }
                
                $query = $data.query
                $maxResults = if ($null -ne $data.max_results) { $data.max_results } else { 10 }
                $threshold = if ($null -ne $data.threshold) { $data.threshold } else { 0.0 }
                $returnContent = if ($null -ne $data.return_content) { $data.return_content } else { $false }
                $whereFilter = if ($null -ne $data.filter) { $data.filter } else { @{} }
                $result = Search-Documents -ChromaDbPath $using:chromaDbPath -OllamaUrl $using:ollamaUrl -EmbeddingModel $using:embeddingModel -Query $query -MaxResults $maxResults -MinScore $threshold -ReturnSourceContent $returnContent -WhereFilter $whereFilter
                
                if ($result.success) {
                    Write-PodeJsonResponse -Value $result
                } else {
                    Write-PodeJsonResponse -StatusCode 500 -Value $result
                }
            } catch {
                 Write-Log "Error in POST /api/search/documents: $_" -Level "ERROR"
                 Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }
    }

    Write-Log "Vectors API server running at $($endpointParams.Protocol)://$($endpointParams.Address):$($endpointParams.Port)"
    Write-Log "Swagger UI available at $($endpointParams.Protocol)://$($endpointParams.Address):$($endpointParams.Port)/swagger"
    Write-Log "Press Ctrl+C to stop the server."

} catch {
    Add-Content -Path "C:\log.txt" -Value "TEST6"

    Write-Log "Fatal error starting Pode server: $_" -Level "ERROR"
    Write-Log "$($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}