# Start-VectorsAPI.ps1
# REST API server for Vectors subsystem
# Provides endpoints for adding and removing documents from the vector database

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility

param (
    [Parameter(Mandatory=$false)]
    [string]$ListenAddress = "localhost",
    
    [Parameter(Mandatory=$true)]
    [int]$Port,
    
    [Parameter(Mandatory=$false)]
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [int]$DefaultChunkSize = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$DefaultChunkOverlap = 200,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseHttps,

    [Parameter(Mandatory=$true)]
    [string]$InstallPath
)

# Determine script path and import modules
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

$ChromaDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db"
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
        Write-Host $logMessage -ForegroundColor Green
    }
    
    # Write to log file
    Add-Content -Path $logFilePath -Value $logMessage
}

function Close-ProcessOnPort {
    $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue

    if ($connection) {
        # Get the process ID (PID) of the process using the port
        $processId = $connection.OwningProcess
    
        # Get process details to identify what is being killed
        $process = Get-Process -Id $processId
    
        # Inform the user which process is being terminated
        Write-Log "Killing process '$($process.ProcessName)' with PID $processId listening on port $Port." -Level "WARNING"
    
        # Attempt to forcefully terminate the process
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            Write-Log "Process killed successfully."
        } catch {
            Write-Log "Failed to kill process: $_" -Level "ERROR"
        }
    }
}

# Function to add a document to the vector database
function Add-Document {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$false)]
        [int]$FileId = 0,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkSize = $DefaultChunkSize,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkOverlap = $DefaultChunkOverlap,
        
        [Parameter(Mandatory=$false)]
        [string]$ContentType = "Text"
    )
    
    try {
        Write-Log "Adding document to vectors: $FilePath (ID: $FileId)"
        
        # Set parameters for Add-DocumentToVectors.ps1
        $params = @{
            FilePath = $FilePath
        }
        
        # Add optional parameters if provided
        if ($ChunkSize -gt 0) {
            $params.ChunkSize = $ChunkSize
        }
        
        if ($ChunkOverlap -gt 0) {
            $params.ChunkOverlap = $ChunkOverlap
        }
        
        if (-not [string]::IsNullOrEmpty($ChromaDbPath)) {
            $params.ChromaDbPath = $ChromaDbPath
        }
        
        if (-not [string]::IsNullOrEmpty($OllamaUrl)) {
            $params.OllamaUrl = $OllamaUrl
        }
        
        if (-not [string]::IsNullOrEmpty($EmbeddingModel)) {
            $params.EmbeddingModel = $EmbeddingModel
        }
        
        # Call Add-DocumentToVectors.ps1
        $addDocumentScript = Join-Path -Path $functionsPath -ChildPath "Add-DocumentToVectors.ps1"
        $result = & $addDocumentScript @params
        
        if ($result) {
            Write-Log "Successfully added document to vectors: $FilePath"
            return @{
                success = $true
                message = "Document added successfully"
                filePath = $FilePath
                fileId = $FileId
            }
        } else {
            Write-Log "Failed to add document to vectors: $FilePath" -Level "ERROR"
            return @{
                success = $false
                error = "Failed to add document to vectors"
                filePath = $FilePath
                fileId = $FileId
            }
        }
    }
    catch {
        Write-Log "Error adding document to vectors: $_ ${$_.ScriptStackTrace}" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
            filePath = $FilePath
            fileId = $FileId
        }
    }
}

# Function to remove a document from the vector database
function Remove-Document {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false)]
        [int]$FileId = 0
    )
    
    try {
        Write-Log "Removing document from vectors: $FilePath (ID: $FileId)"
        
        # Set parameters for Remove-DocumentFromVectors.ps1
        $params = @{
            FilePath = $FilePath
        }
        
        if (-not [string]::IsNullOrEmpty($ChromaDbPath)) {
            $params.ChromaDbPath = $ChromaDbPath
        }
        
        if (-not [string]::IsNullOrEmpty($OllamaUrl)) {
            $params.OllamaUrl = $OllamaUrl
        }
        
        if (-not [string]::IsNullOrEmpty($EmbeddingModel)) {
            $params.EmbeddingModel = $EmbeddingModel
        }
        
        # Call Remove-DocumentFromVectors.ps1
        $removeDocumentScript = Join-Path -Path $functionsPath -ChildPath "Remove-DocumentFromVectors.ps1"
        $result = & $removeDocumentScript @params
        
        if ($result) {
            Write-Log "Successfully removed document from vectors: $FilePath"
            return @{
                success = $true
                message = "Document removed successfully"
                filePath = $FilePath
                fileId = $FileId
            }
        } else {
            Write-Log "Failed to remove document from vectors: $FilePath" -Level "ERROR"
            return @{
                success = $false
                error = "Failed to remove document from vectors"
                filePath = $FilePath
                fileId = $FileId
            }
        }
    }
    catch {
        Write-Log "Error removing document from vectors: $_" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
            filePath = $FilePath
            fileId = $FileId
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
        }
        
        if ($WhereFilter.Count -gt 0) {
            $params.WhereFilter = $WhereFilter
        }
        
        if (-not [string]::IsNullOrEmpty($ChromaDbPath)) {
            $params.ChromaDbPath = $ChromaDbPath
        }
        
        if (-not [string]::IsNullOrEmpty($OllamaUrl)) {
            $params.OllamaUrl = $OllamaUrl
        }
        
        if (-not [string]::IsNullOrEmpty($EmbeddingModel)) {
            $params.EmbeddingModel = $EmbeddingModel
        }
        
        # Call Get-ChunksByQuery.ps1
        $searchScript = Join-Path -Path $functionsPath -ChildPath "Get-ChunksByQuery.ps1"
        $results = & $searchScript @params
        
        # Check if any results were found
        if ($results -and $results.Count -gt 0) {
            Write-Log "Found $($results.Count) matching chunks for query: $Query"
            return @{
                success = $true
                results = $results
                count = $results.Count
                query = $Query
            }
        } else {
            Write-Log "No matching chunks found for query: $Query" -Level "INFO"
            return @{
                success = $true
                results = @()
                count = 0
                query = $Query
            }
        }
    }
    catch {
        Write-Log "Error searching chunks: $_" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
            results = @()
            count = 0
            query = $Query
        }
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
        }
        
        if ($WhereFilter.Count -gt 0) {
            $params.WhereFilter = $WhereFilter
        }
        
        if (-not [string]::IsNullOrEmpty($ChromaDbPath)) {
            $params.ChromaDbPath = $ChromaDbPath
        }
        
        if (-not [string]::IsNullOrEmpty($OllamaUrl)) {
            $params.OllamaUrl = $OllamaUrl
        }
        
        if (-not [string]::IsNullOrEmpty($EmbeddingModel)) {
            $params.EmbeddingModel = $EmbeddingModel
        }
        
        # Call Get-DocumentsByQuery.ps1
        $searchScript = Join-Path -Path $functionsPath -ChildPath "Get-DocumentsByQuery.ps1"
        $results = & $searchScript @params
        
        # Check if any results were found
        if ($results -and $results.Count -gt 0) {
            Write-Log "Found $($results.Count) matching documents for query: $Query"
            return @{
                success = $true
                results = $results
                count = $results.Count
                query = $Query
            }
        } else {
            Write-Log "No matching documents found for query: $Query" -Level "INFO"
            return @{
                success = $true
                results = @()
                count = 0
                query = $Query
            }
        }
    }
    catch {
        Write-Log "Error searching documents: $_" -Level "ERROR"
        return @{
            success = $false
            error = $_.ToString()
            results = @()
            count = 0
            query = $Query
        }
    }
}

# Set up HTTP listener
$listener = New-Object System.Net.HttpListener
if ($UseHttps) {
    $prefix = "https://$($ListenAddress):$Port/"
    
    # Note: HTTPS requires a valid certificate to be bound to the port
    Write-Log "HTTPS requires a certificate to be bound to port $Port" -Level "WARNING"
    Write-Log "You may need to run: netsh http add sslcert ipport=0.0.0.0:$Port certhash=THUMBPRINT appid={GUID}" -Level "INFO"
}
else {
    $prefix = "http://$($ListenAddress):$Port/"
}
$listener.Prefixes.Add($prefix)

try {
    # Start the listener
    $listener.Start()
    
    Write-Log "Vectors API server started at $prefix" -Level "INFO"
    Write-Log "ChromaDB Path: $ChromaDbPath" -Level "INFO"
    Write-Log "Ollama URL: $OllamaUrl" -Level "INFO"
    Write-Log "Embedding model: $EmbeddingModel" -Level "INFO"
    Write-Log "Default chunk size: $DefaultChunkSize" -Level "INFO"
    Write-Log "Default chunk overlap: $DefaultChunkOverlap" -Level "INFO"
    Write-Log "Press Ctrl+C to stop the server" -Level "INFO"
    
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
            
            Write-Log "Received $method request for $route" -Level "INFO"
            
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
                            message = "Vectors API server running"
                            routes = @(
                                "/documents - POST: Add a document to vectors",
                                "/documents/{filePath} - DELETE: Remove a document from vectors",
                                "/api/search/chunks - POST: Search for relevant chunks",
                                "/api/search/documents - POST: Search for relevant documents",
                                "/status - GET: Get server status"
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
                
                # --- Status endpoint ---
                "/status" {
                    if ($method -eq "GET") {
                        $responseBody = @{
                            status = "ok"
                            chromaDbPath = $ChromaDbPath
                            ollamaUrl = $OllamaUrl
                            embeddingModel = $EmbeddingModel
                            defaultChunkSize = $DefaultChunkSize
                            defaultChunkOverlap = $DefaultChunkOverlap
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
                
                # --- Documents endpoint ---
                "/documents" {
                    if ($method -eq "POST") {
                        # Validate required parameters
                        if ($null -eq $requestBody -or [string]::IsNullOrEmpty($requestBody.filePath)) {
                            $statusCode = 400
                            $responseBody = @{
                                error = "Bad request"
                                message = "Required parameter missing: filePath"
                            }
                        }
                        else {
                            # Extract parameters
                            $filePath = $requestBody.filePath
                            $fileId = if ($null -ne $requestBody.fileId) { $requestBody.fileId } else { 0 }
                            $chunkSize = if ($null -ne $requestBody.chunkSize) { $requestBody.chunkSize } else { $DefaultChunkSize }
                            $chunkOverlap = if ($null -ne $requestBody.chunkOverlap) { $requestBody.chunkOverlap } else { $DefaultChunkOverlap }
                            $contentType = if ($null -ne $requestBody.contentType) { $requestBody.contentType } else { "Text" }
                            
                            # Add document to vectors
                            $result = Add-Document -FilePath $filePath -FileId $fileId -ChunkSize $chunkSize -ChunkOverlap $chunkOverlap -ContentType $contentType
                            
                            if ($result.success) {
                                $responseBody = $result
                            }
                            else {
                                $statusCode = 500
                                $responseBody = $result
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
                
                # --- Search Chunks endpoint ---
                "/api/search/chunks" {
                    if ($method -eq "POST") {
                        # Validate required parameters
                        if ($null -eq $requestBody -or [string]::IsNullOrEmpty($requestBody.query)) {
                            $statusCode = 400
                            $responseBody = @{
                                error = "Bad request"
                                message = "Required parameter missing: query"
                            }
                        }
                        else {
                            # Extract parameters
                            $query = $requestBody.query
                            $maxResults = if ($null -ne $requestBody.max_results) { $requestBody.max_results } else { 10 }
                            $threshold = if ($null -ne $requestBody.threshold) { $requestBody.threshold } else { 0.0 }
                            
                            # Prepare filter if needed
                            $whereFilter = @{}
                            if ($null -ne $requestBody.filter) {
                                $whereFilter = $requestBody.filter
                            }
                            
                            # Search chunks
                            $result = Search-Chunks -Query $query -MaxResults $maxResults -MinScore $threshold -WhereFilter $whereFilter
                            
                            if ($result.success) {
                                $responseBody = $result
                            }
                            else {
                                $statusCode = 500
                                $responseBody = $result
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
                
                # --- Search Documents endpoint ---
                "/api/search/documents" {
                    if ($method -eq "POST") {
                        # Validate required parameters
                        if ($null -eq $requestBody -or [string]::IsNullOrEmpty($requestBody.query)) {
                            $statusCode = 400
                            $responseBody = @{
                                error = "Bad request"
                                message = "Required parameter missing: query"
                            }
                        }
                        else {
                            # Extract parameters
                            $query = $requestBody.query
                            $maxResults = if ($null -ne $requestBody.max_results) { $requestBody.max_results } else { 10 }
                            $threshold = if ($null -ne $requestBody.threshold) { $requestBody.threshold } else { 0.0 }
                            $returnContent = if ($null -ne $requestBody.return_content) { $requestBody.return_content } else { $false }
                            
                            # Prepare filter if needed
                            $whereFilter = @{}
                            if ($null -ne $requestBody.filter) {
                                $whereFilter = $requestBody.filter
                            }
                            
                            # Search documents
                            $result = Search-Documents -Query $query -MaxResults $maxResults -MinScore $threshold -ReturnSourceContent $returnContent -WhereFilter $whereFilter
                            
                            if ($result.success) {
                                $responseBody = $result
                            }
                            else {
                                $statusCode = 500
                                $responseBody = $result
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
                
                # --- Remove document endpoint ---
                default {
                    if ($route -match "^/documents/(.+)$" -and $method -eq "DELETE") {
                        $encodedFilePath = $matches[1]
                        $filePath = [System.Web.HttpUtility]::UrlDecode($encodedFilePath)
                        $fileId = if ($null -ne $request.QueryString["fileId"]) { [int]$request.QueryString["fileId"] } else { 0 }
                        
                        # Remove document from vectors
                        $result = Remove-Document -FilePath $filePath -FileId $fileId
                        
                        if ($result.success) {
                            $responseBody = $result
                        }
                        else {
                            $statusCode = 500
                            $responseBody = $result
                        }
                    }
                    else {
                        $statusCode = 404
                        $responseBody = @{
                            error = "Route not found"
                            message = "The requested resource does not exist: $route"
                        }
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
            Write-Log "Error handling request: $_" -Level "ERROR"
            
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
    Write-Log "Fatal error in Vectors API server: $_" -Level "ERROR"
}
finally {
    $context.Response.Close()
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