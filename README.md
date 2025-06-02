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

The system consists of four main components:

### 1. FileTracker
Monitors file collections and tracks changes using SQLite database.
- **Port**: 10003
- **Database**: SQLite-based file tracking
- **Features**: File watching, collection management, change detection

### 2. Processor
Processes documents and converts them to vector embeddings.
- **Port**: 10005
- **Features**: PDF to markdown conversion, text chunking, batch processing

### 3. Vectors
Vector database operations and similarity search.
- **Port**: 10001
- **Features**: Document embedding, similarity search, vector storage

### 4. MCP Server
Model Context Protocol server for AI integration.
- **Technology**: .NET 8.0 C# application
- **Features**: AI assistant integration, protocol compliance

## 📋 Prerequisites

- **PowerShell 7.0+**
- **Ollama** installed and running
- **.NET 8.0 Runtime** (for MCP server)
- **Python 3.8+** (for document processing)

### Required PowerShell Modules
- `Pode` (REST API framework)
- `Microsoft.PowerShell.Management`
- `Microsoft.PowerShell.Utility`

## 🛠️ Installation

### 1. Clone the Repository
```powershell
git clone https://github.com/your-username/Ollama-RAG-Sync.git
cd Ollama-RAG-Sync
```

### 2. Run Setup
```powershell
.\Setup-RAG.ps1 -InstallPath "C:\OllamaRAG"
```

#### Setup Parameters
- `-InstallPath`: Installation directory (required)
- `-EmbeddingModel`: Ollama embedding model (default: `mxbai-embed-large:latest`)
- `-OllamaUrl`: Ollama API URL (default: `http://localhost:11434`)
- `-ChunkSize`: Text chunk size in lines (default: 20)
- `-ChunkOverlap`: Overlap between chunks (default: 2)

### 3. Start the System
```powershell
.\Start-RAG.ps1
```

This will start all components:
- FileTracker API (port 10003)
- Vectors API (port 10001)
- MCP Server

## ⚙️ Configuration

The system uses environment variables for configuration:

| Variable | Description | Default |
|----------|-------------|---------|
| `OLLAMA_RAG_INSTALL_PATH` | Installation directory | Required |
| `OLLAMA_RAG_EMBEDDING_MODEL` | Ollama embedding model | `mxbai-embed-large:latest` |
| `OLLAMA_RAG_URL` | Ollama API URL | `http://localhost:11434` |
| `OLLAMA_RAG_CHUNK_SIZE` | Text chunk size | 20 |
| `OLLAMA_RAG_CHUNK_OVERLAP` | Chunk overlap | 2 |

## 📚 Usage

### Adding a Document Collection
```powershell
# Add a folder to track
.\FileTracker\Add-Folder.ps1 -CollectionName "MyDocs" -FolderPath "C:\Documents"
```

### Processing Documents
```powershell
# Process all dirty files in a collection
.\Processor\Process-Collection.ps1 -CollectionName "MyDocs"
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

### Processor API (Port 10005)
- `POST /api/process/collection` - Process collection
- `POST /api/process/document` - Process single document
- `GET /api/status` - Get processing status

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
├── FileTracker/          # File monitoring and tracking
├── Processor/            # Document processing pipeline
├── Vectors/              # Vector database operations
├── MCP/                  # Model Context Protocol server
├── Setup-RAG.ps1         # Installation script
├── Start-RAG.ps1         # Startup script
└── README.md            # This file
```

## 🔧 Advanced Usage

### Custom Document Processing
```powershell
# Process with custom OCR tool
.\Processor\Process-Collection.ps1 -CollectionName "MyDocs" -OcrTool "tesseract"
```

### Custom Port Configuration
```powershell
# Start with custom ports
.\Start-RAG.ps1 -FileTrackerPort 9003 -VectorsPort 9001 -ProcessorPort 9005
```

### Batch Operations
```powershell
# Refresh all collections
.\FileTracker\Refresh-Collection.ps1 -CollectionName "MyDocs"

# Get collection status
.\FileTracker\Get-CollectionFiles.ps1 -CollectionName "MyDocs"
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
- [FileTracker README](FileTracker/README.md)
- [Processor Documentation](Processor/)
- [Vectors Documentation](Vectors/)
- [MCP Documentation](MCP/)
