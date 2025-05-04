# Ollama-RAG-Sync

A PowerShell project for implementing a Retrieval-Augmented Generation (RAG) system with Ollama, featuring real-time document synchronization capabilities.

## Project Description

Ollama-RAG-Sync is a PowerShell-based solution that enhances local large language models (LLMs) running through Ollama by adding RAG capabilities with live document synchronization. This project creates a pipeline that:

- Monitors designated folders for document changes (adds, updates, deletes)
- Automatically processes and chunks documents as they change
- Creates and maintains vector embeddings of document content
- Provides a simple interface for querying the LLM with relevant context from your document collection
- Works entirely locally, maintaining privacy and security of sensitive documents

## Features

- **Real-time Document Monitoring**: Automatically detects when files are added, modified, or deleted
- **File Tracking System**: Efficiently manages document states and processing status
- **Versatile Document Processing**: Handles multiple file formats including text files and PDFs
- **Smart Text Chunking**: Divides documents into optimal segments for embedding
- **Vector Database Integration**: Uses ChromaDB for efficient similarity search
- **Configurable Embedding Models**: Works with various Ollama embedding models
- **RAG-enhanced Chat Interface**: Simple GUI for interacting with context-aware LLMs
- **Adjustable Relevance Thresholds**: Control precision of document retrieval
- **Context-only Mode**: Force LLM to use only information from the provided document context
- **Fully Local Operation**: No data sent to external services, preserving privacy

## Architecture

The system is organized into several components:

- **FileTracker**: Monitors file changes and maintains a database of file states
- **Processing**: Handles document processing, chunking, and database updates
- **Embeddings**: Generates and manages vector embeddings for document chunks
- **Proxy**: Serves as an API server between the chat interface and the RAG system
- **Conversion**: Utilities for converting between different document formats

## Installation

### Prerequisites

- Windows environment with PowerShell 7.0 or later
- [Ollama](https://ollama.ai/) installed and running locally
   - mxbai-embed-large:latest embedding model
- Python 3.8+ with pip

### Setup

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/Ollama-RAG-Sync.git
   cd Ollama-RAG-Sync
   ```

2. Run the Setup-RAG.ps1 script on your target directory:
   ```powershell
   .\Setup-RAG.ps1 -DirectoryPath "D:\Your\Document\Folder"
   ```

   This will:
   - Create a `.ai` subfolder in your document directory
   - Set up the required databases
   - Initialize the file tracking system
   - Install necessary Python dependencies (ChromaDB, etc.)

## Usage

### Starting the RAG System

Start the RAG system with:

```powershell
.\Start-RAG.ps1 -DirectoryPath "D:\Your\Document\Folder"
```

This will:
- Start the file monitoring service
- Begin processing any changed files
- Launch the API proxy server for RAG functionality

### Optional Parameters

You can customize the behavior with additional parameters:

```powershell
.\Start-RAG.ps1 -DirectoryPath "D:\Your\Document\Folder" `
    -EmbeddingModel "mxbai-embed-large:latest" `
    -ProcessInterval 60 `
    -ChunkSize 1000 `
    -ChunkOverlap 200 `
    -ApiProxyPort 8081 `
    -MaxContextDocs 5 `
    -RelevanceThreshold 0.75 `
    -ContextOnlyMode
```

### Chatting with RAG-Enhanced LLMs

To interact with your documents through the RAG system:

```powershell
.\Chat-RAG.ps1
```

This will open a GUI interface where you can:
- Send queries that will automatically retrieve relevant document context
- View which documents were used as context for each response
- Adjust settings like models and relevance thresholds

## Key Components

- **Setup-RAG.ps1**: Initializes the RAG environment for a specified directory
- **Start-RAG.ps1**: Starts the file monitoring and processing system
- **Chat-RAG.ps1**: Provides a GUI for interacting with the RAG system
- **Process-Collection.ps1**: Processes files that have been marked as changed
- **Update-LocalChromaDb.ps1**: Updates the vector database with new embeddings
- **Get-ChunkEmbeddings.ps1**: Generates embeddings for document chunks
- **Start-RAGProxy.ps1**: Runs the API server that handles RAG operations
- **Start-FileTracker.ps1**: Runs the REST API server for file tracking system

## Documentation

- [Start-RAGProxy Documentation](./Docs/Start-RAGProxy_Documentation.md): Details on configuring and running the RAG proxy server
- [REST API Documentation](./Docs/REST_API_Documentation.md): Comprehensive guide to the REST API endpoints, parameters, and integration examples
- [Get-ChunkEmbeddings README](./Docs/Get-ChunkEmbeddings_README.md): Information about the embedding generation process
- [Process-Collection README](./Docs/Process-Collection_README.md): Documentation for the file processing system
- [Update-LocalChromaDb README](./Docs/Update-LocalChromaDb_README.md): Guide to updating the vector database
- [Get-FileTrackerStatus README](./Docs/Get-FileTrackerStatus_README.md): Documentation for checking file tracking status
- [Init-ProcessorForCollection README](./Docs/Init-ProcessorForCollection_README.md): Guide to initializing custom processors
- [Start-FileTracker Documentation](./Docs/Start-FileTracker_Documentation.md): Information on running the FileTracker API server
- [FileTracker REST API](./Docs/Start-FileTracker_REST_API.md): Documentation for the FileTracker REST API endpoints

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT
