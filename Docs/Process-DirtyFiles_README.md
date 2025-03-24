# Process-DirtyFiles - File Processing System

This system provides an automated workflow for processing files in a monitored directory. It specifically handles:

1. Processing "dirty" (new or modified) files that need attention
2. Converting PDF files to Markdown format for better text processing
3. Creating embeddings for text files and storing them in a ChromaDB vector database
4. Removing deleted files from the ChromaDB database
5. Optionally chunking files for more precise retrieval

## System Components

### Main Scripts

- **Process-DirtyFiles.ps1**: The main script that processes dirty files
- **TestProcessDirtyFiles.ps1**: A helper script for testing and demonstrating the workflow

### Dependencies

The system integrates with several existing components:

- **FileTracker**: Tracks file changes and maintains dirty/processed status
- **Conversion**: Provides PDF to Markdown conversion functionality
- **Get-FileEmbedding.ps1**: Creates embeddings for whole text files and stores them in ChromaDB
- **Get-ChunkEmbeddings.ps1**: Splits documents into chunks and creates embeddings for each chunk

## Requirements

- PowerShell 7.0 or higher
- Python 3.8 or higher
- Ollama running locally (or specified remote URL) for generating embeddings
- Required Python packages:
  - chromadb
  - requests
  - numpy
  - pymupdf (for PDF conversion)

## How It Works

1. **File Tracking**:
   - The FileTracker system monitors files in a specified directory
   - When files are created, modified, or deleted, they are marked as "dirty" in a SQLite database

2. **Processing**:
   - The `Process-DirtyFiles.ps1` script queries the tracker database for dirty files
   - For each dirty file:
     - If the file no longer exists (was deleted), it's removed from the ChromaDB
     - If it's a PDF file, it's converted to Markdown
     - Text files (including converted PDFs) are processed to create embeddings
     - When chunking is enabled, documents are split into smaller segments with overlaps
     - Embeddings are stored in ChromaDB for later retrieval
   - Once processed, files are marked as "clean" in the tracker database

## Usage

### Basic Usage

```powershell
# Process all dirty files in a folder
.\Processing\Process-DirtyFiles.ps1 -DirectoryPath "D:\Documents"
```

### Complete Workflow Example

```powershell
# Initialize file tracking for a folder (only needed once)
.\FileTracker\Initialize-FileTracker.ps1 -FolderPath "D:\Documents"

# Mark specific files as dirty (normally done automatically by FileWatcher)
.\FileTracker\Mark-FileAsDirty.ps1 -FolderPath "D:\Documents" -FilePath "D:\Documents\example.pdf"

# Process all dirty files
.\Processing\Process-DirtyFiles.ps1 -DirectoryPath "D:\Documents"
```

### Using the Test Helper

The included `TestProcessDirtyFiles.ps1` script makes it easy to test the system:

```powershell
# Initialize tracker
.\Tests\TestProcessDirtyFiles.ps1 -FolderToMonitor "D:\Documents" -InitializeTracker

# Mark a file as dirty
.\Tests\TestProcessDirtyFiles.ps1 -FolderToMonitor "D:\Documents" -MarkFileAsDirty -FileToMark "D:\Documents\example.pdf"

# Process all dirty files
.\Tests\TestProcessDirtyFiles.ps1 -FolderToMonitor "D:\Documents" -ProcessDirtyFiles
```

## Configuration Options

### Process-DirtyFiles.ps1 Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| DirectoryPath | The folder to monitor for dirty files | (Required) |
| OllamaUrl | URL for Ollama API | http://localhost:11434 |
| EmbeddingModel | Model to use for embeddings | mxbai-embed-large:latest |
| TextFileExtensions | Comma-separated list of text file extensions | .txt,.md,.html,.csv,.json |
| PDFFileExtension | PDF file extension | .pdf |
| ProcessorScript | Path to a custom processor script | (None) |
| ProcessorScriptParams | Hashtable of additional parameters to pass to the processor script | @{} |
| UseChunking | Whether to use chunking for text files | $true |
| ChunkSize | Size of chunks when using chunking | 1000 |
| ChunkOverlap | Overlap between chunks | 200 |
| ProcessInterval | Minutes between processing runs when in continuous mode | 5 |
| Continuous | Run in continuous mode, checking regularly for dirty files | $false |
| StopFilePath | Path to a file that signals the script to stop processing | .stop_processing |

## Continuous Mode

When run with the `-Continuous` switch, the script will:

1. Process all current dirty files
2. Wait for the specified `ProcessInterval` (in minutes)
3. Check for new dirty files and process them
4. Continue this cycle until stopped

You can create a stop file at the path specified by `StopFilePath` to gracefully stop the continuous processing.

```powershell
# Start continuous processing
.\Processing\Process-DirtyFiles.ps1 -DirectoryPath "D:\Documents" -Continuous -ProcessInterval 10

# In another window, to stop processing:
New-Item -Path "D:\Documents\.stop_processing" -ItemType File -Force
```

## Custom Processor Scripts

One of the key features of Process-DirtyFiles.ps1 is the ability to use custom processor scripts instead of the built-in file processing logic. This allows for flexible handling of different file types and custom processing workflows.

### Using Custom Processors

To use a custom processor script:

```powershell
# Process dirty files using a custom processor script
.\Process-DirtyFiles.ps1 -DirectoryPath "D:\Documents" -ProcessorScript ".\CustomFileProcessor.ps1"

# With custom parameters
.\Process-DirtyFiles.ps1 -DirectoryPath "D:\Documents" `
    -ProcessorScript ".\CustomFileProcessor.ps1" `
    -ProcessorScriptParams @{
        CustomParam1 = "Value1"
        CustomParam2 = "Value2"
    }
```

### Creating Custom Processor Scripts

A custom processor script should:

1. Accept parameters that will be passed from Process-DirtyFiles.ps1
2. Implement file processing logic for different file types
3. Optionally use the same tools as the main script (like Get-FileEmbedding.ps1 or Get-ChunkEmbeddings.ps1)

#### Required Parameters

Your script should accept at least these parameters:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    
    [Parameter(Mandatory=$true)]
    [string]$VectorDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel,
    
    [Parameter(Mandatory=$false)]
    [string]$TempDir,
    
    [Parameter(Mandatory=$false)]
    [string]$ScriptPath
    
    # Add your custom parameters here
)
```

### Example Custom Processor

An example custom processor script (`Update-LocalChromaDb.ps1`) is included that demonstrates:

- Custom logging
- Different processing for various file types
- Text enhancement for specific file types
- Error handling
- Using existing tools like Get-FileEmbedding.ps1 and Get-ChunkEmbeddings.ps1

```powershell
# Example usage with the sample custom processor
.\Process-DirtyFiles.ps1 -DirectoryPath "D:\Documents" `
    -ProcessorScript ".\Processing\Update-LocalChromaDb.ps1" `
    -ProcessorScriptParams @{
        CustomParam1 = "EnhanceHeadings"
        CustomParam2 = "HighlightKeywords"
    }
```

## Integration with RAG Systems

This system is designed to work with:

1. The FileTracker system for continuous monitoring - when changes are detected, files are marked as dirty
2. The Start-RAGProxy.ps1 script which provides a REST API that uses the populated ChromaDB for context-enhanced responses
3. The RAG system can be used for vector search and retrieval in applications, enabling better responses from LLMs

## Troubleshooting

- Check the log files in the temp directory for details on processing
- For PDF conversion issues, check the conversion-specific logs
- Verify that Ollama is running and accessible at the specified URL
- Ensure all required Python packages are installed
- If running in continuous mode and the script isn't stopping, check that the stop file path is accessible

## License

See the LICENSE file for details.
