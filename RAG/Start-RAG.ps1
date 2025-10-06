param (
    [Parameter(Mandatory = $false, HelpMessage = "Installation directory for RAG system files")]
    [ValidateNotNullOrEmpty()]
    [string]$InstallPath,
    
    [Parameter(Mandatory = $false, HelpMessage = "Ollama embedding model")]
    [ValidateNotNullOrEmpty()]
    [string]$EmbeddingModel,
    
    [Parameter(Mandatory = $false, HelpMessage = "Ollama API base URL")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^https?://.+', ErrorMessage = "OllamaUrl must start with http:// or https://")]
    [string]$OllamaUrl,

    [Parameter(Mandatory = $false, HelpMessage = "Number of lines per text chunk")]
    [ValidateRange(1, 1000)]
    [int]$ChunkSize = 0,

    [Parameter(Mandatory = $false, HelpMessage = "Number of overlapping lines between chunks")]
    [ValidateRange(0, 100)]
    [int]$ChunkOverlap = 0,

    [Parameter(Mandatory = $false, HelpMessage = "Port for FileTracker API")]
    [ValidateRange(1, 65535)]
    [int]$FileTrackerPort = 0,
    
    [Parameter(Mandatory = $false, HelpMessage = "Port for Vectors API")]
    [ValidateRange(1, 65535)]
    [int]$VectorsPort = 0
)

# Import common modules
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonPath = Join-Path -Path $scriptDirectory -ChildPath "Common"

Import-Module (Join-Path -Path $commonPath -ChildPath "Logger.psm1") -Force
Import-Module (Join-Path -Path $commonPath -ChildPath "Validation.psm1") -Force
Import-Module (Join-Path -Path $commonPath -ChildPath "EnvironmentHelper.psm1") -Force

# Get environment variables with cross-platform support
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH"
}
if ([string]::IsNullOrWhiteSpace($EmbeddingModel)) {
    $EmbeddingModel = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_EMBEDDING_MODEL" -DefaultValue "mxbai-embed-large:latest"
}
if ([string]::IsNullOrWhiteSpace($OllamaUrl)) {
    $OllamaUrl = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_URL" -DefaultValue "http://localhost:11434"
}
if ($ChunkSize -eq 0) {
    $envChunkSize = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_CHUNK_SIZE" -DefaultValue "20"
    $ChunkSize = [int]$envChunkSize
}
if ($ChunkOverlap -eq 0) {
    $envChunkOverlap = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_CHUNK_OVERLAP" -DefaultValue "2"
    $ChunkOverlap = [int]$envChunkOverlap
}
if ($FileTrackerPort -eq 0) {
    $envFileTrackerPort = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_FILE_TRACKER_API_PORT" -DefaultValue "10003"
    $FileTrackerPort = [int]$envFileTrackerPort
}
if ($VectorsPort -eq 0) {
    $envVectorsPort = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_VECTORS_API_PORT" -DefaultValue "10001"
    $VectorsPort = [int]$envVectorsPort
}

# Validate required parameters and environment variables
try {
    # Validate paths and ports
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        throw "OLLAMA_RAG_INSTALL_PATH is required. Please run Setup-RAG.ps1 first or provide -InstallPath parameter."
    }
    Test-PathExists -Path $InstallPath
    Test-PortValid -Port $VectorsPort
    Test-PortValid -Port $FileTrackerPort
    Test-UrlValid -Url $OllamaUrl -RequireScheme
    
    Write-LogInfo -Message "Configuration validated successfully" -Component "Start"
}
catch {
    Write-LogError -Message $_.Exception.Message -Component "Start" -Exception $_.Exception
    exit 1
}

$fileTrackerDbPath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"
$vectorDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db"

# Check if the FileTracker database exists
try {
    Test-PathExists -Path $fileTrackerDbPath -ErrorMessage "File tracker database not found at '$fileTrackerDbPath'. Please run Setup-RAG.ps1 first."
}
catch {
    Write-LogError -Message $_.Exception.Message -Component "Start"
    exit 1
}

# Start Vectors subsystem
Write-LogInfo -Message "Starting Vectors subsystem..." -Component "Start"
try {
    $vectorsAPIScript = Join-Path -Path $scriptDirectory -ChildPath "Vectors\Start-VectorsAPI.ps1"
    
    if (-not (Test-Path -Path $vectorsAPIScript)) {
        throw "Start-VectorsAPI.ps1 script not found at: $vectorsAPIScript"
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
    
    Write-LogInfo -Message "Vectors API started successfully (Job ID: $($vectorsAPIJob.Id))" -Component "Start"
    Write-LogInfo -Message "Vectors API available at: http://localhost:$VectorsPort/" -Component "Start"
}
catch {
    Write-LogError -Message "Error starting Vectors subsystem" -Component "Start" -Exception $_.Exception
    exit 1
}

# Start the FileTracker subsystem
Write-LogInfo -Message "Starting FileTracker subsystem..." -Component "Start"
try {
    # Start FileTracker API service
    $fileTrackerScript = Join-Path -Path $scriptDirectory -ChildPath "FileTracker\Start-FileTrackerAPI.ps1"
    
    # Verify script exists
    if (-not (Test-Path -Path $fileTrackerScript)) {
        throw "Start-FileTrackerAPI.ps1 script not found at: $fileTrackerScript"
    }
    
    # Start FileTracker as a background job
    $fileTrackerJobScript = {
        param($scriptPath, $installPath, $port)
        & $scriptPath -InstallPath $installPath -Port $port
    }
    
    $fileTrackerJob = Start-Job -ScriptBlock $fileTrackerJobScript -ArgumentList $fileTrackerScript, $InstallPath, $FileTrackerPort

    # Wait a moment for the FileTracker to start
    Start-Sleep -Seconds 2
    
    Write-LogInfo -Message "FileTracker started successfully (Job ID: $($fileTrackerJob.Id))" -Component "Start"
    Write-LogInfo -Message "FileTracker API available at: http://localhost:$FileTrackerPort" -Component "Start"
}
catch {
    Write-LogError -Message "Error starting FileTracker subsystem" -Component "Start" -Exception $_.Exception
    # Try to stop already running jobs
    if ($vectorsAPIJob) { 
        Stop-Job -Id $vectorsAPIJob.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $vectorsAPIJob.Id -Force -ErrorAction SilentlyContinue 
    }
    exit 1
}

# Display summary and useful information
Write-LogInfo -Message "RAG processing started successfully!" -Component "Start"
Write-LogInfo -Message "Summary:" -Component "Start"
Write-LogInfo -Message "- File tracker database: $fileTrackerDbPath" -Component "Start"
Write-LogInfo -Message "- Vector database: $vectorDbPath" -Component "Start"
Write-LogInfo -Message "- Embedding model: $EmbeddingModel" -Component "Start"
if ($ContextOnlyMode) {
    Write-LogInfo -Message "- Context-only Mode: Active - LLM will use ONLY information from context" -Component "Start"
}
Write-LogInfo -Message "- Vectors API job ID: $($vectorsAPIJob.Id)" -Component "Start"
Write-LogInfo -Message "- FileTracker job ID: $($fileTrackerJob.Id)" -Component "Start"

Write-LogInfo -Message "==" -Component "Start"
Write-LogInfo -Message "The system is now running in the background. To stop it:" -Component "Start"
Write-LogInfo -Message "1. Stop the Vectors API job: Stop-Job -Id $($vectorsAPIJob.Id); Remove-Job -Id $($vectorsAPIJob.Id)" -Component "Start"
Write-LogInfo -Message "2. Stop the FileTracker job: Stop-Job -Id $($fileTrackerJob.Id); Remove-Job -Id $($fileTrackerJob.Id)" -Component "Start"

# Keep the script running to maintain the job and provide status
try {
    Write-LogInfo -Message "Press Ctrl+C to stop and view the final status..." -Component "Start"
    
    while ($true) {
        Start-Sleep -Seconds 5
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    # This is expected when the user presses Ctrl+C
    Write-LogInfo -Message "Stopping RAG processing..." -Component "Start"
}
finally {
    # Clean up processes and jobs
    Write-LogInfo -Message "Cleaning up resources..." -Component "Start"
    
    # Stop the Vectors API job
    if ($vectorsAPIJob) {
        Write-LogInfo -Message "Stopping Vectors API job (ID: $($vectorsAPIJob.Id))..." -Component "Start"
        Stop-Job -Id $vectorsAPIJob.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $vectorsAPIJob.Id -Force -ErrorAction SilentlyContinue
        Write-LogInfo -Message "Vectors API job stopped and removed." -Component "Start"
    }
    
    # Stop the FileTracker job
    if ($fileTrackerJob) {
        Write-LogInfo -Message "Stopping FileTracker job (ID: $($fileTrackerJob.Id))..." -Component "Start"
        Stop-Job -Id $fileTrackerJob.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $fileTrackerJob.Id -Force -ErrorAction SilentlyContinue
        Write-LogInfo -Message "FileTracker job stopped and removed." -Component "Start"
    }
    
    Write-LogInfo -Message "RAG processing has been stopped." -Component "Start"
}
