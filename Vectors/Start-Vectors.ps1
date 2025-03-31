# Start-Vectors.ps1
# Main entry point for the Vectors subsystem

param(
    [Parameter(Mandatory=$false)]
    [string]$ChromaDbPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 200,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Info", "Warning", "Error")]
    [string]$LogLevel = "Info",
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowDatabaseInfo,
    
    [Parameter(Mandatory=$false)]
    [switch]$Initialize,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestQuery,
    
    [Parameter(Mandatory=$false)]
    [string]$TestQueryText = "Test query to verify the vector database is working"
)

# Set strict mode for error handling
Set-StrictMode -Version Latest

# Set error action preference
$ErrorActionPreference = "Stop"

# Get the script path
$scriptPath = $PSScriptRoot
$modulesPath = Join-Path -Path $scriptPath -ChildPath "Modules"

# Import required modules
Import-Module "$modulesPath\Vectors-Core.psm1" -Force
Import-Module "$modulesPath\Vectors-Database.psm1" -Force
Import-Module "$modulesPath\Vectors-Embeddings.psm1" -Force

# Create banner
function Show-VectorsBanner {
    $banner = @"
 __      __        _                    
 \ \    / /       | |                   
  \ \  / /__  __ _| |_ ___  _ __ ___    
   \ \/ / _ \/ _` | __/ _ \| '__/ __|   
    \  /  __/ (_| | || (_) | |  \__ \   
     \/ \___|\__,_|\__\___/|_|  |___/   

 Ollama Vectors Subsystem for Document Storage and Retrieval
 Provides vector-based document storage and retrieval capabilities
 Using ChromaDB and Ollama for embeddings
"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host
}

# Show the banner
Show-VectorsBanner

# Ensure ChromaDbPath is set properly
if (-not $ChromaDbPath) {
    # Use default path in the Data directory
    $ChromaDbPath = Join-Path -Path $scriptPath -ChildPath "..\Data\ChromaDb"
}

# Set up configuration
$configOverrides = @{
    ChromaDbPath = $ChromaDbPath
    OllamaUrl = $OllamaUrl
    EmbeddingModel = $EmbeddingModel
    ChunkSize = $ChunkSize
    ChunkOverlap = $ChunkOverlap
    LogLevel = $LogLevel
}

# Initialize configuration
Write-Host "Initializing Vectors configuration..." -ForegroundColor Green
$config = Initialize-VectorsConfig -ConfigOverrides $configOverrides

# Display configuration
Write-Host "Configuration:" -ForegroundColor Green
Write-Host " - ChromaDB Path: $($config.ChromaDbPath)" -ForegroundColor White
Write-Host " - Ollama URL: $($config.OllamaUrl)" -ForegroundColor White
Write-Host " - Embedding Model: $($config.EmbeddingModel)" -ForegroundColor White
Write-Host " - Chunk Size: $($config.ChunkSize)" -ForegroundColor White
Write-Host " - Chunk Overlap: $($config.ChunkOverlap)" -ForegroundColor White

# Check requirements
Write-Host "Checking system requirements..." -ForegroundColor Green
$requirementsMet = Test-VectorsRequirements

if (-not $requirementsMet) {
    Write-Host "Not all system requirements are met. See above details for what's missing." -ForegroundColor Red
    Write-Host "Please install all required dependencies and try again." -ForegroundColor Red
    return
}

# Initialize the vector database
if ($Initialize) {
    Write-Host "Initializing vector database..." -ForegroundColor Green
    $dbInit = Initialize-VectorDatabase
    if (-not $dbInit) {
        Write-Host "Failed to initialize vector database. Check the error logs for details." -ForegroundColor Red
        return
    }
    Write-Host "Vector database initialized successfully." -ForegroundColor Green
}

# Show database info if requested
if ($ShowDatabaseInfo) {
    Write-Host "Retrieving vector database information..." -ForegroundColor Green
    $dbInfo = Get-VectorDatabaseInfo
    
    if ($dbInfo) {
        Write-Host "Database Path: $($dbInfo.db_path)" -ForegroundColor Green
        
        # Display collections
        foreach ($collection in $dbInfo.collections) {
            Write-Host "`nCollection: $($collection.name)" -ForegroundColor Yellow
            Write-Host " - Document Count: $($collection.count)" -ForegroundColor White
            
            # Show sample IDs if available
            if ($collection.sample_ids -and $collection.sample_ids.Count -gt 0) {
                Write-Host " - Sample IDs:" -ForegroundColor White
                foreach ($id in $collection.sample_ids) {
                    Write-Host "   - $id" -ForegroundColor Gray
                }
            }
        }
    } else {
        Write-Host "Failed to retrieve database information or database is empty." -ForegroundColor Yellow
    }
}

# Run a test query if requested
if ($TestQuery) {
    Write-Host "Running test query: '$TestQueryText'" -ForegroundColor Green
    
    # Test document query
    Write-Host "`nQuerying documents..." -ForegroundColor Yellow
    $docResults = Query-VectorDocuments -QueryText $TestQueryText -MaxResults 3
    
    if ($docResults -and $docResults.Count -gt 0) {
        Write-Host "Found $($docResults.Count) matching documents." -ForegroundColor Green
        foreach ($result in $docResults) {
            Write-Host "`n   Document: $($result.id)" -ForegroundColor White
            Write-Host "   Similarity: $([Math]::Round($result.similarity * 100, 2))%" -ForegroundColor White
            Write-Host "   Source: $($result.metadata.source)" -ForegroundColor White
        }
    } else {
        Write-Host "No matching documents found. The database may be empty." -ForegroundColor Yellow
    }
    
    # Test chunk query
    Write-Host "`nQuerying chunks..." -ForegroundColor Yellow
    $chunkResults = Query-VectorChunks -QueryText $TestQueryText -MaxResults 3
    
    if ($chunkResults -and $chunkResults.Count -gt 0) {
        Write-Host "Found $($chunkResults.Count) matching chunks." -ForegroundColor Green
        foreach ($result in $chunkResults) {
            Write-Host "`n   Chunk: $($result.id)" -ForegroundColor White
            Write-Host "   Similarity: $([Math]::Round($result.similarity * 100, 2))%" -ForegroundColor White
            Write-Host "   Source: $($result.metadata.source)" -ForegroundColor White
        }
    } else {
        Write-Host "No matching chunks found. The database may be empty." -ForegroundColor Yellow
    }
}

# If no specific actions requested, explain how to use the service
if (-not ($Initialize -or $ShowDatabaseInfo -or $TestQuery)) {
    Write-Host "`nVectors subsystem is ready to use." -ForegroundColor Green
    Write-Host "To interact with vectors, use the following functions:" -ForegroundColor Yellow
    
    Write-Host "`n  * Add documents to the vector store:" -ForegroundColor White
    Write-Host "    .\Functions\Add-DocumentToVectors.ps1 -FilePath <path>" -ForegroundColor Gray
    
    Write-Host "`n  * Query for similar documents:" -ForegroundColor White
    Write-Host "    .\Functions\Get-DocumentsByQuery.ps1 -QueryText 'your query here'" -ForegroundColor Gray
    
    Write-Host "`n  * Query for relevant document chunks:" -ForegroundColor White
    Write-Host "    .\Functions\Get-ChunksByQuery.ps1 -QueryText 'your query here' -AggregateByDocument" -ForegroundColor Gray
    
    Write-Host "`n  * Remove documents from the vector store:" -ForegroundColor White
    Write-Host "    .\Functions\Remove-DocumentFromVectors.ps1 -FilePath <path>" -ForegroundColor Gray
    
    Write-Host "`nFor more information, see the help comments in each script file." -ForegroundColor Yellow
}

# Export functions from modules to make them accessible
Import-Module "$modulesPath\Vectors-Core.psm1"
Import-Module "$modulesPath\Vectors-Database.psm1"
Import-Module "$modulesPath\Vectors-Embeddings.psm1"

# Return info about the paths to the module files
return @{
    CoreModulePath = "$modulesPath\Vectors-Core.psm1"
    DatabaseModulePath = "$modulesPath\Vectors-Database.psm1"
    EmbeddingsModulePath = "$modulesPath\Vectors-Embeddings.psm1"
    FunctionsPath = Join-Path -Path $scriptPath -ChildPath "Functions"
}
