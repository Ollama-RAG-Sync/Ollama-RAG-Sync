# Process-Collection.ps1

This script processes files in a specified collection that have been marked as "dirty" (needing processing) in the FileTracker database. It's a key component in the Ollama-RAG-Sync pipeline that manages the processing of new and modified files.

## Overview

Process-Collection.ps1 retrieves all files marked as dirty in a collection, processes them according to registered handlers, and updates their status in the database. The script provides flexible processing options including chunk-based embedding generation and custom processing logic.

## Prerequisites

- PowerShell 7.0 or higher
- Access to a FileTracker database
- Ollama running locally or at a specified URL
- Default or custom collection handlers registered using Init-ProcessorForCollection.ps1

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| CollectionId | int | Yes* | - | ID of the collection to process (*Either CollectionId or CollectionName is required) |
| CollectionName | string | Yes* | - | Name of the collection to process (*Either CollectionId or CollectionName is required) |
| DatabasePath | string | No | Auto-detected | Path to the FileTracker SQLite database |
| VectorDbPath | string | No | "[DatabasePath]/../Vectors" | Path to store vector embeddings |
| OllamaUrl | string | No | "http://localhost:11434" | URL for the Ollama API |
| EmbeddingModel | string | No | "mxbai-embed-large:latest" | Model to use for embeddings |
| UseChunking | bool | No | $true | Whether to use chunking for document processing |
| ChunkSize | int | No | 1000 | Size of chunks (in characters) |
| ChunkOverlap | int | No | 200 | Overlap between chunks (in characters) |
| DirectProcess | bool | No | $false | Process files directly without using registered handlers |
| Verbose | switch | No | $false | Enable verbose logging |

## Usage Examples

### Basic Usage

```powershell
# Process a collection by ID
.\Processor\Process-Collection.ps1 -CollectionId 1

# Process a collection by name
.\Processor\Process-Collection.ps1 -CollectionName "Documentation"
```

### Advanced Usage

```powershell
# Process with custom parameters
.\Processor\Process-Collection.ps1 -CollectionName "Documentation" `
    -OllamaUrl "http://192.168.1.100:11434" `
    -EmbeddingModel "nomic-embed-text" `
    -UseChunking $true `
    -ChunkSize 1500 `
    -ChunkOverlap 300 `
    -Verbose
```

### Direct Processing

```powershell
# Process files directly without using registered handlers
.\Processor\Process-Collection.ps1 -CollectionId 2 -DirectProcess
```

## Processing Flow

1. **Initialization**: 
   - Connect to the FileTracker database
   - Identify the collection to process
   - Load registered handlers or use defaults

2. **File Retrieval**:
   - Query all files marked as dirty in the specified collection
   - Skip files marked as deleted

3. **Processing Loop**:
   - For each dirty file, determine file type
   - Apply appropriate preprocessing
   - Generate embeddings (document-level and/or chunk-level)
   - Store embeddings in vector database
   - Update file status in FileTracker database

4. **Cleanup**:
   - Close database connections
   - Report processing statistics

## Handler System

The Process-Collection.ps1 script integrates with the handler system established by Init-ProcessorForCollection.ps1. Handlers allow customized processing based on file types and collection requirements:

1. **Default Handler**: If no custom handler is registered, a default handler processes basic text files
2. **Custom Handlers**: Registered through Init-ProcessorForCollection.ps1 for specialized processing
3. **Direct Processing**: The -DirectProcess parameter bypasses the handler system for simple embedding generation

## Integration with Other Components

Process-Collection.ps1 integrates with several other components from the RAG-Sync system:

- **FileTracker Database**: Retrieves dirty files and updates their status
- **Get-FileEmbedding.ps1** / **Get-ChunkEmbeddings.ps1**: Generate embeddings
- **Update-LocalChromaDb.ps1**: One example of a custom processor
- **Start-Processor.ps1**: Can call Process-Collection.ps1 periodically
- **FileTracker API**: Can trigger processing via the API

## Common Issues

1. **Missing Files**: If files are marked as dirty but no longer exist, the script logs an error but continues processing other files
2. **Database Locking**: If multiple processes access the database, locking issues may occur. The script implements retry logic
3. **Memory Usage**: Processing large collections with chunking enabled can use significant memory. Consider processing collections in batches

## Logging

The script logs operations to the console with timestamps and severity levels:

```
[2025-03-30 09:15:30 INFO] Starting processing for collection 'Documentation' (ID: 1)
[2025-03-30 09:15:32 INFO] Processing file: D:\Documents\example.md
[2025-03-30 09:15:35 INFO] Successfully processed 15 files, 2 files failed
```

When the -Verbose switch is used, additional details about each processing step are logged.
