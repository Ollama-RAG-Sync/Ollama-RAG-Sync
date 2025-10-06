# Parameter Validation

## Overview
This document describes the comprehensive parameter validation implemented in the Python embedding generation scripts to ensure robust error handling and helpful user feedback.

## Validation Features

### 1. Input File Validation

Both scripts validate the input content file thoroughly:

#### File Existence
```python
# Checks if file exists
if not os.path.exists(args.content_file):
    errors.append(f"Content file does not exist: {args.content_file}")
```

#### File Type
```python
# Ensures it's a file, not a directory
if not os.path.isfile(args.content_file):
    errors.append(f"Content file path is not a file: {args.content_file}")
```

#### File Size
```python
# Checks for empty files
if os.path.getsize(args.content_file) == 0:
    errors.append(f"Content file is empty: {args.content_file}")
```

#### File Encoding
```python
# Validates UTF-8 encoding
except UnicodeDecodeError as e:
    print(f"ERROR:File encoding error (not valid UTF-8): {file} - {e}")
```

#### File Permissions
```python
# Checks read permissions
except PermissionError as e:
    print(f"ERROR:Permission denied reading file: {file} - {e}")
```

### 2. Chunk Parameters Validation (`generate_chunk_embeddings.py`)

#### chunk_size Validation
```python
# Must be positive
if args.chunk_size <= 0:
    errors.append(f"chunk-size must be positive, got: {args.chunk_size}")

# Must not be excessive
elif args.chunk_size > 10000:
    errors.append(f"chunk-size is too large (max 10000), got: {args.chunk_size}")
```

**Valid range:** 1 - 10,000 lines

**Recommended values:**
- Small chunks: 10-20 lines
- Medium chunks: 20-50 lines
- Large chunks: 50-100 lines

#### chunk_overlap Validation
```python
# Cannot be negative
if args.chunk_overlap < 0:
    errors.append(f"chunk-overlap cannot be negative, got: {args.chunk_overlap}")

# Must be less than chunk_size
elif args.chunk_overlap >= args.chunk_size:
    errors.append(f"chunk-overlap ({args.chunk_overlap}) must be less than chunk-size ({args.chunk_size})")
```

**Valid range:** 0 to (chunk_size - 1)

**Recommended values:**
- No overlap: 0
- Light overlap: 1-2 lines
- Medium overlap: 2-5 lines
- Heavy overlap: 5-10 lines

#### max_workers Validation
```python
# Must be positive
if args.max_workers <= 0:
    errors.append(f"max-workers must be positive, got: {args.max_workers}")

# Must not be excessive
elif args.max_workers > 50:
    errors.append(f"max-workers is too large (max 50), got: {args.max_workers}")
```

**Valid range:** 1 - 50 workers

**Recommended values:**
- Conservative: 3-5 workers
- Standard: 5-10 workers
- Aggressive: 10-20 workers
- Maximum: 20-50 workers (high-end systems only)

### 3. API Configuration Validation

#### Model Name Validation
```python
# Cannot be empty
if not args.model or not args.model.strip():
    errors.append("model name cannot be empty")
```

**Valid:** Any non-empty string
**Examples:** `llama3`, `mxbai-embed-large`, `nomic-embed-text`

#### Base URL Validation
```python
# Must be a valid HTTP(S) URL
if not args.base_url or not args.base_url.strip():
    errors.append("base-url cannot be empty")
elif not (args.base_url.startswith('http://') or args.base_url.startswith('https://')):
    errors.append(f"base-url must start with http:// or https://, got: {args.base_url}")
```

**Valid formats:**
- `http://localhost:11434`
- `https://api.example.com`
- `http://192.168.1.100:8080`

**Invalid formats:**
- `localhost:11434` (missing protocol)
- `example.com` (missing protocol)
- `ftp://example.com` (wrong protocol)

### 4. Log Path Validation

```python
# Creates directory if it doesn't exist
if args.log_path:
    log_dir = os.path.dirname(args.log_path)
    if log_dir and not os.path.exists(log_dir):
        try:
            os.makedirs(log_dir, exist_ok=True)
        except Exception as e:
            errors.append(f"Cannot create log directory: {e}")
```

**Features:**
- Automatically creates parent directories
- Validates write permissions
- Provides helpful error messages

## Error Messages

### Validation Error Format

When validation fails, the script outputs:
```
ERROR:Parameter validation failed:
  - Content file does not exist: /path/to/file.txt
  - chunk-size must be positive, got: -5
  - max-workers is too large (max 50), got: 100
```

### Runtime Error Format

When runtime errors occur:
```
ERROR:File encoding error (not valid UTF-8): file.txt - 'utf-8' codec can't decode byte 0xff
ERROR:Permission denied reading file: file.txt - [Errno 13] Permission denied
ERROR:Failed to read content file: [Errno 2] No such file or directory
```

## Usage Examples

### Valid Usage

#### Chunk Embeddings
```bash
# Minimum valid command
python generate_chunk_embeddings.py document.txt

# All valid parameters
python generate_chunk_embeddings.py document.txt \
    --chunk-size 20 \
    --chunk-overlap 2 \
    --max-workers 5 \
    --model llama3 \
    --base-url http://localhost:11434 \
    --log-path logs/embeddings.log
```

#### Document Embeddings
```bash
# Minimum valid command
python generate_document_embedding.py document.txt

# All valid parameters
python generate_document_embedding.py document.txt \
    --model llama3 \
    --base-url http://localhost:11434 \
    --log-path logs/embeddings.log \
    --exclude-text
```

### Invalid Usage Examples

#### Missing File
```bash
$ python generate_chunk_embeddings.py nonexistent.txt

ERROR:Parameter validation failed:
  - Content file does not exist: nonexistent.txt
```

#### Invalid chunk_size
```bash
$ python generate_chunk_embeddings.py doc.txt --chunk-size -5

ERROR:Parameter validation failed:
  - chunk-size must be positive, got: -5
```

#### Invalid chunk_overlap
```bash
$ python generate_chunk_embeddings.py doc.txt --chunk-size 10 --chunk-overlap 15

ERROR:Parameter validation failed:
  - chunk-overlap (15) must be less than chunk-size (10)
```

#### Invalid max_workers
```bash
$ python generate_chunk_embeddings.py doc.txt --max-workers 100

ERROR:Parameter validation failed:
  - max-workers is too large (max 50), got: 100
```

#### Invalid base_url
```bash
$ python generate_document_embedding.py doc.txt --base-url localhost:11434

ERROR:Parameter validation failed:
  - base-url must start with http:// or https://, got: localhost:11434
```

#### Empty File
```bash
$ python generate_document_embedding.py empty.txt

ERROR:Parameter validation failed:
  - Content file is empty: empty.txt
```

#### File Encoding Error
```bash
$ python generate_document_embedding.py binary.bin

ERROR:File encoding error (not valid UTF-8): binary.bin - 'utf-8' codec can't decode byte 0xff
```

#### Permission Denied
```bash
$ python generate_document_embedding.py /root/protected.txt

ERROR:Permission denied reading file: /root/protected.txt - [Errno 13] Permission denied
```

## Validation Rules Summary

### generate_chunk_embeddings.py

| Parameter | Type | Valid Range | Default | Required |
|-----------|------|-------------|---------|----------|
| content_file | path | Existing readable UTF-8 file | - | Yes |
| chunk_size | int | 1 - 10,000 | 20 | No |
| chunk_overlap | int | 0 to (chunk_size - 1) | 2 | No |
| max_workers | int | 1 - 50 | 5 | No |
| model | string | Non-empty | llama3 | No |
| base_url | URL | http(s)://... | http://localhost:11434 | No |
| log_path | path | Writable path | None | No |
| exclude_text | flag | - | False | No |

### generate_document_embedding.py

| Parameter | Type | Valid Range | Default | Required |
|-----------|------|-------------|---------|----------|
| content_file | path | Existing readable UTF-8 file | - | Yes |
| model | string | Non-empty | llama3 | No |
| base_url | URL | http(s)://... | http://localhost:11434 | No |
| log_path | path | Writable path | None | No |
| exclude_text | flag | - | False | No |

## Best Practices

### 1. Always Provide Valid Paths
```bash
# Good - absolute path
python generate_chunk_embeddings.py /full/path/to/document.txt

# Good - relative path
python generate_chunk_embeddings.py ./documents/doc.txt

# Bad - nonexistent file
python generate_chunk_embeddings.py missing.txt
```

### 2. Use Reasonable Parameters
```bash
# Good - balanced settings
python generate_chunk_embeddings.py doc.txt \
    --chunk-size 20 \
    --chunk-overlap 2 \
    --max-workers 5

# Bad - extreme settings
python generate_chunk_embeddings.py doc.txt \
    --chunk-size 10000 \
    --chunk-overlap 5000 \
    --max-workers 50
```

### 3. Validate Before Processing
```bash
# Check file exists and is readable
if [ -f "document.txt" ] && [ -r "document.txt" ]; then
    python generate_chunk_embeddings.py document.txt
else
    echo "File not found or not readable"
fi
```

### 4. Handle Errors Gracefully
```bash
# Capture exit code
python generate_chunk_embeddings.py doc.txt
if [ $? -ne 0 ]; then
    echo "Processing failed"
    exit 1
fi
```

### 5. Use Appropriate Chunk Sizes
```bash
# Small documents (< 100 lines)
python generate_chunk_embeddings.py small.txt --chunk-size 10

# Medium documents (100-1000 lines)
python generate_chunk_embeddings.py medium.txt --chunk-size 20

# Large documents (> 1000 lines)
python generate_chunk_embeddings.py large.txt --chunk-size 50
```

## PowerShell Integration

The PowerShell modules automatically handle most validation, but you can add extra checks:

```powershell
# Validate file before processing
function Add-DocumentWithValidation {
    param([string]$FilePath)
    
    # Check file exists
    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return $false
    }
    
    # Check file is not empty
    if ((Get-Item $FilePath).Length -eq 0) {
        Write-Error "File is empty: $FilePath"
        return $false
    }
    
    # Process document
    Add-DocumentToVectorStore -FilePath $FilePath
}
```

## Testing Validation

### Create Test Script

```bash
#!/bin/bash
# test_validation.sh

echo "Testing parameter validation..."

# Test 1: Missing file
echo "Test 1: Missing file"
python generate_chunk_embeddings.py nonexistent.txt 2>&1 | grep "does not exist"

# Test 2: Invalid chunk_size
echo "Test 2: Invalid chunk_size"
python generate_chunk_embeddings.py test.txt --chunk-size -5 2>&1 | grep "must be positive"

# Test 3: Invalid chunk_overlap
echo "Test 3: Invalid chunk_overlap"
python generate_chunk_embeddings.py test.txt --chunk-size 10 --chunk-overlap 15 2>&1 | grep "must be less than"

# Test 4: Invalid max_workers
echo "Test 4: Invalid max_workers"
python generate_chunk_embeddings.py test.txt --max-workers 100 2>&1 | grep "too large"

# Test 5: Invalid base_url
echo "Test 5: Invalid base_url"
python generate_document_embedding.py test.txt --base-url localhost 2>&1 | grep "must start with"

echo "All validation tests completed"
```

### PowerShell Test Script

```powershell
# test_validation.ps1

Write-Host "Testing parameter validation..." -ForegroundColor Cyan

# Create test file
"Test content" | Out-File -FilePath "test.txt" -Encoding UTF8

# Test 1: Valid parameters
Write-Host "`nTest 1: Valid parameters" -ForegroundColor Yellow
python generate_chunk_embeddings.py test.txt --chunk-size 10 --max-workers 5

# Test 2: Invalid chunk_size
Write-Host "`nTest 2: Invalid chunk_size" -ForegroundColor Yellow
python generate_chunk_embeddings.py test.txt --chunk-size -5

# Test 3: Invalid chunk_overlap
Write-Host "`nTest 3: Invalid chunk_overlap" -ForegroundColor Yellow
python generate_chunk_embeddings.py test.txt --chunk-size 10 --chunk-overlap 20

# Test 4: Missing file
Write-Host "`nTest 4: Missing file" -ForegroundColor Yellow
python generate_chunk_embeddings.py nonexistent.txt

# Cleanup
Remove-Item test.txt

Write-Host "`nAll tests completed" -ForegroundColor Green
```

## Troubleshooting

### Issue: "Content file does not exist"

**Cause:** File path is incorrect or file doesn't exist

**Solution:**
```bash
# Check if file exists
ls -la /path/to/file.txt

# Use absolute path
python generate_chunk_embeddings.py /absolute/path/to/file.txt

# Or ensure current directory is correct
pwd
python generate_chunk_embeddings.py ./relative/path/to/file.txt
```

### Issue: "File encoding error (not valid UTF-8)"

**Cause:** File is not encoded in UTF-8

**Solution:**
```bash
# Check file encoding
file -i document.txt

# Convert to UTF-8
iconv -f ISO-8859-1 -t UTF-8 document.txt > document_utf8.txt

# Or use Python to convert
python -c "import sys; open('out.txt', 'w').write(open('in.txt', 'r', encoding='latin1').read())"
```

### Issue: "chunk-overlap must be less than chunk-size"

**Cause:** Overlap parameter is >= chunk size

**Solution:**
```bash
# Bad
python generate_chunk_embeddings.py doc.txt --chunk-size 10 --chunk-overlap 10

# Good
python generate_chunk_embeddings.py doc.txt --chunk-size 10 --chunk-overlap 2
```

### Issue: "max-workers is too large"

**Cause:** Requested more than 50 workers

**Solution:**
```bash
# Bad
python generate_chunk_embeddings.py doc.txt --max-workers 100

# Good - use maximum allowed
python generate_chunk_embeddings.py doc.txt --max-workers 50

# Better - use reasonable number
python generate_chunk_embeddings.py doc.txt --max-workers 10
```

## Benefits

### 1. Early Error Detection
Catches errors before processing begins, saving time and resources.

### 2. Clear Error Messages
Provides specific, actionable error messages instead of cryptic stack traces.

### 3. Prevents Invalid States
Ensures parameters are logically consistent (e.g., overlap < chunk_size).

### 4. Better User Experience
Users get immediate feedback on what's wrong and how to fix it.

### 5. Robust Operation
Scripts handle edge cases gracefully without crashing unexpectedly.

## Summary

The parameter validation system provides:

✅ **Comprehensive validation** - Checks all input parameters
✅ **Clear error messages** - Specific, actionable feedback
✅ **Early failure** - Detects errors before processing
✅ **Logical consistency** - Validates parameter relationships
✅ **Helpful guidance** - Shows valid ranges and examples
✅ **Robust error handling** - Graceful handling of edge cases

**Validation checks:**
- File existence and readability
- File encoding (UTF-8)
- Parameter ranges and types
- Logical parameter relationships
- URL format validation
- Directory permissions

All validation is **automatic** and requires no user configuration!
