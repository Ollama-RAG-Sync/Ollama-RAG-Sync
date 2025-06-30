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
    [bool]$ReturnContent = $true,
    
    [Parameter(Mandatory=$false)]
    [int]$VectorsPort = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", "User")
)
<#
.SYNOPSIS
    Finds the best local documents based on a search query.

.DESCRIPTION
    This script searches for the most relevant local documents using semantic similarity.
    It sends a POST request to the local RAG API to find documents that match the query.

.PARAMETER Query
    The search query to find relevant documents.

.PARAMETER Threshold
    The similarity threshold for documents to return (default: 0.6).

.PARAMETER MaxResults
    The maximum number of results to return (default: 5).

.PARAMETER ReturnContent
    Whether to return the full document content (default: true).

.PARAMETER VectorsApiUrl
    The URL of the search API endpoint (default: http://localhost:10001/api/search/documents).

.EXAMPLE
    .\Get-BestDocuments.ps1 -Query "machine learning algorithms" -MaxResults 10

.EXAMPLE
    .\Get-BestDocuments.ps1 -Query "database design" -Threshold 0.8 -ReturnContent $false
#>

if ([string]::IsNullOrWhiteSpace($VectorsPort)) {
    Write-Log "VectorsPort is required. Please provide it as a parameter or set the OLLAMA_RAG_VECTORS_API_PORT environment variable." -Level "ERROR"
    exit 1
}
$VectorsApiUrl = "http://localhost:$VectorsPort/api/search/documents"

# Create the request payload
$requestData = @{
    query = $Query
    threshold = $Threshold
    max_results = $MaxResults
    return_content = $ReturnContent
    collectionName = $CollectionName
}

# Convert to JSON
$jsonPayload = $requestData | ConvertTo-Json -Depth 10

Write-Host "Searching for documents with query: '$Query'" -ForegroundColor Green
Write-Host "Using endpoint: $VectorsApiUrl" -ForegroundColor Yellow
Write-Host "Parameters: Threshold=$Threshold, MaxResults=$MaxResults, ReturnContent=$ReturnContent" -ForegroundColor Cyan

try {
    # Make the HTTP POST request
    $response = Invoke-RestMethod -Uri $VectorsApiUrl -Method Post -Body $jsonPayload -ContentType "application/json" -ErrorAction Stop
    
    if ($response.success) {
        Write-Host "Successfully found $($response.results.Count) documents" -ForegroundColor Green
        
        # Display results
        foreach ($result in $response.results) {
            Write-Host "`n--- Document Result ---" -ForegroundColor Magenta
            Write-Host "ID: $($result.id)" -ForegroundColor White
            Write-Host "Source: $($result.source)" -ForegroundColor White
            Write-Host "Similarity: $($result.similarity)" -ForegroundColor White
            
            if ($ReturnContent -and $result.document) {
                Write-Host "Content Preview:" -ForegroundColor Yellow
                $preview = if ($result.document.Length -gt 500) { 
                    $result.document.Substring(0, 500) + "..." 
                } else { 
                    $result.document 
                }
                Write-Host $preview -ForegroundColor Gray
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
    Write-Error "Failed to search documents: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.Exception.StackTrace)"
    return $null
}
