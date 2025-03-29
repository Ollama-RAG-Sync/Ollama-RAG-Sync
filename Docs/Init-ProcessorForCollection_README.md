# Init-ProcessorForCollection.ps1

This script sets up a collection handler with a given scriptblock and saves it into the database. It allows you to register custom processing logic for specific collections in the Ollama-RAG-Sync system.

## Overview

The `Init-ProcessorForCollection.ps1` script enables you to register custom processing logic for files in a specific collection. The processor scriptblock you provide will be executed for each file in the collection when processing is triggered.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `CollectionName` | string | Yes | The name of the collection to set up the handler for. |
| `CollectionId` | int | Yes | The ID of the collection in the FileTracker database. |
| `HandlerScript` | scriptblock | Yes | The PowerShell scriptblock containing the processing logic. |
| `HandlerParams` | hashtable | No | Additional parameters to pass to the handler scriptblock when it's executed. |
| `DatabasePath` | string | No | Path to the SQLite database. If not provided, uses the default path. |
| `Verbose` | switch | No | Enable verbose logging. |

## Handler Scriptblock Parameters

When your handler scriptblock is executed during processing, it will receive these parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `FilePath` | string | Path to the file being processed. |
| `VectorDbPath` | string | Path to the vector database directory. |
| `OllamaUrl` | string | URL of the Ollama API. |
| `EmbeddingModel` | string | Name of the embedding model to use. |
| `TempDir` | string | Path to the temporary directory. |
| `ScriptPath` | string | Path to the script directory. |
| `CollectionName` | string | Name of the collection being processed. |
| `FileId` | int | ID of the file being processed. |
| `CollectionId` | int | ID of the collection being processed. |
| *Custom Parameters* | varies | Any additional parameters you defined in `HandlerParams`. |

## Usage Example

```powershell
# Define parameters for the handler
$collectionName = "DocumentCollection"
$collectionId = 1 # The collection ID from your FileTracker database

# Create a handler scriptblock
$handlerScriptBlock = {
    param (
        [string]$FilePath,
        [string]$VectorDbPath,
        # ... other standard parameters
        
        # Custom parameters
        [string]$CustomParam1
    )
    
    # Your custom processing logic goes here
    Write-Host "Processing file: $FilePath"
    
    # Process based on file extension
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    if ($extension -eq ".pdf") {
        # Process PDF files
        # Your PDF processing logic here
    }
    elseif ($extension -eq ".md") {
        # Process markdown files
        # Your markdown processing logic here
    }
    
    # Return true to indicate successful processing
    return $true
}

# Define additional parameters for your handler
$handlerParams = @{
    "CustomParam1" = "Value1"
}

# Register the handler
& .\Processor\Init-ProcessorForCollection.ps1 `
    -CollectionName $collectionName `
    -CollectionId $collectionId `
    -HandlerScript $handlerScriptBlock `
    -HandlerParams $handlerParams
```

## Integration with the Processor System

After registering a handler with `Init-ProcessorForCollection.ps1`, the handler will be automatically used by the processor system when processing files in the specified collection. You can start the processor service using `Start-Processor.ps1`.

The custom processor logic will be executed for each file in the collection when:

1. The collection is initially processed
2. New files are added to the collection
3. Existing files in the collection are modified

## Notes

- The scriptblock is stored as a string in the database and later converted back to a scriptblock when executed.
- The handler scriptblock should return `$true` if processing was successful, or `$false` if it failed.
- You can register different handlers for different collections, allowing specialized processing logic for each collection type.
- If a handler already exists for the collection, it will be updated with the new handler.
