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
    
    # Use Python to generate embedding
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

    $contentScript = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $contentScript -Value $Content -Encoding utf8

    $pythonCode = @"
import sys
import json
import urllib.request
import urllib.error

def get_embedding_from_ollama(text, model="llama3", base_url="http://localhost:11434"):
    """
    Get embeddings from Ollama API
    
    Args:
        text (str): The text to get embeddings for
        model (str): The model to use (default: "llama3")
        base_url (str): The base URL for Ollama API (default: "http://localhost:11434")
        
    Returns:
        list: A list of embedding values
    """
    url = f"{base_url}/api/embeddings"
    
    # Prepare request data
    data = {
        "model": model,
        "prompt": text
    }
    
    # Convert data to JSON and encode as bytes
    data_bytes = json.dumps(data).encode('utf-8')
    
    # Set headers
    headers = {
        'Content-Type': 'application/json'
    }
    
    # Create request
    req = urllib.request.Request(url, data=data_bytes, headers=headers, method="POST")
    
    # Send request and get response
    try:
        with urllib.request.urlopen(req) as response:
            response_text = response.read().decode('utf-8')
            
            # Parse JSON response
            try:
                response_data = json.loads(response_text)
            except json.JSONDecodeError:
                print(f"ERROR:Failed to parse JSON response: {response_text}")
                return None
            
            # Handle different response formats
            if isinstance(response_data, dict):
                # Standard format: {"embedding": [...]}
                if 'embedding' in response_data:
                    return response_data['embedding']
                
                # Alternative format: {"embeddings": [...]}
                elif 'embeddings' in response_data:
                    embeddings = response_data['embeddings']
                    # Handle if embeddings is a list of lists
                    if embeddings and isinstance(embeddings[0], list):
                        return embeddings[0]  # Return first embedding
                    return embeddings
            
            # Handle list format, e.g. [{...}, {...}]
            elif isinstance(response_data, list) and response_data:
                if isinstance(response_data[0], dict):
                    # Try to find embeddings in the first item
                    first_item = response_data[0]
                    if 'embedding' in first_item:
                        return first_item['embedding']
                    elif 'embeddings' in first_item:
                        return first_item['embeddings']
                # Maybe the response is directly a list of floats
                elif isinstance(response_data[0], (int, float)):
                    return response_data
            
            # If we got here, we couldn't identify the embedding format
            print(f"ERROR:Could not identify embedding format in response: {response_data}")
            return None
            
    except urllib.error.URLError as e:
        print(f"ERROR:Error connecting to Ollama: {e}")
        return None

try:
    # Read the document content from file
    with open(r'''$contentScript''', 'r', encoding='utf-8') as file:
        # Example 1: Read the entire file content at once
        text = file.read()
    # Skip empty input
    if not text or not text.strip():
        print("ERROR:Empty input")
        sys.exit(1)
    
    # Generate embedding
    embedding = get_embedding_from_ollama(
        text,
        model="$($config.EmbeddingModel)",
        base_url="$($config.OllamaUrl)"
    )

    if embedding is None:
        print("ERROR:Failed to generate embedding")
        sys.exit(1)
    
    result = {
        "text": text,
        "embedding": embedding            
    }
    
    # Return embedding as JSON
    print(f"SUCCESS:{json.dumps(result)}")
    
except Exception as e:
    print(f"ERROR:{str(e)}")
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        Write-VectorsLog -Message "Generating embedding for document: $FilePath" -Level "Info"
    } else {
        Write-VectorsLog -Message "Generating embedding for document content" -Level "Info"
    }
    
    # Execute the Python script
    try {
        $results = python $tempPythonScript 2>&1
        
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
        Remove-Item -Path $tempPythonScript -Force
        
        return $embedding
    }
    catch {
        Write-VectorsLog -Message "Failed to generate embedding: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $tempPythonScript) {
            Remove-Item -Path $tempPythonScript -Force
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
    Size of each chunk in characters
.PARAMETER ChunkOverlap
    Number of characters to overlap between chunks
.EXAMPLE
    Get-ChunkEmbeddings -FilePath "path/to/document.md" -ChunkSize 500 -ChunkOverlap 100
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

    # Use Python to chunk and generate embeddings
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

    $pythonCode = @"
import sys
import json
import math
import urllib.request
import urllib.error
import unicodedata

def chunk_text(text, chunk_size=1000, chunk_overlap=100):
    """
    Split a text into overlapping chunks of approximately equal size.
    Also tracks the start and end line numbers for each chunk.
    
    Args:
        text (str): The text to split into chunks
        chunk_size (int): The target size for each chunk
        chunk_overlap (int): The amount of overlap between chunks
        
    Returns:
        list: A list of dictionaries containing:
            - text: The chunk text
            - start_line: The starting line number (1-based)
            - end_line: The ending line number (1-based)
    """
    # Handle empty or very small texts
    if not text or len(text) <= chunk_size:
        return [{"text": text, "start_line": 1, "end_line": text.count('\n') + 1}]
    
    # Split text by newlines and track line numbers
    lines = text.split('\n')
    chunks = []
    current_chunk = ""
    current_start_line = 1  # 1-based line numbering
    current_end_line = 1
    line_counter = 1
    
    for line in lines:
        # If we're starting a new chunk, record the starting line number
        if not current_chunk:
            current_start_line = line_counter
        
        # If the line itself is larger than chunk_size, split it by words
        if len(line) > chunk_size:
            words = line.split(' ')
            for word in words:
                if len(current_chunk) + len(word) + 1 > chunk_size:
                    # Current chunk is full, add it to chunks with line info
                    chunks.append({
                        "text": current_chunk,
                        "start_line": current_start_line,
                        "end_line": current_end_line
                    })
                    
                    # Start new chunk with overlap
                    overlap_start = max(0, len(current_chunk) - chunk_overlap)
                    current_chunk = current_chunk[overlap_start:] + " " + word
                    # Line stays the same since we're splitting within a line
                    current_start_line = current_end_line
                else:
                    # Add word to current chunk
                    if current_chunk:
                        current_chunk += " " + word
                    else:
                        current_chunk = word
        else:
            # If adding this line would make the chunk too large, start a new chunk
            if len(current_chunk) + len(line) + 1 > chunk_size:
                # Store current chunk with line info
                chunks.append({
                    "text": current_chunk,
                    "start_line": current_start_line,
                    "end_line": current_end_line
                })
                
                # Start new chunk with overlap
                overlap_start = max(0, len(current_chunk) - chunk_overlap)
                current_chunk = current_chunk[overlap_start:] + "\n" + line
                # New chunk starts from the previous chunk's end line
                current_start_line = current_end_line
            else:
                # Add line to current chunk
                if current_chunk:
                    current_chunk += "\n" + line
                else:
                    current_chunk = line
        
        # Update current end line after processing this line
        current_end_line = line_counter
        line_counter += 1
    
    # Add the last chunk if it's not empty
    if current_chunk:
        chunks.append({
            "text": current_chunk,
            "start_line": current_start_line,
            "end_line": current_end_line
        })
    
    return chunks

def get_embedding_from_ollama(text, model="llama3", base_url="http://localhost:11434"):
    """
    Get embeddings from Ollama API
    
    Args:
        text (str): The text to get embeddings for
        model (str): The model to use (default: "llama3")
        base_url (str): The base URL for Ollama API (default: "http://localhost:11434")
        
    Returns:
        list: A list of embedding values
    """
    url = f"{base_url}/api/embeddings"
    
    # Prepare request data
    data = {
        "model": model,
        "prompt": text
    }
    
    # Convert data to JSON and encode as bytes
    data_bytes = json.dumps(data).encode('utf-8')
    
    # Set headers
    headers = {
        'Content-Type': 'application/json'
    }
    
    # Create request
    req = urllib.request.Request(url, data=data_bytes, headers=headers, method="POST")
    
    # Send request and get response
    try:
        with urllib.request.urlopen(req) as response:
            response_text = response.read().decode('utf-8')
            
            # Parse JSON response
            try:
                response_data = json.loads(response_text)
            except json.JSONDecodeError:
                print(f"ERROR:Failed to parse JSON response: {response_text}")
                return None
            
            # Handle different response formats
            if isinstance(response_data, dict):
                # Standard format: {"embedding": [...]}
                if 'embedding' in response_data:
                    return response_data['embedding']
                
                # Alternative format: {"embeddings": [...]}
                elif 'embeddings' in response_data:
                    embeddings = response_data['embeddings']
                    # Handle if embeddings is a list of lists
                    if embeddings and isinstance(embeddings[0], list):
                        return embeddings[0]  # Return first embedding
                    return embeddings
            
            # Handle list format, e.g. [{...}, {...}]
            elif isinstance(response_data, list) and response_data:
                if isinstance(response_data[0], dict):
                    # Try to find embeddings in the first item
                    first_item = response_data[0]
                    if 'embedding' in first_item:
                        return first_item['embedding']
                    elif 'embeddings' in first_item:
                        return first_item['embeddings']
                # Maybe the response is directly a list of floats
                elif isinstance(response_data[0], (int, float)):
                    return response_data
            
            # If we got here, we couldn't identify the embedding format
            print(f"ERROR:Could not identify embedding format in response: {response_data}")
            return None
            
    except urllib.error.URLError as e:
        print(f"ERROR:Error connecting to Ollama: {e}")
        return None

try:
    # Get parameters
    chunk_size = $ChunkSize
    chunk_overlap = $ChunkOverlap
    model_name = "$($config.EmbeddingModel)"
    api_url = "$($config.OllamaUrl)"
    source_path = "$FilePath"  # Empty for content-based

    # Read the document content from file
    with open(r'''$contentScript''', 'r', encoding='utf-8') as file:
        # Example 1: Read the entire file content at once
        text = file.read()

    # Skip empty input
    if not text or not text.strip():
        print("ERROR:Empty input")
        sys.exit(1)
    
    # Split content into chunks
    chunks = chunk_text(text, chunk_size, chunk_overlap)
    print(f"INFO:Split document into {len(chunks)} chunks")
    
    # Get embeddings for each chunk
    chunk_embeddings = []
    for i, chunk_data in enumerate(chunks):
        print(f"INFO:Processing chunk {i+1}/{len(chunks)}")
        embedding = get_embedding_from_ollama(chunk_data["text"], model_name, api_url)
        if embedding is None:
            print(f"ERROR:Failed to get embedding for chunk {i+1}")
            sys.exit(1)
        
        chunk_embeddings.append({
            'chunk_id': i,
            'text': chunk_data["text"],
            'start_line': chunk_data["start_line"],
            'end_line': chunk_data["end_line"],
            'embedding': embedding
        })
    
    # Return as JSON
    print(f"SUCCESS:{json.dumps(chunk_embeddings)}")
    
except Exception as e:
    print(f"ERROR:{str(e)}")
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        Write-VectorsLog -Message "Generating chunk embeddings for document: $FilePath" -Level "Info"
    } else {
        Write-VectorsLog -Message "Generating chunk embeddings for document content" -Level "Info"
    }
    
    Write-VectorsLog -Message "Chunk size: $ChunkSize, Chunk overlap: $ChunkOverlap" -Level "Debug"
    
    # Execute the Python script
    try {
        $results = python $tempPythonScript 2>&1
        
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
        Remove-Item -Path $tempPythonScript -Force
        Remove-Item -Path $contentScript -Force

        return $chunkEmbeddings
    }
    catch {
        Write-VectorsLog -Message "Failed to generate chunk embeddings: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $tempPythonScript) {
            Remove-Item -Path $tempPythonScript -Force
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
    Size of each chunk in characters
.PARAMETER ChunkOverlap
    Number of characters to overlap between chunks
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
        [int]$ChunkSize = 0,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkOverlap = 0
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
        $documentId = [System.IO.Path]::GetFileName($FilePath)
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
    
    # Use Python to store embeddings
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"
    
    # Convert embeddings to JSON
    $docEmbeddingJson = $docEmbedding | ConvertTo-Json -Compress
    $chunkEmbeddingsJson = $chunkEmbeddings | ConvertTo-Json -Compress -Depth 10

    $docEmbeddingJsonFile = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $docEmbeddingJsonFile -Value $docEmbeddingJson -Encoding utf8
      
    $chunkEmbeddingsJsonFile = [System.IO.Path]::GetTempFileName() + ".txt"
    Set-Content -Path $chunkEmbeddingsJsonFile -Value $chunkEmbeddingsJson -Encoding utf8


    $pythonCode = @"
import os
import sys
import json
import chromadb
import unicodedata
from chromadb.config import Settings

def normalize_text(text):
    normalized = unicodedata.normalize('NFKD', text)
    return normalized

try:
    # Read the document embedding and chunk embeddings from file
    with open(r'''$docEmbeddingJsonFile''', 'r', encoding='utf-8') as file:
        docEmbeddingJson = file.read()  

    with open(r'''$chunkEmbeddingsJsonFile''', 'r', encoding='utf-8') as file:
        chunkEmbeddingsJson = file.read()

    # Parse embeddings from JSON
    document_embedding = json.loads(docEmbeddingJson)
    chunks_data = json.loads(chunkEmbeddingsJson)
    
    # Get paths and IDs
    source_path = r"$sourcePath"
    document_id = r"$documentId"
    
    # Setup ChromaDB client
    output_folder = r'$($config.ChromaDbPath)'
    if not os.path.exists(output_folder):
        os.makedirs(output_folder)
    
    chroma_client = chromadb.PersistentClient(
        path=output_folder, 
        settings=Settings(anonymized_telemetry=False)
    )
    
    # Get collections
    doc_collection = chroma_client.get_collection(name="document_collection")
    chunks_collection = chroma_client.get_collection(name="document_chunks_collection")
    
    # Remove any existing document with this ID or source path
    try:
        doc_collection.delete(ids=[document_id])
        print(f"INFO:Removed existing document with ID: {document_id}")
    except:
        pass  # Ignore errors if document doesn't exist
    
    try:
        doc_collection.delete(where={"source": source_path})
        print(f"INFO:Removed existing document with source: {source_path}")
    except:
        pass  # Ignore errors if document doesn't exist
    
    # Remove any existing chunks for this document
    try:
        chunks_collection.delete(where={"source": source_path})
        print(f"INFO:Removed existing chunks for source: {source_path}")
    except:
        pass  # Ignore errors if chunks don't exist
    
    # Add document to collection
    doc_collection.add(
        documents=[normalize_text(document_embedding["text"])], 
        embeddings=[document_embedding["embedding"]],
        metadatas=[{"source": source_path}],
        ids=[document_id]
    )
    print(f"SUCCESS:Added document to vector store with ID: {document_id}")
    
    # Add chunks to collection
    documents = []
    embeddings = []
    metadatas = []
    ids = []
    
    for chunk_data in chunks_data:
        chunk_id = chunk_data["chunk_id"]
        doc_id = f"{document_id}_chunk_{chunk_id}"
        
        # Add to batch
        documents.append(normalize_text(chunk_data["text"]))
        embeddings.append(chunk_data["embedding"])
        metadatas.append({
            "source": source_path,
            "source_id": document_id,
            "chunk_id": chunk_id,
            "total_chunks": len(chunks_data),
            "start_line": chunk_data.get("start_line", 1),
            "end_line": chunk_data.get("end_line", 1),
            "line_range": f"{chunk_data.get('start_line', 1)}-{chunk_data.get('end_line', 1)}"
        })
        ids.append(doc_id)
    
    # Add all chunks to collection
    chunks_collection.add(
        documents=documents,
        embeddings=embeddings,
        metadatas=metadatas,
        ids=ids
    )
    print(f"SUCCESS:Added {len(chunks_data)} chunks to vector store")
    
except Exception as e:
    print(f"ERROR:{str(e)}")
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    
    # Execute the Python script
    try {
        $results = python $tempPythonScript 2>&1
        
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
        Remove-Item -Path $tempPythonScript -Force
        
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
        if (Test-Path -Path $tempPythonScript) {
            Remove-Item -Path $tempPythonScript -Force
        }
        
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Get-DocumentEmbedding, Get-ChunkEmbeddings, Add-DocumentToVectorStore
