# Start-Processor.ps1
# Exposes a REST API to trigger processing of dirty (new/modified) and deleted files
# Interacts with the FileTracker REST API to get file status and update processed files
# Supports collection-specific processor scripts stored in a SQLite database

#Requires -Version 7.0

param(
    [Parameter(Mandatory=$false)]
    [string]$FileTrackerUrl = "http://localhost:8080",
    
    [Parameter(Mandatory=$false)]
    [string]$FileTrackerApiPath = "/api",
    
    [Parameter(Mandatory=$false)]
    [int]$Port = 10005,
    
    [Parameter(Mandatory=$true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [bool]$UseChunking = $true,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 200,
    
    [Parameter(Mandatory=$false)]
    [string]$HandlerScript,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$HandlerScriptParams = @{}
)
$DatabasePath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"
$TempDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $TempDir)) 
{ 
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null 
}

# Import required modules
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Initialize SQLite Environment once before starting server (using the imported function)
if (-not (Initialize-SqliteEnvironment -InstallPath $InstallPath)) {
   Write-Log "Failed to initialize SQLite environment. API cannot start." -Level "ERROR"
   exit 1
}

# Import processor modules
$modulesPath = Join-Path -Path $scriptPath -ChildPath "Modules"
$processorLoggingModule = Join-Path -Path $modulesPath -ChildPath "Processor-Logging.psm1"
$processorDatabaseModule = Join-Path -Path $modulesPath -ChildPath "Processor-Database.psm1"
$processorFileTrackerAPIModule = Join-Path -Path $modulesPath -ChildPath "Processor-FileTrackerAPI.psm1"
$processorHTTPModule = Join-Path -Path $modulesPath -ChildPath "Processor-HTTP.psm1"
$processorFilesModule = Join-Path -Path $modulesPath -ChildPath "Processor-Files.psm1"

Import-Module $processorLoggingModule -Force
Import-Module $processorDatabaseModule -Force
Import-Module $processorFileTrackerAPIModule -Force
Import-Module $processorHTTPModule -Force
Import-Module $processorFilesModule -Force

# If DatabasePath is not provided, use the default path
if (-not $DatabasePath) {
    $DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
    Write-Host "Using default database path: $DatabasePath" -ForegroundColor Cyan
}

# Initialize log file
$TempDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $TempDir)) 
{ 
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null 
}

$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "Processor_$logDate.log"
$logFilePath = Join-Path -Path $TempDir -ChildPath "$logFileName"


# Define base URL for the API
$baseUrl = "http://localhost:$Port$ApiPath"
# Define FileTracker API URL
$fileTrackerBaseUrl = "$FileTrackerUrl$FileTrackerApiPath"

# Create Write-Log scriptblock for passing to module functions
$WriteLogBlock = {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    Write-Log -Message $Message -Level $Level -LogFilePath $logFilePath 
}

# Initialize the database
Initialize-ProcessorDatabase -DatabasePath $DatabasePath -InstallPath $InstallPath -WriteLog $WriteLogBlock

# Setup scriptblocks for API functions
$GetCollectionsBlock = {
    param($FileTrackerBaseUrl, $WriteLog)
    Get-Collections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
}

$GetCollectionDirtyFilesBlock = {
    param(
        [Parameter(Mandatory=$false)]
        $CollectionId,
        
        [Parameter(Mandatory=$false)]
        $CollectionName,
        
        [Parameter(Mandatory=$true)]
        $FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        $WriteLog
    )
    
    if ($CollectionId) {
        Get-CollectionDirtyFiles -CollectionId $CollectionId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } elseif ($CollectionName) {
        Get-CollectionDirtyFiles -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } else {
        & $WriteLog "Either CollectionId or CollectionName must be provided" -Level "ERROR"
        return $null
    }
}

$GetCollectionDeletedFilesBlock = {
    param(
        [Parameter(Mandatory=$false)]
        $CollectionId,
        
        [Parameter(Mandatory=$false)]
        $CollectionName,
        
        [Parameter(Mandatory=$true)]
        $FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        $WriteLog
    )
    
    if ($CollectionId) {
        Get-CollectionDeletedFiles -CollectionId $CollectionId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } elseif ($CollectionName) {
        Get-CollectionDeletedFiles -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } else {
        & $WriteLog "Either CollectionId or CollectionName must be provided" -Level "ERROR"
        return $null
    }
}

$GetCollectionProcessorBlock = {
    param($CollectionName, $DatabasePath, $WriteLog)
    Get-CollectionHandler -CollectionName $CollectionName -DatabasePath $DatabasePath -WriteLog $WriteLog
}

$SetCollectionProcessorBlock = {
    param($CollectionId, $CollectionName, $HandlerScript, $HandlerParams, $DatabasePath, $WriteLog)
    Set-CollectionHandler -CollectionId $CollectionId -CollectionName $CollectionName -HandlerScript $HandlerScript `
        -HandlerParams $HandlerParams -DatabasePath $DatabasePath -WriteLog $WriteLog
}

$RemoveCollectionProcessorBlock = {
    param($CollectionName, $DatabasePath, $WriteLog)
    Remove-CollectionHandler -CollectionName $CollectionName -DatabasePath $DatabasePath -WriteLog $WriteLog
}

$GetProcessorScriptsCountBlock = {
    param($DatabasePath, $WriteLog)
    Get-ProcessorScriptsCount -DatabasePath $DatabasePath -WriteLog $WriteLog
}

$MarkFileAsProcessedBlock = {
    param(
        [Parameter(Mandatory=$false)]
        $CollectionId,
        
        [Parameter(Mandatory=$false)]
        $CollectionName,
        
        [Parameter(Mandatory=$true)]
        $FileId,
        
        [Parameter(Mandatory=$true)]
        $FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        $WriteLog
    )
    
    if ($CollectionId) {
        Mark-FileAsProcessed -CollectionId $CollectionId -FileId $FileId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } elseif ($CollectionName) {
        Mark-FileAsProcessed -CollectionName $CollectionName -FileId $FileId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } else {
        & $WriteLog "Either CollectionId or CollectionName must be provided" -Level "ERROR"
        return $false
    }
}

$GetFileDetailsBlock = {
    param(
        [Parameter(Mandatory=$false)]
        $CollectionId,
        
        [Parameter(Mandatory=$false)]
        $CollectionName,
        
        [Parameter(Mandatory=$true)]
        $FileId,
        
        [Parameter(Mandatory=$true)]
        $FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        $WriteLog
    )
    
    if ($CollectionId) {
        Get-FileDetails -CollectionId $CollectionId -FileId $FileId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } elseif ($CollectionName) {
        Get-FileDetails -CollectionName $CollectionName -FileId $FileId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
    } else {
        & $WriteLog "Either CollectionId or CollectionName must be provided" -Level "ERROR"
        return $null
    }
}

$ProcessCollectionBlock = {
    param(
        [Parameter(Mandatory=$false)]
        [int]$CollectionId,
        [string]$CollectionName,
        [string]$FileTrackerBaseUrl,
        [string]$DatabasePath,
        # VectorDbPath parameter removed
        [string]$TempDir,
        [string]$OllamaUrl,
        [string]$EmbeddingModel,
        [string]$ScriptPath,
        [bool]$UseChunking,
        [int]$ChunkSize,
        [int]$ChunkOverlap,
        [string]$CustomProcessorScript,
        [hashtable]$CustomProcessorParams,
        [scriptblock]$WriteLog,
        [scriptblock]$GetCollectionDirtyFiles,
        [scriptblock]$GetCollectionDeletedFiles,
        [scriptblock]$GetCollectionProcessor,
        [scriptblock]$MarkFileAsProcessed
    )
    
    # Call Process-Collection with either CollectionId or just CollectionName
    if ($CollectionId) {
        # VectorDbPath argument removed from call
        Process-Collection -CollectionId $CollectionId -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl `
            -DatabasePath $DatabasePath -TempDir $TempDir -OllamaUrl $OllamaUrl `
            -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath -UseChunking $UseChunking -ChunkSize $ChunkSize `
            -ChunkOverlap $ChunkOverlap -CustomProcessorScript $CustomProcessorScript -CustomProcessorParams $CustomProcessorParams `
            -WriteLog $WriteLog -GetCollectionDirtyFiles $GetCollectionDirtyFiles -GetCollectionDeletedFiles $GetCollectionDeletedFiles `
            -GetCollectionProcessor $GetCollectionProcessor -MarkFileAsProcessed $MarkFileAsProcessed
    } else {
        # VectorDbPath argument removed from call
        Process-Collection -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl `
            -DatabasePath $DatabasePath -TempDir $TempDir -OllamaUrl $OllamaUrl `
            -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath -UseChunking $UseChunking -ChunkSize $ChunkSize `
            -ChunkOverlap $ChunkOverlap -CustomProcessorScript $CustomProcessorScript -CustomProcessorParams $CustomProcessorParams `
            -WriteLog $WriteLog -GetCollectionDirtyFiles $GetCollectionDirtyFiles -GetCollectionDeletedFiles $GetCollectionDeletedFiles `
            -GetCollectionProcessor $GetCollectionProcessor -MarkFileAsProcessed $MarkFileAsProcessed
    }
}

# Start the HTTP server
try
{
Start-ProcessorHttpServer -Port $Port -DatabasePath $DatabasePath -FileTrackerBaseUrl $fileTrackerBaseUrl `
    -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $scriptPath `
    -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap -WriteLog $WriteLogBlock `
    -GetCollections $GetCollectionsBlock -GetCollectionDirtyFiles $GetCollectionDirtyFilesBlock `
    -GetCollectionDeletedFiles $GetCollectionDeletedFilesBlock -GetCollectionProcessor $GetCollectionProcessorBlock `
    -SetCollectionProcessor $SetCollectionProcessorBlock -RemoveCollectionProcessor $RemoveCollectionProcessorBlock `
    -GetProcessorScriptsCount $GetProcessorScriptsCountBlock -ProcessCollection $ProcessCollectionBlock `
    -MarkFileAsProcessed $MarkFileAsProcessedBlock -GetFileDetails $GetFileDetailsBlock
}
catch {
    # Check for specific HttpListenerException related to port conflict
    if ($_.Exception -is [System.Net.HttpListenerException] -and $_.Exception.Message -like "*conflicts with an existing registration*") {
        Write-Error "Failed to start HTTP listener on port $Port. The port is already in use or reserved."
        Write-Host "Please ensure no other application is using port $Port." -ForegroundColor Yellow
        Write-Host "You can check existing URL reservations using: netsh http show urlacl" -ForegroundColor Yellow
        Write-Host "If necessary, you might be able to clear registrations using the script: Tools\Clear-PortRegistrations.ps1 (Run as Administrator)" -ForegroundColor Yellow
        Write-Host "Alternatively, try starting the processor with a different -Port parameter." -ForegroundColor Yellow
    } else {
        # Log other errors
        Write-Error "An unexpected error occurred while starting the HTTP server: $($_.Exception.Message)"
        # Ensure Temp directory exists before writing error log
        if (-not (Test-Path -Path $TempDir)) { New-Item -Path $TempDir -ItemType Directory -Force | Out-Null }
        $_ | Out-File -FilePath "$(Join-Path -Path $TempDir -ChildPath 'ProcessorError.log')" -Append
    }
    # Exit in both cases as the server failed to start
    exit 1
}
