# Ollama-RAG-Sync

A PowerShell toolkit for Retrieval-Augmented Generation (RAG) with Ollama, featuring live document sync and vector search.

## Quick Start

### 0. Setup RAG system
```powershell
./Setup-RAG.ps1 -InstallPath "D:\repo\Ollama-RAG-Sync"
```


### 1. Start the RAG System
Use `Start-RAG.ps1` to launch all background services (FileTracker, Vectors API, Proxy):

```powershell
./Start-RAG.ps1 -InstallPath "D:\repo\Ollama-RAG-Sync"
```
- Starts all required services for live RAG operation.
- Use optional parameters to customize ports, chunking, embedding model, etc.

#### Example with custom options:
```powershell
./Start-RAG.ps1 -InstallPath "D:\repo\Ollama-RAG-Sync" -EmbeddingModel "mxbai-embed-large:latest" -ProcessInterval 60 -ChunkSize 1000 -ApiProxyPort 8081
```

### 2. Add a Folder for Tracking
Use `Add-Folder.ps1` to register a folder for monitoring and create a collection in the FileTracker database:

```powershell
# Basic usage
./FileTracker/Add-Folder.ps1 -FolderPath "D:\Docs" -InstallPath "D:\repo\Ollama-RAG-Sync"

# With custom collection name and folder exclusions
./FileTracker/Add-Folder.ps1 -FolderPath "D:\Projects" -InstallPath "D:\repo\Ollama-RAG-Sync" -CollectionName "MyProjects" -OmitFolders @(".git", "node_modules")
```
- All files are added and marked for processing.
- The collection will be monitored for changes (add, modify, delete).

### 3. Process Files in a Collection
Use `Process-Collection.ps1` to process files marked as dirty (changed/added) and update the vector database:

```powershell
./Processor/Process-Collection.ps1 -CollectionName "MyProjects" -InstallPath "D:\repo\Ollama-RAG-Sync" -OcrTool marker
```
- Processes all dirty files in the collection and updates their status.
- Supports PDF OCR via `-OcrTool` (choose: marker, tesseract, ocrmypdf, pymupdf).
- Add `-Continuous` to keep processing in a loop.