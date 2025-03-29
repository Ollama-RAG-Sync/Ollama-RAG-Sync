# Get-ChunkEmbeddings.ps1
# DEPRECATED: This script is maintained for backward compatibility only.
# The functionality has been moved to the Vectors subsystem.
# Please use Vectors/Functions/Add-DocumentToVectors.ps1 instead, which handles
# chunking and embedding generation via the Vectors-Embeddings.psm1 module.
#
# Creates multiple embedding vectors for chunks of a specified text file
# Uses Ollama API for generating embeddings

#Requires -Version 7.0

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 200,
    
    [Parameter(Mandatory=$false)]
    [string]$Extensions = ".txt,.md,.html,.csv,.json",
    
    [Parameter(Mandatory=$true)]
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [switch]$SaveToChroma
)

# Check if Python is installed
try {
    $pythonVersion = python --version
    Write-Host "Found Python: $pythonVersion"
}
catch {
    Write-Host "Python not found. Please install Python 3.8+ to use this script."
    exit 1
}

# Verify the file path exists
if (-not (Test-Path -Path $FilePath)) {
    Write-Host "The specified file path does not exist: $FilePath" 
    exit 1
}

# Check if file has a supported extension
$fileExtension = [System.IO.Path]::GetExtension($FilePath).ToLower()
$supportedExtensions = $Extensions.Split(',') | ForEach-Object { $_.Trim().ToLower() }

if (-not ($supportedExtensions -contains $fileExtension)) {
    Write-Host "The file extension '$fileExtension' is not supported." 
    Write-Host "Supported extensions: $Extensions" 
    exit 1
}

# Check if Ollama is running
Write-Host "Checking if Ollama is running at $OllamaUrl..."
$ollamaStatus = python -c "
import requests
import sys
try:
    response = requests.get('$OllamaUrl/api/tags')
    if response.status_code == 200:
        print('Ollama is running')
        models = response.json().get('models', [])
        available_models = [model['name'] for model in models]
        if '$EmbeddingModel' in available_models:
            print('Model $EmbeddingModel is available')
        else:
            print('WARNING: Model $EmbeddingModel is not available')
            print('Available models: ' + ', '.join(available_models))
    else:
        print('Ollama is not responding correctly')
        sys.exit(1)
except Exception as e:
    print(f'Error connecting to Ollama: {e}')
    sys.exit(1)
" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Ollama is not running or not accessible at $OllamaUrl"
    Write-Host "Please ensure Ollama is running before proceeding." 
    Write-Host "You can download Ollama from https://ollama.ai/" 
    exit 1
}

foreach ($line in $ollamaStatus) {
    if ($line -like "*WARNING*") {
        Write-Host $line -ForegroundColor Yellow
    } else {
        Write-Host $line -ForegroundColor Green
    }
}

# Create the temporary Python script for chunking and generating embeddings
$tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

$pythonCode = @"
import os
import sys
import json
import math
import urllib.request
import urllib.error
import unicodedata

def chunk_text(text, chunk_size=1000, chunk_overlap=200):
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

def normalize_text(text):
    normalized = unicodedata.normalize('NFKD', text)
    return normalized

def process_file(file_path, chunk_size, chunk_overlap, model_name, api_url, save_to_chroma=False, output_folder=None):
    try:
        # Read file content
        with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        
        # Skip empty files
        if not content.strip():
            print("ERROR:File is empty")
            return False
        
        # Split content into chunks
        chunks = chunk_text(content, chunk_size, chunk_overlap)
        print(f"INFO:Split file into {len(chunks)} chunks")
        
        # Get embeddings for each chunk
        chunk_embeddings = []
        for i, chunk_data in enumerate(chunks):
            print(f"INFO:Processing chunk {i+1}/{len(chunks)}")
            embedding = get_embedding_from_ollama(chunk_data["text"], model_name, api_url)
            if embedding is None:
                print(f"ERROR:Failed to get embedding for chunk {i+1}")
                return False
            
            chunk_embeddings.append({
                'chunk_id': i,
                'text': chunk_data["text"],
                'start_line': chunk_data["start_line"],
                'end_line': chunk_data["end_line"],
                'embedding': embedding
            })
        
        # If not saving to ChromaDB, just return the embeddings
        if not save_to_chroma:
            # Print embeddings as JSON to stdout
            print(f"SUCCESS:{json.dumps(chunk_embeddings)}")
            return True
        
        # If saving to ChromaDB, import the required modules
        import chromadb
        from chromadb.config import Settings
        
        # Create output directory if it doesn't exist
        if not os.path.exists(output_folder):
            os.makedirs(output_folder)
        
        # Setup ChromaDB client
        chroma_client = chromadb.PersistentClient(path=output_folder, settings=Settings(anonymized_telemetry=False))
        
        # Get or create collection
        collection = chroma_client.get_or_create_collection(name="document_chunks_collection",
            metadata={
                "hnsw:space": "cosine",
                "hnsw:search_ef": 100
            })
        
        # Create base doc_id from filename
        base_doc_id = os.path.basename(file_path)
        
        # Remove any existing entries for this file
        try:
            collection.delete(where={"source": file_path})
        except:
            pass  # Ignore errors if document doesn't exist
        
        # Add each chunk to collection
        documents = []
        embeddings = []
        metadatas = []
        ids = []
        
        for chunk_data in chunk_embeddings:
            chunk_id = chunk_data['chunk_id']
            doc_id = f"{base_doc_id}_chunk_{chunk_id}"
            
            # Try to delete any existing chunk with this ID
            try:
                existing_ids = collection.get(ids=[doc_id])
                if existing_ids["ids"]:
                    collection.delete(ids=[doc_id])
            except:
                pass  # Ignore errors if document doesn't exist
            
            # Add to batch
            documents.append(normalize_text(chunk_data['text']))
            embeddings.append(chunk_data['embedding'])
            metadatas.append({
                "source": file_path,
                "chunk_id": chunk_id,
                "total_chunks": len(chunks),
                "start_line": chunk_data.get('start_line', 1),
                "end_line": chunk_data.get('end_line', 1),
                "line_range": f"{chunk_data.get('start_line', 1)}-{chunk_data.get('end_line', 1)}"
            })
            ids.append(doc_id)
        
        # Add all chunks to collection
        collection.add(
            documents=documents,
            embeddings=embeddings,
            metadatas=metadatas,
            ids=ids
        )
        print(f"SUCCESS:Added {len(chunks)} chunks to ChromaDB at {output_folder}")
        return True
            
    except Exception as e:
        print(f"ERROR:{str(e)}")
        return False

if __name__ == "__main__":
    file_path = sys.argv[1]
    chunk_size = int(sys.argv[2])
    chunk_overlap = int(sys.argv[3])
    model_name = sys.argv[4]
    api_url = sys.argv[5]
    save_to_chroma = sys.argv[6].lower() == "true"
    output_folder = sys.argv[7] if len(sys.argv) > 7 else None
    
    process_file(file_path, chunk_size, chunk_overlap, model_name, api_url, save_to_chroma, output_folder)
"@

$pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8

Write-Host "Generating chunk embeddings for file: $FilePath" -ForegroundColor Cyan
Write-Host "Chunk size: $ChunkSize, Chunk overlap: $ChunkOverlap" -ForegroundColor Cyan
Write-Host "Using Ollama URL: $OllamaUrl" -ForegroundColor Cyan
Write-Host "Embedding model: $EmbeddingModel" -ForegroundColor Cyan

if ($SaveToChroma) {
    Write-Host "Embeddings will be saved to vector Db at: $ChromaDbPath" -ForegroundColor Cyan
    
    # Create the output directory if it doesn't exist
    if (-not (Test-Path -Path $ChromaDbPath)) {
        New-Item -Path $ChromaDbPath -ItemType Directory | Out-Null
        Write-Host "Created output directory: $ChromaDbPath" -ForegroundColor Green
    }
}

# Process the file
$saveToChromaStr = if ($SaveToChroma) { "true" } else { "false" }
$results = python $tempPythonScript $FilePath $ChunkSize $ChunkOverlap $EmbeddingModel $OllamaUrl $saveToChromaStr $ChromaDbPath 2>&1

# Process the output
$embeddings = $null
foreach ($line in $results) {
    if ($line -match "^SUCCESS:(.*)$") {
        $successData = $Matches[1]
        
        # Check if this is the embedding JSON
        if ($successData.StartsWith('[') -or $successData.StartsWith('{')) {
            try {
                $embeddings = $successData | ConvertFrom-Json
                Write-Host "Successfully generated chunk embeddings." -ForegroundColor Green
            } catch {
                Write-Host "Generated embeddings but couldn't parse JSON." -ForegroundColor Yellow
            }
        } else {
            Write-Host $successData -ForegroundColor Green
        }
    }
    elseif ($line -match "^ERROR:(.*)$") {
        $errorData = $Matches[1]
        Write-Host "Error: $errorData" -ForegroundColor Red
    }
    elseif ($line -match "^INFO:(.*)$") {
        $infoData = $Matches[1]
        Write-Host "Info: $infoData" -ForegroundColor Cyan
    }
    else {
        # Handle non-status output
        Write-Host $line -ForegroundColor Gray
    }
}

# Return the embedding objects
if ($SaveToChroma -eq $false) {
    $embeddings
}

# Clean up
$null = Remove-Item -Path $tempPythonScript -Force

# Summary
if ($SaveToChroma) {
    Write-Host "`nChunk embeddings have been saved to ChromaDB at: $ChromaDbPath" -ForegroundColor Green
    Write-Host "Documents were split into $(($embeddings.Count)) chunks." -ForegroundColor Cyan
    Write-Host "You can use this database with various retrieval tools and RAG applications." -ForegroundColor Cyan
} else {
    Write-Host "`nChunk embeddings have been generated successfully." -ForegroundColor Green
    Write-Host "The document was split into $(($embeddings.Count)) chunks." -ForegroundColor Cyan
    Write-Host "Each embedding vector contains $(($embeddings[0].embedding | Measure-Object).Count) dimensions." -ForegroundColor Cyan
    Write-Host "To save these embeddings to ChromaDB, run with the -SaveToChroma switch." -ForegroundColor Yellow
    Write-Host "Example: .\Get-ChunkEmbeddings.ps1 -FilePath '$FilePath' -SaveToChroma" -ForegroundColor Yellow
    Write-Host "You can specify a custom ChromaDB path with: -ChromaDbPath 'path/to/chromadb'" -ForegroundColor Yellow
}
