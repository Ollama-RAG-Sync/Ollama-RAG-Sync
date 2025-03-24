# Ollama-RAG-Sync REST API Documentation

The Ollama-RAG-Sync project provides a REST API server that enables interaction with the RAG system. This API allows applications to query documents, retrieve relevant context, and generate LLM responses using document context.

## API Server Overview

The REST API server is implemented by the `Start-RAGProxy.ps1` script, which creates a lightweight HTTP server that:

1. Provides endpoints for searching document collections
2. Retrieves relevant context for user queries
3. Interfaces with Ollama to generate context-enhanced responses
4. Offers model information and system statistics

## Starting the API Server

To start the API server, use:

```powershell
./Start-RAGProxy.ps1 -DirectoryPath "D:\Your\Document\Folder"
```

See [Start-RAGProxy Documentation](./Start-RAGProxy_Documentation.md) for complete configuration options.

## Authentication and Security

By default, the API server binds to `localhost` only and does not require authentication. This configuration is suitable for development and local use. For production environments, consider:

- Using the `-UseHttps` switch to enable HTTPS (requires certificate)
- Implementing a reverse proxy with authentication if exposing the API outside localhost
- Setting `-ListenAddress` to a specific interface rather than all interfaces

## Base URL

All API endpoints are relative to the base URL: `http://localhost:8081/` (or your configured host/port)

## API Endpoints

### 1. Server Information

**GET /**

Returns basic information about the API server.

**Response Example:**

```json
{
  "status": "ok",
  "message": "API proxy running",
  "contextOnlyMode": false,
  "routes": [
    "/api/chat - POST: Chat with context augmentation",
    "/api/search - POST: Search for relevant documents",
    "/api/models - GET: Get list of available models",
    "/api/stats - GET: Get statistics about ChromaDB collections",
    "/status - GET: Get API proxy status (includes Context-only Mode status)"
  ]
}
```

### 2. Chat with Context

**POST /api/chat**

Main endpoint for generating LLM responses with document context augmentation.

**Request Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| messages | array | Yes | - | Array of message objects with role and content (follows OpenAI format) |
| model | string | No | llama3 | Ollama model name to use for generation |
| max_context_docs | integer | No | 5 | Maximum number of document chunks to include as context |
| threshold | float | No | 0.75 | Minimum similarity threshold (0-1) for including context |
| enhance_context | boolean | No | true | Whether to retrieve and include document context |
| temperature | float | No | 0.7 | Temperature for LLM response generation |
| num_ctx | integer | No | 40000 | Context window size for Ollama model |
| query_mode | string | No | both | Which collections to query: "chunks", "documents", or "both" |
| chunk_weight | float | No | 0.6 | Weight for chunk results when using "both" mode |
| document_weight | float | No | 0.4 | Weight for document results when using "both" mode |

**Request Body Example:**

```json
{
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What is RAG and how does it improve LLM responses?"}
  ],
  "model": "llama3",
  "max_context_docs": 5,
  "threshold": 0.75,
  "enhance_context": true,
  "temperature": 0.7
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| id | string | Response identifier |
| object | string | Object type (typically "chat.completion") |
| created | integer | Unix timestamp when the response was created |
| model | string | Model name used for generation |
| message | object | Response message with role and content |
| context_count | integer | Number of document chunks used as context |
| context_info | array | Information about the sources used for context |

**Response Example:**

```json
{
  "id": "chatcmpl-123456789",
  "object": "chat.completion",
  "created": 1679351234,
  "model": "llama3",
  "message": {
    "role": "assistant",
    "content": "RAG (Retrieval Augmented Generation) is a technique that enhances LLM responses by retrieving relevant documents or information from a knowledge base before generating an answer. It improves LLM responses in several ways:\n\n1. **Accuracy**: By providing the model with relevant context, RAG ensures the model has the most up-to-date and specific information.\n\n2. **Reduced hallucinations**: Since the model can reference actual documents, it's less likely to generate incorrect or made-up information.\n\n3. **Knowledge updates**: You can update the knowledge base without retraining the entire model.\n\n4. **Domain specificity**: RAG allows general models to give domain-specific responses based on your documents."
  },
  "context_count": 3,
  "context_info": [
    {
      "source": "rag_overview.md",
      "line_range": "10-25",
      "similarity": 0.89
    },
    {
      "source": "llm_optimization.md",
      "line_range": "45-60",
      "similarity": 0.82
    },
    {
      "source": "vector_databases.md",
      "line_range": "30-42",
      "similarity": 0.77
    }
  ]
}
```

**Error Responses:**

- `400 Bad Request`: Missing required parameters
- `404 Not Found`: Model not found
- `500 Internal Server Error`: Server error during processing

### 3. Document Search

**POST /api/search**

Search for relevant documents without generating a response.

**Request Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| query | string | Yes | - | The query text to search for |
| max_results | integer | No | 5 | Maximum number of results to return |
| threshold | float | No | 0.75 | Minimum similarity threshold (0-1) |
| query_mode | string | No | both | Which collections to query: "chunks", "documents", or "both" |
| chunk_weight | float | No | 0.6 | Weight for chunk results when using "both" mode |
| document_weight | float | No | 0.4 | Weight for document results when using "both" mode |

**Request Body Example:**

```json
{
  "query": "How does vector similarity search work?",
  "max_results": 3,
  "threshold": 0.7
}
```

**Response Example:**

```json
{
  "success": true,
  "query": "How does vector similarity search work?",
  "results": [
    {
      "document": "Vector similarity search works by comparing the distance between vectors in a high-dimensional space. Common distance metrics include cosine similarity, Euclidean distance, and dot product. The closer two vectors are in this space, the more similar the content they represent is likely to be.",
      "metadata": {
        "source": "D:/Documents/vector_search.md",
        "line_range": "15-20",
        "type": "markdown"
      },
      "similarity": 0.92,
      "is_chunk": true
    },
    {
      "document": "Efficient vector search is typically implemented using approximate nearest neighbor algorithms like HNSW (Hierarchical Navigable Small World) or IVF (Inverted File Index). These algorithms enable fast retrieval from large vector collections by organizing vectors into graph structures or clusters.",
      "metadata": {
        "source": "D:/Documents/vector_algorithms.md",
        "line_range": "25-30",
        "type": "markdown"
      },
      "similarity": 0.85,
      "is_chunk": true
    }
  ],
  "count": 2
}
```

### 4. Available Models

**GET /api/models**

Get a list of available models from Ollama.

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| include_details | boolean | No | false | Include model details beyond just names |

**Example Request:**

```
GET /api/models?include_details=true
```

**Response Example (include_details=false):**

```json
{
  "models": [
    "llama3",
    "llama3:8b",
    "mistral",
    "codellama",
    "mxbai-embed-large"
  ],
  "count": 5
}
```

**Response Example (include_details=true):**

```json
{
  "models": [
    {
      "name": "llama3",
      "modified_at": "2024-03-01T12:34:56Z",
      "size": 8053063680,
      "digest": "sha256:abc123...",
      "details": {
        "family": "llama",
        "parameter_size": "8B",
        "quantization_level": "Q5_K_M"
      }
    },
    {
      "name": "mistral",
      "modified_at": "2024-02-15T09:12:34Z",
      "size": 4939212800,
      "digest": "sha256:def456...",
      "details": {
        "family": "mistral",
        "parameter_size": "7B",
        "quantization_level": "Q4_K_M"
      }
    }
  ],
  "count": 2
}
```

### 5. ChromaDB Collection Statistics

**GET /api/stats**

Get statistics about the ChromaDB collections used by the system.

**Response Example:**

```json
{
  "success": true,
  "stats": {
    "total_collections": 2,
    "total_items": 1250,
    "collections": [
      {
        "name": "document_collection",
        "count": 150,
        "sample_metadata": {
          "source": "D:/Documents/example.md",
          "type": "markdown",
          "created_at": "2024-03-15T10:30:00Z"
        }
      },
      {
        "name": "document_chunks_collection",
        "count": 1100,
        "sample_metadata": {
          "source": "D:/Documents/example.md",
          "start_line": 1,
          "end_line": 10,
          "line_range": "1-10",
          "type": "markdown"
        }
      }
    ]
  }
}
```

### 6. API Status

**GET /status**

Get detailed status information about the API server.

**Response Example:**

```json
{
  "status": "ok",
  "vectorDbPath": "D:/Your/Document/Folder/.ai/Vectors",
  "ollamaUrl": "http://localhost:11434",
  "embeddingModel": "mxbai-embed-large:latest",
  "relevanceThreshold": 0.75,
  "maxContextDocs": 5,
  "defaultTemperature": 0.7,
  "defaultNumCtx": 40000,
  "contextOnlyMode": false
}
```

## Context-Only Mode

When the API server is started with the `-ContextOnlyMode` switch, responses from the `/api/chat` endpoint will be limited to information found in the provided context only. The LLM will not use its general knowledge to answer questions.

In this mode, the system message sent to the LLM is modified to include specific instructions to:
- Only use information from the provided context
- Not use any built-in knowledge or training data
- Respond with "I don't have enough information in the provided context" when the context doesn't contain relevant information

This mode is useful for:
- Creating strict knowledge-grounded responses
- Ensuring compliance with regulatory requirements
- Preventing the LLM from using outdated or incorrect information from its training data

## Integration Examples

### Python Client Example

```python
import requests
import json

def query_rag_api(query, model="llama3"):
    url = "http://localhost:8081/api/chat"
    
    payload = {
        "messages": [
            {"role": "user", "content": query}
        ],
        "model": model,
        "max_context_docs": 5,
        "threshold": 0.75
    }
    
    response = requests.post(url, json=payload)
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Error: {response.status_code}")
        print(response.text)
        return None

# Example usage
result = query_rag_api("What are the benefits of RAG for legal document analysis?")
print(result["message"]["content"])

# Print sources used
print("\nSources:")
for source in result["context_info"]:
    print(f"- {source['source']} (lines {source['line_range']}, similarity: {source['similarity']:.2f})")
```

### PowerShell Client Example

```powershell
function Invoke-RagQuery {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$false)]
        [string]$Model = "llama3",
        
        [Parameter(Mandatory=$false)]
        [string]$ServerUrl = "http://localhost:8081"
    )
    
    $payload = @{
        messages = @(
            @{
                role = "user"
                content = $Query
            }
        )
        model = $Model
        max_context_docs = 5
        threshold = 0.75
    }
    
    $response = Invoke-RestMethod -Uri "$ServerUrl/api/chat" -Method Post -Body ($payload | ConvertTo-Json) -ContentType "application/json"
    
    # Return response
    return $response
}

# Example usage
$result = Invoke-RagQuery -Query "How does vector similarity search work?"

# Display result
Write-Host $result.message.content

# Display sources
Write-Host "`nSources:"
foreach ($source in $result.context_info) {
    Write-Host "- $($source.source) (lines $($source.line_range), similarity: $([math]::Round($source.similarity, 2)))"
}
```

## Error Handling

The API uses standard HTTP status codes to indicate success or failure:

- `200 OK`: Request succeeded
- `400 Bad Request`: Missing required parameters or invalid request format
- `404 Not Found`: Requested resource not found (e.g., model, collection)
- `405 Method Not Allowed`: Wrong HTTP method used for the endpoint
- `500 Internal Server Error`: Server-side error during processing

Error responses include a JSON body with `error` and `message` fields:

```json
{
  "error": "Bad request",
  "message": "Required parameter missing: messages"
}
```

## Rate Limiting and Performance

The API server does not implement rate limiting by default. Consider:

- For high-traffic deployments, implement a reverse proxy with rate limiting
- Response times are primarily determined by:
  - Vector search performance (affected by database size)
  - Ollama LLM inference speed (affected by model size and hardware)

## Streaming Responses

Currently, the API does not support streaming responses. All responses are returned as complete JSON objects once processing is finished.
