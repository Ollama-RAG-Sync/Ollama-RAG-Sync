# Process-Document.ps1

## Overview
The `Process-Document.ps1` script processes a single file/document by specifying its ID from the FileTracker database, instead of processing all files in a collection like `Process-Collection.ps1`.

## Features
- **Single File Processing**: Processes one specific file by ID rather than entire collections
- **Cross-Collection Search**: Automatically searches all collections to find the file by ID
- **PDF Conversion Support**: Supports multiple OCR tools (marker, tesseract, ocrmypdf, pymupdf)
- **Vector Integration**: Adds processed documents to the vector database
- **Status Management**: Updates file status in FileTracker after processing

## Parameters
- `FileId` (Mandatory): The ID of the file to process from the FileTracker database
- `InstallPath` (Mandatory): Path to the Ollama-RAG-Sync installation
- `VectorsApiUrl` (Optional): Vectors API URL (default: http://localhost:10001)
- `FileTrackerApiUrl` (Optional): FileTracker API URL (default: http://localhost:10003/api)
- `ChunkSize` (Optional): Chunk size for vector processing (default: 1000)
- `ChunkOverlap` (Optional): Chunk overlap for vector processing (default: 100)
- `OcrTool` (Optional): OCR tool for PDF processing (default: pymupdf)

## Usage Examples

### Basic Usage
```powershell
.\Process-Document.ps1 -FileId 123 -InstallPath "D:\repo\Ollama-RAG-Sync"
```

### With Custom OCR Tool
```powershell
.\Process-Document.ps1 -FileId 123 -InstallPath "D:\repo\Ollama-RAG-Sync" -OcrTool marker
```

### With Custom API URLs
```powershell
.\Process-Document.ps1 -FileId 123 -InstallPath "D:\repo\Ollama-RAG-Sync" -VectorsApiUrl "http://localhost:10001" -FileTrackerApiUrl "http://localhost:10003/api"
```

## Key Functions

### `Get-FileById`
- Searches across all collections to find a file by its ID
- Returns file information with collection details

### `Set-FileProcessedStatus`
- Marks a file as processed (not dirty) in the FileTracker database
- Uses approved PowerShell verb naming

### `Invoke-DocumentProcessing`
- Main processing function for individual documents
- Handles PDF conversion, vector addition, and status updates
- Uses approved PowerShell verb naming

## Differences from Process-Collection.ps1
1. **Input Parameter**: Takes `FileId` instead of `CollectionName`
2. **File Discovery**: Searches across collections to find the file by ID
3. **Single File Focus**: Processes only one file per execution
4. **Function Names**: Uses approved PowerShell verbs (Invoke-, Set-, Get-)

## Prerequisites
- FileTracker API must be running
- Vectors API must be running
- Python with required OCR libraries (depending on chosen tool)
- File must exist in the FileTracker database

## Error Handling
- Validates file existence in database
- Checks for file accessibility on disk
- Handles PDF conversion errors
- Reports vector processing failures
- Logs all operations with timestamps

## Logging
- Creates timestamped log files in the `Temp` directory
- Format: `ProcessDocument_{FileId}_{Date}.log`
- Includes DEBUG, INFO, WARNING, and ERROR levels
