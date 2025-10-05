# Remove-DocumentFromVectors.ps1
# Remove a document and its chunks from the vector database

param(
    [Parameter(Mandatory=$true, ParameterSetName="ByPath")]
    [string]$FilePath,
    
    [Parameter(Mandatory=$true, ParameterSetName="ById")]
    [string]$DocumentId,
    
    [Parameter(Mandatory=$false)]
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel,
    
    [Parameter(Mandatory=$false)]
    [string]$CollectionName = "default"
)

# Import required modules
$scriptsPath = $PSScriptRoot
$modulesPath = Join-Path -Path $scriptsPath -ChildPath "..\Modules"

# Import modules
Import-Module "$modulesPath\Vectors-Core.psm1" -Force
Import-Module "$modulesPath\Vectors-Database.psm1" -Force

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

# Remove document from vector store
$parameters = @{
    CollectionName = $CollectionName + "_" + $EmbeddingModel
}

if ($PSCmdlet.ParameterSetName -eq "ByPath") {
    Write-VectorsLog -Message "Removing document by path: $FilePath (Collection: $CollectionName)" -Level "Info"
    $parameters.FilePath = $FilePath
} else {
    Write-VectorsLog -Message "Removing document by ID: $DocumentId (Collection: $CollectionName)" -Level "Info"
    $parameters.DocumentId = $DocumentId
}

$result = Remove-VectorDocument @parameters

if ($result) {
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        Write-VectorsLog -Message "Document successfully removed from vector store: $FilePath" -Level "Info"
    } else {
        Write-VectorsLog -Message "Document successfully removed from vector store: $DocumentId" -Level "Info"
    }
} else {
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        Write-VectorsLog -Message "Failed to remove document from vector store: $FilePath" -Level "Error"
    } else {
        Write-VectorsLog -Message "Failed to remove document from vector store: $DocumentId" -Level "Error"
    }
}

return $result
