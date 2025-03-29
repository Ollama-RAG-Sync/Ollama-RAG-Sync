# Example-InitProcessor.ps1
# Demonstrates how to use Init-ProcessorForCollection.ps1 to set up a collection handler

# Define parameters for the handler
$collectionName = "DocumentCollection"
$collectionId = 1 # This should be the actual collection ID from your FileTracker database

# Create a handler scriptblock
# This scriptblock will be converted to a string and stored in the database
# When processing is triggered, this script will be executed for each file in the collection
$handlerScriptBlock = {
    param (
        # These parameters will be passed to your scriptblock when it's executed
        [string]$FilePath,
        [string]$VectorDbPath,
        [string]$OllamaUrl,
        [string]$EmbeddingModel,
        [string]$TempDir,
        [string]$ScriptPath,
        [string]$CollectionName,
        [int]$FileId,
        [int]$CollectionId,
        
        # Any custom parameters you added will also be available
        [string]$CustomParam1,
        [string]$CustomParam2
    )
    
    # Your custom processing logic goes here
    Write-Host "Processing file: $FilePath" -ForegroundColor Cyan
    Write-Host "Custom Parameter 1: $CustomParam1" -ForegroundColor Yellow
    Write-Host "Custom Parameter 2: $CustomParam2" -ForegroundColor Yellow
    
    # Example: Different processing based on file extension
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    if ($extension -eq ".pdf") {
        # Process PDF files
        Write-Host "Processing PDF file..." -ForegroundColor Magenta
        # Your PDF processing logic here
    }
    elseif ($extension -eq ".md" -or $extension -eq ".txt") {
        # Process markdown or text files
        Write-Host "Processing text/markdown file..." -ForegroundColor Green
        # Your text processing logic here
    }
    else {
        Write-Host "Unsupported file type: $extension" -ForegroundColor Red
    }
    
    # Return true to indicate successful processing
    return $true
}

# Define additional parameters for your handler
# These will be passed to your scriptblock when it's executed
$handlerParams = @{
    "CustomParam1" = "Value1"
    "CustomParam2" = "Value2"
    "MaxFileSize" = 10485760  # 10MB in bytes
}

# Path to the Init-ProcessorForCollection.ps1 script
$initScript = Join-Path -Path $PSScriptRoot -ChildPath "Init-ProcessorForCollection.ps1"

# Call the Init-ProcessorForCollection.ps1 script to register the handler
& $initScript `
    -CollectionName $collectionName `
    -CollectionId $collectionId `
    -HandlerScript $handlerScriptBlock `
    -HandlerParams $handlerParams `
    -Verbose

Write-Host "`nThe handler has been registered for collection '$collectionName'." -ForegroundColor Cyan
Write-Host "When files in this collection are processed, your custom handler will be used." -ForegroundColor Cyan
Write-Host "You can now use Start-Processor.ps1 to start the processor service." -ForegroundColor Cyan
