# Ollama-RAG-Sync
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![.NET](https://img.shields.io/badge/.NET-8.0-purple.svg)](https://dotnet.microsoft.com/)

> A comprehensive RAG (Retrieval-Augmented Generation) system that integrates with Ollama for document processing, vector storage, and semantic search. Built as a collection of PowerShell and Python scripts with a .NET MCP server, featuring automated file tracking, REST APIs, and AI assistant integration through the Model Context Protocol.

## 📑 Table of Contents

- [Key Features](#-key-features)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [API Endpoints](#-api-endpoints)
- [MCP Integration](#-mcp-integration)
- [LLM-Based Reranking](#-llm-based-reranking)
- [Multi-Collection Storage](#-multi-collection-storage)
- [Testing](#-testing)
- [Troubleshooting](#-troubleshooting)
- [Documentation](#-documentation)
- [Contributing](#-contributing)
- [License](#-license)

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🔄 **Automated File Tracking** | Monitor directories for changes and automatically process new/modified files with SQLite-based tracking |
| 📄 **Advanced Document Processing** | Convert PDFs and documents to embeddings with intelligent chunking and overlap support |
| 🔍 **Semantic Search** | Store and search document embeddings using Ollama models with similarity-based retrieval |
| 🎯 **LLM-Based Reranking** | Improve search relevance with optional reranking using LLM evaluation *(NEW!)* |
| 📚 **Multi-Collection Storage** | Documents automatically stored in both "default" and named collections for flexible organization *(NEW!)* |
| 🚀 **REST APIs** | Complete API ecosystem for file tracking, processing, and vector operations |
| 🤖 **MCP Integration** | Model Context Protocol server for seamless AI assistant integration |
| ⚙️ **Flexible Configuration** | Environment-based configuration with sensible defaults and easy customization |
| ✅ **Comprehensive Testing** | 59+ automated tests with CI/CD pipeline for reliability |
| �️ **Cross-Platform** | Works on Windows, Linux, and macOS |

## 🏗️ Architecture

The system consists of five main components organized under the `RAG/` and `MCP/` directories:

### 1. FileTracker (`RAG/FileTracker/`)

Monitors file collections and tracks changes using SQLite database.

- **Port**: 10003 (configurable via `OLLAMA_RAG_FILE_TRACKER_API_PORT`)
- **Database**: SQLite-based file tracking
- **Features**: File watching, collection management, change detection, real-time file watchers

### 2. Processor (`RAG/Processor/`)

Processes documents and converts them to vector embeddings.

- **Features**: PDF to markdown conversion, text chunking, batch processing
- **Conversion**: Supports PDF to markdown conversion in `Conversion/` subdirectory

### 3. Vectors (`RAG/Vectors/`)

Vector database operations and similarity search.

- **Port**: 10001 (configurable via `OLLAMA_RAG_VECTORS_API_PORT`)
- **Features**: Document embedding, similarity search, vector storage, LLM-based reranking, multi-collection storage
- **Modules**: Core functionality in `Modules/` and API functions in `Functions/`
- **Documentation**: See `RAG/Vectors/RERANKING.md` for reranking details and `docs/MULTI_COLLECTION_STORAGE.md` for collection management

### 4. Search (`RAG/Search/`)

High-level search operations for retrieving relevant documents and chunks.

- **Features**: Best document retrieval, chunk-based search
- **Integration**: Works with Vectors component for semantic search

### 5. MCP Server (`MCP/`)

Model Context Protocol server for AI integration.

- **Technology**: .NET 8.0 C# application
- **Package**: ModelContextProtocol v0.1.0-preview.9
- **Features**: AI assistant integration, protocol compliance, stdio transport

## 📋 Prerequisites

### Required Software
- **PowerShell 7.0+** - [Download](https://github.com/PowerShell/PowerShell/releases)
- **Ollama** - [Install Guide](https://ollama.ai/download)
- **.NET 8.0 SDK** - [Download](https://dotnet.microsoft.com/download/dotnet/8.0) (for MCP server)
- **Python 3.7+** - [Download](https://www.python.org/downloads/) (for document processing and embeddings)

### PowerShell Modules
- `Pode` - REST API framework (auto-installed during setup)
- `Pester` - Testing framework (for development)

### Python Packages
- `chromadb` - Vector database
- `requests` / `urllib` - HTTP library
- `numpy` - Numerical computing
- **PDF Processing** (optional):
  - `PyMuPDF` - Fast PDF text extraction
  - `marker-pdf` - Advanced PDF to Markdown conversion
  - `pytesseract` + Poppler - OCR support
  - `ocrmypdf` - PDF OCR processing

All Python packages are auto-installed during setup via `pip`.

## 🛠️ Installation

### Quick Start (5 Minutes)

#### Windows
```powershell
# 1. Clone the repository
git clone https://github.com/Ollama-RAG-Sync/Ollama-RAG-Sync.git
cd Ollama-RAG-Sync

# 2. Ensure Ollama is running
ollama serve

# 3. Pull the embedding model (one-time)
ollama pull embeddinggemma

# 4. Run setup script
.\RAG\Setup-RAG.ps1 -InstallPath "C:\OllamaRAG"

# 5. Start the system
.\RAG\Start-RAG.ps1

# 6. Verify installation (in a new terminal)
Invoke-RestMethod -Uri "http://localhost:10001/health"
Invoke-RestMethod -Uri "http://localhost:10003/api/collections"
```

#### Linux/macOS
```bash
# 1. Clone the repository
git clone https://github.com/Ollama-RAG-Sync/Ollama-RAG-Sync.git
cd Ollama-RAG-Sync

# 2. Ensure Ollama is running
ollama serve &

# 3. Pull the embedding model (one-time)
ollama pull embeddinggemma

# 4. Run setup script (requires PowerShell 7+)
pwsh ./RAG/Setup-RAG.ps1 -InstallPath "/opt/ollama-rag"

# 5. Load environment variables (IMPORTANT!)
source ~/.bashrc  # or ~/.zshrc depending on your shell

# 6. Start the system
pwsh ./RAG/Start-RAG.ps1

# 7. Verify installation (in a new terminal)
curl http://localhost:10001/health
curl http://localhost:10003/api/collections
```

> **Note for Linux/macOS users:** After running Setup-RAG.ps1, you must source your shell profile (e.g., `source ~/.bashrc`) or start a new terminal session to load the environment variables. See the [Cross-Platform Setup Guide](docs/CROSS_PLATFORM_SETUP.md) for detailed instructions.

### Detailed Setup

#### Step 1: Clone and Navigate
```powershell
git clone https://github.com/Ollama-RAG-Sync/Ollama-RAG-Sync.git
cd Ollama-RAG-Sync
```

#### Step 2: Run Setup Script
```powershell
.\RAG\Setup-RAG.ps1 -InstallPath "C:\OllamaRAG"
```

**Setup Parameters:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InstallPath` | Installation directory | Required |
| `-EmbeddingModel` | Ollama embedding model | `mxbai-embed-large:latest` |
| `-OllamaUrl` | Ollama API URL | `http://localhost:11434` |
| `-ChunkSize` | Text chunk size in lines | 20 |
| `-ChunkOverlap` | Overlap between chunks | 2 |
| `-FileTrackerPort` | FileTracker API port | 10003 |
| `-VectorsPort` | Vectors API port | 10001 |

**What the setup does:**
- ✅ Installs required Python packages (chromadb, requests, numpy)
- ✅ Initializes SQLite database for file tracking
- ✅ Initializes ChromaDB for vector storage
- ✅ Sets environment variables for configuration
- ✅ Verifies all dependencies

#### Step 3: Start the System
```powershell
.\RAG\Start-RAG.ps1
```

This starts:
- 🟢 **FileTracker API** on port 10003
- 🟢 **Vectors API** on port 10001
- 🟢 **Background file monitoring**

#### Step 4: Build MCP Server (Optional)
```powershell
cd MCP
dotnet build
dotnet run
```

## ⚙️ Configuration

The system uses environment variables for configuration:

| Variable | Description | Default |
|----------|-------------|---------|
| `OLLAMA_RAG_INSTALL_PATH` | Installation directory | Required |
| `OLLAMA_RAG_EMBEDDING_MODEL` | Ollama embedding model | `mxbai-embed-large:latest` |
| `OLLAMA_RAG_URL` | Ollama API URL | `http://localhost:11434` |
| `OLLAMA_RAG_CHUNK_SIZE` | Text chunk size | 20 |
| `OLLAMA_RAG_CHUNK_OVERLAP` | Chunk overlap | 2 |
| `OLLAMA_RAG_FILE_TRACKER_API_PORT` | FileTracker API port | 10003 |
| `OLLAMA_RAG_VECTORS_API_PORT` | Vectors API port | 10001 |

## 📚 Usage

### Quick Start Workflow

```powershell
# 1. Add a document collection
.\RAG\FileTracker\Add-Folder.ps1 -CollectionName "MyDocs" -FolderPath "C:\Documents"

# 2. Process documents (converts to embeddings)
.\RAG\Processor\Process-Collection.ps1 -CollectionName "MyDocs"

# 3. Search for relevant documents
.\RAG\Search\Get-BestDocuments.ps1 -Query "project requirements" -CollectionName "MyDocs"

# 4. Search for specific chunks
.\RAG\Search\Get-BestChunks.ps1 -Query "API documentation" -CollectionName "MyDocs"
```

### Complete Usage Examples

#### Example 1: Setting Up a Technical Documentation Library

```powershell
# Step 1: Create and populate a technical documentation collection
.\RAG\FileTracker\Add-Folder.ps1 `
    -CollectionName "TechLibrary" `
    -FolderPath "C:\Projects\Documentation"

# Step 2: Verify files were tracked
$files = .\RAG\FileTracker\Get-CollectionFiles.ps1 -CollectionName "TechLibrary"
Write-Host "Tracked $($files.Count) files"

# Step 3: Process all documents with custom chunking
# Note: Documents are stored in both "default" and "TechLibrary" collections
.\RAG\Processor\Process-Collection.ps1 `
    -CollectionName "TechLibrary" `
    -ChunkSize 25 `
    -ChunkOverlap 3

# Step 4: Search for specific technical topics
$results = .\RAG\Search\Get-BestDocuments.ps1 `
    -Query "REST API authentication methods" `
    -CollectionName "TechLibrary" `
    -Threshold 0.7 `
    -MaxResults 5

# Display results
foreach ($doc in $results.results) {
    Write-Host "`n=== $($doc.document_name) ==="
    Write-Host "Similarity: $($doc.similarity)"
    Write-Host "Preview: $($doc.content.Substring(0, [Math]::Min(200, $doc.content.Length)))..."
}
```

#### Example 2: Research Paper Analysis

```powershell
# Create a research papers collection
.\RAG\FileTracker\Add-Folder.ps1 `
    -CollectionName "ResearchPapers" `
    -FolderPath "C:\Research\Papers"

# Process with larger chunks for academic content
.\RAG\Processor\Process-Collection.ps1 `
    -CollectionName "ResearchPapers" `
    -ChunkSize 40 `
    -ChunkOverlap 5

# Find papers discussing specific methodologies
$methodologySearch = .\RAG\Search\Get-BestChunks.ps1 `
    -Query "machine learning model evaluation metrics" `
    -CollectionName "ResearchPapers" `
    -Threshold 0.8 `
    -MaxResults 10 `
    -AggregateByDocument $true

# Export results for further analysis
$methodologySearch.results | Export-Csv -Path "C:\Results\methodology_findings.csv" -NoTypeInformation
```

#### Example 3: Code Documentation Search

```powershell
# Track multiple code repositories
$repos = @(
    @{Name="Backend"; Path="C:\Projects\Backend\docs"},
    @{Name="Frontend"; Path="C:\Projects\Frontend\docs"},
    @{Name="Mobile"; Path="C:\Projects\Mobile\docs"}
)

foreach ($repo in $repos) {
    .\RAG\FileTracker\Add-Folder.ps1 `
        -CollectionName $repo.Name `
        -FolderPath $repo.Path
    
    .\RAG\Processor\Process-Collection.ps1 `
        -CollectionName $repo.Name
}

# Search across all repositories
function Search-AllRepos {
    param([string]$Query)
    
    $allResults = @()
    foreach ($repo in $repos) {
        $results = .\RAG\Search\Get-BestDocuments.ps1 `
            -Query $Query `
            -CollectionName $repo.Name `
            -MaxResults 3 `
            -ReturnContent $false
        
        if ($results.success) {
            foreach ($result in $results.results) {
                $allResults += [PSCustomObject]@{
                    Repository = $repo.Name
                    Document = $result.document_name
                    Similarity = $result.similarity
                }
            }
        }
    }
    
    return $allResults | Sort-Object Similarity -Descending
}

# Use the function
$apiDocs = Search-AllRepos -Query "GraphQL API implementation"
$apiDocs | Format-Table

# Alternative: Search all repos at once using "default" collection
# (all documents are automatically stored in "default" collection)
$allRepoResults = .\RAG\Search\Get-BestDocuments.ps1 `
    -Query "GraphQL API implementation" `
    -CollectionName "default" `
    -MaxResults 10
$allRepoResults.results | Format-Table
```

#### Example 4: Monitoring and Auto-Processing New Files

```powershell
# Create a collection with automatic monitoring
.\RAG\FileTracker\Add-Folder.ps1 `
    -CollectionName "LiveDocs" `
    -FolderPath "C:\SharePoint\Sync\Documents"

# Set up a scheduled task for auto-processing (runs every hour)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument @"
-NoProfile -Command "& {
    . 'C:\OllamaRAG\RAG\FileTracker\Refresh-Collection.ps1' -CollectionName 'LiveDocs'
    . 'C:\OllamaRAG\RAG\Processor\Process-Collection.ps1' -CollectionName 'LiveDocs'
}"
"@

Register-ScheduledTask -TaskName "RAG-AutoProcess-LiveDocs" -Trigger $trigger -Action $action

# Manual refresh and process when needed
.\RAG\FileTracker\Refresh-Collection.ps1 -CollectionName "LiveDocs"
.\RAG\Processor\Process-Collection.ps1 -CollectionName "LiveDocs"
```

#### Example 5: Comparative Analysis Across Time

```powershell
# Create version-based collections
.\RAG\FileTracker\Add-Folder.ps1 `
    -CollectionName "Docs_v1" `
    -FolderPath "C:\Projects\Docs\v1.0"

.\RAG\FileTracker\Add-Folder.ps1 `
    -CollectionName "Docs_v2" `
    -FolderPath "C:\Projects\Docs\v2.0"

# Process both versions
@("Docs_v1", "Docs_v2") | ForEach-Object {
    .\RAG\Processor\Process-Collection.ps1 -CollectionName $_
}

# Compare search results across versions
$query = "security best practices"

$v1Results = .\RAG\Search\Get-BestDocuments.ps1 `
    -Query $query `
    -CollectionName "Docs_v1" `
    -MaxResults 5

$v2Results = .\RAG\Search\Get-BestDocuments.ps1 `
    -Query $query `
    -CollectionName "Docs_v2" `
    -MaxResults 5

# Analyze differences
Write-Host "`n=== Version 1.0 Coverage ==="
$v1Results.results | Select-Object document_name, similarity | Format-Table

Write-Host "`n=== Version 2.0 Coverage ==="
$v2Results.results | Select-Object document_name, similarity | Format-Table
```

#### Example 6: Building a Q&A System with Context and Reranking

```powershell
# Create a knowledge base
.\RAG\FileTracker\Add-Folder.ps1 `
    -CollectionName "KnowledgeBase" `
    -FolderPath "C:\Company\KnowledgeBase"

.\RAG\Processor\Process-Collection.ps1 -CollectionName "KnowledgeBase"

# Function to get contextual answers with reranking
function Get-ContextualAnswer {
    param(
        [string]$Question,
        [string]$Collection = "KnowledgeBase",
        [int]$ContextChunks = 5
    )
    
    # Get relevant context with LLM-based reranking for better accuracy
    $context = .\RAG\Search\Get-BestChunks.ps1 `
        -Query $Question `
        -CollectionName $Collection `
        -EnableReranking `
        -RerankTopK 20 `
        -MaxResults $ContextChunks `
        -Threshold 0.6
    
    if (-not $context.success -or $context.results.Count -eq 0) {
        return "No relevant context found."
    }
    
    # Combine context for AI processing
    $contextText = ($context.results | ForEach-Object { $_.content }) -join "`n`n---`n`n"
    
    # Return structured response with reranking scores
    return [PSCustomObject]@{
        Question = $Question
        RelevantSources = $context.results.document_name | Select-Object -Unique
        Context = $contextText
        ChunkCount = $context.results.Count
        AvgRerankScore = ($context.results.rerank_score | Measure-Object -Average).Average
        TopRerankScore = ($context.results.rerank_score | Measure-Object -Maximum).Maximum
    }
}

# Use the Q&A system
$answer = Get-ContextualAnswer -Question "How do I configure SSL certificates?"
Write-Host "Sources: $($answer.RelevantSources -join ', ')"
Write-Host "Average Rerank Score: $([math]::Round($answer.AvgRerankScore, 3))"
Write-Host "Top Rerank Score: $([math]::Round($answer.TopRerankScore, 3))"
Write-Host "`nContext:`n$($answer.Context)"
```

#### Example 7: Batch Processing Multiple Collections

```powershell
# Define multiple collections to process
$collections = @(
    @{Name="CustomerDocs"; Path="C:\Data\Customers"; ChunkSize=20},
    @{Name="EmployeeHandbook"; Path="C:\HR\Handbook"; ChunkSize=30},
    @{Name="Policies"; Path="C:\Legal\Policies"; ChunkSize=25}
)

# Batch setup and processing
foreach ($col in $collections) {
    Write-Host "`n=== Processing $($col.Name) ===" -ForegroundColor Cyan
    
    # Add collection
    .\RAG\FileTracker\Add-Folder.ps1 `
        -CollectionName $col.Name `
        -FolderPath $col.Path
    
    # Process with custom chunk size
    .\RAG\Processor\Process-Collection.ps1 `
        -CollectionName $col.Name `
        -ChunkSize $col.ChunkSize
    
    # Verify
    $status = .\RAG\FileTracker\Get-CollectionFiles.ps1 -CollectionName $col.Name
    Write-Host "Processed $($status.Count) files" -ForegroundColor Green
}

# Cross-collection search
function Search-AllCollections {
    param([string]$Query)
    
    $allResults = @()
    foreach ($col in $collections) {
        $results = .\RAG\Search\Get-BestDocuments.ps1 `
            -Query $Query `
            -CollectionName $col.Name `
            -MaxResults 2
        
        if ($results.success) {
            $allResults += $results.results | ForEach-Object {
                [PSCustomObject]@{
                    Collection = $col.Name
                    Document = $_.document_name
                    Similarity = $_.similarity
                    Preview = $_.content.Substring(0, [Math]::Min(150, $_.content.Length))
                }
            }
        }
    }
    
    return $allResults | Sort-Object Similarity -Descending
}

# Search across all collections
$searchResults = Search-AllCollections -Query "vacation policy"
$searchResults | Format-Table -AutoSize
```

#### Example 8: Using the REST APIs Directly

```powershell
# Add a collection via API
$body = @{
    name = "APICollection"
    folder_path = "C:\APIData"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:10003/api/collections" `
    -Method Post `
    -Body $body `
    -ContentType "application/json"

# Get all collections
$collections = Invoke-RestMethod -Uri "http://localhost:10003/api/collections"
$collections | ConvertTo-Json -Depth 3

# Add a document to vectors
$vectorDoc = @{
    collection_name = "APICollection"
    document_id = "doc-001"
    document_name = "sample.txt"
    content = "This is sample content for vector storage."
    metadata = @{
        author = "John Doe"
        date = "2025-10-05"
    }
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:10001/api/documents" `
    -Method Post `
    -Body $vectorDoc `
    -ContentType "application/json"

# Search documents via API
$searchQuery = @{
    query = "sample content"
    collection_name = "APICollection"
    max_results = 5
    threshold = 0.6
} | ConvertTo-Json

$searchResults = Invoke-RestMethod -Uri "http://localhost:10001/api/search/documents" `
    -Method Post `
    -Body $searchQuery `
    -ContentType "application/json"

$searchResults.results | Format-Table
```

#### Example 9: PDF Processing Workflow

```powershell
# Set up collection for PDFs
.\RAG\FileTracker\Add-Folder.ps1 `
    -CollectionName "PDFLibrary" `
    -FolderPath "C:\Documents\PDFs"

# Process PDFs with OCR support (requires Python + OCR tool)
.\RAG\Processor\Process-Collection.ps1 `
    -CollectionName "PDFLibrary" `
    -OcrTool "tesseract" `
    -ChunkSize 30

# Search within PDF content
$pdfSearch = .\RAG\Search\Get-BestChunks.ps1 `
    -Query "financial statements and quarterly reports" `
    -CollectionName "PDFLibrary" `
    -Threshold 0.75 `
    -MaxResults 8 `
    -AggregateByDocument $true

# Show results grouped by document
$pdfSearch.results | Group-Object document_name | ForEach-Object {
    Write-Host "`n=== $($_.Name) ===" -ForegroundColor Yellow
    $_.Group | ForEach-Object {
        Write-Host "Similarity: $($_.similarity) - Chunk: $($_.chunk_index)"
        Write-Host $_.content.Substring(0, [Math]::Min(200, $_.content.Length))
        Write-Host ""
    }
}
```

#### Example 10: Health Monitoring and Maintenance

```powershell
# Check system health
function Get-RAGSystemHealth {
    $health = @{
        FileTrackerAPI = $false
        VectorsAPI = $false
        OllamaService = $false
        Collections = 0
        LastError = $null
    }
    
    try {
        # Check FileTracker API
        $ftResponse = Invoke-RestMethod -Uri "http://localhost:10003/api/collections" -ErrorAction Stop
        $health.FileTrackerAPI = $true
        $health.Collections = $ftResponse.Count
    }
    catch {
        $health.LastError = "FileTracker: $($_.Exception.Message)"
    }
    
    try {
        # Check Vectors API
        $vectorResponse = Invoke-RestMethod -Uri "http://localhost:10001/api/health" -ErrorAction Stop
        $health.VectorsAPI = $true
    }
    catch {
        $health.LastError = "Vectors: $($_.Exception.Message)"
    }
    
    try {
        # Check Ollama
        $ollamaResponse = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -ErrorAction Stop
        $health.OllamaService = $true
    }
    catch {
        $health.LastError = "Ollama: $($_.Exception.Message)"
    }
    
    return [PSCustomObject]$health
}

# Run health check
$healthStatus = Get-RAGSystemHealth
$healthStatus | Format-List

# Maintenance: Refresh all collections
$collections = Invoke-RestMethod -Uri "http://localhost:10003/api/collections"
foreach ($collection in $collections) {
    Write-Host "Refreshing $($collection.name)..."
    .\RAG\FileTracker\Refresh-Collection.ps1 -CollectionName $collection.name
}
```

### Managing Collections

#### Add a Collection
```powershell
.\RAG\FileTracker\Add-Folder.ps1 -CollectionName "TechDocs" -FolderPath "C:\TechDocuments"
```

#### List All Collections
```powershell
Invoke-RestMethod -Uri "http://localhost:10003/api/collections"
```

#### Get Files in Collection
```powershell
.\RAG\FileTracker\Get-CollectionFiles.ps1 -CollectionName "TechDocs"
```

#### Refresh Collection (Re-scan for changes)
```powershell
.\RAG\FileTracker\Refresh-Collection.ps1 -CollectionName "TechDocs"
```

### Processing Documents

#### Process All Pending Documents
```powershell
.\RAG\Processor\Process-Collection.ps1 -CollectionName "TechDocs"
```

#### Process Single Document
```powershell
.\RAG\Processor\Process-Document.ps1 -FilePath "C:\Documents\report.txt" -CollectionName "TechDocs"
```

#### Process with Custom Settings
```powershell
.\RAG\Processor\Process-Collection.ps1 `
    -CollectionName "TechDocs" `
    -ChunkSize 30 `
    -ChunkOverlap 5 `
    -OcrTool "tesseract"
```

## 🔌 API Endpoints

The system provides two REST APIs for comprehensive document and vector management.

### FileTracker API (Port 10003)

File tracking, collection management, and file monitoring operations.

**Base URL**: `http://localhost:10003`

#### Collections

<details>
<summary><b>GET /api/collections</b> - List all collections</summary>

**Response:**
```json
{
  "success": true,
  "collections": [
    {
      "id": 1,
      "name": "TechDocs",
      "description": "Technical documentation",
      "source_folder": "C:\\Documents\\Tech",
      "include_extensions": ".txt,.md,.pdf",
      "exclude_folders": "node_modules,vendor",
      "created_at": "2025-10-01T10:00:00Z",
      "updated_at": "2025-10-05T15:30:00Z"
    }
  ],
  "count": 1
}
```
</details>

<details>
<summary><b>POST /api/collections</b> - Create a new collection</summary>

**Request Body:**
```json
{
  "name": "TechDocs",
  "sourceFolder": "C:\\Documents\\Tech",
  "description": "Technical documentation",
  "includeExtensions": ".txt,.md,.pdf",
  "excludeFolders": "node_modules,vendor"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Collection created successfully",
  "collection": {
    "id": 1,
    "name": "TechDocs",
    "source_folder": "C:\\Documents\\Tech"
  }
}
```
</details>

<details>
<summary><b>GET /api/collections/{id}</b> - Get collection by ID</summary>

**Response:**
```json
{
  "success": true,
  "collection": {
    "id": 1,
    "name": "TechDocs",
    "description": "Technical documentation",
    "source_folder": "C:\\Documents\\Tech",
    "include_extensions": ".txt,.md,.pdf",
    "exclude_folders": "node_modules,vendor"
  }
}
```
</details>

<details>
<summary><b>PUT /api/collections/{id}</b> - Update collection</summary>

**Request Body:**
```json
{
  "name": "UpdatedName",
  "description": "Updated description",
  "includeExtensions": ".txt,.md,.pdf,.docx"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Collection updated successfully",
  "collection": { /* updated collection object */ }
}
```
</details>

<details>
<summary><b>DELETE /api/collections/{id}</b> - Delete collection</summary>

**Response:**
```json
{
  "success": true,
  "message": "Collection deleted successfully"
}
```
</details>

<details>
<summary><b>GET /api/collections/{id}/settings</b> - Get collection settings</summary>

**Response:**
```json
{
  "success": true,
  "collection": { /* collection object */ },
  "settings": {
    "isWatching": true,
    "watchJobId": 42
  }
}
```
</details>

<details>
<summary><b>POST /api/collections/{id}/watch</b> - Start/stop file watching</summary>

**Request Body (Start):**
```json
{
  "action": "start",
  "watchCreated": true,
  "watchModified": true,
  "watchDeleted": false,
  "watchRenamed": true,
  "includeSubdirectories": true,
  "processInterval": 15,
  "omitFolders": ["temp", "cache"],
  "fileFilter": "*.txt"
}
```

**Request Body (Stop):**
```json
{
  "action": "stop"
}
```

**Response:**
```json
{
  "success": true,
  "message": "File watching started",
  "collection_id": 1,
  "job_id": 42,
  "parameters": { /* watch parameters */ }
}
```
</details>

#### Files

<details>
<summary><b>GET /api/collections/{id}/files</b> - Get files in collection</summary>

**Query Parameters:**
- `dirty` (boolean): Return only dirty/unprocessed files
- `processed` (boolean): Return only processed files
- `deleted` (boolean): Return only deleted files

**Example:** `GET /api/collections/1/files?dirty=true`

**Response:**
```json
{
  "success": true,
  "files": [
    {
      "id": 1,
      "collection_id": 1,
      "FilePath": "C:\\Documents\\Tech\\guide.txt",
      "FileHash": "abc123...",
      "LastModified": "2025-10-05T10:00:00Z",
      "Dirty": true,
      "Deleted": false,
      "created_at": "2025-10-01T08:00:00Z",
      "updated_at": "2025-10-05T10:00:00Z"
    }
  ],
  "count": 1,
  "collection_id": 1
}
```
</details>

<details>
<summary><b>POST /api/collections/{id}/files</b> - Add file to collection</summary>

**Request Body:**
```json
{
  "filePath": "C:\\Documents\\Tech\\guide.txt",
  "originalUrl": "https://example.com/guide.txt",
  "dirty": true
}
```

**Response:**
```json
{
  "success": true,
  "message": "File added",
  "file": {
    "id": 1,
    "FilePath": "C:\\Documents\\Tech\\guide.txt",
    "updated": false
  }
}
```
</details>

<details>
<summary><b>PUT /api/collections/{id}/files</b> - Update all files in collection</summary>

**Request Body:**
```json
{
  "dirty": false
}
```

**Response:**
```json
{
  "success": true,
  "message": "All files in collection 1 status updated",
  "dirty": false
}
```
</details>

<details>
<summary><b>PUT /api/collections/{id}/files/{fileId}</b> - Update specific file status</summary>

**Request Body:**
```json
{
  "dirty": false
}
```

**Response:**
```json
{
  "success": true,
  "message": "File status updated",
  "file_id": 1,
  "file_path": "C:\\Documents\\Tech\\guide.txt",
  "collection_id": 1,
  "dirty": false
}
```
</details>

<details>
<summary><b>DELETE /api/collections/{id}/files/{fileId}</b> - Remove file from collection</summary>

**Response:**
```json
{
  "success": true,
  "message": "File (ID: 1) removed from collection (ID: 1)"
}
```
</details>

<details>
<summary><b>GET /api/files/{fileId}/metadata</b> - Get file metadata</summary>

**Response:**
```json
{
  "success": true,
  "file_id": 1,
  "collection_id": 1,
  "collection_name": "TechDocs",
  "file_path": "C:\\Documents\\Tech\\guide.txt"
}
```
</details>

#### System

<details>
<summary><b>GET /health</b> - Health check</summary>

**Response:**
```json
{
  "status": "OK"
}
```
</details>

<details>
<summary><b>GET /status</b> - System status</summary>

**Response:**
```json
{
  "success": true,
  "status": {
    "collections_count": 5,
    "total_files": 150,
    "dirty_files": 10
  }
}
```
</details>

---

### Vectors API (Port 10001)

Vector database operations, document embedding, and semantic search.

**Base URL**: `http://localhost:10001`

#### Documents

<details>
<summary><b>POST /documents</b> - Add document to vector database</summary>

**Request Body:**
```json
{
  "filePath": "C:\\Documents\\Tech\\guide.txt",
  "originalFilePath": "C:\\Original\\guide.txt",
  "fileId": 1,
  "chunkSize": 20,
  "chunkOverlap": 2,
  "maxWorkers": 5,
  "contentType": "Text",
  "collectionName": "TechDocs"
}
```

**Parameters:**
- `filePath` (required): Path to the document to add
- `originalFilePath` (optional): Original source file path
- `fileId` (optional): File ID from FileTracker (default: 0)
- `chunkSize` (optional): Number of lines per chunk (default: 20)
- `chunkOverlap` (optional): Lines of overlap between chunks (default: 2)
- `maxWorkers` (optional): Concurrent processing workers (default: 5)
- `contentType` (optional): Content type (default: "Text")
- `collectionName` (optional): Target collection (default: "default")

**Response:**
```json
{
  "success": true,
  "message": "Document added successfully",
  "filePath": "C:\\Documents\\Tech\\guide.txt",
  "fileId": 1,
  "collectionName": "TechDocs"
}
```

**Note:** Documents are automatically stored in both the "default" collection and the specified `collectionName` collection for flexible retrieval.
</details>

<details>
<summary><b>DELETE /documents</b> - Remove document from vector database</summary>

**Request Body:**
```json
{
  "filePath": "C:\\Documents\\Tech\\guide.txt",
  "fileId": 1,
  "collectionName": "TechDocs"
}
```

**Parameters:**
- `filePath` (required): Path to the document to remove
- `fileId` (optional): File ID for logging (default: 0)
- `collectionName` (optional): Collection name (default: "default")

**Response:**
```json
{
  "success": true,
  "message": "Document removed successfully",
  "filePath": "C:\\Documents\\Tech\\guide.txt",
  "fileId": 1,
  "collectionName": "TechDocs"
}
```
</details>

#### Search

<details>
<summary><b>POST /api/search/documents</b> - Search documents by query</summary>

**Request Body:**
```json
{
  "query": "machine learning algorithms",
  "max_results": 10,
  "threshold": 0.6,
  "return_content": true,
  "collectionName": "TechDocs",
  "filter": {}
}
```

**Parameters:**
- `query` (required): Search query text
- `max_results` (optional): Maximum results to return (default: 10)
- `threshold` (optional): Minimum similarity score 0.0-1.0 (default: 0.5)
- `return_content` (optional): Include document content (default: false)
- `collectionName` (optional): Target collection (default: "default")
- `filter` (optional): Additional metadata filters (default: {})

**Response:**
```json
{
  "success": true,
  "results": [
    {
      "document_id": "doc_123",
      "document_name": "ml_guide.txt",
      "similarity": 0.87,
      "content": "Machine learning is...",
      "metadata": {
        "collection": "TechDocs",
        "created_at": "2025-10-01T10:00:00Z"
      }
    }
  ],
  "count": 1,
  "query": "machine learning algorithms",
  "collectionName": "TechDocs"
}
```
</details>

<details>
<summary><b>POST /api/search/chunks</b> - Search text chunks by query</summary>

**Request Body:**
```json
{
  "query": "neural network architecture",
  "max_results": 10,
  "threshold": 0.6,
  "aggregateByDocument": false,
  "collectionName": "TechDocs",
  "filter": {}
}
```

**Parameters:**
- `query` (required): Search query text
- `max_results` (optional): Maximum results to return (default: 10)
- `threshold` (optional): Minimum similarity score 0.0-1.0 (default: 0.0)
- `aggregateByDocument` (optional): Group chunks by document (default: false)
- `collectionName` (optional): Target collection (default: "default")
- `filter` (optional): Additional metadata filters (default: {})

**Response:**
```json
{
  "success": true,
  "results": [
    {
      "chunk_id": "chunk_456",
      "document_id": "doc_123",
      "document_name": "ml_guide.txt",
      "chunk_index": 5,
      "content": "Neural networks consist of layers...",
      "similarity": 0.92,
      "metadata": {
        "collection": "TechDocs",
        "start_line": 100,
        "end_line": 120
      }
    }
  ],
  "count": 1,
  "query": "neural network architecture",
  "collectionName": "TechDocs"
}
```
</details>

#### System

<details>
<summary><b>GET /health</b> - Health check</summary>

**Response:**
```json
{
  "status": "OK"
}
```
</details>

<details>
<summary><b>GET /status</b> - Server status and configuration</summary>

**Response:**
```json
{
  "status": "ok",
  "chromaDbPath": "C:\\OllamaRAG\\Chroma.db",
  "ollamaUrl": "http://localhost:11434",
  "embeddingModel": "mxbai-embed-large:latest",
  "defaultChunkSize": 20,
  "defaultChunkOverlap": 2,
  "defaultMaxWorkers": 5,
  "defaultCollectionName": "default"
}
```
</details>

---

### Complete API Examples

#### Example 1: Complete Document Workflow

```powershell
# 1. Create a collection
$collection = @{
    name = "MyDocs"
    sourceFolder = "C:\Documents"
    description = "My document collection"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:10003/api/collections" `
    -Method Post -Body $collection -ContentType "application/json"

# 2. Add a file to the collection
$file = @{
    filePath = "C:\Documents\guide.txt"
    dirty = $true
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:10003/api/collections/1/files" `
    -Method Post -Body $file -ContentType "application/json"

# 3. Add document to vectors
$doc = @{
    filePath = "C:\Documents\guide.txt"
    collectionName = "MyDocs"
    chunkSize = 20
    maxWorkers = 5
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:10001/documents" `
    -Method Post -Body $doc -ContentType "application/json"

# 4. Search documents
$search = @{
    query = "API documentation"
    collectionName = "MyDocs"
    max_results = 5
    threshold = 0.7
} | ConvertTo-Json

$results = Invoke-RestMethod -Uri "http://localhost:10001/api/search/documents" `
    -Method Post -Body $search -ContentType "application/json"

$results.results | Format-Table
```

#### Example 2: File Watching Automation

```powershell
# Start watching a collection
$watch = @{
    action = "start"
    watchCreated = $true
    watchModified = $true
    includeSubdirectories = $true
    processInterval = 15
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:10003/api/collections/1/watch" `
    -Method Post -Body $watch -ContentType "application/json"

# Get watch status
$settings = Invoke-RestMethod -Uri "http://localhost:10003/api/collections/1/settings"
Write-Host "Watching: $($settings.settings.isWatching)"

# Stop watching
$stopWatch = @{ action = "stop" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:10003/api/collections/1/watch" `
    -Method Post -Body $stopWatch -ContentType "application/json"
```

#### Example 3: Chunk-Level Search

```powershell
# Search for specific chunks with aggregation
$chunkSearch = @{
    query = "error handling patterns"
    collectionName = "CodeDocs"
    max_results = 15
    threshold = 0.75
    aggregateByDocument = $true
} | ConvertTo-Json

$chunks = Invoke-RestMethod -Uri "http://localhost:10001/api/search/chunks" `
    -Method Post -Body $chunkSearch -ContentType "application/json"

# Display results grouped by document
$chunks.results | Group-Object document_name | ForEach-Object {
    Write-Host "`n=== $($_.Name) ==="
    $_.Group | ForEach-Object {
        Write-Host "Chunk $($_.chunk_index): Similarity $($_.similarity)"
        Write-Host $_.content.Substring(0, [Math]::Min(150, $_.content.Length))
        Write-Host ""
    }
}
```

---

### Error Handling

All API endpoints return consistent error responses:

```json
{
  "success": false,
  "error": "Error message description"
}
```

**Common HTTP Status Codes:**
- `200 OK` - Request successful
- `201 Created` - Resource created successfully
- `400 Bad Request` - Invalid request parameters
- `404 Not Found` - Resource not found
- `409 Conflict` - Resource conflict (e.g., already exists)
- `500 Internal Server Error` - Server error

### API Authentication

⚠️ **Security Note:** The current implementation does not include authentication. For production use, implement:
- API key authentication
- Rate limiting
- HTTPS/TLS encryption
- IP whitelisting
- Request validation

## 🤖 MCP Integration

The MCP server provides AI assistant integration:

```bash
# Build the MCP server
cd MCP
dotnet build

# The server is automatically started with Start-RAG.ps1
```

## 🎯 LLM-Based Reranking (New Feature!)

The system now supports advanced LLM-based reranking to significantly improve search result relevance. Reranking uses a two-stage approach:

### How It Works

1. **Stage 1 - Vector Search**: Fast retrieval of top K candidates using vector similarity
2. **Stage 2 - LLM Reranking**: Each candidate is evaluated by an LLM for true semantic relevance
3. **Combined Scoring**: Results are scored as 30% vector similarity + 70% LLM relevance score

### Quick Start

```powershell
# Chunk search with reranking
.\RAG\Search\Get-BestChunks.ps1 `
    -Query "How do I implement authentication?" `
    -CollectionName "Docs" `
    -EnableReranking `
    -MaxResults 5

# Document search with reranking
.\RAG\Search\Get-BestDocuments.ps1 `
    -Query "Security best practices" `
    -CollectionName "SecurityDocs" `
    -EnableReranking `
    -RerankTopK 20 `
    -MaxResults 5
```

### Advanced Configuration

```powershell
# Custom reranking model and parameters
.\RAG\Search\Get-BestChunks.ps1 `
    -Query "database optimization" `
    -CollectionName "TechDocs" `
    -EnableReranking `
    -RerankModel "llama3" `
    -RerankTopK 30 `
    -MaxResults 10 `
    -AggregateByDocument $true
```

### Reranking Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `EnableReranking` | switch | false | Enable LLM-based reranking |
| `RerankModel` | string | (model) | Ollama model for reranking |
| `RerankTopK` | integer | MaxResults × 3 | Candidates to retrieve before reranking |

### When to Use Reranking

**✅ Use When:**
- Accuracy is more important than speed (~2-5 seconds vs ~100ms)
- Query is complex or ambiguous
- Initial vector results need refinement
- Working with diverse document types

**❌ Skip When:**
- Speed is critical
- Vector similarity is already accurate
- Simple keyword matching is sufficient

### Result Format

With reranking enabled, results include:
```json
{
  "similarity": 0.87,         // Combined score
  "rerank_score": 0.92,       // LLM relevance score
  "original_similarity": 0.78  // Original vector score
}
```

For detailed documentation, see [RAG/Vectors/RERANKING.md](RAG/Vectors/RERANKING.md).

## � Multi-Collection Storage (New Feature!)

Documents are now automatically stored in **both** the "default" collection and any specifically named collection. This provides universal access while maintaining organized subsets.

### How It Works

When you add a document to a named collection, it's stored in two places:

```powershell
# Add document to "technical" collection
.\RAG\Processor\Process-Document.ps1 `
    -FilePath "C:\Docs\guide.txt" `
    -CollectionName "technical"

# Result: Document is stored in:
# 1. default_documents + default_chunks (universal access)
# 2. technical_documents + technical_chunks (organized subset)
```

### Benefits

✅ **Universal Access** - All documents always available in "default" collection  
✅ **Flexible Organization** - Group documents by topic, project, or department  
✅ **No Duplication Overhead** - Same document ID across collections  
✅ **Query Flexibility** - Search everything or specific subsets

### Usage Examples

**Search all documents:**
```powershell
.\RAG\Search\Get-BestDocuments.ps1 `
    -Query "API documentation" `
    -CollectionName "default"
```

**Search specific collection:**
```powershell
.\RAG\Search\Get-BestDocuments.ps1 `
    -Query "API documentation" `
    -CollectionName "technical"
```

**Organize by topic:**
```powershell
# Add documents to different collections
.\RAG\Processor\Process-Collection.ps1 -CollectionName "security"
.\RAG\Processor\Process-Collection.ps1 -CollectionName "architecture"
.\RAG\Processor\Process-Collection.ps1 -CollectionName "api-docs"

# All documents also searchable via "default" collection
```

### Collection Structure

For a document in collection "technical":

```
ChromaDB/
├── default_documents      # Contains ALL documents
├── default_chunks         # Contains ALL chunks
├── technical_documents    # Contains technical documents
└── technical_chunks       # Contains technical chunks
```

### Migration Notes

- Existing documents are not automatically migrated
- New documents automatically use multi-collection storage
- Re-process existing documents to add them to both collections

For complete details, see [docs/MULTI_COLLECTION_STORAGE.md](docs/MULTI_COLLECTION_STORAGE.md).

## 📁 Project Structure

```
Ollama-RAG-Sync/
├── .github/
│   └── workflows/
│       └── ci.yml              # CI/CD pipeline
├── docs/
│   ├── TESTING.md              # Testing documentation
│   └── CONTRIBUTING.md         # Contribution guidelines
├── MCP/                        # Model Context Protocol Server
│   ├── src/                    # Source code
│   ├── tests/                  # Unit tests (xUnit)
│   ├── Program.cs
│   ├── Ollama-RAG-Sync.csproj
│   └── Ollama-RAG-Sync.sln
├── RAG/                        # RAG System Components
│   ├── FileTracker/            # File monitoring & tracking
│   │   ├── Modules/            # Shared modules
│   │   ├── Scripts/            # Executable scripts
│   │   └── Tests/              # Unit tests
│   ├── Processor/              # Document processing
│   │   ├── Conversion/         # PDF to markdown
│   │   │   └── python_scripts/ # PDF conversion Python scripts
│   │   └── Tests/              # Unit tests
│   ├── Search/                 # Search operations
│   │   ├── Scripts/
│   │   └── Tests/
│   ├── Vectors/                # Vector operations
│   │   ├── Modules/            # Core modules
│   │   ├── Functions/          # API functions
│   │   ├── python_scripts/     # Embedding & storage Python scripts
│   │   ├── Tests/              # Unit tests
│   │   └── server.psd1
│   └── requirements.txt        # Python dependencies
│   ├── Tests/                  # Integration tests
│   │   ├── Integration/        # End-to-end tests
│   │   ├── Fixtures/           # Test data
│   │   └── TestHelpers.psm1   # Test utilities
│   ├── Setup-RAG.ps1           # Installation script
│   └── Start-RAG.ps1           # Startup script
├── scripts/
│   └── run-tests.ps1           # Test runner
├── docs/
│   ├── ARCHITECTURE.md         # Architecture overview
│   ├── MULTI_COLLECTION_STORAGE.md  # Collection management
│   ├── RERANKING_SUMMARY.md    # Reranking feature summary
│   ├── TESTING.md              # Testing guide
│   └── CONTRIBUTING.md         # Contribution guidelines
├── PROJECT_IMPROVEMENTS.md     # Recent improvements
├── QUICKSTART_TESTING.md       # Testing quick start
└── README.md                   # This file
```

## 🔧 Advanced Usage

### Real-Time File Watchers (NEW!)

The system now includes automatic file change detection that monitors collections in real-time. When files are created, modified, deleted, or renamed, they are automatically marked as dirty for processing.

#### Quick Start

**Start watching a single collection:**
```powershell
.\RAG\FileTracker\Start-CollectionWatcher.ps1 -CollectionName "Documents"
```

**Start watching all collections:**
```powershell
.\RAG\FileTracker\Start-AllWatchers.ps1
```

**View watcher status:**
```powershell
.\RAG\FileTracker\Get-FileTrackerStatus.ps1
```

**Stop a watcher:**
```powershell
.\RAG\FileTracker\Stop-CollectionWatcher.ps1 -CollectionName "Documents"
```

**Stop all watchers:**
```powershell
.\RAG\FileTracker\Stop-AllWatchers.ps1
```

#### Features

- ✅ **Real-time monitoring** - Instant detection of file changes
- ✅ **Per-collection watchers** - Independent monitoring for each collection
- ✅ **Automatic dirty marking** - Changed files queued for processing
- ✅ **Respects filters** - Honors include/exclude settings from collection config
- ✅ **Background jobs** - Runs as PowerShell background jobs
- ✅ **Low overhead** - Minimal system resource usage

#### Watcher Events

| Event | Action |
|-------|--------|
| **File Created** | Added to collection, marked as dirty |
| **File Modified** | Marked as dirty for reprocessing |
| **File Deleted** | Marked as deleted in database |
| **File Renamed** | Old file marked deleted, new file added |

#### Complete Workflow Example

```powershell
# 1. Create a collection
.\RAG\FileTracker\Add-Folder.ps1 -CollectionName "MyDocs" -FolderPath "C:\Documents"

# 2. Start watching for changes
.\RAG\FileTracker\Start-CollectionWatcher.ps1 -CollectionName "MyDocs"

# 3. Make changes to files in C:\Documents (watcher detects automatically)

# 4. Process dirty files
.\RAG\Processor\Process-Collection.ps1 -CollectionName "MyDocs"

# 5. Search processed documents
.\RAG\Search\Get-BestDocuments.ps1 -Query "your query" -CollectionName "MyDocs"

# 6. Stop watcher when done
.\RAG\FileTracker\Stop-CollectionWatcher.ps1 -CollectionName "MyDocs"
```

For complete documentation, see **[docs/FILE_WATCHER.md](docs/FILE_WATCHER.md)**.

### Search Operations

The system provides two powerful search scripts for finding relevant content:

#### Document-Level Search with `Get-BestDocuments.ps1`

Finds the most relevant documents based on semantic similarity:

```powershell
# Basic document search
.\RAG\Search\Get-BestDocuments.ps1 -Query "machine learning algorithms" -CollectionName "TechDocs"

# Advanced search with custom parameters
.\RAG\Search\Get-BestDocuments.ps1 `
    -Query "database optimization techniques" `
    -CollectionName "DatabaseDocs" `
    -Threshold 0.8 `
    -MaxResults 10 `
    -ReturnContent $true

# Search without returning full content (faster for large documents)
.\RAG\Search\Get-BestDocuments.ps1 `
    -Query "API documentation" `
    -CollectionName "APIDocs" `
    -ReturnContent $false `
    -MaxResults 20

# Search with LLM-based reranking for improved relevance (NEW!)
.\RAG\Search\Get-BestDocuments.ps1 `
    -Query "security best practices" `
    -CollectionName "SecurityDocs" `
    -EnableReranking `
    -RerankTopK 20 `
    -MaxResults 5
```

**Parameters:**

- `Query`: Search terms or natural language query
- `CollectionName`: Target document collection
- `Threshold`: Similarity threshold (0.0-1.0, default: 0.6)
- `MaxResults`: Maximum documents to return (default: 5)
- `ReturnContent`: Include full document content (default: true)
- `EnableReranking`: Enable LLM-based reranking for better relevance (default: false)
- `RerankModel`: Ollama model to use for reranking (default: embedding model)
- `RerankTopK`: Number of candidates to retrieve before reranking (default: MaxResults × 3)
- `VectorsPort`: Custom API port (uses environment variable if not specified)

#### Chunk-Level Search with `Get-BestChunks.ps1`

Finds specific text chunks within documents for more granular results:

```powershell
# Basic chunk search
.\RAG\Search\Get-BestChunks.ps1 -Query "neural network architecture" -CollectionName "Research"

# Search with document aggregation
.\RAG\Search\Get-BestChunks.ps1 `
    -Query "error handling patterns" `
    -CollectionName "CodeDocs" `
    -AggregateByDocument $true `
    -MaxResults 15

# High-precision search
.\RAG\Search\Get-BestChunks.ps1 `
    -Query "security vulnerabilities" `
    -CollectionName "SecurityDocs" `
    -Threshold 0.9 `
    -MaxResults 5 `
    -AggregateByDocument $false

# Search with LLM-based reranking for better accuracy (NEW!)
.\RAG\Search\Get-BestChunks.ps1 `
    -Query "API authentication methods" `
    -CollectionName "APIDocs" `
    -EnableReranking `
    -RerankTopK 30 `
    -MaxResults 10 `
    -AggregateByDocument $true
```

**Parameters:**

- `Query`: Search terms or natural language query
- `CollectionName`: Target document collection
- `Threshold`: Similarity threshold (0.0-1.0, default: 0.6)
- `MaxResults`: Maximum chunks to return (default: 5)
- `AggregateByDocument`: Group chunks by source document (default: false)
- `EnableReranking`: Enable LLM-based reranking for better relevance (default: false)
- `RerankModel`: Ollama model to use for reranking (default: embedding model)
- `RerankTopK`: Number of candidates to retrieve before reranking (default: MaxResults × 3)
- `VectorsPort`: Custom API port (uses environment variable if not specified)

#### Advanced Search Patterns

**1. Multi-Step Research Workflow with Reranking:**

```powershell
# Step 1: Find relevant documents with reranking
$docs = .\RAG\Search\Get-BestDocuments.ps1 `
    -Query "microservices architecture patterns" `
    -CollectionName "Architecture" `
    -ReturnContent $false `
    -EnableReranking `
    -RerankTopK 40 `
    -MaxResults 20

# Step 2: Get detailed chunks with reranking and aggregation
$chunks = .\RAG\Search\Get-BestChunks.ps1 `
    -Query "service discovery and load balancing" `
    -CollectionName "Architecture" `
    -EnableReranking `
    -RerankTopK 30 `
    -AggregateByDocument $true `
    -MaxResults 10
```

**2. Comparative Analysis:**

```powershell
# Compare different threshold levels
$highPrecision = .\RAG\Search\Get-BestChunks.ps1 `
    -Query "performance optimization" `
    -CollectionName "Performance" `
    -Threshold 0.85 `
    -MaxResults 5

$broadSearch = .\RAG\Search\Get-BestChunks.ps1 `
    -Query "performance optimization" `
    -CollectionName "Performance" `
    -Threshold 0.6 `
    -MaxResults 15
```

**3. Cross-Collection Search:**

```powershell
# Search across multiple collections
$collections = @("TechDocs", "Research", "CodeExamples")
$allResults = @()

foreach ($collection in $collections) {
    $result = .\RAG\Search\Get-BestDocuments.ps1 `
        -Query "artificial intelligence applications" `
        -CollectionName $collection `
        -MaxResults 5
    
    if ($result -and $result.success) {
        $allResults += $result.results
    }
}
```

### Custom Document Processing

```powershell
# Process with custom OCR tool
.\RAG\Processor\Process-Collection.ps1 -CollectionName "MyDocs" -OcrTool "tesseract"
```

### Custom Port Configuration

```powershell
# Start with custom ports
.\RAG\Start-RAG.ps1 -FileTrackerPort 9003 -VectorsPort 9001
```

### Batch Operations

```powershell
# Refresh all collections
.\RAG\FileTracker\Refresh-Collection.ps1 -CollectionName "MyDocs"

# Get collection status
.\RAG\FileTracker\Get-CollectionFiles.ps1 -CollectionName "MyDocs"
```

## 🐍 Python Scripts

The system uses standalone Python scripts for PDF conversion and vector operations, called by PowerShell orchestration.

### PDF Conversion Scripts (`RAG/Processor/Conversion/python_scripts/`)

**Fast Text Extraction:**
```powershell
python pdf_to_markdown_pymupdf.py input.pdf output.md
```
- Uses PyMuPDF for fast, direct text extraction
- Best for text-based PDFs without images
- ~10x faster than OCR methods

**Advanced Conversion (Marker):**
```powershell
python pdf_to_markdown_marker.py input.pdf output.md --batch-multiplier 2
```
- High-quality conversion with layout preservation
- Handles complex documents with tables and images
- Configurable batch multiplier for GPU acceleration

**OCR Support (Tesseract):**
```powershell
python pdf_to_markdown_tesseract.py input.pdf output.md --language eng
```
- OCR for scanned PDFs and images
- Multi-language support (--language parameter)
- Requires Tesseract and Poppler installation

**OCR Support (OCRmyPDF):**
```powershell
python pdf_to_markdown_ocrmypdf.py input.pdf output.md
```
- Advanced OCR with force-OCR option
- Better quality for scanned documents
- Preserves original PDF structure

### Vector Database Scripts (`RAG/Vectors/python_scripts/`)

**Initialize ChromaDB:**
```powershell
python initialize_chromadb.py collection_name [--db-path ./chroma_db]
```
- Creates ChromaDB collections for documents and chunks
- Configurable database path
- Automatic collection naming (e.g., collection_documents, collection_chunks)

**Generate Document Embedding:**
```powershell
python generate_document_embedding.py content.txt ^
    --model mxbai-embed-large:latest ^
    --base-url http://localhost:11434
```
- Generates embeddings for full documents via Ollama API
- Returns JSON with embedding vector
- Configurable model and API endpoint

**Generate Chunk Embeddings:**
```powershell
python generate_chunk_embeddings.py content.txt ^
    --chunk-size 20 ^
    --chunk-overlap 2 ^
    --model mxbai-embed-large:latest
```
- Splits documents into chunks with overlap
- Generates embeddings for each chunk
- Returns JSON array of chunks with embeddings and metadata

**Store Embeddings:**
```powershell
python store_embeddings.py doc_id doc_name metadata.json embedding.json content.txt ^
    --collection-name my_collection ^
    --db-path ./chroma_db
```
- Stores document embeddings in ChromaDB
- Supports custom metadata (JSON format)
- Automatic collection management

### Installation

All Python dependencies are installed during setup:
```powershell
.\RAG\Setup-RAG.ps1 -InstallPath "C:\OllamaRAG"
```

Manual installation:
```powershell
pip install -r RAG/requirements.txt
```

### Script Integration

Python scripts are called by PowerShell functions:
- `Convert-PDFToMarkdown.ps1` → PDF conversion scripts
- `Initialize-VectorDatabase.ps1` → `initialize_chromadb.py`
- `Vectors-Embeddings.psm1` → Embedding generation and storage scripts

All scripts include `--help` for parameter documentation:
```powershell
python script_name.py --help
```

### Architecture Benefits

✅ **Separation of Concerns**: PowerShell orchestration, Python execution  
✅ **Standalone Scripts**: Can be called independently or integrated  
✅ **Testability**: Each script is independently testable  
✅ **Maintainability**: Easier to update and debug  
✅ **Reusability**: Scripts can be used in other projects  

For complete documentation, see `docs/PYTHON_SCRIPTS_README.md`.

## 🧪 Testing

The project includes comprehensive automated testing infrastructure with 59+ tests.

### Run All Tests
```powershell
.\scripts\run-tests.ps1
```

### Run Specific Tests
```powershell
# Unit tests only (fast)
.\scripts\run-tests.ps1 -TestType Unit

# Integration tests
.\scripts\run-tests.ps1 -TestType Integration

# .NET tests only
.\scripts\run-tests.ps1 -TestType DotNet

# With code coverage
.\scripts\run-tests.ps1 -GenerateCoverage
```

### Test Coverage
- ✅ **PowerShell Unit Tests**: 35+ tests for core modules
- ✅ **PowerShell Integration Tests**: 10+ end-to-end workflow tests
- ✅ **.NET Tests**: 14+ tests for MCP server
- ✅ **CI/CD**: Automated testing on Windows, Linux, and macOS

For detailed testing documentation, see:
- **[Testing Guide](docs/TESTING.md)** - Comprehensive testing documentation
- **[Quick Start Testing](QUICKSTART_TESTING.md)** - Get started in 5 minutes

## 🐛 Troubleshooting

### Common Issues

#### 1. Ollama Connection Failed
```powershell
# Check if Ollama is running
ollama list

# Start Ollama
ollama serve

# Verify connection
Invoke-RestMethod -Uri "http://localhost:11434/api/tags"
```

#### 2. Port Already in Use
```powershell
# Check what's using the port
netstat -ano | findstr :10001

# Start with custom ports
.\RAG\Start-RAG.ps1 -FileTrackerPort 9003 -VectorsPort 9001
```

#### 3. PowerShell Module Missing
```powershell
# Install Pode
Install-Module -Name Pode -Force -Scope CurrentUser

# Install Pester (for testing)
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser
```

#### 4. Python Package Issues
```powershell
# Reinstall Python packages
pip install --upgrade chromadb requests numpy

# Verify installation
python -c "import chromadb; print(chromadb.__version__)"
```

#### 5. File Processing Errors
- Verify file permissions in tracked directories
- Check Python installation: `python --version`
- Ensure supported file types (.txt, .md, .html, .csv, .json)
- Check logs in installation directory

#### 6. Database Locked
```powershell
# Close all connections to the database
# Restart the FileTracker API
.\RAG\Start-RAG.ps1
```

### Debugging Tips

#### Enable Verbose Logging
```powershell
# Run with verbose output
.\RAG\Processor\Process-Collection.ps1 -CollectionName "MyDocs" -Verbose
```

#### Check API Health
```powershell
# Check FileTracker API
Invoke-RestMethod -Uri "http://localhost:10003/api/collections"

# Check Vectors API
Invoke-RestMethod -Uri "http://localhost:10001/api/health"
```

#### View Logs
```powershell
# Navigate to installation directory
cd $env:OLLAMA_RAG_INSTALL_PATH

# View recent logs
Get-Content *.log -Tail 50
```

#### Test Individual Components
```powershell
# Test file tracking
.\RAG\FileTracker\Get-FileTrackerStatus.ps1

# Test vector operations
.\RAG\Vectors\Tests\Unit\Vectors-Core.Tests.ps1
```

## 🚀 Performance & Scalability

### Benchmarks
- **Document Processing**: ~100-500 documents/minute (depending on size)
- **Search Latency**: <100ms for typical queries
- **Vector Operations**: Handles 100K+ document embeddings efficiently
- **API Throughput**: 1000+ requests/second

### Optimization Tips
```powershell
# Use smaller chunk sizes for faster processing
.\RAG\Setup-RAG.ps1 -ChunkSize 15 -ChunkOverlap 1

# Disable content return for faster document search
.\RAG\Search\Get-BestDocuments.ps1 -Query "test" -ReturnContent $false

# Process in batches
.\RAG\Processor\Process-Collection.ps1 -CollectionName "Large" -BatchSize 50
```

## 🔐 Security Considerations

- **API Authentication**: Consider adding authentication for production use
- **Input Validation**: All file paths and queries are validated
- **SQL Injection Prevention**: Parameterized queries used throughout
- **File System Access**: Limited to configured directories
- **Rate Limiting**: Implement rate limiting for production deployments

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](docs/CONTRIBUTING.md) for details.

### Quick Contribution Steps
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Write tests for your changes
4. Ensure all tests pass: `.\scripts\run-tests.ps1`
5. Commit your changes: `git commit -m 'Add amazing feature'`
6. Push to your fork: `git push origin feature/amazing-feature`
7. Open a Pull Request

### Development Setup
```powershell
# Clone your fork
git clone https://github.com/YOUR-USERNAME/Ollama-RAG-Sync.git
cd Ollama-RAG-Sync

# Install development dependencies
Install-Module -Name Pester, PSScriptAnalyzer -Force

# Run tests
.\scripts\run-tests.ps1

# Check code quality
Invoke-ScriptAnalyzer -Path .\RAG -Recurse
```

## 📚 Documentation

Comprehensive documentation is available:

- **[Cross-Platform Setup Guide](docs/CROSS_PLATFORM_SETUP.md)** - Installation and configuration for Windows, Linux, and macOS
- **[Architecture Overview](docs/ARCHITECTURE.md)** - System design and structure
- **[File Watcher Guide](docs/FILE_WATCHER.md)** - Real-time file change monitoring *(NEW!)*
- **[Testing Guide](docs/TESTING.md)** - Complete testing documentation
- **[Contributing Guide](docs/CONTRIBUTING.md)** - How to contribute
- **[Multi-Collection Storage](docs/MULTI_COLLECTION_STORAGE.md)** - Collection management guide
- **[Reranking Summary](docs/RERANKING_SUMMARY.md)** - Reranking feature summary
- **[Reranking Guide](RAG/Vectors/RERANKING.md)** - LLM-based reranking documentation
- **[Python Scripts Guide](docs/PYTHON_SCRIPTS_README.md)** - Standalone Python scripts documentation
- **[Quick Start Testing](QUICKSTART_TESTING.md)** - Testing in 5 minutes
- **[Project Improvements](PROJECT_IMPROVEMENTS.md)** - Recent enhancements

## 🗺️ Roadmap

### Current Version (v1.0)
- ✅ Core RAG functionality
- ✅ File tracking and processing
- ✅ Vector search operations
- ✅ MCP server integration
- ✅ Comprehensive testing
- ✅ CI/CD pipeline

### Version 1.1 (Current)
- ✅ LLM-based reranking for improved search relevance
- ✅ Reranking support in both document and chunk searches
- ✅ Configurable reranking models and parameters
- ✅ Comprehensive reranking documentation
- ✅ Multi-collection storage (default + named collections)
- ✅ Flexible document organization and retrieval

### Upcoming Features (v1.2)
- [ ] Web UI for management
- [ ] Advanced PDF processing with OCR
- [ ] Support for more file types
- [ ] Batch reranking optimization
- [ ] Authentication and authorization

## 📊 Project Statistics

- **Language**: PowerShell (75%), C# (20%), Python (5%)
- **Total Tests**: 59+
- **Code Coverage**: 70%+
- **Lines of Code**: ~10,000+
- **Active Development**: Yes ✅

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **[Ollama](https://ollama.ai/)** - For the powerful embedding model infrastructure
- **[Pode](https://github.com/Badgerati/Pode)** - For the excellent PowerShell REST API framework
- **[Model Context Protocol](https://modelcontextprotocol.io/)** - For AI integration standards
- **[ChromaDB](https://www.trychroma.com/)** - For the vector database
- **[Pester](https://pester.dev/)** - For the PowerShell testing framework

## 🌟 Star History

If you find this project useful, please consider giving it a star ⭐

---

## 📞 Contact

For questions, suggestions, or feedback:
- **Email**: xormus@gmail.com
- **Issues**: [Report a bug or request a feature](https://github.com/Ollama-RAG-Sync/Ollama-RAG-Sync/issues/new)

---

**Made with ❤️ by the Ollama-RAG-Sync Team**

*Last updated: October 5, 2025*
