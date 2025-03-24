# Update-LocalChromaDb - Custom File Processor for ChromaDB

`Update-LocalChromaDb.ps1` is a custom file processor designed to work with the Process-DirtyFiles.ps1 system. This script processes various file types and updates a local ChromaDB vector database with their embeddings.

## Overview

This script serves as an example of a custom processor that can be passed to Process-DirtyFiles.ps1. It demonstrates:

1. Processing different file types (PDF, TXT, MD) with custom logic
2. Converting PDF files to text
3. Enhancing content before embedding (e.g., highlighting important terms, enhancing headers)
4. Creating both whole-document embeddings and chunk embeddings
5. Storing embeddings in a local ChromaDB instance with appropriate metadata

## Requirements

- PowerShell 7.0 or higher
- ChromaDB setup locally
- Ollama running locally (or remote URL specified)
- Access to Get-FileEmbedding.ps1 and Get-ChunkEmbeddings.ps1 scripts

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| FilePath | Yes | Path to the file being processed |
| VectorDbPath | Yes | Path to the ChromaDB database |
| OllamaUrl | No | URL for the Ollama API (default: http://localhost:11434) |
| EmbeddingModel | No | Model to use for embeddings (default varies) |
| TempDir | No | Directory for temporary files |
| ScriptPath | No | Path to the root directory containing supporting scripts |
| CustomParam1 | No | Custom parameter for script configuration |
| CustomParam2 | No | Custom parameter for script configuration |

## File Type Processing

### PDF Files
- Converts PDF to markdown using Convert-PDFToMarkdown.ps1
- Adds custom metadata/headers to the converted content
- Creates both whole-document embeddings and chunk embeddings
- Stores all embeddings in ChromaDB

### Text Files (.txt)
- Processes the content by highlighting important terms
- Replaces words like "important" with "IMPORTANT" and "urgent" with "URGENT"
- Creates both whole-document embeddings and chunk embeddings
- Stores all embeddings in ChromaDB

### Markdown Files (.md)
- Enhances headers by adding "[Enhanced]" to each heading
- Creates both whole-document embeddings and chunk embeddings
- Stores all embeddings in ChromaDB

### Other File Types
- Attempts to process if the file is text-based
- If successful, creates whole-document embeddings and chunk embeddings
- Stores all embeddings in ChromaDB
- Logs an error if the file cannot be read as text

## Custom Logging

The script includes a custom logging function (`Write-CustomLog`) that:
- Timestamps all log messages
- Identifies the source as "CUSTOM" to distinguish from other system logs
- Includes appropriate severity level (INFO, WARNING, ERROR)
- Writes to both console and a file-specific log

## Usage Examples

### Basic Usage with Process-DirtyFiles.ps1

```powershell
# Process dirty files using this custom processor
.\Processing\Process-DirtyFiles.ps1 -DirectoryPath "D:\Documents" `
    -ProcessorScript ".\Processing\Update-LocalChromaDb.ps1" 
```

### With Custom Parameters

```powershell
# Using custom parameters to modify processing behavior
.\Processing\Process-DirtyFiles.ps1 -DirectoryPath "D:\Documents" `
    -ProcessorScript ".\Processing\Update-LocalChromaDb.ps1" `
    -ProcessorScriptParams @{
        CustomParam1 = "EnhanceHeadings"
        CustomParam2 = "HighlightKeywords"
    }
```

### Direct Usage

The script can also be called directly for testing or one-off processing:

```powershell
# Direct usage example
.\Processing\Update-LocalChromaDb.ps1 `
    -FilePath "D:\Documents\example.pdf" `
    -VectorDbPath "D:\Repository\.ai\Vectors" `
    -OllamaUrl "http://localhost:11434" `
    -EmbeddingModel "mxbai-embed-large:latest" `
    -TempDir "D:\Repository\.ai\temp" `
    -ScriptPath "D:\Repository" `
    -CustomParam1 "Value1" `
    -CustomParam2 "Value2"
```

## Customization Options

This script is designed to be used as a template that you can customize for your specific needs:

1. **Custom File Processing**: Modify the switch statement to handle additional file types or change processing logic
2. **Custom Parameters**: Add or modify the parameters to control processing behavior
3. **Pre-processing Logic**: Enhance the content transformation logic to better suit your requirements
4. **Integration**: Modify how it interfaces with ChromaDB or other systems

## Dual Embedding Approach

This processor demonstrates a dual approach to embeddings:

1. **Whole-document embeddings** using Get-FileEmbedding.ps1:
   - Best for capturing overall document topics and themes
   - Useful for finding generally related documents
   - Stored in the "document_collection" collection

2. **Chunk-based embeddings** using Get-ChunkEmbeddings.ps1:
   - Better for finding specific information within documents
   - Includes line number tracking for source attribution
   - Enables more precise retrieval of relevant context
   - Stored in the "document_chunks_collection" collection

The Start-RAGProxy.ps1 can be configured to use either or both collections with weighted scoring.

## Integration with Other Components

This script integrates with several other components from the RAG-Sync system:

- **Get-FileEmbedding.ps1**: Used to create whole-document embeddings
- **Get-ChunkEmbeddings.ps1**: Used to split documents into chunks and create embeddings for each
- **Convert-PDFToMarkdown.ps1**: Used to convert PDF files to markdown text
- **Process-DirtyFiles.ps1**: The main script that calls this processor
- **FileTracker**: Indirectly integrated through Process-DirtyFiles.ps1

## Processing Flow Diagram

```
[Input File] → [File Type Detection] → [Type-Specific Processing] 
→ [Content Enhancement] → [Get-FileEmbedding.ps1] → [ChromaDB/document_collection]
                       → [Get-ChunkEmbeddings.ps1] → [ChromaDB/document_chunks_collection]
```

## Troubleshooting

- Check that the VectorDbPath is valid and accessible
- Verify Ollama is running at the specified URL
- Check that supporting scripts (Get-FileEmbedding.ps1, Get-ChunkEmbeddings.ps1, etc.) are accessible at the ScriptPath
- Review console output and log files for detailed error messages
- Ensure temporary directory (TempDir) exists and is writable
- For PDF conversion issues, check the conversion logs in the temp directory

## Notes

- This script is designed as an example custom processor for the Process-DirtyFiles.ps1 system
- It demonstrates proper parameter handling, logging, and integration with other system components
- The dual embedding approach provides flexibility in how documents are retrieved and used in RAG systems
- For production use, consider adding more robust error handling and recovery mechanisms
