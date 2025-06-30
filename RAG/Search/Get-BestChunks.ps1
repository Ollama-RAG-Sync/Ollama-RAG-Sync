param(
    [Parameter(Mandatory = $true)]
    [string]$Query,

    [Parameter(Mandatory = $true)]
    [string]$CollectionName,
    
    [Parameter(Mandatory = $false)]
    [decimal]$Threshold = 0.6,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxResults = 5,
    
    [Parameter(Mandatory = $false)]
    [bool]$AggregateByDocument = $false,
    
    [Parameter(Mandatory=$false)]
    [int]$VectorsPort = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", "User")
)

<#
.SYNOPSIS
    Finds the best local chunks based on a search query.

.DESCRIPTION
    This script searches for the most relevant local document chunks using semantic similarity.
    It sends a POST request to the local RAG API to find chunks that match the query.
    Can optionally aggregate results by document.

.PARAMETER Query
    The search query to find relevant chunks.

.PARAMETER Threshold
    The similarity threshold for chunks to return (default: 0.6).

.PARAMETER MaxResults
    The maximum number of results to return (default: 5).

.PARAMETER AggregateByDocument
    Whether to group chunks by their source document (default: false).

.PARAMETER VectorsApiUrl
    The URL of the search API endpoint (default: http://localhost:10001/api/search/chunks).

.EXAMPLE
    .\Get-BestChunks.ps1 -Query "neural networks" -MaxResults 10

.EXAMPLE
    .\Get-BestChunks.ps1 -Query "database optimization" -Threshold 0.8 -AggregateByDocument $true

.EXAMPLE
    .\Get-BestChunks.ps1 -Query "machine learning" -AggregateByDocument $false -MaxResults 15
#>

# Check if environment variable is set for Vectors API URL

if ([string]::IsNullOrWhiteSpace($VectorsPort)) {
    Write-Log "VectorsPort is required. Please provide it as a parameter or set the OLLAMA_RAG_VECTORS_API_PORT environment variable." -Level "ERROR"
    exit 1
}
$VectorsApiUrl = "http://localhost:$VectorsPort/api/search/chunks"

# Create the request payload
$requestData = @{
    query = $Query
    threshold = $Threshold
    max_results = $MaxResults
    aggregateByDocument = $AggregateByDocument
    collectionName = $CollectionName
}

# Convert to JSON
$jsonPayload = $requestData | ConvertTo-Json -Depth 10

Write-Host "Searching for chunks with query: '$Query'" -ForegroundColor Green
Write-Host "Using endpoint: $VectorsApiUrl" -ForegroundColor Yellow
Write-Host "Parameters: Threshold=$Threshold, MaxResults=$MaxResults, AggregateByDocument=$AggregateByDocument" -ForegroundColor Cyan

try {
    # Make the HTTP POST request
    $response = Invoke-RestMethod -Uri $VectorsApiUrl -Method Post -Body $jsonPayload -ContentType "application/json" -ErrorAction Stop
    
    if ($response.success) {
        if ($AggregateByDocument) {
            Write-Host "Successfully found chunks from $($response.results.Count) documents" -ForegroundColor Green
            
            # Display aggregated results
            foreach ($docResult in $response.results) {
                Write-Host "`n=== Document: $($docResult.source) ===" -ForegroundColor Magenta
                Write-Host "Found $($docResult.chunks.Count) chunks in this document" -ForegroundColor Yellow
                
                foreach ($chunk in $docResult.chunks) {
                    Write-Host "`n--- Chunk ---" -ForegroundColor Cyan
                    Write-Host "ID: $($chunk.id)" -ForegroundColor White
                    Write-Host "Similarity: $($chunk.similarity)" -ForegroundColor White
                    
                    if ($chunk.metadata -and $chunk.metadata.line_range) {
                        Write-Host "Line Range: $($chunk.metadata.line_range)" -ForegroundColor White
                    }
                    
                    if ($chunk.chunk) {
                        Write-Host "Content Preview:" -ForegroundColor Yellow
                        $preview = if ($chunk.chunk.Length -gt 300) { 
                            $chunk.chunk.Substring(0, 300) + "..." 
                        } else { 
                            $chunk.chunk 
                        }
                        Write-Host $preview -ForegroundColor Gray
                    }
                }
            }
        }
        else {
            Write-Host "Successfully found $($response.results.Count) chunks" -ForegroundColor Green
            
            # Display individual chunk results
            foreach ($result in $response.results) {
                Write-Host "`n--- Chunk Result ---" -ForegroundColor Magenta
                Write-Host "ID: $($result.id)" -ForegroundColor White
                Write-Host "Source: $($result.source)" -ForegroundColor White
                Write-Host "Similarity: $($result.similarity)" -ForegroundColor White
                
                if ($result.metadata -and $result.metadata.line_range) {
                    Write-Host "Line Range: $($result.metadata.line_range)" -ForegroundColor White
                }
                
                if ($result.chunk) {
                    Write-Host "Content Preview:" -ForegroundColor Yellow
                    $preview = if ($result.chunk.Length -gt 300) { 
                        $result.chunk.Substring(0, 300) + "..." 
                    } else { 
                        $result.chunk 
                    }
                    Write-Host $preview -ForegroundColor Gray
                }
            }
        }
        
        # Return the response object for further processing
        return $response
    }
    else {
        Write-Error "Search request failed: Response indicated failure"
        return $null
    }
}
catch {
    Write-Error "Failed to search chunks: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.Exception.StackTrace)"
    return $null
}
