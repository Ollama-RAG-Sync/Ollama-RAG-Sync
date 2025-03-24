# Start-RAGProxy Documentation

The Start-RAGProxy script creates a REST API proxy server that provides a `/api/chat` endpoint. The proxy uses ChromaDB for vector search to find relevant context related to user queries, and forwards enhanced prompts to the Ollama REST API.

## Requirements

- PowerShell 7.0 or higher
- Python 3.8 or higher
- Ollama (running locally or accessible via network)
- ChromaDB (will be used by the proxy)

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| ListenAddress | string | No | localhost | The IP address the server should listen on |
| Port | int | No | 8081 | The port the server should listen on |
| DirectoryPath | string | Yes | - | Path to the directory containing the `.ai` folder with vector database |
| OllamaBaseUrl | string | No | http://localhost:11434 | Base URL for the Ollama API |
| EmbeddingModel | string | No | mxbai-embed-large:latest | Model to use for generating embeddings |
| RelevanceThreshold | decimal | No | 0.75 | Minimum similarity score for context |
| MaxContextDocs | int | No | 5 | Maximum number of context documents to include |
| QueryMode | string | No | both | Mode for querying: "chunks", "documents", or "both" |
| ChunkWeight | double | No | 0.6 | Weight for chunk results when using "both" mode |
| DocumentWeight | double | No | 0.4 | Weight for document results when using "both" mode |
| UseHttps | switch | No | false | Use HTTPS instead of HTTP (requires certificate) |
| ContextOnlyMode | switch | No | false | Instruct LLM to use ONLY information from provided context |

## Usage

Basic usage:

```powershell
./Start-RAGProxy.ps1 -DirectoryPath "C:/Path/To/Documents"
```

With custom port and Ollama URL:

```powershell
./Start-RAGProxy.ps1 -DirectoryPath "C:/Path/To/Documents" -Port 8082 -OllamaBaseUrl "http://192.168.1.100:11434"
```

Using Context-only Mode:

```powershell
./Start-RAGProxy.ps1 -DirectoryPath "C:/Path/To/Documents" -ContextOnlyMode
```

## API Endpoints

### GET /

Returns basic information about the API.

### POST /api/chat

Main endpoint for chat with context augmentation.

**Request Body:**

```json
{
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What are the benefits of RAG?"}
  ],
  "model": "llama3",
  "max_context_docs": 5,
  "threshold": 0.75,
  "enhance_context": true,
  "temperature": 0.7,
  "num_ctx": 40000
}
```

**Response:**

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1679351234,
  "model": "llama3",
  "message": {
    "role": "assistant",
    "content": "RAG (Retrieval Augmented Generation) offers several benefits..."
  },
  "context_count": 3,
  "context_info": [
    {
      "source": "rag_benefits.md",
      "line_range": "10-25",
      "similarity": 0.89
    },
    ...
  ]
}
```

When using Context-only Mode, the response will be limited to information from the provided context:

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1679351234,
  "model": "llama3",
  "message": {
    "role": "assistant",
    "content": "Based solely on the provided context, RAG offers these benefits: 1) improved answer accuracy by retrieving relevant information, 2) reduced hallucinations since answers are grounded in retrieved content, 3) knowledge updates without retraining the model..."
  },
  "context_count": 3,
  "context_info": [
    {
      "source": "rag_benefits.md",
      "line_range": "10-25",
      "similarity": 0.89
    },
    ...
  ]
}
```

### POST /api/search

Search for relevant documents without generating a response.

### GET /api/models

Get list of available models from Ollama.

### GET /api/stats

Get statistics about ChromaDB collections.

### GET /status

Get API proxy status.

## Context-only Mode

The Context-only Mode is a special operating mode that instructs the LLM to use ONLY the information from the provided context when generating responses. This can be useful for:

1. Creating strict knowledge-grounded responses that only use information from your documents
2. Preventing the LLM from using its built-in knowledge to answer questions
3. Ensuring compliance with regulatory requirements by limiting responses to approved content
4. Testing RAG functionality without the risk of "hallucinations" or made-up information

When in Context-only Mode, the LLM will:
- Be explicitly instructed to only use information from the provided context
- Respond with "I don't have enough information in the provided context to answer this question" when the context doesn't contain relevant information
- Not use its built-in knowledge or training data to supplement answers

The response still comes from the LLM, but the system message is modified to enforce these restrictions. The API response will include all the same metadata as normal mode, including:
- Context count and information
- Source documents and similarity scores
- All standard LLM response fields

Enable Context-only Mode by adding the `-ContextOnlyMode` switch when starting the server.
