<#
.SYNOPSIS
    Starts files processing and live-synchronization in a Retrieval-Augmented Generation (RAG) environment.

.DESCRIPTION
    This script begins the processing of dirty files in the RAG environment and sets up live-synchronization for 
    added, changed, and removed files. It:
    1. Starts the file tracking system to mark changed files as dirty
    2. Initiates a process to periodically check for and process dirty files
    3. Starts the API proxy server for RAG-enhanced chat capabilities
    4. Maintains background jobs that continuously update the vector database

.PARAMETER DirectoryPath
    The path to the directory being monitored for RAG operations.
    
.PARAMETER EmbeddingModel
    The name of the embedding model to use (default: "mxbai-embed-large:latest").

.PARAMETER OllamaUrl
    The URL of the Ollama API (default: "http://localhost:11434").

.PARAMETER FileFilter
    The filter for files to monitor (default: "*.*").

.PARAMETER IncludeSubdirectories
    Whether to include subdirectories when monitoring files (default: true).

.PARAMETER ProcessInterval
    How often (in seconds) to process dirty files (default: 30).

.PARAMETER TextFileExtensions
    File extensions to be processed as text (default: ".txt,.md,.html,.csv,.json").

.PARAMETER PDFFileExtension
    File extension for PDF documents (default: ".pdf").

.PARAMETER UseChunking
    Whether to use chunking for text processing (default: true).

.PARAMETER ChunkSize
    Size of chunks when chunking is enabled (default: 1000).

.PARAMETER ChunkOverlap
    Overlap between chunks when chunking is enabled (default: 200).

.PARAMETER FileTrackerPort
    Port for the FileTracker service (default: 8080).

.PARAMETER ProcessorPort
    Port for the Processor REST API service (default: 8083).

.PARAMETER VectorsPort
    Port for the Vectors API service (default: 8082).

.PARAMETER ApiProxyPort
    Port for the API proxy server (default: 8081).

.PARAMETER MaxContextDocs
    Maximum number of context documents to include in RAG responses (default: 5).

.PARAMETER RelevanceThreshold
    Minimum similarity score for context to be included in responses (default: 0.75).

.PARAMETER ContextOnlyMode
    Instructs the LLM to use ONLY information from the provided context when generating responses.

.EXAMPLE
    .\Start-RAG.ps1 -DirectoryPath "D:\Documents"

.EXAMPLE
    .\Start-RAG.ps1 -DirectoryPath "D:\Documents" -ProcessInterval 60 -EmbeddingModel "llama3" -UseChunking $false -ApiProxyPort 9000

.EXAMPLE
    .\Start-RAG.ps1 -DirectoryPath "D:\Documents" -FileTrackerPort 9001 -ProcessorPort 9002 -VectorsPort 9003 -ApiProxyPort 9004
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,
    [Parameter(Mandatory = $true)]
    [string]$DirectoryPath,
    [Parameter(Mandatory = $false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    [Parameter(Mandatory = $false)]
    [string]$OllamaUrl = "http://localhost:11434",
    [Parameter(Mandatory = $false)]
    [string]$FileFilter = "*.*",
    [Parameter(Mandatory = $false)]
    [bool]$IncludeSubdirectories = $true,
    [Parameter(Mandatory = $false)]
    [int]$ProcessInterval = 30,
    [Parameter(Mandatory = $false)]
    [string]$TextFileExtensions = ".txt,.md,.html,.csv,.json",
    [Parameter(Mandatory = $false)]
    [string]$PDFFileExtension = ".pdf",
    [Parameter(Mandatory = $false)]
    [bool]$UseChunking = $true,
    [Parameter(Mandatory = $false)]
    [int]$ChunkSize = 1000,
    [Parameter(Mandatory = $false)]
    [int]$ChunkOverlap = 200,
    [Parameter(Mandatory = $false)]
    [int]$FileTrackerPort = 11090,
    [Parameter(Mandatory = $false)]
    [int]$ProcessorPort = 11093,
    [Parameter(Mandatory = $false)]
    [int]$VectorsPort = 11092,
    [Parameter(Mandatory = $false)]
    [int]$ApiProxyPort = 11091,
    [Parameter(Mandatory = $false)]
    [int]$MaxContextDocs = 5,

    [Parameter(Mandatory = $false)]
    [decimal]$RelevanceThreshold = 0.75,
    [Parameter(Mandatory=$false)]
    [switch]$ContextOnlyMode
)


.\Tools\Clear-PortRegistrations.ps1 -Ports $FileTrackerPort, $ProcessorPort, $VectorsPort, $ApiProxyPort

# Function to log messages with timestamp and color-coding
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage }
        "WARNING" { Write-Host $logMessage }
        default { Write-Host $logMessage }
    }
}

# Validate the directory exists
if (-not (Test-Path -Path $DirectoryPath)) {
    Write-Log "Directory '$DirectoryPath' does not exist." -Level "ERROR"
    exit 1
}

$fileTrackerDbPath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"
$chromaDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db"
# Get script directory for accessing other scripts
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Check if the FileTracker database exists
if (-not (Test-Path -Path $fileTrackerDbPath)) {
    Write-Log "File tracker database not found at '$fileTrackerDbPath'. Please run Setup-RAG.ps1 first." -Level "ERROR"
    exit 1
}

# Start Vectors subsystem
Write-Log "Starting Vectors subsystem..." -Level "INFO"
try {
    $vectorsAPIScript = Join-Path -Path $scriptDirectory -ChildPath "Vectors\Start-VectorsAPI.ps1"
    
    if (-not (Test-Path -Path $vectorsAPIScript)) {
        Write-Log "Start-VectorsAPI.ps1 script not found at: $vectorsAPIScript" -Level "ERROR"
        exit 1
    }
    
    # Start Vectors API as a background job
    $vectorsAPIJobScript = {
        param($installPath, $scriptPath, $chromaDbPath, $ollamaUrl, $embeddingModel, $chunkSize, $chunkOverlap, $apiPort)
        & $scriptPath -InstallPath $installPath -ChromaDbPath $chromaDbPath -OllamaUrl $ollamaUrl -EmbeddingModel $embeddingModel -DefaultChunkSize $chunkSize -DefaultChunkOverlap $chunkOverlap -Port $apiPort
    }
    
    $vectorsAPIJob = Start-Job -ScriptBlock $vectorsAPIJobScript -ArgumentList $InstallPath, $vectorsAPIScript, $vectorDbPath, $OllamaUrl, $EmbeddingModel, $ChunkSize, $ChunkOverlap, $VectorsPort
    
    # Wait a moment for the API to start
    Start-Sleep -Seconds 2
    
    Write-Log "Vectors API started successfully (Job ID: $($vectorsAPIJob.Id))" -Level "INFO"
    Write-Log "Vectors API available at: http://localhost:$VectorsPort/" -Level "INFO"
}
catch {
    Write-Log "Error starting Vectors subsystem: $_" -Level "ERROR"
    exit 1
}

# Start the FileTracker subsystem
Write-Log "Starting FileTracker subsystem..." -Level "INFO"
try {
    # Start FileTracker API service
    $fileTrackerScript = Join-Path -Path $scriptDirectory -ChildPath "FileTracker\Start-FileTracker.ps1"
    
    # Verify script exists
    if (-not (Test-Path -Path $fileTrackerScript)) {
        Write-Log "Start-FileTracker.ps1 script not found at: $fileTrackerScript" -Level "ERROR"
        exit 1
    }
    
    # Start FileTracker as a background job
    $fileTrackerJobScript = {
        param($scriptPath, $installPath, $omitFolders, $port)
        & $scriptPath -InstallPath $installPath -OmitFolders $omitFolders -Port $port
    }
    
    $fileTrackerJob = Start-Job -ScriptBlock $fileTrackerJobScript -ArgumentList $fileTrackerScript, $InstallPath, @('.git'), $FileTrackerPort
    
    # Wait a moment for the FileTracker to start
    Start-Sleep -Seconds 2
    
    Write-Log "FileTracker started successfully (Job ID: $($fileTrackerJob.Id))" -Level "INFO"
    Write-Log "FileTracker API available at: http://localhost:$FileTrackerPort/api" -Level "INFO"
}
catch {
    Write-Log "Error starting FileTracker subsystem: $_" -Level "ERROR"
    # Try to stop already running jobs
    if ($vectorsAPIJob) { Stop-Job -Id $vectorsAPIJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $vectorsAPIJob.Id -Force -ErrorAction SilentlyContinue }
    exit 1
}

# Start the Processor REST API to handle file processing
Write-Log "Starting Processor REST API..." -Level "INFO"
try {
    # Start Processor API service
    $processorScript = Join-Path -Path $scriptDirectory -ChildPath "Processor\Start-Processor.ps1"
    
    # Verify script exists
    if (-not (Test-Path -Path $processorScript)) {
        Write-Log "Start-Processor.ps1 script not found at: $processorScript" -Level "ERROR"
        exit 1
    }
    
    # Create processor API job
    $processorJobScript = {
        param($scriptPath, $fileTrackerApiUrl, $ollamaUrl, $embeddingModel, $chunkSize, $chunkOverlap, $port, $installPath)
        try
        {
            & $scriptPath -FileTrackerUrl $fileTrackerApiUrl -InstallPath $installPath -OllamaUrl $ollamaUrl -EmbeddingModel $embeddingModel -ChunkSize $chunkSize -ChunkOverlap $chunkOverlap -UseChunking $true -Port $port
        }
        catch {
            Write-Log "Error starting Processor API: $_" -Level "ERROR"
            exit 1
        }
    }
    $processorJob = Start-Job -ScriptBlock $processorJobScript -ArgumentList $processorScript, $fileTrackerApiUrl, $OllamaUrl, $EmbeddingModel, $ChunkSize, $ChunkOverlap, $ProcessorPort,$InstallPath
    
    # Wait a moment for the Processor API to start
    Start-Sleep -Seconds 2
    
    Write-Log "Processor REST API started successfully (Job ID: $($processorJob.Id))" -Level "INFO"
    Write-Log "Processor API available at: http://localhost:$ProcessorPort/api" -Level "INFO"
}
catch {
    Write-Log "Error starting Processor subsystem: $_" -Level "ERROR"
    # Try to stop already running jobs
    if ($vectorsAPIJob) { Stop-Job -Id $vectorsAPIJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $vectorsAPIJob.Id -Force -ErrorAction SilentlyContinue }
    if ($fileTrackerJob) { Stop-Job -Id $fileTrackerJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $fileTrackerJob.Id -Force -ErrorAction SilentlyContinue }
    if ($watchCollectionJob) { Stop-Job -Id $watchCollectionJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $watchCollectionJob.Id -Force -ErrorAction SilentlyContinue }
    exit 1
}

# Start the API proxy server as a background job
Write-Log "Starting API proxy server for RAG-enhanced chat capabilities..." -Level "INFO"
try {
    $proxyScript = Join-Path -Path $scriptDirectory -ChildPath "Proxy\Start-Proxy.ps1"
    
    # Verify script exists
    if (-not (Test-Path -Path $proxyScript)) {
        Write-Log "Start-Proxy.ps1 script not found at: $proxyScript" -Level "ERROR"
        exit 1
    }
    # Create proxy job
    $proxyJobScript = {
        param($scriptPath, $listenAddress, $port, $installPath, $ollamaUrl, $vectorsApiUrl, $embeddingModel, $relevanceThreshold, $maxContextDocs, $contextOnlyMode)
        
        & $scriptPath -ListenAddress $listenAddress -Port $port -InstallPath $installPath -OllamaBaseUrl $ollamaUrl -VectorsApiUrl $vectorsApiUrl -EmbeddingModel $embeddingModel -RelevanceThreshold $relevanceThreshold -MaxContextDocs $maxContextDocs -ContextOnlyMode:$contextOnlyMode
    }
    
    $vectorsApiUrl = "http://localhost:$VectorsPort"

    $apiProxyJob = Start-Job -ScriptBlock $proxyJobScript -ArgumentList $proxyScript, "localhost", $ApiProxyPort, $InstallPath, $OllamaUrl, $vectorsApiUrl, $EmbeddingModel, $RelevanceThreshold, $MaxContextDocs, $ContextOnlyMode
    
    Write-Log "API proxy server started successfully (Job ID: $($apiProxyJob.Id))" -Level "INFO"
    Write-Log "API will be available at: http://localhost:$ApiProxyPort/" -Level "INFO"
}
catch {
    Write-Log "Error setting up API proxy server job: $_" -Level "ERROR"
    # Try to stop already running jobs
    if ($vectorsAPIJob) { Stop-Job -Id $vectorsAPIJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $vectorsAPIJob.Id -Force -ErrorAction SilentlyContinue }
    if ($fileTrackerJob) { Stop-Job -Id $fileTrackerJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $fileTrackerJob.Id -Force -ErrorAction SilentlyContinue }
    if ($watchCollectionJob) { Stop-Job -Id $watchCollectionJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $watchCollectionJob.Id -Force -ErrorAction SilentlyContinue }
    if ($processorJob) { Stop-Job -Id $processorJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $processorJob.Id -Force -ErrorAction SilentlyContinue }
}

# Display summary and useful information
Write-Log "RAG processing started successfully!" -Level "INFO"
Write-Log "Summary:" -Level "INFO"
Write-Log "- File tracker database: $fileTrackerDbPath" -Level "INFO"
Write-Log "- Vector database: $vectorDbPath" -Level "INFO"
Write-Log "- Embedding model: $EmbeddingModel" -Level "INFO"
Write-Log "- Processing interval: Every $ProcessInterval seconds" -Level "INFO"
if ($ContextOnlyMode) {
    Write-Log "- Context-only Mode: Active - LLM will use ONLY information from context" -Level "INFO"
}
Write-Log "- Vectors API job ID: $($vectorsAPIJob.Id)" -Level "INFO" 
Write-Log "- FileTracker job ID: $($fileTrackerJob.Id)" -Level "INFO"
Write-Log "- Processor API job ID: $($processorJob.Id)" -Level "INFO"
Write-Log "- API proxy server job ID: $($apiProxyJob.Id)" -Level "INFO"
Write-Log "- API endpoint: http://localhost:$ApiProxyPort/" -Level "INFO"

Write-Log "`nThe system is now running in the background. To stop it:" -Level "INFO"
Write-Log "1. Stop the Vectors API job: Stop-Job -Id $($vectorsAPIJob.Id); Remove-Job -Id $($vectorsAPIJob.Id)" -Level "INFO"
Write-Log "2. Stop the FileTracker job: Stop-Job -Id $($fileTrackerJob.Id); Remove-Job -Id $($fileTrackerJob.Id)" -Level "INFO"
Write-Log "3. Stop the collection watcher job: Stop-Job -Id $($watchCollectionJob.Id); Remove-Job -Id $($watchCollectionJob.Id)" -Level "INFO"
Write-Log "4. Stop the Processor API job: Stop-Job -Id $($processorJob.Id); Remove-Job -Id $($processorJob.Id)" -Level "INFO"
Write-Log "5. Stop the API proxy server job: Stop-Job -Id $($apiProxyJob.Id); Remove-Job -Id $($apiProxyJob.Id)" -Level "INFO"

Write-Log "`nTo interact with the RAG system:" -Level "INFO"
Write-Log "- Use http://localhost:$ApiProxyPort/api/chat for RAG-enhanced chat" -Level "INFO"
Write-Log "- Use http://localhost:$ApiProxyPort/api/search for document search" -Level "INFO"
Write-Log "- Use http://localhost:$ApiProxyPort/api/models to list available models" -Level "INFO"

# Keep the script running to maintain the job and provide status
try {
    Write-Log "`nPress Ctrl+C to stop and view the final status..." -Level "INFO"
    
    while ($true) {
        Start-Sleep -Seconds 5
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    # This is expected when the user presses Ctrl+C
    Write-Log "`nStopping RAG processing..." -Level "INFO"
}
finally {
    # Clean up processes and jobs
    Write-Log "Cleaning up resources..." -Level "INFO"
    
    # Stop the Vectors API job
    if ($vectorsAPIJob) {
        Write-Log "Stopping Vectors API job (ID: $($vectorsAPIJob.Id))..." -Level "INFO"
        Stop-Job -Id $vectorsAPIJob.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $vectorsAPIJob.Id -Force -ErrorAction SilentlyContinue
        Write-Log "Vectors API job stopped and removed." -Level "INFO"
    }
    
    # Stop the FileTracker job
    if ($fileTrackerJob) {
        Write-Log "Stopping FileTracker job (ID: $($fileTrackerJob.Id))..." -Level "INFO"
        Stop-Job -Id $fileTrackerJob.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $fileTrackerJob.Id -Force -ErrorAction SilentlyContinue
        Write-Log "FileTracker job stopped and removed." -Level "INFO"
    }
    
    # Stop the collection watcher job
    if ($watchCollectionJob) {
        Write-Log "Stopping collection watcher job (ID: $($watchCollectionJob.Id))..." -Level "INFO"
        Stop-Job -Id $watchCollectionJob.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $watchCollectionJob.Id -Force -ErrorAction SilentlyContinue
        Write-Log "Collection watcher job stopped and removed." -Level "INFO"
    }
    
    # Stop the Processor API job
    if ($processorJob) {
        Write-Log "Stopping Processor API job (ID: $($processorJob.Id))..." -Level "INFO"
        Stop-Job -Id $processorJob.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $processorJob.Id -Force -ErrorAction SilentlyContinue
        Write-Log "Processor API job stopped and removed." -Level "INFO"
    }
    
    # Stop and remove the API proxy server job
    if ($apiProxyJob) {
        Write-Log "Stopping API proxy server job (ID: $($apiProxyJob.Id))..." -Level "INFO"
        Stop-Job -Id $apiProxyJob.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $apiProxyJob.Id -Force -ErrorAction SilentlyContinue
        Write-Log "API proxy server job stopped and removed." -Level "INFO"
    }
    
    Write-Log "RAG processing has been stopped." -Level "INFO"
}
