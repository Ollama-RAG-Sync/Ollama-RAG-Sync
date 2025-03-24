<#
.SYNOPSIS
    Sets up a Retrieval-Augmented Generation (RAG) environment for a specified directory.

.DESCRIPTION
    This script initializes a complete RAG environment by:
    1. Creating a .ai subfolder in the specified directory
    2. Setting up a SQLite database to track file modifications
    3. Initializing a ChromaDB vector database for embeddings
    4. Starting a file watcher to monitor changes in the directory

.PARAMETER DirectoryPath
    The path to the directory to monitor and set up RAG for.
    
.PARAMETER EmbeddingModel
    The name of the embedding model to use (default: "mxbai-embed-large:latest").

.PARAMETER OllamaUrl
    The URL of the Ollama API (default: "http://localhost:11434").

.PARAMETER FileFilter
    The filter for files to monitor (default: "*.*").

.PARAMETER IncludeSubdirectories
    Whether to include subdirectories when monitoring files (default: true).

.PARAMETER ProcessExistingFiles
    Whether to process existing files in the directory (default: true).

.EXAMPLE
    .\Setup-RAG.ps1 -DirectoryPath "D:\Documents"

.EXAMPLE
    .\Setup-RAG.ps1 -DirectoryPath "D:\Documents" -EmbeddingModel "llama3" -OllamaUrl "http://localhost:11434" -IncludeSubdirectories $false
#>

param (
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
    [bool]$ProcessExistingFiles = $true
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

Ensure-Package "chromadb"
Ensure-Package "requests"
Ensure-Package "numpy"

# Create .ai subfolder
$aiFolder = Join-Path -Path $DirectoryPath -ChildPath ".ai"
if (-not (Test-Path -Path $aiFolder)) {
    Write-Log "Creating .ai folder at '$aiFolder'..." -Level "INFO"
    try {
        New-Item -Path $aiFolder -ItemType Directory -Force | Out-Null
        Write-Log "Created .ai folder successfully" -Level "INFO"
    }
    catch {
        Write-Log "Failed to create .ai folder: $_" -Level "ERROR"
        exit 1
    }
}

# Create libs subfolder in .ai
$libsFolder = Join-Path -Path $aiFolder -ChildPath "libs"
if (-not (Test-Path -Path $libsFolder)) {
    Write-Log "Creating libs folder at '$libsFolder'..." -Level "INFO"
    try {
        New-Item -Path $libsFolder -ItemType Directory -Force | Out-Null
        Write-Log "Created libs folder successfully" -Level "INFO"
    }
    catch {
        Write-Log "Failed to create libs folder: $_" -Level "ERROR"
        exit 1
    }
}

# Define paths
$fileTrackerDbPath = Join-Path -Path $aiFolder -ChildPath "FileTracker.db"
$vectorDbPath = Join-Path -Path $aiFolder -ChildPath "Vectors"

# Get script directory for accessing other scripts
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Install File Tracker
Write-Log "Installing FileTracker..." -Level "INFO"
try {
    $installScript = Join-Path -Path $scriptDirectory -ChildPath "FileTracker\Install-FileTracker.ps1"
    & $installScript -FolderPath $DirectoryPath
    Write-Log "FileTracker installed successfully" -Level "INFO"
}
catch {
    Write-Log "Error installing FileTracker: $_" -Level "ERROR"
    exit 1
}

# Initialize file tracker database
Write-Log "Initializing file tracker database at '$fileTrackerDbPath'..." -Level "INFO"
try {
    $initializeScript = Join-Path -Path $scriptDirectory -ChildPath "FileTracker\Initialize-FileTracker.ps1"
    & $initializeScript -FolderPath $DirectoryPath -DatabasePath $fileTrackerDbPath
    
    if (-not (Test-Path -Path $fileTrackerDbPath)) {
        Write-Log "File tracker database was not created successfully" -Level "ERROR"
        exit 1
    }
    
    Write-Log "File tracker database initialized successfully" -Level "INFO"
}
catch {
    Write-Log "Error initializing file tracker database: $_" -Level "ERROR"
    exit 1
}

# Initialize ChromaDB using Process-DirtyFiles.ps1 and Update-LocalChromaDb.ps1
Write-Log "Initializing ChromaDB using Process-DirtyFiles.ps1 and Update-LocalChromaDb.ps1..." -Level "INFO"
try {
    # Check for required Python packages
    Ensure-Package "chromadb"

    # Get script paths
    $processDirtyFilesScript = Join-Path -Path $scriptDirectory -ChildPath "Processing\Process-DirtyFiles.ps1"
    $updateLocalChromaDbScript = Join-Path -Path $scriptDirectory -ChildPath "Processing\Update-LocalChromaDb.ps1"

    # Verify scripts exist
    if (-not (Test-Path -Path $processDirtyFilesScript)) {
        Write-Log "Process-DirtyFiles.ps1 script not found at: $processDirtyFilesScript" -Level "ERROR"
        exit 1
    }

    if (-not (Test-Path -Path $updateLocalChromaDbScript)) {
        Write-Log "Update-LocalChromaDb.ps1 script not found at: $updateLocalChromaDbScript" -Level "ERROR"
        exit 1
    }

    # Create temporary directory for processing if it doesn't exist
    $tempDir = Join-Path -Path $aiFolder -ChildPath "temp"
    if (-not (Test-Path -Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    }

    # Configure custom processor (Update-LocalChromaDb.ps1) parameters
    $processorScriptParams = @{
        "TempDir" = $tempDir
        "CustomParam1" = "Initial Setup"
        "CustomParam2" = "Configuration"
    }

    # Process any existing files to initialize the database
    if ($ProcessExistingFiles) {
        Write-Log "Processing existing files to initialize ChromaDB..." -Level "INFO"
        & $processDirtyFilesScript -DirectoryPath $DirectoryPath -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ProcessorScript $updateLocalChromaDbScript -ProcessorScriptParams $processorScriptParams
    } else {
        Write-Log "Skipping processing of existing files as specified by parameter." -Level "INFO"
    }
    
    Write-Log "ChromaDB initialized successfully using Process-DirtyFiles.ps1 and Update-LocalChromaDb.ps1" -Level "INFO"
}
catch {
    Write-Log "Error initializing ChromaDB: $_" -Level "ERROR"
    exit 1
}

# Display summary and next steps
Write-Log "RAG environment setup complete!" -Level "INFO"
Write-Log "Summary:" -Level "INFO"
Write-Log "- Directory being monitored: $DirectoryPath" -Level "INFO"
Write-Log "- File tracker database: $fileTrackerDbPath" -Level "INFO"
Write-Log "- Vector database: $vectorDbPath" -Level "INFO"
Write-Log "- Embedding model: $EmbeddingModel" -Level "INFO"
Write-Log "- Ollama URL: $OllamaUrl" -Level "INFO"

Write-Log "`nNext steps:" -Level "INFO"
Write-Log "1. Use Start-RAG.ps1 to begin processing files and updating the vector database" -Level "INFO"
Write-Log "2. Use Chat-RAG.ps1 to interact with your documents using RAG" -Level "INFO"
Write-Log "`nExample: .\Start-RAG.ps1 -DirectoryPath '$DirectoryPath'" -Level "INFO"
