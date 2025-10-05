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
import time
import datetime
import os

def log_to_file(message, log_path):
    """Log message to file with timestamp"""
    if log_path and log_path != "()":
        try:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_entry = f"[{timestamp}] {message}\n"
            
            # Ensure directory exists
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(log_entry)
        except Exception:
            pass  # Silent fail for logging errors

def get_embedding_from_ollama(text, model="llama3", base_url="http://localhost:11434", log_path=None):
    """
    Get embeddings from Ollama API
    
    Args:
        text (str): The text to get embeddings for
        model (str): The model to use (default: "llama3")
        base_url (str): The base URL for Ollama API (default: "http://localhost:11434")
        
    Returns:
        dict: A dictionary with "embedding" (list) and "duration" (float), or None if error.
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
    
    embedding = None
    duration = 0.0
    start_time = time.time()
    
    # Send request and get response
    try:
        with urllib.request.urlopen(req) as response:
            response_text = response.read().decode('utf-8')
            end_time = time.time()
            duration = end_time - start_time
            # Parse JSON response
            try:
                response_data = json.loads(response_text)
            except json.JSONDecodeError:
                log_to_file(f"ERROR:Failed to parse JSON response: {response_text}", log_path)
                return {"embedding": None, "duration": duration} # Return duration of attempt
            
            # Handle different response formats
            if isinstance(response_data, dict):
                if 'embedding' in response_data:
                    embedding = response_data['embedding']
                elif 'embeddings' in response_data:
                    embeddings_val = response_data['embeddings']
                    if embeddings_val and isinstance(embeddings_val[0], list):
                        embedding = embeddings_val[0]
                    else:
                        embedding = embeddings_val
            elif isinstance(response_data, list) and response_data:
                if isinstance(response_data[0], dict):
                    first_item = response_data[0]
                    if 'embedding' in first_item:
                        embedding = first_item['embedding']
                    elif 'embeddings' in first_item:
                        embedding = first_item['embeddings']
                elif isinstance(response_data[0], (int, float)):
                    embedding = response_data
            
            if embedding is None:
                log_to_file(f"ERROR:Could not identify embedding format in response: {response_data}", log_path)
            
            return {"embedding": embedding, "duration": duration, "created_at": datetime.datetime.now().isoformat()}

    except urllib.error.URLError as e:
        end_time = time.time()
        duration = end_time - start_time
        log_to_file(f"ERROR:Error connecting to Ollama: {e}", log_path)
        return {"embedding": None, "duration": duration, "created_at": datetime.datetime.now().isoformat()}

try:
    # Get log path
    log_path = r"$Env:vectorLogFilePath"
    
    # Read the document content from file
    with open(r'''$contentScript''', 'r', encoding='utf-8') as file:
        text = file.read()
    # Skip empty input
    if not text or not text.strip():
        log_to_file("ERROR:Empty input", log_path)
        sys.exit(1)

    # Generate embedding
    embedding_data = get_embedding_from_ollama(
        text,
        model="$($config.EmbeddingModel)",
        base_url="$($config.OllamaUrl)",
        log_path=log_path
    )

    if embedding_data is None or embedding_data["embedding"] is None:
        log_to_file("ERROR:Failed to generate embedding", log_path)
        sys.exit(1)
    
    result = {
        "text": text,
        "embedding": embedding_data["embedding"],
        "duration": embedding_data["duration"],
        "created_at": embedding_data["created_at"]
    }
    # Return embedding as JSON
    print(f"SUCCESS:{json.dumps(result)}")
    
except Exception as e:
    log_to_file(f"ERROR:{str(e)}", log_path)
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
    }    # Use Python to chunk and generate embeddings
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

    $pythonCode = @"
import sys
import json
import math
import urllib.request
import urllib.error
import unicodedata
import time
import datetime
import os

def log_to_file(message, log_path):
    """Log message to file with timestamp"""
    if log_path and log_path != "()":
        try:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_entry = f"[{timestamp}] {message}\n"
            
            # Ensure directory exists
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(log_entry)
        except Exception:
            pass  # Silent fail for logging errors

def chunk_text(text, chunk_size=20, chunk_overlap=2):
    """
    Split a text into chunks by fixed number of lines.
    Each chunk contains exactly chunk_size lines, except the last chunk which contains remaining lines.
    
    Args:
        text (str): The text to split into chunks
        chunk_size (int): The number of lines per chunk (default: 20)
        chunk_overlap (int): The number of lines to overlap between chunks (default: 0)
        
    Returns:
        list: A list of dictionaries containing:
            - text: The chunk text
            - start_line: The starting line number (1-based)
            - end_line: The ending line number (1-based)
    """
    # Handle empty text
    if not text or not text.strip():
        return [{"text": text, "start_line": 1, "end_line": 1}]
    
    # Split text by newlines
    lines = text.split('\n')
    total_lines = len(lines)
    
    # Handle case where text has fewer lines than chunk_size
    if total_lines <= chunk_size:
        return [{"text": text, "start_line": 1, "end_line": total_lines}]
    
    chunks = []
    current_line_index = 0
    
    while current_line_index < total_lines:
        # Calculate the end index for this chunk
        end_line_index = min(current_line_index + chunk_size, total_lines)
        
        # Extract lines for this chunk
        chunk_lines = lines[current_line_index:end_line_index]
        chunk_text = '\n'.join(chunk_lines)
        
        # Create chunk info (1-based line numbering)
        chunk_info = {
            "text": chunk_text,
            "start_line": current_line_index + 1,
            "end_line": end_line_index
        }
        
        chunks.append(chunk_info)
        
        # Move to next chunk position, accounting for overlap
        # If this is the last chunk (end_line_index == total_lines), break to avoid infinite loop
        if end_line_index == total_lines:
            break
            
        # Move forward by chunk_size minus overlap
        current_line_index += max(1, chunk_size - chunk_overlap)
    
    return chunks

def get_embedding_from_ollama(text, model="llama3", base_url="http://localhost:11434", log_path=None):
    """
    Get embeddings from Ollama API
    
    Args:
        text (str): The text to get embeddings for
        model (str): The model to use (default: "llama3")
        base_url (str): The base URL for Ollama API (default: "http://localhost:11434")
        log_path (str): Path to log file (optional)
        
    Returns:
        dict: A dictionary with "embedding" (list) and "duration" (float), or None if error.
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
    
    embedding = None
    duration = 0.0
    start_time = time.time()
    
    # Send request and get response
    try:
        with urllib.request.urlopen(req) as response:
            response_text = response.read().decode('utf-8')
            end_time = time.time()
            duration = end_time - start_time
            # Parse JSON response
            try:
                response_data = json.loads(response_text)
            except json.JSONDecodeError:
                log_to_file(f"ERROR:Failed to parse JSON response: {response_text}", log_path)
                return {"embedding": None, "duration": duration}
            
            # Handle different response formats
            if isinstance(response_data, dict):
                if 'embedding' in response_data:
                    embedding = response_data['embedding']
                elif 'embeddings' in response_data:
                    embeddings_val = response_data['embeddings']
                    if embeddings_val and isinstance(embeddings_val[0], list):
                        embedding = embeddings_val[0]
                    else:
                        embedding = embeddings_val
            elif isinstance(response_data, list) and response_data:
                if isinstance(response_data[0], dict):
                    first_item = response_data[0]
                    if 'embedding' in first_item:
                        embedding = first_item['embedding']
                    elif 'embeddings' in first_item:
                        embedding = first_item['embeddings']
                elif isinstance(response_data[0], (int, float)):
                    embedding = response_data
            if embedding is None:
                log_to_file(f"ERROR:Could not identify embedding format in response: {response_data}", log_path)
            
            return {"embedding": embedding, "duration": duration, "created_at": datetime.datetime.now().isoformat()}
            
    except urllib.error.URLError as e:
        end_time = time.time()
        duration = end_time - start_time
        log_to_file(f"ERROR:Error connecting to Ollama: {e}", log_path)
        return {"embedding": None, "duration": duration, "created_at": datetime.datetime.now().isoformat()}

try:
    # Get parameters
    chunk_size = $ChunkSize
    chunk_overlap = $ChunkOverlap
    model_name = "$($config.EmbeddingModel)"
    api_url = "$($config.OllamaUrl)"
    log_path = r"$Env:vectorLogFilePath"
    source_path = "$FilePath"  # Empty for content-based

    # Read the document content from file
    with open(r'''$contentScript''', 'r', encoding='utf-8') as file:
        text = file.read()    # Skip empty input
    if not text or not text.strip():
        log_to_file("ERROR:Empty input", log_path)
        sys.exit(1)
    # Split content into chunks
    chunks = chunk_text(text, chunk_size, chunk_overlap)
    log_to_file(f"INFO:Split document into {len(chunks)} chunks", log_path)
    
    # Get embeddings for each chunk
    chunk_embeddings = []
    for i, chunk_data in enumerate(chunks):
        embedding_result = get_embedding_from_ollama(chunk_data["text"], model_name, api_url, log_path)
        if embedding_result is None or embedding_result["embedding"] is None:
            log_to_file(f"ERROR:Failed to get embedding for chunk {i+1}", log_path)
            sys.exit(1)
        
        chunk_embeddings.append({
            'chunk_id': i,
            'text': chunk_data["text"],
            'start_line': chunk_data["start_line"],
            'end_line': chunk_data["end_line"],
            'embedding': embedding_result["embedding"],
            'duration': embedding_result["duration"],
            'created_at': embedding_result["created_at"]
        })
        
        log_to_file(f"INFO:Chunk {i} / {len(chunks)} embeddings created", log_path)

    # Return as JSON
    print(f"SUCCESS:{json.dumps(chunk_embeddings)}")
    
except Exception as e:
    log_to_file(f"ERROR:{str(e)}", log_path)
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        Write-VectorsLog -Message "Generating chunk embeddings for document: $FilePath" -Level "Info"
    } else {
        Write-VectorsLog -Message "Generating chunk embeddings for document content" -Level "Info"
    }
    
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
import datetime
from chromadb.config import Settings

def log_to_file(message, log_path):
    """Log message to file with timestamp"""
    if log_path and log_path != "()":
        try:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_entry = f"[{timestamp}] {message}\n"
            
            # Ensure directory exists
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(log_entry)
        except Exception:
            pass  # Silent fail for logging errors

def normalize_text(text):
    normalized = unicodedata.normalize('NFKD', text)
    return normalized

try:
    # Get log path
    log_path = r"$Env:vectorLogFilePath"
    
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
    collection_name = r"$CollectionName"
    
    # Setup ChromaDB client
    output_folder = r'$($config.ChromaDbPath)'
    if not os.path.exists(output_folder):
        os.makedirs(output_folder)
    
    chroma_client = chromadb.PersistentClient(
        path=output_folder, 
        settings=Settings(anonymized_telemetry=False)
    )
    
    # Always use both "default" and the specified collection
    collection_names_to_use = ["default"]
    if collection_name and collection_name.lower() != "default":
        collection_names_to_use.append(collection_name)
    
    # Iterate through each collection to store in
    for coll_name in collection_names_to_use:
        # Get collections with dynamic names
        doc_collection_name = f"{coll_name}_documents"
        
        doc_collection = chroma_client.get_or_create_collection(
            name=doc_collection_name,
            metadata={
                "hnsw:space": "cosine",
                "hnsw:search_ef": 100
            }
        )
        chunks_collection_name = f"{coll_name}_chunks"
     
        chunks_collection = chroma_client.get_or_create_collection(
            name=chunks_collection_name,
            metadata={
                "hnsw:space": "cosine",
                "hnsw:search_ef": 100
            }
        )
        try:
            doc_collection.delete(ids=[document_id])
            log_to_file(f"INFO:Removed existing document with ID: {document_id} from {coll_name}", log_path)
        except:
            pass
        try:
            doc_collection.delete(where={"source": source_path})
            log_to_file(f"INFO:Removed existing document with source: {source_path} from {coll_name}", log_path)
        except:
            pass
        # Remove any existing chunks for this document
        try:
            chunks_collection.delete(where={"source": source_path})
            log_to_file(f"INFO:Removed existing chunks for source: {source_path} from {coll_name}", log_path)
        except:
            pass
        
        # Add document to collection
        doc_metadata = {"source": source_path, "collection": coll_name}
        if "duration" in document_embedding:
            doc_metadata["duration"] = document_embedding["duration"]

        doc_metadata["created_at"] = document_embedding.get("created_at", None)

        doc_collection.add(
            documents=[normalize_text(document_embedding["text"])], 
            embeddings=[document_embedding["embedding"]],
            metadatas=[doc_metadata], # Updated metadata
            ids=[document_id]
        )
        log_to_file(f"INFO:Added document to {coll_name} collection with ID: {document_id}", log_path)
        
        # Add chunks to collection
        documents = []
        embeddings = []
        metadatas = []
        ids = []
        
        for chunk_data in chunks_data:
            chunk_id = chunk_data["chunk_id"]
            doc_id = f"{document_id}_chunk_{chunk_id}"
            
            chunk_metadata = {
                "source": source_path,
                "collection": coll_name,
                "source_id": document_id,
                "chunk_id": chunk_id,
                "total_chunks": len(chunks_data),
                "start_line": chunk_data.get("start_line", 1),
                "end_line": chunk_data.get("end_line", 1),
                "line_range": f"{chunk_data.get('start_line', 1)}-{chunk_data.get('end_line', 1)}",
                "created_at": chunk_data.get("created_at", None)
            }
            if "duration" in chunk_data:
                chunk_metadata["duration"] = chunk_data["duration"]
            
            documents.append(normalize_text(chunk_data["text"]))
            embeddings.append(chunk_data["embedding"])
            metadatas.append(chunk_metadata) # Updated metadata
            ids.append(doc_id)
        
        # Add all chunks to collection
        if documents: # Ensure there's something to add
            chunks_collection.add(
                documents=documents,
                embeddings=embeddings,
                metadatas=metadatas,
                ids=ids
            )
            log_to_file(f"INFO:Added {len(chunks_data)} chunks to {coll_name} collection", log_path)
        else:
            log_to_file(f"INFO:No chunks to add for document ID: {document_id} in {coll_name}", log_path)
    
    print(f"SUCCESS:Added document to vector store with ID: {document_id} in collections: {', '.join(collection_names_to_use)}")
    
except Exception as e:
    log_to_file(f"ERROR:{str(e)}", log_path)
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
