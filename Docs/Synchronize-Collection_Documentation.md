# Synchronize-Collection Documentation

The `Synchronize-Collection.ps1` script provides a mechanism to synchronize dirty files from the FileTracker system to the Vectors subsystem using REST APIs. This enables automatic updating of vector embeddings when files are modified, added, or deleted.

## Overview

When files are tracked by FileTracker, they are marked as "dirty" when they are newly added or modified. The `Synchronize-Collection.ps1` script queries FileTracker for these dirty files and processes them by adding them to the Vectors subsystem, then marks them as processed.

This synchronization process can run as a one-time operation or continuously in the background, ensuring that vector embeddings always reflect the latest state of the files.

## Usage

### Direct Script Usage

```powershell
# One-time synchronization
.\Processor\Synchronize-Collection.ps1 -CollectionName "MyCollection"

# Continuous synchronization (polls for changes)
.\Processor\Synchronize-Collection.ps1 -CollectionName "MyCollection" -Continuous -ProcessInterval 5
```

### Via REST API

The synchronization process can also be triggered through the REST API:

```powershell
# Example using Invoke-RestMethod
$params = @{
    collection_name = "MyCollection"
    filetracker_api_url = "http://localhost:8080"
    vectors_api_url = "http://localhost:8082"
    continuous = $false
}

Invoke-RestMethod -Uri "http://localhost:8081/api/synchronize" -Method POST -Body ($params | ConvertTo-Json) -ContentType "application/json"
```

## Parameters

### Script Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| CollectionName | string | Yes | - | Name of the collection to synchronize |
| DatabasePath | string | No | - | Path to the FileTracker database (if not using REST API) |
| VectorsApiUrl | string | No | "http://localhost:8082" | URL for the Vectors REST API |
| FileTrackerApiUrl | string | No | "http://localhost:8080" | URL for the FileTracker REST API |
| ChunkSize | int | No | 1000 | Size of chunks for vector embeddings |
| ChunkOverlap | int | No | 200 | Overlap between consecutive chunks |
| Continuous | switch | No | false | Whether to run in continuous mode |
| ProcessInterval | int | No | 5 | Minutes between synchronization batches in continuous mode |
| StopFilePath | string | No | ".stop_synchronization" | Path to a file that, when created, stops the continuous synchronization |

### REST API Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| collection_name | string | Yes | - | Name of the collection to synchronize |
| filetracker_api_url | string | No | "http://localhost:8080" | URL for the FileTracker REST API |
| vectors_api_url | string | No | "http://localhost:8082" | URL for the Vectors REST API |
| chunk_size | int | No | 1000 | Size of chunks for vector embeddings |
| chunk_overlap | int | No | 200 | Overlap between consecutive chunks |
| continuous | boolean | No | false | Whether to run in continuous mode |

## Process Flow

1. **Query for Dirty Files**: The script queries the FileTracker API to get a list of files marked as "dirty" in the specified collection.

2. **Process Each File**: For each dirty file, the script:
   - Verifies the file exists
   - Determines the file type (text or PDF)
   - Calls the Vectors API to add the document to the vector database
   - Marks the file as processed in FileTracker if the vector operation is successful

3. **Continuous Mode**: If running in continuous mode, the script will:
   - Process the current batch of dirty files
   - Sleep for the specified interval
   - Check for a stop file before each iteration
   - Repeat the process until stopped

## Example Workflows

### Initial Synchronization

When setting up a new RAG system:

1. Initialize a collection in FileTracker
2. Add files to the collection
3. Run `Synchronize-Collection.ps1` to process all files
4. The vector database is now populated and ready for querying

### Continuous Synchronization

For a live system with changing documents:

1. Start FileTracker in watch mode to monitor file changes
2. Start `Synchronize-Collection.ps1` with the `-Continuous` switch
3. As files are added or modified, FileTracker marks them as dirty
4. The synchronization script periodically processes these dirty files
5. The vector database stays up-to-date with the latest document changes

### REST API Integration

For web applications or services:

1. Start the Proxy server with `Start-RAGProxy.ps1`
2. When documents are updated, call the `/api/synchronize` endpoint
3. The synchronization runs as a background job
4. Your application can continue without waiting for completion

## REST API Response

When calling the `/api/synchronize` endpoint, the response includes:

```json
{
  "success": true,
  "message": "Synchronization started for collection: MyCollection",
  "job_id": 123,
  "collection_name": "MyCollection",
  "continuous": false
}
```

- `success`: Whether the synchronization job was started successfully
- `message`: Description of the action taken
- `job_id`: PowerShell job ID (useful for tracking or stopping the job)
- `collection_name`: The collection being synchronized
- `continuous`: Whether the job is running in continuous mode

## Stopping a Continuous Synchronization

There are two ways to stop a continuous synchronization:

1. **Create a stop file**: Create an empty file at the location specified by the `StopFilePath` parameter (default: `.stop_synchronization` in the current directory)

2. **Stop the PowerShell job**: If started via the REST API, you can stop the job using:
   ```powershell
   Stop-Job -Id <job_id>
   ```

## Troubleshooting

### Logs

The script logs its operations to a log file:

```
%APPDATA%\FileTracker\temp\SynchronizeCollection_<CollectionName>_<date>.log
```

This log file contains information about:
- Files being processed
- API calls made
- Errors encountered
- Synchronization status

### Common Issues

1. **API Connection Errors**: Ensure both FileTracker and Vectors API servers are running on the expected URLs.

2. **File Access Issues**: The script needs read access to the files being synchronized.

3. **Missing Files**: If files are deleted before being processed, the script will handle this gracefully and continue.

4. **Database Lock**: If running multiple synchronization processes simultaneously, you may encounter database locking issues.
