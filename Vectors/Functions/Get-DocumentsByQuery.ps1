# Get-DocumentsByQuery.ps1
# Query the vector database for similar documents

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
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel,
    
    [Parameter(Mandatory=$false)]
    [switch]$ReturnSourceContent
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

$results = Query-VectorDocuments @parameters

# If requested, load source content for each result
if ($ReturnSourceContent -and $results) {
    foreach ($result in $results) {
        if ($result.metadata -and $result.metadata.source) {
            $sourcePath = $result.metadata.source
            # Check if source is a file or content ID
            if ($sourcePath -match '^content://') {
                $result | Add-Member -MemberType NoteProperty -Name "source_content" -Value "Content not available for content:// sources"
            } else {
                # Only try to load content if file exists
                if (Test-Path -Path $sourcePath) {
                    try {
                        $content = Get-Content -Path $sourcePath -Raw -ErrorAction SilentlyContinue
                        $result | Add-Member -MemberType NoteProperty -Name "source_content" -Value $content
                    } catch {
                        $result | Add-Member -MemberType NoteProperty -Name "source_content" -Value "Error loading source content: $($_.Exception.Message)"
                    }
                } else {
                    $result | Add-Member -MemberType NoteProperty -Name "source_content" -Value "Source file not found"
                }
            }
        }
    }
}

# Return the results
$results
