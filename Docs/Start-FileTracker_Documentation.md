# Start-FileTracker Documentation

The Start-FileTracker.ps1 script launches the REST API server that enables HTTP-based interaction with the FileTracker system. This server allows applications to monitor file changes, manage file processing status, and retrieve system status information over HTTP.

## Overview

Start-FileTracker.ps1 creates a lightweight HTTP server that:

1. Provides REST API endpoints for managing file collections
2. Enables querying and updating of file status
3. Allows remote applications to interact with the file tracking system
4. Supports scanning directories and monitoring for changes

## Requirements

- PowerShell 7.0 or higher
- SQLite database (created automatically if not present)
- Administrative privileges may be required for certain port bindings

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| FolderPath | string | Yes | - | Path to the folder to monitor for file changes |
| DatabasePath | string | No | [FolderPath]\.ai\FileTracker.db | Path to the SQLite database file |
| Port | int | No | 8080 | Port number for the HTTP server |
| Url | string | No | http://localhost | Base URL for the server |
| ApiPath | string | No | /api | Base path for API endpoints |
| OmitFolders | array | No | @(".ai") | Array of folder names to exclude from tracking |

## Usage Examples

### Basic Usage

```powershell
# Start the server with minimal parameters
.\FileTracker\Start-FileTracker.ps1 -FolderPath "D:\MyDocuments"
```

### Advanced Usage

```powershell
# Start with custom port and excluded folders
.\FileTracker\Start-FileTracker.ps1 -FolderPath "D:\MyDocuments" `
    -Port 8888 `
    -Url "http://localhost" `
    -ApiPath "/filetracker/api" `
    -OmitFolders @(".ai", ".git", "node_modules", "bin")
```

### Using in Scripts

```powershell
# Programmatically start the server
$params = @{
    FolderPath = "D:\MyDocuments"
    Port = 8888
    OmitFolders = @(".ai", ".git")
}
Start-Process -FilePath "pwsh" -ArgumentList "-File .\FileTracker\Start-FileTracker.ps1",
    "-FolderPath `"$($params.FolderPath)`"",
    "-Port $($params.Port)",
    "-OmitFolders @(`"$($params.OmitFolders -join '`",`"')`")" -NoNewWindow
```

## Server Output

When the server starts, it will display:

```
Starting FileTracker REST API Server...
Server listening at http://localhost:8080/api
Press Ctrl+C to stop the server
```

## API Endpoints

For detailed information on the available REST API endpoints and how to use them, see [FileTracker REST API Documentation](./Start-FileTracker_REST_API.md).

## How It Works

1. **Server Initialization**: 
   - The script initializes an HTTP listener on the specified URL and port
   - Routes are registered for each API endpoint
   - Database connection is established

2. **Request Handling**:
   - Incoming HTTP requests are parsed and routed to appropriate handlers
   - JSON request bodies are deserialized into PowerShell objects
   - Database operations are performed based on the request
   - Results are serialized back to JSON and returned

3. **Directory Watching**:
   - The server can initiate directory watching for collections
   - File system events are captured and processed
   - File status is updated in the database

## Security Considerations

The FileTracker REST API server is designed for use in a trusted environment. By default, it binds to localhost only and does not implement authentication. For production use, consider:

1. Using a reverse proxy like Nginx or IIS with SSL/TLS
2. Setting up network rules to restrict access to the API server
3. Running the server with appropriate user permissions

## Common Issues

1. **Port Already In Use**:
   - If the specified port is already in use, the server will fail to start
   - Use a different port with the `-Port` parameter
   - Check for existing processes using the port with `netstat -ano | findstr :8080`

2. **Permission Issues**:
   - Ensure the process has read/write access to the folder and database
   - Run with elevated privileges if necessary

3. **Database Locking**:
   - If multiple processes try to access the database, locking issues may occur
   - The server implements retry logic but may fail if locks persist

## Integration with Other Components

The FileTracker REST API server integrates with these components:

- **FileTracker Database**: Stores collection and file information
- **File Watchers**: Can be started/stopped via API calls
- **Process-Collection.ps1**: Can be triggered to process files marked as dirty
- **Watch-FileTracker.ps1**: Used for file system change detection
- **Client Applications**: Can connect to the REST API for status and control

## Logging

The server logs operations to the console with timestamps and severity levels:

```
[2025-03-30 09:08:50 INFO] Server started at http://localhost:8080/api
[2025-03-30 09:09:15 INFO] GET request received for /api/collections
[2025-03-30 09:10:30 WARNING] Collection ID 5 not found
```

## Stopping the Server

To stop the server, press Ctrl+C in the terminal where it's running. The server will perform cleanup operations before shutting down.
