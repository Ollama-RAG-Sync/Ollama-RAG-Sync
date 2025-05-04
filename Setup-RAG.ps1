<#
.SYNOPSIS
    Sets up a Retrieval-Augmented Generation (RAG) environment for a specified directory.

.DESCRIPTION
    This script initializes a complete RAG environment by:
    2. Setting up a SQLite database to track file modifications
    3. Initializing a ChromaDB vector database for embeddings
    4. Starting a file watcher to monitor changes in the directory

.PARAMETER EmbeddingModel
    The name of the embedding model to use (default: "mxbai-embed-large:latest").

.PARAMETER OllamaUrl
    The URL of the Ollama API (default: "http://localhost:11434").

#>

param (
    [Parameter(Mandatory = $true)]
    [string]$InstallPath,

    [Parameter(Mandatory = $false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory = $false)]
    [string]$OllamaUrl = "http://localhost:11434"   
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

function Ensure-Package {
    param([string]$PackageName)
    
    $installed = pwsh.exe -c "try: 
        import $PackageName
        print('installed')
    except ImportError: 
        print('not installed')" 2>$null
    
    if ($installed -ne "installed") {
        Write-Log "Installing $PackageName..." -Level "INFO"
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

# Display summary and next steps
Write-Log "RAG environment setup complete!" -Level "INFO"
Write-Log "Summary:" -Level "INFO"
Write-Log "- File tracker database: $fileTrackerDbPath" -Level "INFO"
Write-Log "- Vector database: $vectorDbPath" -Level "INFO"
Write-Log "- Embedding model: $EmbeddingModel" -Level "INFO"
Write-Log "- Ollama URL: $OllamaUrl" -Level "INFO"