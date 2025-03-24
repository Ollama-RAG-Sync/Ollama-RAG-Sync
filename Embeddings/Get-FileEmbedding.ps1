# GetFileEmbedding.ps1
# Creates a single embedding vector for a specified text file
# Uses Ollama API for generating embeddings

#Requires -Version 7.0

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    
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
    Write-Host "Found Python: $pythonVersion" -ForegroundColor Green
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
    Write-Host "Ollama is not running or not accessible at $OllamaUrl" -ForegroundColor Red
    Write-Host "Please ensure Ollama is running before proceeding." -ForegroundColor Red
    Write-Host "You can download Ollama from https://ollama.ai/" -ForegroundColor Cyan
    exit 1
}

foreach ($line in $ollamaStatus) {
    if ($line -like "*WARNING*") {
        Write-Host $line -ForegroundColor Yellow
    } else {
        Write-Host $line -ForegroundColor Green
    }
}

# Create the temporary Python script for generating embeddings
$tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

$pythonCode = @"
import os
import sys
import json
import urllib.request
import urllib.error
import unicodedata

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

def process_file(file_path, model_name, api_url, save_to_chroma=False, output_folder=None):
    try:
        # Read file content
        with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        
        # Skip empty files
        if not content.strip():
            print("ERROR:File is empty")
            return False
        
        # Get embedding from Ollama
        embedding = get_embedding_from_ollama(content, model_name, api_url)
        if embedding is None:
            print(f"ERROR:Failed to get embedding for {file_path}")
            return False
        
        # If not saving to ChromaDB, just print the embedding
        if not save_to_chroma:
            # Print embedding as JSON to stdout
            print(f"SUCCESS:{json.dumps(embedding)}")
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
        collection = chroma_client.get_or_create_collection(name="document_collection",
            metadata={
                "hnsw:space": "cosine",
                "hnsw:search_ef": 100
        })
        
        
        # Create doc_id from filename
        doc_id = os.path.basename(file_path)
        
        # Remove any existing entries for this file
        try:
            collection.delete(where={"source": file_path})
        except:
            pass  # Ignore errors if document doesn't exist
            
        try:
            # Also try deleting by ID
            existing_ids = collection.get(ids=[doc_id])
            if existing_ids["ids"]:
                collection.delete(ids=[doc_id])
        except:
            pass  # Ignore errors if document doesn't exist
        
        # Add document to collection
        collection.add(
            documents=[normalize_text(content)],
            embeddings=[embedding],
            metadatas=[{"source": file_path}],
            ids=[doc_id]
        )
        print(f"SUCCESS:Embedding saved to ChromaDB at {output_folder}")
        return True
            
    except Exception as e:
        print(f"ERROR:{str(e)}")
        return False

if __name__ == "__main__":
    file_path = sys.argv[1]
    model_name = sys.argv[2]
    api_url = sys.argv[3]
    save_to_chroma = sys.argv[4].lower() == "true"
    output_folder = sys.argv[5] if len(sys.argv) > 5 else None
    
    process_file(file_path, model_name, api_url, save_to_chroma, output_folder)
"@

$pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8

Write-Host "Generating embedding for file: $FilePath" -ForegroundColor Cyan
Write-Host "Using Ollama URL: $OllamaUrl" -ForegroundColor Cyan
Write-Host "Embedding model: $EmbeddingModel" -ForegroundColor Cyan

if ($SaveToChroma) {
    Write-Host "Embedding will be saved to ChromaDB at: $ChromaDbPath" -ForegroundColor Cyan
    
    # Create the output directory if it doesn't exist
    if (-not (Test-Path -Path $ChromaDbPath)) {
        New-Item -Path $ChromaDbPath -ItemType Directory | Out-Null
        Write-Host "Created output directory: $ChromaDbPath" -ForegroundColor Green
    }
}

# Process the file
$saveToVectorDbPath = if ($ChromaDbPath) { "true" } else { "false" }
$results = python $tempPythonScript $FilePath $EmbeddingModel $OllamaUrl $saveToVectorDbPath $ChromaDbPath 2>&1

# Process the output
$embedding = $null
Write-Host $results
foreach ($line in $results) {
    if ($line -match "^SUCCESS:(.*)$") {
        $successData = $Matches[1]
        
        # Check if this is the embedding JSON
        if ($successData.StartsWith('[') -or $successData.StartsWith('{')) {
            try {
                $embedding = $successData | ConvertFrom-Json
                Write-Host "Successfully generated embedding vector." -ForegroundColor Green
            } catch {
                Write-Host "Generated embedding but couldn't parse JSON." -ForegroundColor Yellow
            }
        } else {
            Write-Host $successData -ForegroundColor Green
        }
    }
    elseif ($line -match "^ERROR:(.*)$") {
        $errorData = $Matches[1]
        Write-Host "Error: $errorData" -ForegroundColor Red
    }
    else {
        # Handle non-status output
        Write-Host $line -ForegroundColor Gray
    }
}

# Return the embedding object

if ($SaveToChroma -eq $false)
{
    $embedding
}

# Clean up
Remove-Item -Path $tempPythonScript -Force

# Summary
if ($SaveToChroma) {
    Write-Host "`nEmbedding has been saved to ChromaDB at: $ChromaDbPath" -ForegroundColor Green
    Write-Host "You can use this database with various retrieval tools and RAG applications." -ForegroundColor Cyan
} else {
    Write-Host "`nEmbedding vector has been generated successfully." -ForegroundColor Green
    Write-Host "The embedding vector contains $(($embedding | Measure-Object).Count) dimensions." -ForegroundColor Cyan
    Write-Host "To save this embedding to ChromaDB, run with the -SaveToChroma switch." -ForegroundColor Yellow
    Write-Host "Example: .\GetFileEmbedding.ps1 -FilePath '$FilePath' -SaveToChroma" -ForegroundColor Yellow
    Write-Host "You can specify a custom ChromaDB path with: -ChromaDbPath 'path/to/chromadb'" -ForegroundColor Yellow
}
