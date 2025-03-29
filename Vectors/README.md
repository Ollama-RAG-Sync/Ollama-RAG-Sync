# Vectors Subsystem

The Vectors subsystem provides functionality for storing and querying documents using vector embeddings. It leverages ChromaDB for vector storage and Ollama for generating embeddings.

## Overview

The Vectors subsystem allows you to:

- Store document embeddings in a vector database
- Generate embeddings for entire documents and document chunks
- Query for similar documents based on semantic similarity
- Query for specific chunks of documents relevant to a search
- Manage documents in the vector database

## Components

The subsystem consists of the following components:

### Core Modules

- **Vectors-Core.psm1**: Core functionality, configuration, logging, and utility functions
- **Vectors-Database.psm1**: ChromaDB interaction for storing and querying vectors
- **Vectors-Embeddings.psm1**: Functions for generating embeddings using Ollama

### Function Scripts

- **Add-DocumentToVectors.ps1**: Add a document to the vector database
- **Get-DocumentsByQuery.ps1**: Retrieve documents similar to a query
- **Get-ChunksByQuery.ps1**: Retrieve document chunks similar to a query
- **Remove-DocumentFromVectors.ps1**: Remove documents from the vector database

### Main Script

- **Start-Vectors.ps1**: Main entry point for initializing and using the Vectors subsystem

## Requirements

- PowerShell 7.0 or higher
- Python 3.8 or higher
- Ollama running locally or accessible via URL
- ChromaDB Python package (`pip install chromadb`)

## Getting Started

1. Ensure Ollama is running (default: http://localhost:11434)
2. Ensure you have the ChromaDB Python package installed
3. Initialize the Vectors subsystem:

```powershell
.\Start-Vectors.ps1 -Initialize
```

## Usage Examples

### Adding Documents

To add a document to the vector database:

```powershell
.\Functions\Add-DocumentToVectors.ps1 -FilePath "path/to/document.md"
```

You can specify custom chunk sizes and overlap:

```powershell
.\Functions\Add-DocumentToVectors.ps1 -FilePath "path/to/document.md" -ChunkSize 500 -ChunkOverlap 100
```

### Querying Documents

To search for documents similar to a query:

```powershell
.\Functions\Get-DocumentsByQuery.ps1 -QueryText "Your search query here"
```

To get the source content along with results:

```powershell
.\Functions\Get-DocumentsByQuery.ps1 -QueryText "Your search query here" -ReturnSourceContent
```

### Querying Chunks

To search for specific chunks similar to a query:

```powershell
.\Functions\Get-ChunksByQuery.ps1 -QueryText "Your search query here"
```

To aggregate chunks by document (useful for summarizing results):

```powershell
.\Functions\Get-ChunksByQuery.ps1 -QueryText "Your search query here" -AggregateByDocument
```

### Removing Documents

To remove a document from the vector database:

```powershell
.\Functions\Remove-DocumentFromVectors.ps1 -FilePath "path/to/document.md"
```

Or by document ID:

```powershell
.\Functions\Remove-DocumentFromVectors.ps1 -DocumentId "document_id"
```

## Configuration

You can configure the Vectors subsystem by passing parameters to the Start-Vectors.ps1 script:

```powershell
.\Start-Vectors.ps1 -ChromaDbPath "path/to/chromadb" -OllamaUrl "http://localhost:11434" -EmbeddingModel "mxbai-embed-large:latest" -ChunkSize 1000 -ChunkOverlap 200
```

## Integration with Ollama-RAG-Sync

The Vectors subsystem is designed to integrate with the Ollama-RAG-Sync system. It provides the vector database capabilities needed for the RAG (Retrieval-Augmented Generation) workflow.
