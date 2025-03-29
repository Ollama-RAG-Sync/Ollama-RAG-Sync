# FileTracker REST API Documentation

The FileTracker REST API provides HTTP endpoints to interact with the file tracking system. This enables applications to monitor file changes, manage file processing status, and retrieve system status information over HTTP.

## Starting the Server

To start the FileTracker REST API server, run the `Start-FileTracker.ps1` script with the following parameters:

```powershell
# Basic usage with required parameters
.\FileTracker\Start-FileTracker.ps1 -FolderPath "D:\MyDocuments"

# With optional parameters
.\FileTracker\Start-FileTracker.ps1 -FolderPath "D:\MyDocuments" -Port 8888 -Url "http://localhost" -ApiPath "/api" -OmitFolders @(".ai", ".git")
```

### Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| FolderPath | Path to the folder to monitor for file changes | - | Yes |
| DatabasePath | Path to the SQLite database file | [FolderPath]\.ai\FileTracker.db | No |
| Port | Port number for the HTTP server | 8080 | No |
| Url | Base URL for the server | http://localhost | No |
| ApiPath | Base path for API endpoints | /api | No |
| OmitFolders | Array of folder names to exclude from tracking | @(".ai") | No |

## API Endpoints

### Collection Management

#### GET /collections

Returns a list of all collections.

**Example Request:**
```
GET http://localhost:8080/api/collections
```

**Response:**
```json
{
  "success": true,
  "collections": [
    {
      "id": 1,
      "name": "My Documents",
      "description": "Personal documents collection"
    }
  ],
  "count": 1
}
```

#### POST /collections

Creates a new collection.

**Request Body:**
```json
{
  "name": "Work Documents",
  "description": "Work-related documents collection"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Collection created successfully",
  "collection": {
    "id": 2,
    "name": "Work Documents",
    "description": "Work-related documents collection"
  }
}
```

#### GET /collections/{id}

Returns information about a specific collection.

**Example Request:**
```
GET http://localhost:8080/api/collections/1
```

**Response:**
```json
{
  "success": true,
  "collection": {
    "id": 1,
    "name": "My Documents",
    "description": "Personal documents collection"
  }
}
```

#### PUT /collections/{id}

Updates a collection's information.

**Request Body:**
```json
{
  "name": "Updated Collection Name",
  "description": "Updated description"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Collection updated successfully",
  "collection": {
    "id": 1,
    "name": "Updated Collection Name",
    "description": "Updated description"
  }
}
```

#### DELETE /collections/{id}

Deletes a collection.

**Example Request:**
```
DELETE http://localhost:8080/api/collections/1
```

**Response:**
```json
{
  "success": true,
  "message": "Collection deleted successfully"
}
```

### Collection Files Management

#### GET /collections/{id}/files

Returns a list of files in a specific collection.

**Query Parameters:**
- `dirty=true` - Get only files marked as dirty (need processing)
- `processed=true` - Get only processed files
- `deleted=true` - Get only files marked as deleted

**Example Request:**
```
GET http://localhost:8080/api/collections/1/files?dirty=true
```

**Response:**
```json
{
  "success": true,
  "files": [
    {
      "id": 1,
      "filePath": "D:\\MyDocuments\\document.txt",
      "lastModified": "2025-03-29T12:00:00.0000000Z",
      "dirty": true,
      "deleted": false,
      "collection_id": 1
    }
  ],
  "count": 1,
  "collection_id": 1
}
```

#### POST /collections/{id}/files

Adds a file to a collection.

**Request Body:**
```json
{
  "filePath": "D:\\MyDocuments\\newdocument.txt",
  "originalUrl": "http://source.com/newdocument.txt",
  "dirty": true
}
```

**Response:**
```json
{
  "success": true,
  "message": "File added to collection",
  "file": {
    "id": 2,
    "filePath": "D:\\MyDocuments\\newdocument.txt",
    "originalUrl": "http://source.com/newdocument.txt",
    "lastModified": "2025-03-29T14:30:00.0000000Z",
    "dirty": true,
    "deleted": false,
    "collection_id": 1
  }
}
```

#### PUT /collections/{id}/files

Marks all files in a collection as dirty or processed.

**Request Body:**
```json
{
  "dirty": true
}
```

**Response:**
```json
{
  "success": true,
  "message": "All files in collection updated successfully",
  "dirty": true
}
```

#### DELETE /collections/{id}/files/{fileId}

Removes a file from a collection.

**Example Request:**
```
DELETE http://localhost:8080/api/collections/1/files/2
```

**Response:**
```json
{
  "success": true,
  "message": "File removed from collection"
}
```

#### PUT /collections/{id}/files/{fileId}

Updates a file's status in a collection.

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
  "message": "File status updated successfully",
  "file_id": 1,
  "dirty": false
}
```

#### POST /collections/{id}/update

Scans the monitored folder for changes and updates the collection.

**Request Body (optional):**
```json
{
  "omitFolders": [".ai", ".git", "node_modules"]
}
```

**Response:**
```json
{
  "success": true,
  "message": "Collection files updated successfully",
  "summary": {
    "newFiles": 5,
    "modifiedFiles": 3,
    "unchangedFiles": 20,
    "removedFiles": 1,
    "filesToProcess": 9,
    "filesToDelete": 1
  },
  "collection_id": 1,
  "omittedFolders": [".ai", ".git", "node_modules"]
}
```

### Common Endpoints

#### GET /status

Returns overall status information about tracked files.

**Example Request:**
```
GET http://localhost:8080/api/status
```

**Response:**
```json
{
  "success": true,
  "status": {
    "totalFiles": 30,
    "dirtyFiles": 9,
    "processedFiles": 21,
    "deletedFiles": 1
  }
}
```

## Error Handling

All endpoints return a consistent error format:

```json
{
  "success": false,
  "error": "Error message describing what went wrong"
}
```

HTTP status codes are used appropriately:
- 200: Success
- 400: Bad Request (missing or invalid parameters)
- 404: Endpoint not found
- 405: Method Not Allowed
- 500: Internal Server Error

## CORS Support

The API includes CORS (Cross-Origin Resource Sharing) support, allowing access from web applications hosted on different domains. The following headers are included in responses:

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

## Integration Examples

### PowerShell

```powershell
# Get files from a collection
$response = Invoke-RestMethod -Uri "http://localhost:8080/api/collections/1/files?dirty=true" -Method Get

# Mark a file as processed
$body = @{
    dirty = $false
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "http://localhost:8080/api/collections/1/files/1" -Method Put -Body $body -ContentType "application/json"

# Update a collection
$response = Invoke-RestMethod -Uri "http://localhost:8080/api/collections/1/update" -Method Post
```

### JavaScript/Fetch

```javascript
// Get status
fetch('http://localhost:8080/api/status')
  .then(response => response.json())
  .then(data => console.log(data));

// Mark all files in a collection as dirty
fetch('http://localhost:8080/api/collections/1/files', {
  method: 'PUT',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    dirty: true
  })
})
  .then(response => response.json())
  .then(data => console.log(data));
```

### Python/Requests

```python
import requests
import json

# Get dirty files from a collection
response = requests.get('http://localhost:8080/api/collections/1/files?dirty=true')
data = response.json()
print(f"Found {data['count']} dirty files in collection {data['collection_id']}")

# Update collection with custom omit folders
payload = {
    'omitFolders': ['.ai', '.git', 'bin']
}
response = requests.post('http://localhost:8080/api/collections/1/update', json=payload)
data = response.json()
print(f"Update summary: {data['summary']}")
```

## Security Considerations

The FileTracker REST API is designed for use in a trusted environment. It does not include authentication or encryption by default. If security is required:

1. Use a reverse proxy like Nginx or IIS with SSL/TLS
2. Set up network rules to restrict access to the API server
3. Run the server with appropriate user permissions
