# Update-LocalChromaDb.ps1
# Example custom processor script for Update-LocalChromaDb.ps1
# This script demonstrates how to create a custom processor that can be passed to Process-DirtyFiles.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    
    [Parameter(Mandatory=$true)]
    [string]$VectorDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel,
    
    [Parameter(Mandatory=$false)]
    [string]$TempDir,
    
    [Parameter(Mandatory=$false)]
    [string]$ScriptPath,
    
    [Parameter(Mandatory=$false)]
    [string]$CustomParam1,
    
    [Parameter(Mandatory=$false)]
    [string]$CustomParam2,
    
    [Parameter(Mandatory=$false)]
    [string]$VectorsApiUrl = "http://localhost:8082",
    
    [Parameter(Mandatory=$false)]
    [int]$DefaultChunkSize = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$DefaultChunkOverlap = 200
)

$ChromaDbPath = $VectorDbPath
$logFilePath = Join-Path -Path $TempDir -ChildPath "$(Split-Path -Leaf $FilePath)_processing.txt"

# Function to log messages
function Write-CustomLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [CUSTOM] [$Level] $Message"
    
    # Write to console with appropriate color
    if ($Level -eq "ERROR") {
        Write-Host $logMessage 
    }
    elseif ($Level -eq "WARNING") {
        Write-Host $logMessage
    }
    else {
        Write-Host $logMessage
    }
    Add-Content -Path $logFilePath  -Value $logMessage
}

# Function to add document to vectors using REST API
function Add-DocumentToVectorsApi {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkSize = $DefaultChunkSize,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkOverlap = $DefaultChunkOverlap
    )
    
    try {
        Write-CustomLog "Adding document to vectors via API: $FilePath"
        
        # Prepare request body
        $body = @{
            filePath = $FilePath
            chunkSize = $ChunkSize
            chunkOverlap = $ChunkOverlap
        }
        
        # Invoke REST API
        $response = Invoke-RestMethod -Uri "$VectorsApiUrl/documents" -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop
        
        # Check response
        if ($response.success -eq $true) {
            Write-CustomLog "Successfully added document to vectors: $FilePath"
            return $true
        }
        else {
            Write-CustomLog "API returned error: $($response.error)" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-CustomLog "Error calling Vectors API: $_" -Level "ERROR"
        return $false
    }
}

# Function to check if Vectors API is available
function Test-VectorsApiAvailable {
    try {
        $response = Invoke-RestMethod -Uri "$VectorsApiUrl/status" -Method Get -ErrorAction Stop
        Write-CustomLog "Vectors API is available at $VectorsApiUrl"
        return $true
    }
    catch {
        Write-CustomLog "Vectors API is not available at $VectorsApiUrl: $_" -Level "ERROR"
        return $false
    }
}

# Main processing logic
Write-CustomLog "Custom processor started for file: $FilePath"

# Check if Vectors API is available
$apiAvailable = Test-VectorsApiAvailable
if (-not $apiAvailable) {
    Write-CustomLog "Will attempt to use direct PowerShell functions as fallback" -Level "WARNING"
}

# Example: Determine file type and process accordingly
$fileExtension = [System.IO.Path]::GetExtension($FilePath).ToLower()

# Example custom processing logic
switch ($fileExtension) {
    ".pdf" {
        Write-CustomLog "Processing PDF file with custom logic"
        
        # Example: Convert PDF to text and process
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $outputPath = Join-Path -Path $TempDir -ChildPath "$fileName.txt"
        $logPath = Join-Path -Path $TempDir -ChildPath "$fileName.txt"
        
        # Call your custom PDF processing logic here
        # For demonstration, we'll just use the built-in ConvertPDFToMarkdown.ps1
        $convertScript = Join-Path -Path $ScriptPath -ChildPath "..\Conversion\Convert-PDFToMarkdown.ps1"
        & $convertScript -PdfFilePath $FilePath -OutputFilePath $outputPath -LogFilePath $logPath
        
        # Add custom post-processing for PDF files
        if (Test-Path $outputPath) {
            Write-CustomLog "PDF converted successfully, performing custom post-processing"
            # Example: Add custom metadata or modify the content
            $content = Get-Content -Path $outputPath -Raw
            $content = "# Custom Processed File`n`n$content"
            $content | Set-Content -Path $outputPath -Encoding utf8
            
            # Use the Vectors API to add the document to the vector database
            if ($apiAvailable) {
                $result = Add-DocumentToVectorsApi -FilePath $outputPath
            }
            else {
                # Fallback to direct PowerShell function
                $vectorsAddDocumentScript = Join-Path -Path $ScriptPath -ChildPath "..\..\Vectors\Functions\Add-DocumentToVectors.ps1"
                Write-CustomLog "Adding document to vector database using direct script call..."
                $result = & $vectorsAddDocumentScript -FilePath $outputPath -ChromaDbPath $ChromaDbPath -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel
            }
            
            if (-not $result) {
                Write-CustomLog "Failed to add document to vector database" -Level "ERROR"
            }
        }
        else {
            Write-CustomLog "Failed to convert PDF file" -Level "ERROR"
        }
    }
    ".txt" {
        Write-CustomLog "Processing text file with custom logic"
        
        # Read the content and add custom processing
        $content = Get-Content -Path $FilePath -Raw
        $processedContent = $content -replace "important", "IMPORTANT" -replace "urgent", "URGENT"
        
        # Save to a temporary file
        $tempFile = Join-Path -Path $TempDir -ChildPath "processed_$(Split-Path -Leaf $FilePath)"
        $processedContent | Set-Content -Path $tempFile -Encoding utf8
        
        # Use the Vectors API to add the document to the vector database
        if ($apiAvailable) {
            $result = Add-DocumentToVectorsApi -FilePath $tempFile
        }
        else {
            # Fallback to direct PowerShell function
            $vectorsAddDocumentScript = Join-Path -Path $ScriptPath -ChildPath "..\..\Vectors\Functions\Add-DocumentToVectors.ps1"
            Write-CustomLog "Adding document to vector database using direct script call..."
            $result = & $vectorsAddDocumentScript -FilePath $tempFile -ChromaDbPath $ChromaDbPath -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel
        }
        
        if (-not $result) {
            Write-CustomLog "Failed to add document to vector database" -Level "ERROR"
        }
    }
    ".md" {
        Write-CustomLog "Processing markdown file with custom logic"
        
        # Add custom processing for markdown
        $content = Get-Content -Path $FilePath -Raw
        
        # Example: Extract and enhance headers
        $enhancedContent = $content -replace "(#+\s*)(.*)", '$1[Enhanced] $2'
        
        # Save to a temporary file
        $tempFile = Join-Path -Path $TempDir -ChildPath "enhanced_$(Split-Path -Leaf $FilePath)"
        $enhancedContent | Set-Content -Path $tempFile -Encoding utf8
        
        # Use the Vectors API to add the document to the vector database
        if ($apiAvailable) {
            $result = Add-DocumentToVectorsApi -FilePath $tempFile
        }
        else {
            # Fallback to direct PowerShell function
            $vectorsAddDocumentScript = Join-Path -Path $ScriptPath -ChildPath "..\..\Vectors\Functions\Add-DocumentToVectors.ps1"
            Write-CustomLog "Adding document to vector database using direct script call..."
            $result = & $vectorsAddDocumentScript -FilePath $tempFile -ChromaDbPath $ChromaDbPath -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel
        }
        
        if (-not $result) {
            Write-CustomLog "Failed to add document to vector database" -Level "ERROR"
        }
    }
    default {
        Write-CustomLog "Unsupported file type: $fileExtension, using default processing" -Level "WARNING"
        
        # For unsupported file types, just add to ChromaDB directly if it's a text-based file
        if (Test-Path $FilePath) {
            try {
                # Attempt to read as text
                $null = Get-Content -Path $FilePath -Raw -ErrorAction Stop
                
                # Use the Vectors API to add the document to the vector database
                if ($apiAvailable) {
                    $result = Add-DocumentToVectorsApi -FilePath $FilePath
                }
                else {
                    # Fallback to direct PowerShell function
                    $vectorsAddDocumentScript = Join-Path -Path $ScriptPath -ChildPath "..\..\Vectors\Functions\Add-DocumentToVectors.ps1"
                    Write-CustomLog "Adding document to vector database using direct script call..."
                    $result = & $vectorsAddDocumentScript -FilePath $FilePath -ChromaDbPath $ChromaDbPath -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel
                }
                
                if (-not $result) {
                    Write-CustomLog "Failed to add document to vector database" -Level "ERROR"
                }
            }
            catch {
                Write-CustomLog "File is not text-based or cannot be read: $_" -Level "ERROR"
            }
        }
    }
}

Write-CustomLog "Custom processing completed for: $FilePath"
