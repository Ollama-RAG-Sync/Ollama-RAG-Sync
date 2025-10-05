param (
    [Parameter(Mandatory = $false, HelpMessage = "Installation directory for RAG system files and databases")]
    [ValidateNotNullOrEmpty()]
    [string]$InstallPath = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", "User"),

    [Parameter(Mandatory = $false, HelpMessage = "Ollama embedding model to use (e.g., mxbai-embed-large:latest)")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[\w\-]+:[\w\.\-]+$', ErrorMessage = "EmbeddingModel must be in format 'model:version'")]
    [string]$EmbeddingModel = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_EMBEDDING_MODEL", "User") ?? "mxbai-embed-large:latest",
    
    [Parameter(Mandatory = $false, HelpMessage = "Ollama API base URL")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^https?://.+', ErrorMessage = "OllamaUrl must start with http:// or https://")]
    [string]$OllamaUrl = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_URL", "User") ?? "http://localhost:11434",

    [Parameter(Mandatory = $false, HelpMessage = "Number of lines per text chunk (1-1000)")]
    [ValidateRange(1, 1000)]
    [int]$ChunkSize = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_CHUNK_SIZE", "User") ?? 20,

    [Parameter(Mandatory = $false, HelpMessage = "Number of overlapping lines between chunks (0-100)")]
    [ValidateRange(0, 100)]
    [int]$ChunkOverlap = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_CHUNK_OVERLAP", "User") ?? 2,

    [Parameter(Mandatory = $false, HelpMessage = "Port for FileTracker API (1-65535)")]
    [ValidateRange(1, 65535)]
    [int]$FileTrackerPort = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_FILE_TRACKER_API_PORT", "User") ?? 10003,

    [Parameter(Mandatory = $false, HelpMessage = "Port for Vectors API (1-65535)")]
    [ValidateRange(1, 65535)]
    [int]$VectorsPort = [System.Environment]::GetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", "User") ?? 10001
)

# Import common modules
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonPath = Join-Path -Path $scriptDirectory -ChildPath "Common"

Import-Module (Join-Path -Path $commonPath -ChildPath "Logger.psm1") -Force
Import-Module (Join-Path -Path $commonPath -ChildPath "Validation.psm1") -Force

# Validate InstallPath
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-LogError -Message "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable." -Component "Setup"
    exit 1
}

# Validate URL format
try {
    Test-UrlValid -Url $OllamaUrl -RequireScheme
    Write-LogDebug -Message "OllamaUrl validation passed: $OllamaUrl" -Component "Setup"
}
catch {
    Write-LogError -Message "Invalid Ollama URL: $_" -Component "Setup"
    exit 1
}

# Ensure InstallPath directory exists
try {
    Test-PathExists -Path $InstallPath -Create -ErrorMessage "Failed to create install directory"
    Write-LogInfo -Message "Install directory validated: $InstallPath" -Component "Setup"
}
catch {
    Write-LogError -Message $_.Exception.Message -Component "Setup" -Exception $_.Exception
    exit 1
}

# Save environment variables
Write-LogInfo -Message "Saving configuration as environment variables..." -Component "Setup"
try {
    [System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_INSTALL_PATH", $InstallPath, "User")
    [System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_EMBEDDING_MODEL", $EmbeddingModel, "User")
    [System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_URL", $OllamaUrl, "User")
    [System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_CHUNK_SIZE", $ChunkSize, "User")
    [System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_CHUNK_OVERLAP", $ChunkOverlap, "User")
    [System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_FILE_TRACKER_API_PORT", $FileTrackerPort, "User")
    [System.Environment]::SetEnvironmentVariable("OLLAMA_RAG_VECTORS_API_PORT", $VectorsPort, "User")
    Write-LogInfo -Message "Environment variables saved successfully" -Component "Setup"
}
catch {
    Write-LogError -Message "Failed to save environment variables" -Component "Setup" -Exception $_.Exception
    exit 1
}

# Install required packages if not already installed
function Ensure-Package {
    param([string]$PackageName)
    
    $installed = python -c "try: 
        import $PackageName
        print('installed')
    except ImportError: 
        print('not installed')" 2>$null
    
    if ($installed -ne "installed") {
        Write-LogInfo -Message "Installing required Python package: $PackageName..." -Component "Setup"
        python -m pip install $PackageName
        if ($LASTEXITCODE -ne 0) {
            Write-LogError -Message "Failed to install $PackageName. Please install it manually with 'pip install $PackageName'" -Component "Setup"
            exit 1
        }
        Write-LogInfo -Message "$PackageName installed successfully." -Component "Setup"
    }
    else {
        Write-LogDebug -Message "$PackageName is already installed." -Component "Setup"
    }
}

Write-LogInfo -Message "Installing python packages..." -Component "Setup"
Ensure-Package "chromadb"
Ensure-Package "requests"
Ensure-Package "numpy"

# Define paths
$fileTrackerDbPath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"
$vectorDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db"

# Get script directory for accessing other scripts
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Install File Tracker
Write-LogInfo -Message "Installing FileTracker..." -Component "Setup"
try {
    $installScript = Join-Path -Path $scriptDirectory -ChildPath "FileTracker\Install-FileTracker.ps1"
    if (-not (Test-Path -Path $installScript)) {
        throw "FileTracker installation script not found: $installScript"
    }
    & $installScript -InstallPath $InstallPath
    Write-LogInfo -Message "FileTracker installed successfully" -Component "Setup"
}
catch {
    Write-LogError -Message "Error installing FileTracker" -Component "Setup" -Exception $_.Exception
    exit 1
}

$intializeVectorDatabase = Join-Path -Path $scriptDirectory -ChildPath "Vectors\Functions\Initialize-VectorDatabase.ps1"
$dbInitialized = & $intializeVectorDatabase -ChromaDbPath $vectorDbPath
if (-not $dbInitialized) {
    Write-VectorsLog -Message "Failed to initialize vector database" -Level "Error"
    return $false
}

# Display summary and next steps
Write-LogInfo -Message "RAG environment setup complete!" -Component "Setup"
Write-LogInfo -Message "Summary:" -Component "Setup"
Write-LogInfo -Message "- File tracker database: $fileTrackerDbPath" -Component "Setup"
Write-LogInfo -Message "- Vector database: $vectorDbPath" -Component "Setup"
Write-LogInfo -Message "- Embedding model: $EmbeddingModel" -Component "Setup"
Write-LogInfo -Message "- Ollama URL: $OllamaUrl" -Component "Setup"
Write-LogInfo -Message "==" -Component "Setup"
Write-LogInfo -Message "Next Steps:" -Component "Setup"
Write-LogInfo -Message "1. Start the RAG system: .\Start-RAG.ps1" -Component "Setup"
Write-LogInfo -Message "2. Add a collection: .\FileTracker\Add-Folder.ps1 -CollectionName 'MyDocs' -FolderPath 'C:\Documents'" -Component "Setup"
Write-LogInfo -Message "3. Process documents: .\Processor\Process-Collection.ps1 -CollectionName 'MyDocs'" -Component "Setup"