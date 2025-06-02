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
    [int]$ChunkOverlap = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_CHUNK_OVERLAP", "User") ?? 2
)

# Function to log messages
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
}

# Validate InstallPath
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-Log "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable." -Level "ERROR"
    exit 1
}

# Ensure InstallPath directory exists
if (-not (Test-Path -Path $InstallPath)) {
    try {
        New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
        Write-Log "Created install directory: $InstallPath" -Level "INFO"
    }
    catch {
        Write-Log "Failed to create install directory: $InstallPath - $_" -Level "ERROR"
        exit 1
    }
}

# Save environment variables
Write-Log "Saving configuration as environment variables..." -Level "INFO"
[System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", $InstallPath, "User")
[System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_EMBEDDING_MODEL", $EmbeddingModel, "User")
[System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_URL", $OllamaUrl, "User")
[System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_CHUNK_SIZE", $ChunkSize, "User")
[System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_CHUNK_OVERLAP", $ChunkOverlap, "User")
Write-Log "Environment variables saved successfully" -Level "INFO"

# Install required packages if not already installed
function Ensure-Package {
    param([string]$PackageName)
    
    $installed = python -c "try: 
        import $PackageName
        print('installed')
    except ImportError: 
        print('not installed')" 2>$null
    
    if ($installed -ne "installed") {
        Write-Log "Installing required Python package: $PackageName..." -Level "INFO"
        python -m pip install $PackageName
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to install $PackageName. Please install it manually with 'pip install $PackageName'" -Level "ERROR"
            exit 1
        }
        Write-Log "$PackageName installed successfully." -Level "INFO"
    }
    else {
        Write-Log "$PackageName is already installed." -Level "INFO"
    }
}

Write-Log "Installing python packages..." -Level "INFO"
Ensure-Package "chromadb"
Ensure-Package "requests"
Ensure-Package "numpy"

# Define paths
$fileTrackerDbPath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"
$vectorDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db"

# Get script directory for accessing other scripts
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Install File Tracker
Write-Log "Installing FileTracker..." -Level "INFO"
try {
    $installScript = Join-Path -Path $scriptDirectory -ChildPath "FileTracker\Install-FileTracker.ps1"
    & $installScript -InstallPath $InstallPath
    Write-Log "FileTracker installed successfully" -Level "INFO"
}
catch {
    Write-Log "Error installing FileTracker: $_" -Level "ERROR"
    exit 1
}

$intializeVectorDatabase = Join-Path -Path $scriptDirectory -ChildPath "Vectors\Functions\Initialize-VectorDatabase.ps1"
$dbInitialized = & $intializeVectorDatabase -ChromaDbPath $vectorDbPath
if (-not $dbInitialized) {
    Write-VectorsLog -Message "Failed to initialize vector database" -Level "Error"
    return $false
}

# Display summary and next steps
Write-Log "RAG environment setup complete!" -Level "INFO"
Write-Log "Summary:" -Level "INFO"
Write-Log "- File tracker database: $fileTrackerDbPath" -Level "INFO"
Write-Log "- Vector database: $vectorDbPath" -Level "INFO"
Write-Log "- Embedding model: $EmbeddingModel" -Level "INFO"
Write-Log "- Ollama URL: $OllamaUrl" -Level "INFO"