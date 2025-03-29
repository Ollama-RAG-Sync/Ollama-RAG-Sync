# Get-ChunksByQuery.ps1
# Query the vector database for similar document chunks

param(
    [Parameter(Mandatory=$true)]
    [string]$QueryText,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxResults = 10,
    
    [Parameter(Mandatory=$false)]
    [double]$MinScore = 0.0,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$WhereFilter = @{},
    
    [Parameter(Mandatory=$false)]
    [switch]$AggregateByDocument,
    
    [Parameter(Mandatory=$false)]
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel
)

# Import required modules
$scriptsPath = $PSScriptRoot
$modulesPath = Join-Path -Path $scriptsPath -ChildPath "..\Modules"

# Import modules
Import-Module "$modulesPath\Vectors-Core.psm1" -Force
Import-Module "$modulesPath\Vectors-Database.psm1" -Force
Import-Module "$modulesPath\Vectors-Embeddings.psm1" -Force

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

Initialize-VectorsConfig -ConfigOverrides $configOverrides

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

if ($AggregateByDocument) {
    $parameters.AggregateByDocument = $true
}

$results = Query-VectorChunks @parameters

# Return the results
$results
