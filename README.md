# Ollama-RAG-Sync

A comprehensive PowerShell-based RAG (Retrieval-Augmented Generation) system that integrates with Ollama for document processing, vector storage, and intelligent search capabilities. The system automatically tracks file changes, processes documents, and maintains synchronized vector embeddings for efficient retrieval.

## 🚀 Features

- **Automated File Tracking**: Monitor directories for changes and automatically process new/modified files
- **Document Processing**: Convert PDFs and other documents to embeddings with chunking support
- **Vector Database**: Store and search document embeddings using Ollama models
- **REST APIs**: Complete API ecosystem for file tracking, processing, and vector operations
- **MCP Integration**: Model Context Protocol server for AI assistant integration
- **Flexible Configuration**: Environment-based configuration with sensible defaults

## 🏗️ Architecture

The system consists of five main components organized under the `RAG/` and `MCP/` directories:

### 1. FileTracker (`RAG/FileTracker/`)

Monitors file collections and tracks changes using SQLite database.

- **Port**: 10003 (configurable via `OLLAMA_RAG_FILE_TRACKER_API_PORT`)
- **Database**: SQLite-based file tracking
- **Features**: File watching, collection management, change detection

### 2. Processor (`RAG/Processor/`)

Processes documents and converts them to vector embeddings.

- **Features**: PDF to markdown conversion, text chunking, batch processing
- **Conversion**: Supports PDF to markdown conversion in `Conversion/` subdirectory

### 3. Vectors (`RAG/Vectors/`)

Vector database operations and similarity search.

- **Port**: 10001 (configurable via `OLLAMA_RAG_VECTORS_API_PORT`)
- **Features**: Document embedding, similarity search, vector storage
- **Modules**: Core functionality in `Modules/` and API functions in `Functions/`

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

- **PowerShell 7.0+**
- **Ollama** installed and running
- **.NET 8.0 Runtime** (for MCP server)
- **Python 3.8+** (for document processing)

### Required PowerShell Modules
- `Pode` (REST API framework)

## 🛠️ Installation

### 1. Clone the Repository
```powershell
git clone https://github.com/your-username/Ollama-RAG-Sync.git
cd Ollama-RAG-Sync
```

### 2. Run Setup

```powershell
.\RAG\Setup-RAG.ps1 -InstallPath "C:\OllamaRAG"
```

#### Setup Parameters

- `-InstallPath`: Installation directory (required)
- `-EmbeddingModel`: Ollama embedding model (default: `mxbai-embed-large:latest`)
- `-OllamaUrl`: Ollama API URL (default: `http://localhost:11434`)
- `-ChunkSize`: Text chunk size in lines (default: 20)
- `-ChunkOverlap`: Overlap between chunks (default: 2)

### 3. Start the System

```powershell
.\RAG\Start-RAG.ps1
```

This will start all components:
- FileTracker API (port 10003)
- Vectors API (port 10001)

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

### Adding a Document Collection

```powershell
# Add a folder to track
.\RAG\FileTracker\Add-Folder.ps1 -CollectionName "MyDocs" -FolderPath "C:\Documents"
```

### Processing Documents

```powershell
# Process all dirty files in a collection
.\RAG\Processor\Process-Collection.ps1 -CollectionName "MyDocs"
```

### Searching Documents
Use the REST API endpoints or integrate with the MCP server for AI-powered search.

## 🔌 API Endpoints

### FileTracker API (Port 10003)
- `GET /api/collections` - List all collections
- `POST /api/collections` - Create new collection
- `GET /api/collections/{name}/files` - Get files in collection
- `PUT /api/files/{id}/status` - Update file status

### Vectors API (Port 10001)

- `POST /api/documents` - Add document to vector database
- `DELETE /api/documents/{id}` - Remove document
- `POST /api/search/documents` - Search documents by query
- `POST /api/search/chunks` - Search text chunks

## 🤖 MCP Integration

The MCP server provides AI assistant integration:

```bash
# Build the MCP server
cd MCP
dotnet build

# The server is automatically started with Start-RAG.ps1
```

## 📁 Project Structure

```
Ollama-RAG-Sync/
├── RAG/                  # Main RAG system components
│   ├── FileTracker/      # File monitoring and tracking
│   ├── Processor/        # Document processing pipeline
│   │   └── Conversion/   # PDF to markdown conversion
│   ├── Search/           # High-level search operations
│   ├── Vectors/          # Vector database operations
│   │   ├── Functions/    # Vector API functions
│   │   └── Modules/      # Core vector modules
│   ├── Setup-RAG.ps1     # Installation script
│   └── Start-RAG.ps1     # Startup script
├── MCP/                  # Model Context Protocol server
│   ├── Program.cs        # MCP server implementation
│   ├── Ollama-RAG-Sync.csproj
│   └── Ollama-RAG-Sync.sln
└── README.md            # This file
```

## 🔧 Advanced Usage

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
```

**Parameters:**

- `Query`: Search terms or natural language query
- `CollectionName`: Target document collection
- `Threshold`: Similarity threshold (0.0-1.0, default: 0.6)
- `MaxResults`: Maximum documents to return (default: 5)
- `ReturnContent`: Include full document content (default: true)
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
```

**Parameters:**

- `Query`: Search terms or natural language query
- `CollectionName`: Target document collection
- `Threshold`: Similarity threshold (0.0-1.0, default: 0.6)
- `MaxResults`: Maximum chunks to return (default: 5)
- `AggregateByDocument`: Group chunks by source document (default: false)
- `VectorsPort`: Custom API port (uses environment variable if not specified)

#### Advanced Search Patterns

**1. Multi-Step Research Workflow:**

```powershell
# Step 1: Find relevant documents
$docs = .\RAG\Search\Get-BestDocuments.ps1 `
    -Query "microservices architecture patterns" `
    -CollectionName "Architecture" `
    -ReturnContent $false `
    -MaxResults 20

# Step 2: Get detailed chunks from top documents
$chunks = .\RAG\Search\Get-BestChunks.ps1 `
    -Query "service discovery and load balancing" `
    -CollectionName "Architecture" `
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

## 🐛 Troubleshooting

### Common Issues

1. **Ollama Connection Failed**
   - Ensure Ollama is running: `ollama serve`
   - Check the URL in environment variables

2. **Port Conflicts**
   - Modify port numbers in `Start-RAG.ps1`
   - Check for running processes: `netstat -an | findstr :10001`

3. **PowerShell Module Missing**

   ```powershell
   Install-Module -Name Pode -Force
   ```

4. **File Processing Errors**
   - Check Python dependencies for PDF processing
   - Verify file permissions in tracked directories

### Logs and Debugging

- Log files are created in the installation directory
- Use `-Verbose` flag on scripts for detailed output
- Check Windows Event Log for system-level issues

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the terms specified in the LICENSE file.

## 🙏 Acknowledgments

- [Ollama](https://ollama.ai/) for the embedding model infrastructure
- [Pode](https://github.com/Badgerati/Pode) for the PowerShell REST API framework
- [Model Context Protocol](https://modelcontextprotocol.io/) for AI integration standards

---

For detailed component documentation, see the README files in each subdirectory:

- [FileTracker README](RAG/FileTracker/README.md)
- [Processor Documentation](RAG/Processor/)
- [Vectors Documentation](RAG/Vectors/)
- [Search Documentation](RAG/Search/)
- [MCP Documentation](MCP/)
