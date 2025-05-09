# Vectors-Database.psm1
# ChromaDB interaction for the Vectors subsystem

# Import the core module
if (-not (Get-Module -Name "Vectors-Core")) {
    Import-Module "$PSScriptRoot\Vectors-Core.psm1" -Force
}

<#
.SYNOPSIS
    Gets information about the ChromaDB collections
.DESCRIPTION
    Returns metadata and statistics about the ChromaDB collections
.EXAMPLE
    Get-VectorDatabaseInfo
#>
function Get-VectorDatabaseInfo {
    [CmdletBinding()]
    param ()
    
    $config = Get-VectorsConfig
    
    # Use Python to get database info
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

    $pythonCode = @"
import os
import sys
import json
import chromadb
from chromadb.config import Settings

try:
    # Setup ChromaDB client
    output_folder = r'$($config.ChromaDbPath)'
    chroma_client = chromadb.PersistentClient(
        path=output_folder, 
        settings=Settings(anonymized_telemetry=False)
    )
    
    # Get collections info
    collection_names = chroma_client.list_collections()
    
    # Build detailed info for each collection
    collections_info = []
    
    for collection in collection_names:
        coll = chroma_client.get_collection(name=collection.name)
        
        # Get count of documents
        count = coll.count()
        
        # Get sample of IDs (limit to 5)
        ids = []
        if count > 0:
            try:
                # Try to get some sample IDs to see what's in there
                samples = coll.get(limit=5)
                ids = samples["ids"]
            except:
                pass
        
        # Add to collections info
        collections_info.append({
            "name": collection.name,
            "count": count,
            "metadata": collection.metadata,
            "sample_ids": ids
        })
    
    # Return as JSON
    result = {
        "db_path": output_folder,
        "collections": collections_info
    }
    
    print(f"SUCCESS:{json.dumps(result)}")
    
except Exception as e:
    print(f"ERROR:{str(e)}")
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    
    Write-VectorsLog -Message "Getting ChromaDB information from $($config.ChromaDbPath)" -Level "Debug"
    
    # Execute the Python script
    try {
        $results = python $tempPythonScript 2>&1
        
        # Process the output
        $dbInfo = $null
        foreach ($line in $results) {
            if ($line -match "^SUCCESS:(.*)$") {
                $successData = $Matches[1]
                try {
                    $dbInfo = $successData | ConvertFrom-Json
                }
                catch {
                    Write-VectorsLog -Message "Failed to parse database info: $($_.Exception.Message)" -Level "Error"
                }
            }
            elseif ($line -match "^ERROR:(.*)$") {
                $errorData = $Matches[1]
                Write-VectorsLog -Message "ChromaDB error: $errorData" -Level "Error"
            }
        }
        
        # Clean up
        Remove-Item -Path $tempPythonScript -Force
        
        return $dbInfo
    }
    catch {
        Write-VectorsLog -Message "Failed to get vector database info: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $tempPythonScript) {
            Remove-Item -Path $tempPythonScript -Force
        }
        
        return $null
    }
}

<#
.SYNOPSIS
    Performs a query against the document vector collection
.DESCRIPTION
    Searches for similar documents in the vector database
.PARAMETER QueryText
    The query text to search for
.PARAMETER MaxResults
    The maximum number of results to return
.PARAMETER MinScore
    The minimum similarity score (0-1) for results
.PARAMETER WhereFilter
    Optional filter to apply to the query (e.g. @{source = "path/to/file.md"})
.EXAMPLE
    Query-VectorDocuments -QueryText "How to implement RAG?" -MaxResults 5
#>
function Query-VectorDocuments {
    param (
        [Parameter(Mandatory=$true)]
        [string]$QueryText,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxResults = 10,
        
        [Parameter(Mandatory=$false)]
        [double]$MinScore = 0.0,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$WhereFilter = @{}
    )
    
    $config = Get-VectorsConfig
    
    # Use Python to query the database
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"
    
    # Convert WhereFilter to JSON
    $whereFilterJson = "{}"
    if ($WhereFilter.Count -gt 0) {
        $whereFilterJson = $WhereFilter | ConvertTo-Json -Compress
    }

    $pythonCode = @"
import os
import sys
import json
import chromadb
import urllib.request
import urllib.error
from chromadb.config import Settings

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
    # Parse parameters
    query_text = r"""$QueryText"""
    max_results = $MaxResults
    min_score = $MinScore
    where_filter = json.loads(r'''$whereFilterJson''')
    
    # Generate embedding for query
    print(f"INFO:Generating embedding for query: {query_text[:50]}...")
    embedding = get_embedding_from_ollama(
        query_text, 
        model="$($config.EmbeddingModel)", 
        base_url="$($config.OllamaUrl)"
    )
    
    if embedding is None:
        print("ERROR:Failed to generate embedding for query")
        sys.exit(1)
    
    # Setup ChromaDB client
    output_folder = r'$($config.ChromaDbPath)'
    chroma_client = chromadb.PersistentClient(
        path=output_folder, 
        settings=Settings(anonymized_telemetry=False)
    )
    
    # Get the document collection
    collection = chroma_client.get_collection(name="document_collection")
    
    # Perform query
    print(f"INFO:Querying document collection with filter: {where_filter}")
    
    # Handle empty where_filter
    if not where_filter:
        results = collection.query(
            query_embeddings=[embedding],
            n_results=max_results,
            include=["documents", "metadatas", "distances"]
        )
    else:
        results = collection.query(
            query_embeddings=[embedding],
            n_results=max_results,
            where=where_filter,
            include=["documents", "metadatas", "distances"]
        )
    
    # Process results
    processed_results = []
    
    # Check if we have results
    if results and "ids" in results and results["ids"]:
        ids = results["ids"][0]  # First query results
        documents = results["documents"][0]  # First query documents
        metadatas = results["metadatas"][0]  # First query metadatas
        distances = results["distances"][0]  # First query distances
        
        for i in range(len(ids)):
            # Convert distance to similarity score (cosine distance to similarity)
            similarity = 1 - distances[i]
            
            # Skip results below minimum score
            if similarity < min_score:
                continue
                
            processed_results.append({
                "id": ids[i],
                "document": documents[i],  
                "metadata": metadatas[i],
                "similarity": similarity
            })
    
    # Return as JSON
    print(f"SUCCESS:{json.dumps(processed_results)}")
    
except Exception as e:
    print(f"ERROR:{str(e)}")
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    
    Write-VectorsLog -Message "Querying document collection for: $($QueryText.Substring(0, [Math]::Min(50, $QueryText.Length)))..." -Level "Info"
    
    # Execute the Python script
    try {
        $results = python $tempPythonScript 2>&1
        
        # Process the output
        $queryResults = @()
        foreach ($line in $results) {
            if ($line -match "^SUCCESS:(.*)$") {
                $successData = $Matches[1]
                try {
                    $queryResults = ConvertFrom-Json -InputObject $successData -NoEnumerate
                    Write-VectorsLog -Message "Found $($queryResults.Count) matching documents" -Level "Info"
                }
                catch {
                    Write-VectorsLog -Message "Failed to parse query results: $($_.Exception.Message)" -Level "Error"
                }
            }
            elseif ($line -match "^ERROR:(.*)$") {
                $errorData = $Matches[1]
                Write-VectorsLog -Message "Query error: $errorData" -Level "Error"
            }
            elseif ($line -match "^INFO:(.*)$") {
                $infoData = $Matches[1]
                Write-VectorsLog -Message $infoData -Level "Debug"
            }
        }
        
        if (Test-Path -Path $tempPythonScript) {
            Remove-Item -Path $tempPythonScript -Force
        }
        
        return Write-Output -NoEnumerate $queryResults
    }
    catch {
        $null = Write-VectorsLog -Message "Failed to execute query: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $tempPythonScript) {
            $null = Remove-Item -Path $tempPythonScript -Force
        }
        
        return @()
    }
}

<#
.SYNOPSIS
    Performs a query against the document chunks vector collection
.DESCRIPTION
    Searches for similar chunks in the vector database
.PARAMETER QueryText
    The query text to search for
.PARAMETER MaxResults
    The maximum number of results to return
.PARAMETER MinScore
    The minimum similarity score (0-1) for results
.PARAMETER WhereFilter
    Optional filter to apply to the query (e.g. @{source = "path/to/file.md"})
.PARAMETER AggregateByDocument
    Whether to aggregate results by source document
.EXAMPLE
    Query-VectorChunks -QueryText "How to implement RAG?" -MaxResults 5
#>
function Query-VectorChunks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$QueryText,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxResults = 10,
        
        [Parameter(Mandatory=$false)]
        [double]$MinScore = 0.0,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$WhereFilter = @{},
        
        [Parameter(Mandatory=$false)]
        [switch]$AggregateByDocument
    )
    
    $config = Get-VectorsConfig
    
    # Use Python to query the database
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"
    
    # Convert WhereFilter to JSON
    $whereFilterJson = "{}"
    if ($WhereFilter.Count -gt 0) {
        $whereFilterJson = $WhereFilter | ConvertTo-Json -Compress
    }
    
    # Set aggregate flag
    $aggregateFlag = if ($AggregateByDocument) { "True" } else { "False" }

    $pythonCode = @"
import os
import sys
import json
import chromadb
import urllib.request
import urllib.error
from chromadb.config import Settings
from collections import defaultdict

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
    # Parse parameters
    query_text = r"""$QueryText"""
    max_results = $MaxResults
    min_score = $MinScore
    where_filter = json.loads(r'''$whereFilterJson''')
    aggregate_by_document = $aggregateFlag
    
    # Generate embedding for query
    print(f"INFO:Generating embedding for query: {query_text[:50]}...")
    embedding = get_embedding_from_ollama(
        query_text, 
        model="$($config.EmbeddingModel)", 
        base_url="$($config.OllamaUrl)"
    )
    
    if embedding is None:
        print("ERROR:Failed to generate embedding for query")
        sys.exit(1)
    
    # Setup ChromaDB client
    output_folder = r'$($config.ChromaDbPath)'
    chroma_client = chromadb.PersistentClient(
        path=output_folder, 
        settings=Settings(anonymized_telemetry=False)
    )
    
    # Get the chunks collection
    collection = chroma_client.get_collection(name="document_chunks_collection")
    
    # Adjust max_results for aggregation
    query_limit = max_results
    if aggregate_by_document:
        # If we're aggregating, get more results to ensure we have enough after aggregation
        query_limit = max_results * 3
    
    # Perform query
    print(f"INFO:Querying chunks collection with filter: {where_filter}")
    
    # Handle empty where_filter
    if not where_filter:
        results = collection.query(
            query_embeddings=[embedding],
            n_results=query_limit,
            include=["documents", "metadatas", "distances"]
        )
    else:
        results = collection.query(
            query_embeddings=[embedding],
            n_results=query_limit,
            where=where_filter,
            include=["documents", "metadatas", "distances"]
        )
    
    # Process results
    processed_results = []
    
    # Check if we have results
    if results and "ids" in results and results["ids"]:
        ids = results["ids"][0]  # First query results
        documents = results["documents"][0]  # First query documents
        metadatas = results["metadatas"][0]  # First query metadatas
        distances = results["distances"][0]  # First query distances
        
        # If aggregating by document
        if aggregate_by_document:
            # Group by source document
            document_chunks = defaultdict(list)
            
            for i in range(len(ids)):
                # Convert distance to similarity score (cosine distance to similarity)
                similarity = 1 - distances[i]
                
                # Skip results below minimum score
                if similarity < min_score:
                    continue
                
                # Get source document
                if "source" in metadatas[i]:
                    source = metadatas[i]["source"]
                    
                    # Add to document chunks
                    document_chunks[source].append({
                        "id": ids[i],
                        "chunk": documents[i][:500] + ("..." if len(documents[i]) > 500 else ""),  # Truncate long chunks
                        "metadata": metadatas[i],
                        "similarity": similarity
                    })
            
            # Convert to list of documents with chunks
            for source, chunks in document_chunks.items():
                # Sort chunks by similarity
                chunks.sort(key=lambda x: x["similarity"], reverse=True)
                
                # Calculate average similarity
                avg_similarity = sum(chunk["similarity"] for chunk in chunks) / len(chunks)
                
                processed_results.append({
                    "source": source,
                    "chunks": chunks[:5],  # Limit to 5 chunks per document
                    "chunk_count": len(chunks),
                    "avg_similarity": avg_similarity
                })
                
            # Sort by average similarity
            processed_results.sort(key=lambda x: x["avg_similarity"], reverse=True)
            
            # Limit to max_results
            processed_results = processed_results[:max_results]
        else:
            # Simple list of chunks
            for i in range(len(ids)):
                # Convert distance to similarity score (cosine distance to similarity)
                similarity = 1 - distances[i]
                
                # Skip results below minimum score
                if similarity < min_score:
                    continue
                    
                processed_results.append({
                    "id": ids[i],
                    "chunk": documents[i][:1000] + ("..." if len(documents[i]) > 1000 else ""),  # Truncate long chunks
                    "metadata": metadatas[i],
                    "similarity": similarity
                })
                
            # Limit to max_results
            processed_results = processed_results[:max_results]
    
    # Return as JSON
    print(f"SUCCESS:{json.dumps(processed_results)}")
    
except Exception as e:
    print(f"ERROR:{str(e)}")
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    
    Write-VectorsLog -Message "Querying document chunks for: $($QueryText.Substring(0, [Math]::Min(50, $QueryText.Length)))..." -Level "Info"
    
    # Execute the Python script
    try {
        $results = python $tempPythonScript 2>&1
        
        # Process the output
        $queryResults = @()
        foreach ($line in $results) {
            if ($line -match "^SUCCESS:(.*)$") {
                $successData = $Matches[1]
                try {
                    $queryResults = ConvertFrom-Json -InputObject $successData -NoEnumerate
                    if ($AggregateByDocument) {
                        Write-VectorsLog -Message "Found $($queryResults.Count) matching documents with relevant chunks" -Level "Info"
                    } else {
                        Write-VectorsLog -Message "Found $($queryResults.Count) matching chunks" -Level "Info"
                    }
                }
                catch {
                    Write-VectorsLog -Message "Failed to parse query results: $($_.Exception.Message)" -Level "Error"
                }
            }
            elseif ($line -match "^ERROR:(.*)$") {
                $errorData = $Matches[1]
                Write-VectorsLog -Message "Query error: $errorData" -Level "Error"
            }
            elseif ($line -match "^INFO:(.*)$") {
                $infoData = $Matches[1]
                Write-VectorsLog -Message $infoData -Level "Debug"
            }
        }

        Remove-Item -Path $tempPythonScript -Force
        return $queryResults
    }
    catch {
        Write-VectorsLog -Message "Failed to execute query: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $tempPythonScript) {
            Remove-Item -Path $tempPythonScript -Force
        }
        
        return @()
    }
}

<#
.SYNOPSIS
    Removes document and its chunks from the vector database
.DESCRIPTION
    Deletes document entries and associated chunks from ChromaDB
.PARAMETER FilePath
    Path to the document file to remove
.PARAMETER DocumentId
    ID of the document to remove (alternative to FilePath)
.EXAMPLE
    Remove-VectorDocument -FilePath "path/to/document.md"
#>
function Remove-VectorDocument {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ParameterSetName="ByPath")]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false, ParameterSetName="ById")]
        [string]$DocumentId
    )
    
    $config = Get-VectorsConfig
    
    # Use Python to remove document
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

    # Create filter based on parameter set
    $whereClause = ""
    $idClause = ""
    
    if ($PSCmdlet.ParameterSetName -eq "ByPath") {
        $whereClause = "where={'source': r'$FilePath'}"
        $docId = [System.IO.Path]::GetFileName($FilePath)
        $idClause = "ids=['$docId']"
    }
    else {
        $idClause = "ids=['$DocumentId']"
    }

    $pythonCode = @"
import os
import sys
import chromadb
from chromadb.config import Settings

try:
    # Setup ChromaDB client
    output_folder = r'$($config.ChromaDbPath)'
    chroma_client = chromadb.PersistentClient(
        path=output_folder, 
        settings=Settings(anonymized_telemetry=False)
    )
    
    # Get the document collection
    doc_collection = chroma_client.get_collection(name="document_collection")
    
    # Get the chunks collection
    chunks_collection = chroma_client.get_collection(name="document_chunks_collection")
    
    # Remove from document collection
    if "$whereClause":
        doc_collection.delete($whereClause)
        print(f"SUCCESS:Removed document using filter: $whereClause")
    elif "$idClause":
        doc_collection.delete($idClause)
        print(f"SUCCESS:Removed document with ID: $DocumentId")
    
    # Remove chunks
    if "$whereClause":
        chunks_collection.delete($whereClause)
        print(f"SUCCESS:Removed associated chunks using filter: $whereClause")
    elif "$idClause":
        # For chunks we need to find all that start with the document ID as a prefix
        try:
            chunks_collection.delete(where={"source": doc_collection.get($idClause)["metadatas"][0]["source"]})
            print(f"SUCCESS:Removed associated chunks for document")
        except Exception as e:
            print(f"INFO:No chunks found for document")
    
except Exception as e:
    print(f"ERROR:{str(e)}")
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    
    Write-VectorsLog -Message "Removing document from vector database" -Level "Info"
    
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
                Write-VectorsLog -Message "Error removing document: $errorData" -Level "Error"
            }
            elseif ($line -match "^INFO:(.*)$") {
                $infoData = $Matches[1]
                Write-VectorsLog -Message $infoData -Level "Info"
            }
        }
        
        # Clean up
        Remove-Item -Path $tempPythonScript -Force
        
        return $success
    }
    catch {
        Write-VectorsLog -Message "Failed to remove document: $($_.Exception.Message)" -Level "Error"
        
        # Clean up
        if (Test-Path -Path $tempPythonScript) {
            Remove-Item -Path $tempPythonScript -Force
        }
        
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Get-VectorDatabaseInfo, Query-VectorDocuments, Query-VectorChunks, Remove-VectorDocument
