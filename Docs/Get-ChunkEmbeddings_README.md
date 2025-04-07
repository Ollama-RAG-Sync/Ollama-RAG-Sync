# Get-ChunkEmbeddings.ps1

This script creates embedding vectors for multiple chunks of a specified text file, using the Ollama API for generating embeddings. It's an enhancement over Get-FileEmbedding.ps1 that provides better semantic search capabilities by splitting documents into smaller, overlapping chunks.

## Prerequisites

- PowerShell 7.0 or higher
- Python 3.8 or higher
- Ollama running locally or at a specified URL
- An embedding model available in your Ollama installation (default: mxbai-embed-large:latest)

## Parameters

- **FilePath** (Required): Path to the text file to generate embeddings for
- **ChromaDbPath** (Required): Path to the ChromaDB directory
- **ChunkSize** (Optional, Default: 1000): The target size (in characters) for each chunk
- **ChunkOverlap** (Optional, Default: 200): The amount of overlap between chunks
- **Extensions** (Optional, Default: ".txt,.md,.html,.csv,.json"): Comma-separated list of supported file extensions
- **OllamaUrl** (Optional, Default: "http://localhost:11434"): URL for the Ollama API
- **EmbeddingModel** (Optional, Default: "mxbai-embed-large:latest"): Ollama model to use for embeddings
- **SaveToChroma** (Switch): If specified, save embeddings to ChromaDB instead of returning them

## How It Works

1. The script reads the specified text file
2. It splits the content into chunks based on the ChunkSize and ChunkOverlap parameters, tracking line numbers for each chunk
3. For each chunk, it generates an embedding vector using the Ollama API
4. If SaveToChroma is specified, it stores these chunks and their embeddings in a ChromaDB collection named "document_chunks_collection"
5. Otherwise, it returns the chunks and their embeddings as PowerShell objects

## Chunking Logic

The chunking algorithm follows these principles:
- Tries to split at natural paragraph boundaries when possible
- Ensures chunks don't exceed the specified size
- Maintains context between chunks with the specified overlap
- For very large paragraphs, splits at word boundaries
- Tracks the start and end line numbers for each chunk, which is crucial for source attribution in RAG systems

## Metadata Tracking

Each chunk stored in ChromaDB includes metadata that enhances retrieval:
- **source**: The full file path to the source document
- **chunk_id**: Sequential ID of the chunk within the document
- **total_chunks**: Total number of chunks the document was split into
- **start_line**: First line number in the original document
- **end_line**: Last line number in the original document
- **line_range**: String representation of the line range (e.g., "10-15")

This metadata is particularly useful for the RAG proxy, which can show users exactly which parts of which documents were used to generate responses.

## Integration with Process-DirtyFiles

Get-ChunkEmbeddings.ps1 is integrated with the Process-DirtyFiles.ps1 system, which can be configured to use chunking via the UseChunking parameter:

```powershell
.\Processing\Process-DirtyFiles.ps1 -DirectoryPath "path/to/folder" -UseChunking $true -ChunkSize 1000 -ChunkOverlap 200
```

## Benefits of Chunking

- **Improved retrieval precision**: Smaller chunks make it easier to find specific information
- **Better context handling**: Overlapping chunks preserve context between segments
- **More accurate embeddings**: Embedding models often perform better on shorter, focused text
- **Enhanced semantic search**: Find relevant information even in long documents
- **Source attribution**: Line number tracking allows linking retrieved information back to its exact location

## Python Dependencies

The script requires the following Python packages:
- requests (for HTTP communication with Ollama)
- chromadb (if saving to ChromaDB)
- numpy (required by ChromaDB)

Make sure these packages are installed in your Python environment before running the script.
