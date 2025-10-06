# Python Scripts Documentation

This directory contains Python scripts that have been extracted from PowerShell scripts for better maintainability and reusability.

## PDF to Markdown Conversion Scripts

Located in: `RAG/Processor/Conversion/python_scripts/`

### 1. pdf_to_markdown_marker.py
Converts PDF files to Markdown using the Marker library.

**Usage:**
```bash
python pdf_to_markdown_marker.py <pdf_file> <output_markdown_file>
```

**Example:**
```bash
python pdf_to_markdown_marker.py document.pdf output.md
```

**Dependencies:**
- marker-pdf
- PyMuPDF (fitz)

---

### 2. pdf_to_markdown_tesseract.py
Converts PDF files to Markdown using Tesseract OCR.

**Usage:**
```bash
python pdf_to_markdown_tesseract.py <pdf_file> <output_markdown_file> [--poppler-path <path>]
```

**Example:**
```bash
python pdf_to_markdown_tesseract.py document.pdf output.md
python pdf_to_markdown_tesseract.py document.pdf output.md --poppler-path "C:\poppler\bin"
```

**Dependencies:**
- pytesseract
- Pillow
- pdf2image
- Tesseract OCR (system installation required)
- Poppler (system installation required)

---

### 3. pdf_to_markdown_ocrmypdf.py
Converts PDF files to Markdown using OCRmyPDF and PyMuPDF.

**Usage:**
```bash
python pdf_to_markdown_ocrmypdf.py <pdf_file> <output_markdown_file> [--no-force-ocr]
```

**Example:**
```bash
python pdf_to_markdown_ocrmypdf.py document.pdf output.md
python pdf_to_markdown_ocrmypdf.py document.pdf output.md --no-force-ocr
```

**Dependencies:**
- ocrmypdf
- PyMuPDF (fitz)
- Tesseract OCR (system installation required)
- Ghostscript (system installation required)

---

### 4. pdf_to_markdown_pymupdf.py
Converts PDF files to Markdown using PyMuPDF (fastest option, no OCR).

**Usage:**
```bash
python pdf_to_markdown_pymupdf.py <pdf_file> <output_markdown_file>
```

**Example:**
```bash
python pdf_to_markdown_pymupdf.py document.pdf output.md
```

**Dependencies:**
- PyMuPDF (fitz)

---

## Vector Database and Embedding Scripts

Located in: `RAG/Vectors/python_scripts/`

### initialize_chromadb.py
Initializes ChromaDB collections for document and chunk storage.

**Usage:**
```bash
python initialize_chromadb.py <chroma_db_path>
```

**Example:**
```bash
python initialize_chromadb.py "C:\RAG\ChromaDB"
```

**Dependencies:**
- chromadb

**Output:**
The script outputs status messages in the format:
- `SUCCESS:<message>` - Successful operations
- `INFO:<message>` - Informational messages
- `ERROR:<message>` - Error messages

---

### generate_document_embedding.py
Generates vector embeddings for entire documents using Ollama API.

**Usage:**
```bash
python generate_document_embedding.py <content_file> [--model MODEL] [--base-url URL] [--log-path PATH]
```

**Example:**
```bash
python generate_document_embedding.py document.txt --model llama3 --base-url http://localhost:11434
python generate_document_embedding.py content.txt --model llama3 --log-path vectors.log
```

**Parameters:**
- `content_file` - Path to file containing document text (required)
- `--model` - Embedding model to use (default: llama3)
- `--base-url` - Ollama API base URL (default: http://localhost:11434)
- `--log-path` - Path to log file (optional)

**Dependencies:**
- Standard library only (urllib, json)
- Requires Ollama API running

**Output:**
Returns JSON with format:
```json
{
  "text": "document content...",
  "embedding": [0.1, 0.2, ...],
  "duration": 1.23,
  "created_at": "2025-10-06T12:00:00"
}
```

---

### generate_chunk_embeddings.py
Chunks document content by lines and generates embeddings for each chunk using Ollama API.

**Usage:**
```bash
python generate_chunk_embeddings.py <content_file> [--chunk-size SIZE] [--chunk-overlap OVERLAP] [--model MODEL] [--base-url URL] [--log-path PATH]
```

**Example:**
```bash
python generate_chunk_embeddings.py document.txt --chunk-size 20 --chunk-overlap 2
python generate_chunk_embeddings.py content.txt --chunk-size 50 --model llama3 --log-path chunks.log
```

**Parameters:**
- `content_file` - Path to file containing document text (required)
- `--chunk-size` - Number of lines per chunk (default: 20)
- `--chunk-overlap` - Number of lines to overlap between chunks (default: 2)
- `--model` - Embedding model to use (default: llama3)
- `--base-url` - Ollama API base URL (default: http://localhost:11434)
- `--log-path` - Path to log file (optional)

**Dependencies:**
- Standard library only (urllib, json)
- Requires Ollama API running

**Output:**
Returns JSON array of chunks with format:
```json
[
  {
    "chunk_id": 0,
    "text": "chunk content...",
    "start_line": 1,
    "end_line": 20,
    "embedding": [0.1, 0.2, ...],
    "duration": 0.45,
    "created_at": "2025-10-06T12:00:00"
  },
  ...
]
```

---

### store_embeddings.py
Stores document and chunk embeddings in ChromaDB vector database.

**Usage:**
```bash
python store_embeddings.py <doc_embedding_file> <chunk_embeddings_file> <source_path> <document_id> <chroma_db_path> [--collection-name NAME] [--log-path PATH]
```

**Example:**
```bash
python store_embeddings.py doc.json chunks.json "path/to/doc.txt" "doc_123" "C:\RAG\ChromaDB"
python store_embeddings.py doc.json chunks.json "content://id" "unique_id" "C:\DB" --collection-name mycollection --log-path store.log
```

**Parameters:**
- `doc_embedding_file` - Path to JSON file containing document embedding (required)
- `chunk_embeddings_file` - Path to JSON file containing chunk embeddings (required)
- `source_path` - Source file path or identifier (required)
- `document_id` - Unique document identifier (required)
- `chroma_db_path` - Path to ChromaDB storage directory (required)
- `--collection-name` - Collection name to store in (default: default)
- `--log-path` - Path to log file (optional)

**Dependencies:**
- chromadb

**Output:**
Returns success message with document ID and collections used:
```
SUCCESS:Added document to vector store with ID: doc_123 in collections: default, mycollection
```

**Note:** Always stores in "default" collection plus any specified collection name.

---

## Installation

To install all required Python dependencies, run:

```bash
# Install all dependencies from requirements file
pip install -r RAG/requirements.txt

# Or install individually:

# For PDF conversion tools
pip install PyMuPDF marker-pdf pytesseract Pillow pdf2image ocrmypdf

# For vector database and embeddings
pip install chromadb
```

**Note:** Some PDF converters require additional system-level installations:
- **Tesseract OCR**: Download from [UB-Mannheim/tesseract](https://github.com/UB-Mannheim/tesseract/wiki)
- **Poppler**: Download from [poppler-windows](https://github.com/oschwartz10612/poppler-windows/releases/)
- **Ghostscript**: Download from [ghostscript.com](https://ghostscript.com/releases/gsdnld.html)

## Notes

### All Scripts Are Callable
All Python scripts are designed to be:
1. **Executable directly**: They include shebang (`#!/usr/bin/env python3`) and proper `if __name__ == "__main__"` guards
2. **Importable as modules**: Functions can be imported and used in other Python scripts
3. **Well-documented**: Each script includes docstrings and argument parsing with help messages

### Script Categories

**PDF Conversion Scripts (4 scripts):**
- `pdf_to_markdown_marker.py` - Best quality, slowest
- `pdf_to_markdown_tesseract.py` - Good for scanned documents
- `pdf_to_markdown_ocrmypdf.py` - OCR with text extraction
- `pdf_to_markdown_pymupdf.py` - Fastest, no OCR (best for text PDFs)

**Vector & Embedding Scripts (4 scripts):**
- `initialize_chromadb.py` - Database setup
- `generate_document_embedding.py` - Full document vectors
- `generate_chunk_embeddings.py` - Chunked document vectors
- `store_embeddings.py` - Vector database storage

### Exit Codes
All scripts follow standard Unix exit code conventions:
- `0` = Success
- `1` = Failure

### Error Handling
All scripts include comprehensive error handling and will output error messages to stderr when failures occur.

### Output Formats
- Scripts use `SUCCESS:`, `ERROR:`, and `INFO:` prefixes for structured output
- Embedding scripts return JSON for easy parsing
- All timestamps use ISO 8601 format

## Integration with PowerShell

The PowerShell scripts have been updated to call these external Python scripts instead of embedding Python code inline. This provides several benefits:

1. **Better maintainability**: Python code can be edited separately
2. **Easier testing**: Python scripts can be tested independently
3. **Code reusability**: Scripts can be used from other tools or languages
4. **Better IDE support**: Python editors can provide proper syntax highlighting and linting
5. **Version control**: Changes to Python code are more visible in git diffs

### PowerShell Files Updated:
- `RAG/Processor/Conversion/Convert-PDFToMarkdown.ps1` - PDF conversion
- `RAG/Vectors/Functions/Initialize-VectorDatabase.ps1` - ChromaDB initialization
- `RAG/Vectors/Modules/Vectors-Embeddings.psm1` - Embedding generation and storage

### Usage from PowerShell (unchanged):
```powershell
# PDF Conversion
.\RAG\Processor\Conversion\Convert-PDFToMarkdown.ps1 `
    -PdfFilePath "document.pdf" `
    -OutputFilePath "output.md" `
    -OcrTool "pymupdf"

# ChromaDB Initialization
.\RAG\Vectors\Functions\Initialize-VectorDatabase.ps1 `
    -ChromaDbPath "C:\RAG\ChromaDB"

# Generate embeddings (via module)
Import-Module .\RAG\Vectors\Modules\Vectors-Embeddings.psm1
$embedding = Get-DocumentEmbedding -FilePath "document.txt"
$chunks = Get-ChunkEmbeddings -Content $text -ChunkSize 20
Add-DocumentToVectorStore -FilePath "document.txt" -CollectionName "docs"
```

## Troubleshooting

### Script Not Found Errors
If you get "Python script not found" errors from PowerShell, ensure:
1. The Python script files exist in the correct directories
2. File paths are correct (check backslashes on Windows)
3. You're running the PowerShell scripts from the expected location

### Python Import Errors
If you get import errors, ensure all dependencies are installed:
```bash
pip list  # Check installed packages
pip install <missing-package>  # Install missing packages
```

### Permission Errors
On Unix-like systems, you may need to make the scripts executable:
```bash
chmod +x RAG/Processor/Conversion/python_scripts/*.py
chmod +x RAG/Vectors/python_scripts/*.py
```

### Ollama API Errors
If embedding generation fails:
1. Ensure Ollama is running: `ollama serve`
2. Check the model is available: `ollama list`
3. Pull the model if needed: `ollama pull llama3`
4. Verify the base URL is correct (default: http://localhost:11434)

### ChromaDB Errors
If database operations fail:
1. Ensure the ChromaDB path exists and is writable
2. Check ChromaDB version: `pip show chromadb`
3. Try initializing manually: `python initialize_chromadb.py <path>`
4. Check logs for detailed error messages

## Complete Script Reference

### PDF Conversion Scripts
| Script | Use Case | Speed | Quality | OCR |
|--------|----------|-------|---------|-----|
| `pdf_to_markdown_pymupdf.py` | Text PDFs | ⚡⚡⚡ Fast | Good | ❌ No |
| `pdf_to_markdown_marker.py` | High quality | 🐌 Slow | Excellent | ✅ Yes |
| `pdf_to_markdown_tesseract.py` | Scanned docs | 🐌 Slow | Good | ✅ Yes |
| `pdf_to_markdown_ocrmypdf.py` | Mixed content | 🐌 Slow | Good | ✅ Yes |

### Vector & Embedding Scripts
| Script | Purpose | Requires Ollama |
|--------|---------|-----------------|
| `initialize_chromadb.py` | Setup database | ❌ No |
| `generate_document_embedding.py` | Full doc vectors | ✅ Yes |
| `generate_chunk_embeddings.py` | Chunked vectors | ✅ Yes |
| `store_embeddings.py` | Save to database | ❌ No |

## Quick Start

### Convert a PDF:
```bash
python RAG/Processor/Conversion/python_scripts/pdf_to_markdown_pymupdf.py input.pdf output.md
```

### Setup Vector Database:
```bash
python RAG/Vectors/python_scripts/initialize_chromadb.py "C:\RAG\ChromaDB"
```

### Generate Embeddings:
```bash
# Create a text file
echo "Sample document content" > doc.txt

# Generate document embedding
python RAG/Vectors/python_scripts/generate_document_embedding.py doc.txt --model llama3 > doc_embedding.json

# Generate chunk embeddings
python RAG/Vectors/python_scripts/generate_chunk_embeddings.py doc.txt --chunk-size 20 > chunk_embeddings.json

# Store in database
python RAG/Vectors/python_scripts/store_embeddings.py doc_embedding.json chunk_embeddings.json "doc.txt" "doc_001" "C:\RAG\ChromaDB"
```

## Additional Resources

- **Full Documentation**: See `PYTHON_EXTRACTION_SUMMARY.md` for complete migration details
- **Verification Guide**: See `VERIFICATION_GUIDE.md` for testing instructions
- **Vector Module Details**: See `VECTORS_EMBEDDINGS_EXTRACTION.md` for embedding specifics
- **Requirements File**: `RAG/requirements.txt` for all dependencies
