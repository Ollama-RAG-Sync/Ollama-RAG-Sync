param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 0,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 0,
    
    [Parameter(Mandatory=$true)]
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OllamaUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel
)

try
{
    # Import required modules
    $scriptsPath = $PSScriptRoot

    Write-Host $scriptPath

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

    if ($ChromaDbPath) {
        $configOverrides.ChromaDbPath = $ChromaDbPath
    }

    Write-Host "4)ChromaDbPath: $ChromaDbPath"
    Write-Host "3)OllamaUrl: $OllamaUrl"      
    Write-Host "2)EmbeddingModel: $EmbeddingModel"
    Write-Host "1)ChunkSize: $ChunkSize"
    Write-Host "$configOverrides"

    Initialize-VectorsConfig -ConfigOverrides $configOverrides

    # Verify requirements
    if (-not (Test-VectorsRequirements)) {
        Write-VectorsLog -Message "Not all requirements are met. Please install missing dependencies." -Level "Error"
        return
    }
    Initialize-VectorDatabase

    # Add document to vector store
    $parameters = @{
        FilePath = $FilePath
    }

    if ($ChunkSize -gt 0) {
        $parameters.ChunkSize = $ChunkSize
    }

    if ($ChunkOverlap -gt 0) {
        $parameters.ChunkOverlap = $ChunkOverlap
    }
    Write-VectorsLog -Message $parameters
    $result = Add-DocumentToVectorStore @parameters

    if ($result) {
        Write-VectorsLog -Message "Document added successfully to vector store: $FilePath" -Level "Info"
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