param (
    [Parameter(Mandatory = $false)]
    [string]$InstallPath = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "User"),
    
    [Parameter(Mandatory = $false)]
    [string]$EmbeddingModel = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_EMBEDDING_MODEL", "User") ?? "mxbai-embed-large:latest",
    
    [Parameter(Mandatory = $false)]
    [string]$OllamaUrl = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_URL", "User") ?? "http://localhost:11434",

    [Parameter(Mandatory = $false)]
    [int]$ChunkSize = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_CHUNK_SIZE", "User") ?? 20,

    [Parameter(Mandatory = $false)]
    [int]$ChunkOverlap = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_CHUNK_OVERLAP", "User") ?? 2,

    [Parameter(Mandatory = $false)]
    [int]$FileTrackerPort = 10003,
    
    [Parameter(Mandatory = $false)]
    [int]$ProcessorPort = 10005,
    
    [Parameter(Mandatory = $false)]
    [int]$VectorsPort = 10001
)

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

# Validate InstallPath
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-Log "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable." -Level "ERROR"
    exit 1
}

$fileTrackerDbPath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"
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
        param($installPath, $scriptPath, $ollamaUrl, $embeddingModel, $chunkSize, $chunkOverlap, $apiPort)

        & $scriptPath -InstallPath $installPath -OllamaUrl $ollamaUrl -EmbeddingModel $embeddingModel -DefaultChunkSize $chunkSize -DefaultChunkOverlap $chunkOverlap -Port $apiPort -ErrorAction Stop 
    }
    
    #& $vectorsAPIScript -InstallPath $InstallPath -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -DefaultChunkSize $ChunkSize -DefaultChunkOverlap $ChunkOverlap -Port $VectorsPort
    $vectorsAPIJob = Start-Job -ScriptBlock $vectorsAPIJobScript -ArgumentList $InstallPath, $vectorsAPIScript, $OllamaUrl, $EmbeddingModel, $ChunkSize, $ChunkOverlap, $VectorsPort

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
    $fileTrackerScript = Join-Path -Path $scriptDirectory -ChildPath "FileTracker\Start-FileTrackerAPI.ps1"
    
    # Verify script exists
    if (-not (Test-Path -Path $fileTrackerScript)) {
        Write-Log "Start-FileTrackerAPI.ps1 script not found at: $fileTrackerScript" -Level "ERROR"
        exit 1
    }
    
    # Start FileTracker as a background job
    $fileTrackerJobScript = {
        param($scriptPath, $installPath, $port)
        & $scriptPath -InstallPath $installPath -Port $port
    }
    
    $fileTrackerJob = Start-Job -ScriptBlock $fileTrackerJobScript -ArgumentList $fileTrackerScript, $InstallPath, $FileTrackerPort

    # Wait a moment for the FileTracker to start
    Start-Sleep -Seconds 2
    
    Write-Log "FileTracker started successfully (Job ID: $($fileTrackerJob.Id))" -Level "INFO"
    Write-Log "FileTracker API available at: http://localhost:$FileTrackerPort" -Level "INFO"
}
catch {
    Write-Log "Error starting FileTracker subsystem: $_" -Level "ERROR"
    # Try to stop already running jobs
    if ($vectorsAPIJob) { Stop-Job -Id $vectorsAPIJob.Id -ErrorAction SilentlyContinue; Remove-Job -Id $vectorsAPIJob.Id -Force -ErrorAction SilentlyContinue }
    exit 1
}

# Display summary and useful information
Write-Log "RAG processing started successfully!" -Level "INFO"
Write-Log "Summary:" -Level "INFO"
Write-Log "- File tracker database: $fileTrackerDbPath" -Level "INFO"
Write-Log "- Vector database: $vectorDbPath" -Level "INFO"
Write-Log "- Embedding model: $EmbeddingModel" -Level "INFO"
if ($ContextOnlyMode) {
    Write-Log "- Context-only Mode: Active - LLM will use ONLY information from context" -Level "INFO"
}
Write-Log "- Vectors API job ID: $($vectorsAPIJob.Id)" -Level "INFO" 
Write-Log "- FileTracker job ID: $($fileTrackerJob.Id)" -Level "INFO"

Write-Log "`nThe system is now running in the background. To stop it:" -Level "INFO"
Write-Log "1. Stop the Vectors API job: Stop-Job -Id $($vectorsAPIJob.Id); Remove-Job -Id $($vectorsAPIJob.Id)" -Level "INFO"
Write-Log "2. Stop the FileTracker job: Stop-Job -Id $($fileTrackerJob.Id); Remove-Job -Id $($fileTrackerJob.Id)" -Level "INFO"

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
    
    Write-Log "RAG processing has been stopped." -Level "INFO"
}
