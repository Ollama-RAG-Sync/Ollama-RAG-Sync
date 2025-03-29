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
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$DirectoryPath,
    
    [Parameter(Mandatory = $false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory = $false)]
    [string]$OllamaBaseUrl = "http://localhost:11434",
    
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
    [int]$ApiProxyPort = 8081,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxContextDocs = 5,

    [Parameter(Mandatory = $false)]
    [decimal]$RelevanceThreshold = 0.75,
    
    [Parameter(Mandatory=$false)]
    [switch]$ContextOnlyMode
)

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

# Define paths
$aiFolder = Join-Path -Path $DirectoryPath -ChildPath ".ai"
$fileTrackerDbPath = Join-Path -Path $aiFolder -ChildPath "FileTracker.db"
$vectorDbPath = Join-Path -Path $aiFolder -ChildPath "Vectors"
$tempDir = Join-Path -Path $aiFolder -ChildPath "temp"

# Ensure .ai folder exists
if (-not (Test-Path -Path $aiFolder)) {
    Write-Log ".ai folder not found at '$aiFolder'. Please run Setup-RAG.ps1 first." -Level "ERROR"
    exit 1
}

# Get script directory for accessing other scripts
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Check if the FileTracker database exists
if (-not (Test-Path -Path $fileTrackerDbPath)) {
    Write-Log "File tracker database not found at '$fileTrackerDbPath'. Please run Setup-RAG.ps1 first." -Level "ERROR"
    exit 1
}

# Ensure the vector database directory exists
if (-not (Test-Path -Path $vectorDbPath)) {
    Write-Log "Vector database directory not found at '$vectorDbPath'. Please run Setup-RAG.ps1 first." -Level "ERROR"
    exit 1
}

# Ensure temp directory exists
if (-not (Test-Path -Path $tempDir)) {
    Write-Log "Creating temporary directory at '$tempDir'..." -Level "INFO"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
}

# Start the file tracker watcher
Write-Log "Starting file tracker watcher for directory '$DirectoryPath'..." -Level "INFO"
try {
    $jobScript = {
        try {
            
            # Function to log with timestamp
            function LogMessage {
                param([string]$Message)
                
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Write-Host "[$timestamp] $Message"
            }

            LogMessage "Starting periodic dirty files processor."
            LogMessage "Will watch for changes every $ProcessInterval minutes."

            # Run the ProcessDirtyFiles.ps1 script
            $output = & "FileTracker\Watch-FileTracker.ps1" -DirectoryToWatch $using:DirectoryPath -FileFilter $FileFilter -WatchCreated -WatchModified -WatchDeleted -WatchRenamed -IncludeSubdirectories -LogPath (Join-Path -Path $using:tempDir -ChildPath "watcher.log") -OmitFolders @('.ai')

            # Log any output from the script
            foreach ($line in $output) {
                LogMessage "ProcessDirtyFiles: $line"
            }
        }
        catch {
            Write-Host $_
        }
        
    }
    $fileTrackerWatcherProcess = Start-Job -ScriptBlock $jobScript 
    Write-Log "Watch files job started successfully (Job ID: $($fileTrackerWatcherProcess.Id))" -Level "INFO"
}
catch {
    Write-Log "Error setting up watch files job: $_" -Level "ERROR"
    # Try to stop the file tracker watcher if it was started
    if ($fileTrackerWatcherProcess -and -not $fileTrackerWatcherProcess.HasExited) {
        Stop-Process -Id $fileTrackerWatcherProcess.Id -Force
    }
    exit 1
}

# Start a background job to process dirty files periodically
Write-Log "Setting up periodic processing of dirty files (every $ProcessInterval seconds)..." -Level "INFO"
try {
    $output = & ".\Processing\Process-DirtyFiles.ps1" -DirectoryPath $DirectoryPath -HandlerScript ".\Processing\Update-LocalChromaDb.ps1" &
    Write-Log "Dirty files processor job started successfully (Job ID: $($processingJob.Id))" -Level "INFO"
}
catch {
    Write-Log "Error setting up periodic dirty files processor: $_" -Level "ERROR"
    # Try to stop the file tracker watcher if it was started
    if ($processingJob -and -not $processingJob.HasExited) {
        Stop-Process -Id $processingJob.Id -Force
    }
    exit 1
}

# Start the API proxy server as a background job
Write-Log "Starting API proxy server as a background job for RAG-enhanced chat capabilities..." -Level "INFO"
try {
    & ".\Proxy\Start-RAGProxy.ps1" -ContextOnlyMode:$ContextOnlyMode -ListenAddress "localhost" -Port $ApiProxyPort -RelevanceThreshold $RelevanceThreshold -DirectoryPath $DirectoryPath -OllamaBaseUrl $OllamaBaseUrl -EmbeddingModel $EmbeddingModel -MaxContextDocs $MaxContextDocs
    #$apiProxyJob = Start-Job -ScriptBlock $jobScript
    Write-Log "API proxy server job started successfully (Job ID: $($apiProxyJob.Id))" -Level "INFO"
    Write-Log "API will be available at: http://localhost:$ApiProxyPort/" -Level "INFO"
}
catch {
    Write-Log "Error setting up API proxy server job: $_" -Level "ERROR"
}

# Display summary and useful information
Write-Log "RAG processing started successfully!" -Level "INFO"
Write-Log "Summary:" -Level "INFO"
Write-Log "- Directory being monitored: $DirectoryPath" -Level "INFO"
Write-Log "- File tracker database: $fileTrackerDbPath" -Level "INFO"
Write-Log "- Vector database: $vectorDbPath" -Level "INFO"
Write-Log "- Embedding model: $EmbeddingModel" -Level "INFO"
Write-Log "- Processing interval: Every $ProcessInterval seconds" -Level "INFO"
if ($ContextOnlyMode) {
    Write-Log "- Context-only Mode: Active - LLM will use ONLY information from context" -Level "INFO"
}
Write-Log "- File tracker watcher" -Level "INFO"
Write-Log "- Processing" -Level "INFO"
Write-Log "- API proxy server job ID: $($apiProxyJob.Id)" -Level "INFO"
Write-Log "- API endpoint: http://localhost:$ApiProxyPort/" -Level "INFO"

Write-Log "`nThe system is now running in the background. To stop it:" -Level "INFO"
Write-Log "1. Stop the file tracker watcher: Stop-Process -Id $($fileTrackerWatcherProcess.Id)" -Level "INFO"
Write-Log "2. Stop the processing job: Stop-Job -Id $($processingJob.Id); Remove-Job -Id $($processingJob.Id)" -Level "INFO"
Write-Log "3. Stop the API proxy server job: Stop-Job -Id $($apiProxyJob.Id); Remove-Job -Id $($apiProxyJob.Id)" -Level "INFO"
Write-Log "`nTo check the status of the processing job: Receive-Job -Id $($processingJob.Id)" -Level "INFO"
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
    
    # Stop the file tracker watcher
    if ($fileTrackerWatcherProcess -and -not $fileTrackerWatcherProcess.HasExited) {
        Write-Log "Stopping file tracker watcher process (PID: $($fileTrackerWatcherProcess.Id))..." -Level "INFO"
        Stop-Process -Id $fileTrackerWatcherProcess.Id -Force
        Write-Log "File tracker watcher stopped." -Level "INFO"
    }
    
    # Stop and remove the API proxy server job
    Write-Log "Stopping API proxy server job (ID: $($apiProxyJob.Id))..." -Level "INFO"
    Stop-Job -Id $apiProxyJob.Id -ErrorAction SilentlyContinue
    
    # Display the final API proxy job output
    Write-Log "Final API proxy job output:" -Level "INFO"
    $finalApiJobOutput = Receive-Job -Id $apiProxyJob.Id -ErrorAction SilentlyContinue
    if ($finalApiJobOutput) {
        foreach ($line in $finalApiJobOutput) {
            Write-Host "    $line"
        }
    }
    
    Remove-Job -Id $apiProxyJob.Id -Force -ErrorAction SilentlyContinue
    Write-Log "API proxy server job stopped and removed." -Level "INFO"
    
    # Stop and remove the processing job
    Write-Log "Stopping processing job (ID: $($processingJob.Id))..." -Level "INFO"
    Stop-Job -Id $processingJob.Id -ErrorAction SilentlyContinue
    
    # Display the final job output
    Write-Log "Final job output:" -Level "INFO"
    $finalJobOutput = Receive-Job -Id $processingJob.Id -ErrorAction SilentlyContinue
    if ($finalJobOutput) {
        foreach ($line in $finalJobOutput) {
            Write-Host "    $line"
        }
    }
    
    Remove-Job -Id $processingJob.Id -Force -ErrorAction SilentlyContinue
    Write-Log "Processing job stopped and removed." -Level "INFO"
    Write-Log "RAG processing has been stopped." -Level "INFO"
}
