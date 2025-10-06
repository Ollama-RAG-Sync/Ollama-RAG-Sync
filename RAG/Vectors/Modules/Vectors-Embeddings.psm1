# Vectors-Embeddings.psm1
# Embedding generation for the Vectors subsystem

# Import the core module
if (-not (Get-Module -Name "Vectors-Core")) {
    Import-Module ".\Vectors-Core.psm1" -Force
}

<#
.SYNOPSIS
    Generates an embedding for a document
.DESCRIPTION
    Creates a vector embedding for an entire document using Ollama
.PARAMETER FilePath
    Path to the document file
.PARAMETER Content
    Document content (alternative to FilePath)
.EXAMPLE
    Get-DocumentEmbedding -FilePath "path/to/document.md"
#>
function Get-DocumentEmbedding {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ParameterSetName="ByPath")]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false, ParameterSetName="ByContent")]
        [string]$Content
    )
    
    $config = Get-VectorsConfig
    
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        # Get file content
        $Content = Get-FileContent -FilePath $FilePath
        if ($null -eq $Content) {
            return $null
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($Content)) {
        Write-VectorsLog -Message "Document content is empty" -Level "Error"
        return $null
    }
    
    # Use Python script to generate embedding
    $scriptDir = Split-Path -Parent $PSScriptRoot
    $pythonScriptPath = Join-Path $scriptDir "python_scripts\generate_document_embedding.py"
    
    if (-not (Test-Path -Path $pythonScriptPath)) {
        Write-VectorsLog -Message "Python script not found: $pythonScriptPath" -Level "Error"
        return $null
    }

    $contentScript = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $contentScript -Value $Content -Encoding utf8

    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        Write-VectorsLog -Message "Generating embedding for document: $FilePath" -Level "Info"
    } else {
        Write-VectorsLog -Message "Generating embedding for document content" -Level "Info"
    }
    
    # Execute the Python script
    try {
        $results = python $pythonScriptPath $contentScript --model $($config.EmbeddingModel) --base-url $($config.OllamaUrl) --log-path $Env:vectorLogFilePath 2>&1
        
        # Process the output
        $embedding = $null
        foreach ($line in $results) {
            if ($line -match "^SUCCESS:(.*)$") {
                $successData = $Matches[1]
                try {
                    $embedding = $successData | ConvertFrom-Json
                    Write-VectorsLog -Message "Successfully generated embedding vector" -Level "Info"
                } catch {
                    Write-VectorsLog -Message "Generated embedding but couldn't parse JSON" -Level "Error"
                }
            }
            elseif ($line -match "^ERROR:(.*)$") {
                $errorData = $Matches[1]
                Write-VectorsLog -Message "Error generating embedding: $errorData" -Level "Error"
            }
        }
        
        # Clean up
        Remove-Item -Path $contentScript -Force -ErrorAction SilentlyContinue
        
        return $embedding
    }
    catch {
        Write-VectorsLog -Message "Failed to generate embedding: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $contentScript) {
            Remove-Item -Path $contentScript -Force
        }
        
        return $null
    }
}

<#
.SYNOPSIS
    Chunks document content and generates embeddings for each chunk
.DESCRIPTION
    Divides document content into chunks and creates vector embeddings for each chunk
.PARAMETER FilePath
    Path to the document file
.PARAMETER Content
    Document content (alternative to FilePath)
.PARAMETER ChunkSize
    Number of lines per chunk
.PARAMETER ChunkOverlap
    Number of lines to overlap between chunks
.EXAMPLE
    Get-ChunkEmbeddings -FilePath "path/to/document.md" -ChunkSize 20 -ChunkOverlap 2
#>
function Get-ChunkEmbeddings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ParameterSetName="ByPath")]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false, ParameterSetName="ByContent")]
        [string]$Content,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkSize = 0,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkOverlap = 0
    )
    
    $config = Get-VectorsConfig
    
    # Use config values if not specified
    if ($ChunkSize -le 0) {
        $ChunkSize = $config.ChunkSize
    }
    
    if ($ChunkOverlap -le 0) {
        $ChunkOverlap = $config.ChunkOverlap
    }
    
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        # Get file content
        $Content = Get-FileContent -FilePath $FilePath
        if ($null -eq $Content) {
            return $null
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($Content)) {
        Write-VectorsLog -Message "Document content is empty" -Level "Error"
        return $null
    }
    
    $contentScript = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $contentScript -Value $Content -Encoding utf8
    $lines = (Get-Content -Path $contentScript).Count

    $estimation = $lines / $ChunkSize
    Write-VectorsLog -Message "Lines per chunk: $ChunkSize, Line overlap: $ChunkOverlap" -Level "Debug"
    Write-VectorsLog -Message "Estimated number of chunks: $estimation" -Level "Debug"

    $maxChunks = 300
    if ($estimation -gt $maxChunks) {
        $ChunkSize = [System.Math]::Ceiling($lines / $maxChunks)
        Write-VectorsLog -Message "Warning: Estimated number of chunks $estimation exceeds $maxChunks. Changing chunk size to $ChunkSize" -Level "Warning"
    }    # Use Python script to chunk and generate embeddings
    $scriptDir = Split-Path -Parent $PSScriptRoot
    $pythonScriptPath = Join-Path $scriptDir "python_scripts\generate_chunk_embeddings.py"
    
    if (-not (Test-Path -Path $pythonScriptPath)) {
        Write-VectorsLog -Message "Python script not found: $pythonScriptPath" -Level "Error"
        return $null
    }
    
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        Write-VectorsLog -Message "Generating chunk embeddings for document: $FilePath" -Level "Info"
    } else {
        Write-VectorsLog -Message "Generating chunk embeddings for document content" -Level "Info"
    }
    
    # Execute the Python script
    try {
        $results = python $pythonScriptPath $contentScript --chunk-size $ChunkSize --chunk-overlap $ChunkOverlap --model $($config.EmbeddingModel) --base-url $($config.OllamaUrl) --log-path $Env:vectorLogFilePath 2>&1
        
        # Process the output
        $chunkEmbeddings = $null
        foreach ($line in $results) {
            if ($line -match "^SUCCESS:(.*)$") {
                $successData = $Matches[1]
                try {
                    $chunkEmbeddings = $successData | ConvertFrom-Json
                    Write-VectorsLog -Message "Successfully generated embeddings for $($chunkEmbeddings.Count) chunks" -Level "Info"
                } catch {
                    Write-VectorsLog -Message "Generated embeddings but couldn't parse JSON" -Level "Error"
                }
            }
            elseif ($line -match "^ERROR:(.*)$") {
                $errorData = $Matches[1]
                Write-VectorsLog -Message "Error generating chunk embeddings: $errorData" -Level "Error"
            }
            elseif ($line -match "^INFO:(.*)$") {
                $infoData = $Matches[1]
                Write-VectorsLog -Message $infoData -Level "Debug"
            }
        }
        
        # Clean up
        Remove-Item -Path $contentScript -Force -ErrorAction SilentlyContinue

        return $chunkEmbeddings
    }
    catch {
        Write-VectorsLog -Message "Failed to generate chunk embeddings: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $contentScript) {
            Remove-Item -Path $contentScript -Force
        }
        
        return $null
    }
}

<#
.SYNOPSIS
    Stores document and chunk embeddings in the vector database
.DESCRIPTION
    Generates embeddings for a document and its chunks and stores them in ChromaDB
.PARAMETER FilePath
    Path to the document file
.PARAMETER Content
    Document content (alternative to FilePath)
.PARAMETER ChunkSize
    Number of lines per chunk
.PARAMETER ChunkOverlap
    Number of lines to overlap between chunks
.EXAMPLE
    Add-DocumentToVectorStore -FilePath "path/to/document.md"
#>
function Add-DocumentToVectorStore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ParameterSetName="ByPath")]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false, ParameterSetName="ByContent")]
        [string]$Content,
        
        [Parameter(Mandatory=$false, ParameterSetName="ByContent")]
        [string]$ContentId,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkSize = 20,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkOverlap = 2,
        
        [Parameter(Mandatory=$false)]
        [string]$CollectionName = "default"
    )
    
    $config = Get-VectorsConfig
    
    Write-Host $config

    # Use config values if not specified
    if ($ChunkSize -le 0) {
        $ChunkSize = $config.ChunkSize
    }
    
    if ($ChunkOverlap -le 0) {
        $ChunkOverlap = $config.ChunkOverlap
    }
    
    # Read content from file if using path
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {        
        $documentContent = Get-FileContent -FilePath $FilePath
        if ($null -eq $documentContent) {
            return $false
        }
        $sourcePath = $FilePath
        $filePathHash = [System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($FilePath))
        $hashString = [System.BitConverter]::ToString($filePathHash).Replace("-", "").Substring(0, 8)
        $documentId = [System.IO.Path]::GetFileName($FilePath) + "_" + $hashString
    }
    else {
        # Content provided directly
        if ([string]::IsNullOrWhiteSpace($Content)) {
            Write-VectorsLog -Message "Document content is empty" -Level "Error"
            return $false
        }
        
        $documentContent = $Content
        
        if ([string]::IsNullOrWhiteSpace($ContentId)) {
            # Generate a unique ID if not provided
            $ContentId = "doc_" + [Guid]::NewGuid().ToString("N")
        }
        
        $sourcePath = "content://$ContentId"
        $documentId = $ContentId
    }
    
    # Get document embedding
    Write-VectorsLog -Message "Generating document embedding..." -Level "Info"
    $docEmbedding = Get-DocumentEmbedding -Content $documentContent
    if ($null -eq $docEmbedding) {
        Write-VectorsLog -Message "Failed to generate document embedding" -Level "Error"
        return $false
    }
    
    # Get chunk embeddings
    Write-VectorsLog -Message "Generating chunk embeddings..." -Level "Info"
    $chunkEmbeddings = Get-ChunkEmbeddings -Content $documentContent -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap
    if ($null -eq $chunkEmbeddings) {
        Write-VectorsLog -Message "Failed to generate chunk embeddings" -Level "Error"
        return $false
    }
    
    # Save embeddings to ChromaDB
    Write-VectorsLog -Message "Storing embeddings in ChromaDB..." -Level "Info"
    
    # Get path to Python script
    $scriptDir = Split-Path -Parent $PSScriptRoot
    $pythonScriptPath = Join-Path $scriptDir "python_scripts\store_embeddings.py"
    
    if (-not (Test-Path -Path $pythonScriptPath)) {
        Write-VectorsLog -Message "Python script not found: $pythonScriptPath" -Level "Error"
        return $false
    }
    
    # Convert embeddings to JSON
    $docEmbeddingJson = $docEmbedding | ConvertTo-Json -Compress
    $chunkEmbeddingsJson = $chunkEmbeddings | ConvertTo-Json -Compress -Depth 10

    $docEmbeddingJsonFile = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $docEmbeddingJsonFile -Value $docEmbeddingJson -Encoding utf8
      
    $chunkEmbeddingsJsonFile = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $chunkEmbeddingsJsonFile -Value $chunkEmbeddingsJson -Encoding utf8
    
    # Execute the Python script
    try {
        $results = python $pythonScriptPath $docEmbeddingJsonFile $chunkEmbeddingsJsonFile $sourcePath $documentId $($config.ChromaDbPath) --collection-name $CollectionName --log-path $Env:vectorLogFilePath 2>&1

        
        # Process the output
        $success = $false
        foreach ($line in $results) {
            if ($line -match "^SUCCESS:(.*)$") {
                $successData = $Matches[1]
                Write-VectorsLog -Message $successData -Level "Info"
                $success = $true
            }
            elseif ($line -match "^ERROR:(.*)$") {
                $errorData = $Matches[1]
                Write-VectorsLog -Message "Error storing embeddings: $errorData" -Level "Error"
            }
            elseif ($line -match "^INFO:(.*)$") {
                $infoData = $Matches[1]
                Write-VectorsLog -Message $infoData -Level "Debug"
            }
        }
        
        # Clean up
        Remove-Item -Path $docEmbeddingJsonFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $chunkEmbeddingsJsonFile -Force -ErrorAction SilentlyContinue
        
        if ($success) {
            Write-VectorsLog -Message "Document successfully added to vector store" -Level "Info"
            return $true
        } else {
            Write-VectorsLog -Message "Failed to add document to vector store" -Level "Error"
            return $false
        }
    }
    catch {
        Write-VectorsLog -Message "Failed to store embeddings: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $docEmbeddingJsonFile) {
            Remove-Item -Path $docEmbeddingJsonFile -Force
        }
        if (Test-Path -Path $chunkEmbeddingsJsonFile) {
            Remove-Item -Path $chunkEmbeddingsJsonFile -Force
        }
        
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Get-DocumentEmbedding, Get-ChunkEmbeddings, Add-DocumentToVectorStore
