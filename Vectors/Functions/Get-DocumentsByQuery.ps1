# Get-DocumentsByQuery.ps1
# Query the vector database for similar documents

param(
    [Parameter(Mandatory=$true)]
    [string]$QueryText,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxResults = 10,
    
    [Parameter(Mandatory=$false)]
    [double]$MinScore = 0.5,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$WhereFilter = @{},
    
    [Parameter(Mandatory=$false)]
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel,
    
    [Parameter(Mandatory=$false)]
    [switch]$ReturnSourceContent
)

# Initialize configuration with overrides
$configOverrides = @{}

if ($ChromaDbPath) {
    $configOverrides.ChromaDbPath = $ChromaDbPath
}

if ($OllamaUrl) {
    $configOverrides.OllamaUrl = $OllamaUrl
}

if ($EmbeddingModel) {
    $configOverrides.EmbeddingModel = $EmbeddingModel
}

$null = Initialize-VectorsConfig -ConfigOverrides $configOverrides

# Verify requirements
if (-not (Test-VectorsRequirements)) {
    Write-VectorsLog -Message "Not all requirements are met. Please install missing dependencies." -Level "Error"
    return
}

# Query the vector store
$parameters = @{
    QueryText = $QueryText
    MaxResults = $MaxResults
    MinScore = $MinScore
}

if ($WhereFilter.Count -gt 0) {
    $parameters.WhereFilter = $WhereFilter
}

$results = Query-VectorDocuments @parameters
# Return the results
$results
