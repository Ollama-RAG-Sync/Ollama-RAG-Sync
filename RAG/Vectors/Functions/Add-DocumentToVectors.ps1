
param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [Parameter(Mandatory=$true)]
    [string]$OriginalFilePath,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 0,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 0,
    
    [Parameter(Mandatory=$true)]
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OllamaUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel,
    
    [Parameter(Mandatory=$false)]
    [string]$CollectionName = "default"
)

try
{
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

    if ($ChromaDbPath) {
        $configOverrides.ChromaDbPath = $ChromaDbPath
    }

    $null = Initialize-VectorsConfig -ConfigOverrides $configOverrides

    # Verify requirements
    if (-not (Test-VectorsRequirements)) {
        Write-VectorsLog -Message "Not all requirements are met. Please install missing dependencies." -Level "Error"
        return
    }
    

    # Add document to vector store
    $parameters = @{
        FilePath = $FilePath
        CollectionName = $CollectionName
    }

    if ($ChunkSize -gt 0) {
        $parameters.ChunkSize = $ChunkSize
    }

    if ($ChunkOverlap -gt 0) {
        $parameters.ChunkOverlap = $ChunkOverlap
    }
    $result = Add-DocumentToVectorStore @parameters

    if ($result) {
        Write-VectorsLog -Message "Document added successfully to vector store: $FilePath" -Level "Info"
        Write-VectorsLog -Message "Based on: $OriginalFilePath" -Level "Info"
    } else {
        Write-VectorsLog -Message "Failed to add document to vector store: $FilePath" -Level "Error"
    }   

    return $result
}
catch 
{
    Write-VectorsLog "Error adding document to vectors:$_, $($_.ScriptStackTrace)" -Level "ERROR" # Removed ScriptStackTrace for brevity
    return $false
}