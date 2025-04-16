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
$databaseSharedModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\FileTracker\Database-Shared.psm1"
Import-Module -Name $databaseSharedModulePath -Force -Verbose

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
$processorFilesModule = Join-Path -Path $modulesPath -ChildPath "Processor-Collections.psm1"

Import-Module $processorLoggingModule -Force
Import-Module $processorDatabaseModule -Force
Import-Module $processorFileTrackerAPIModule -Force
Import-Module $processorFilesModule -Force

# Check if Pode module is installed
if (-not (Get-Module -ListAvailable -Name Pode)) {
    Write-Host "Pode module is required but not installed. Installing..." -ForegroundColor Yellow
    Install-Module -Name Pode -Scope CurrentUser -Force
}
Import-Module -Name Pode -Force

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

# Define the HTTP server function
function Start-ProcessorHttpServer {
    param (
        [Parameter(Mandatory=$false)]
        [string]$ListenAddress = "localhost",
        
        [Parameter(Mandatory=$false)]
        [int]$Port = 10005,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$TempDir,
        
        [Parameter(Mandatory=$true)]
        [string]$OllamaUrl,
        
        [Parameter(Mandatory=$true)]
        [string]$EmbeddingModel,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath, # Path to the Processor directory
        
        [Parameter(Mandatory=$true)]
        [bool]$UseChunking,
        
        [Parameter(Mandatory=$true)]
        [int]$ChunkSize,
        
        [Parameter(Mandatory=$true)]
        [int]$ChunkOverlap,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollections,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionDirtyFiles,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionDeletedFiles,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetCollectionProcessor,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$SetCollectionProcessor,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$RemoveCollectionProcessor,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetProcessorScriptsCount,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$ProcessCollection,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$MarkFileAsProcessed,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$GetFileDetails
    )
    
    try {
        & $WriteLog "Starting Processor REST API server using Pode..."
        & $WriteLog "FileTracker API URL: $FileTrackerBaseUrl"
        & $WriteLog "Database Path: $DatabasePath"

        Start-PodeServer -Threads 4 {
            Add-PodeEndpoint -Address $ListenAddress -Port $Port -Protocol Http
            # Middleware & OpenAPI Setup
            Enable-PodeOpenApi -Title "Processor API" -Version "1.0.0" -Description "API for managing and triggering file processing tasks" -ErrorAction Stop

            # --- API Routes ---

            # GET /
            Add-PodeRoute -Method Get -Path "/" -ScriptBlock {
                Write-PodeJsonResponse -Value @{
                    status = "ok"
                    message = "Processor API server running"
                    routes = @(
                        @{ method = "GET"; path = "/api/status"; description = "Get server status" },
                        @{ method = "GET"; path = "/api/collections"; description = "Get all collections" },
                        @{ method = "GET"; path = "/api/collections/:collectionId/processor"; description = "Get processor for a specific collection" },
                        @{ method = "PUT"; path = "/api/collections/:collectionId/processor"; description = "Set processor for a specific collection" },
                        @{ method = "DELETE"; path = "/api/collections/:collectionId/processor"; description = "Remove processor for a specific collection" },
                        @{ method = "POST"; path = "/api/collections/:collectionId/process"; description = "Process files in a specific collection" },
                        @{ method = "POST"; path = "/api/process"; description = "Process all collections" }
                    )
                }
            } 

            # GET /api/status
            Add-PodeRoute -Method Get -Path "/api/status" -ScriptBlock {
                try {
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    $processorScriptsCount = & $GetProcessorScriptsCount -DatabasePath $DatabasePath -WriteLog $WriteLog
                    
                    $statusData = @{
                        collections = if ($null -ne $collections) { $collections.Count } else { 0 }
                        processor_scripts = $processorScriptsCount
                        running_since = (Get-PodeServer).StartedAt.ToString("yyyy-MM-dd HH:mm:ss")
                        version = "1.0.0" # Consider making this dynamic later
                    }
                    
                    Write-PodeJsonResponse -Value @{ success = $true; status = $statusData }
                } catch {
                    & $WriteLog "Error in GET /status: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } 

            # GET /api/collections
            Add-PodeRoute -Method Get -Path "/api/collections" -ScriptBlock {
                try {
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    
                    if ($collections -ne $null) {
                        foreach ($collection in $collections) {
                            $processor = & $GetCollectionProcessor -CollectionName $collection.name -DatabasePath $DatabasePath -WriteLog $WriteLog
                            if ($processor) {
                                $collection | Add-Member -MemberType NoteProperty -Name "has_processor" -Value $true
                                $collection | Add-Member -MemberType NoteProperty -Name "processor_script" -Value $processor.HandlerScript
                            } else {
                                $collection | Add-Member -MemberType NoteProperty -Name "has_processor" -Value $false
                            }
                        }
                        Write-PodeJsonResponse -Value @{ success = $true; collections = $collections; count = $collections.Count }
                    } else {
                        Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Failed to fetch collections from FileTracker" }
                    }
                } catch {
                    & $WriteLog "Error in GET /collections: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } 

            # GET /api/collections/{id}/processor
            Add-PodeRoute -Method Get -Path "/api/collections/:collectionId/processor" -ScriptBlock {
                try {
                    $collectionId = [int]$WebEvent.Parameters['collectionId']
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                    
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    $collectionName = $collection.name
                    $processor = & $GetCollectionProcessor -CollectionName $collectionName -DatabasePath $DatabasePath -WriteLog $WriteLog
                    
                    if ($processor) {
                        Write-PodeJsonResponse -Value @{ success = $true; processor = $processor }
                    } else {
                        Write-PodeJsonResponse -StatusCode 404 -Value @{ success = $false; error = "No processor found for collection" }
                    }
                } catch {
                    & $WriteLog "Error in GET /collections/$($WebEvent.Parameters['collectionId'])/processor: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } 

            # PUT /api/collections/{id}/processor
            Add-PodeRoute -Method Put -Path "/api/collections/:collectionId/processor" -ScriptBlock {
                try {
                    $collectionId = [int]$WebEvent.Parameters['collectionId']
                    $data = $WebEvent.Data
                    
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    if (-not $data -or -not $data.processor_script) { Set-PodeResponseStatus -Code 400; Write-PodeJsonResponse -Value @{ success = $false; error = "Missing required field: processor_script" }; return }
                    
                    $collectionName = $collection.name
                    $processorScript = $data.processor_script
                    $processorParams = if ($data.processor_params) { $data.processor_params } else { @{} }
                    
                    $success = & $SetCollectionProcessor -CollectionId $collectionId -CollectionName $collectionName `
                        -HandlerScript $processorScript -HandlerParams $processorParams -DatabasePath $DatabasePath -WriteLog $WriteLog
                    
                    if ($success) {
                        Write-PodeJsonResponse -Value @{ success = $true; message = "Processor set successfully"; collection_id = $collectionId; collection_name = $collectionName; processor_script = $processorScript }
                    } else {
                        Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Failed to set processor" }
                    }
                } catch {
                    & $WriteLog "Error in PUT /collections/$($WebEvent.Parameters['collectionId'])/processor: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            }

            # DELETE /api/collections/{id}/processor
            Add-PodeRoute -Method Delete -Path "/api/collections/:collectionId/processor" -ScriptBlock {
                try {
                    $collectionId = [int]$WebEvent.Parameters['collectionId']
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    $collectionName = $collection.name
                    $success = & $RemoveCollectionProcessor -CollectionName $collectionName -DatabasePath $DatabasePath -WriteLog $WriteLog
                    
                    if ($success) {
                        Write-PodeJsonResponse -Value @{ success = $true; message = "Processor removed successfully"; collection_id = $collectionId; collection_name = $collectionName }
                    } else {
                        Write-PodeJsonResponse -StatusCode 404 -Value @{ success = $false; error = "No processor found for collection or failed to remove" }
                    }
                } catch {
                    & $WriteLog "Error in DELETE /collections/$($WebEvent.Parameters['collectionId'])/processor: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.ScriptStackTrace)" }
                }
            } 

            # POST /api/collections/{id}/process
            Add-PodeRoute -Method Post -Path "/api/collections/:collectionId/process" -ScriptBlock {
                try {
                    $collectionId = [int]$WebEvent.Parameters['collectionId']
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    $collection = $collections | Where-Object { $_.id -eq $collectionId }
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    $collectionName = $collection.name
                    $data = $WebEvent.Data
                    $customProcessorScript = if ($data.processor_script) { $data.processor_script } else { $null }
                    $customProcessorParams = if ($data.processor_params) { $data.processor_params } else { @{} }
                    
                    # Process the collection (Note: This runs synchronously in the route)
                    $result = & $ProcessCollection -CollectionId $collectionId -CollectionName $collectionName `
                        -FileTrackerBaseUrl $FileTrackerBaseUrl -DatabasePath $DatabasePath `
                        -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath `
                        -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap `
                        -CustomProcessorScript $customProcessorScript -CustomProcessorParams $customProcessorParams `
                        -WriteLog $WriteLog -GetCollectionDirtyFiles $GetCollectionDirtyFiles `
                        -GetCollectionDeletedFiles $GetCollectionDeletedFiles `
                        -GetCollectionProcessor $GetCollectionProcessor -MarkFileAsProcessed $MarkFileAsProcessed
                    
                    Write-PodeJsonResponse -Value @{ success = $true; message = $result.message; collection_id = $collectionId; collection_name = $collectionName; processed_files = $result.processed; errors = $result.errors }
                    
                } catch {
                    & $WriteLog "Error in POST /collections/$($WebEvent.Parameters['collectionId'])/process: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            }

            # POST /api/collections/name/{name}/process
            Add-PodeRoute -Method Post -Path "/api/collections/name/:collectionName/process" -ScriptBlock {
                 try {
                    $collectionName = $WebEvent.Parameters['collectionName']
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    $collection = $collections | Where-Object { $_.name -eq $collectionName }
                    if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return }
                    
                    $collectionId = $collection.id # Get ID for consistency if needed later
                    $data = $WebEvent.Data
                    $customProcessorScript = if ($data.processor_script) { $data.processor_script } else { $null }
                    $customProcessorParams = if ($data.processor_params) { $data.processor_params } else { @{} }
                    
                    # Process the collection (Note: This runs synchronously in the route)
                    $result = & $ProcessCollection -CollectionName $collectionName `
                        -FileTrackerBaseUrl $FileTrackerBaseUrl -DatabasePath $DatabasePath `
                        -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath `
                        -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap `
                        -CustomProcessorScript $customProcessorScript -CustomProcessorParams $customProcessorParams `
                        -WriteLog $WriteLog -GetCollectionDirtyFiles $GetCollectionDirtyFiles `
                        -GetCollectionDeletedFiles $GetCollectionDeletedFiles `
                        -GetCollectionProcessor $GetCollectionProcessor -MarkFileAsProcessed $MarkFileAsProcessed
                    
                    Write-PodeJsonResponse -Value @{ success = $true; message = $result.message; collection_name = $collectionName; processed_files = $result.processed; errors = $result.errors }
                    
                } catch {
                    & $WriteLog "Error in POST /collections/name/$($WebEvent.Parameters['collectionName'])/process: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            }

            # POST /api/process
            Add-PodeRoute -Method Post -Path "/api/process" -ScriptBlock {
                try {
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    if (-not $collections -or $collections.Count -eq 0) { Write-PodeJsonResponse -StatusCode 404  -Value @{ success = $false; error = "No collections found" }; return }
                    
                    $totalProcessed = 0
                    $totalErrors = 0
                    $collectionResults = @()
                    
                    foreach ($collection in $collections) {
                        $collectionName = $collection.name
                        $collectionId = $collection.id
                        & $WriteLog "Processing collection: $collectionName (ID: $collectionId)"
                        
                        # Process the collection (Note: This runs synchronously in the route)
                        $result = & $ProcessCollection -CollectionId $collectionId -CollectionName $collectionName `
                            -FileTrackerBaseUrl $FileTrackerBaseUrl -DatabasePath $DatabasePath `
                            -TempDir $TempDir -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath `
                            -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap -WriteLog $WriteLog `
                            -GetCollectionDirtyFiles $GetCollectionDirtyFiles `
                            -GetCollectionDeletedFiles $GetCollectionDeletedFiles `
                            -GetCollectionProcessor $GetCollectionProcessor -MarkFileAsProcessed $MarkFileAsProcessed
                        
                        $totalProcessed += $result.processed
                        $totalErrors += $result.errors
                        $collectionResults += @{ collection_id = $collectionId; collection_name = $collectionName; processed_files = $result.processed; errors = $result.errors }
                    }
                    
                    Write-PodeJsonResponse -Value @{ success = $true; message = "Processing completed for all collections"; total_processed = $totalProcessed; total_errors = $totalErrors; collections = $collectionResults }
                    
                } catch {
                    & $WriteLog "Error in POST /process: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            } 

            # POST /api/files/{id}/process
            Add-PodeRoute -Method Post -Path "/api/files/:fileId/process" -ScriptBlock {
                try {
                    $fileId = [int]$WebEvent.Parameters['fileId']
                    $data = $WebEvent.Data
                    
                    if (-not $data -or (-not $data.collection_id -and -not $data.collection_name)) { Set-PodeResponseStatus -Code 400; Write-PodeJsonResponse -Value @{ success = $false; error = "Either collection_id or collection_name must be provided" }; return }
                    
                    $collectionId = $data.collection_id
                    $collectionName = $data.collection_name
                    $collections = & $GetCollections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    $collection = $null
                    
                    if ($collectionId) {
                        $collection = $collections | Where-Object { $_.id -eq $collectionId }
                        if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection with ID $collectionId not found" }; return }
                        $collectionName = $collection.name
                    } elseif ($collectionName) {
                        $collection = $collections | Where-Object { $_.name -eq $collectionName }
                        if (-not $collection) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection with name '$collectionName' not found" }; return }
                        $collectionId = $collection.id
                    }
                    
                    $file = & $GetFileDetails -CollectionId $collectionId -FileId $fileId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                    if (-not $file) { Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "File not found in collection" }; return }
                    
                    $file | Add-Member -MemberType NoteProperty -Name "CollectionName" -Value $collectionName
                    
                    $processorScript = if ($data.processor_script) { $data.processor_script } else { $null }
                    $processorParams = if ($data.processor_params) { $data.processor_params } else { @{} }
                    
                    if (-not $processorScript) {
                        $collectionProcessor = & $GetCollectionProcessor -CollectionName $collectionName -DatabasePath $DatabasePath -WriteLog $WriteLog
                        if ($collectionProcessor) {
                            $processorScript = $collectionProcessor.HandlerScript
                            $processorParams = $collectionProcessor.HandlerParams
                        } else {
                            $processorScript = Join-Path -Path $ScriptPath -ChildPath "Handlers\Update-LocalChromaDb.ps1" # Default processor
                        }
                    }
                    
                    # Import the file processing module locally (needed if running in separate runspace/thread)
                    $processorFilesModule = Join-Path -Path $ScriptPath -ChildPath "Modules\Processor-Collections.psm1"
                    Import-Module $processorFilesModule -Force
                    
                    $success = Process-CollectionFile -FileInfo $file -HandlerScript $processorScript `
                        -HandlerScriptParams $processorParams -TempDir $TempDir `
                        -OllamaUrl $OllamaUrl -EmbeddingModel $EmbeddingModel -ScriptPath $ScriptPath `
                        -UseChunking $UseChunking -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap -WriteLog $WriteLog
                    
                    if ($success) {
                        $markResult = & $MarkFileAsProcessed -CollectionId $collectionId -FileId $fileId -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
                        if ($markResult) {
                            Write-PodeJsonResponse -Value @{ success = $true; message = "File processed and marked successfully"; file_id = $fileId; file_path = $file.FilePath; collection_id = $collectionId; collection_name = $collectionName }
                        } else {
                            Set-PodeResponseStatus -Code 500
                            Write-PodeJsonResponse -Value @{ success = $false; error = "File processed but failed to mark as processed" }
                        }
                    } else {
                        Set-PodeResponseStatus -Code 500
                        Write-PodeJsonResponse -Value @{ success = $false; error = "Failed to process file" }
                    }
                    
                } catch {
                    & $WriteLog "Error in POST /files/$($WebEvent.Parameters['fileId'])/process: $_" -Level "ERROR"
                    Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
                }
            }
        }

        & $WriteLog "Processor REST API server running at http://localhost:$Port"
        & $WriteLog "Press Ctrl+C to stop the server."

    } catch {
        & $WriteLog "Fatal error starting Pode server: $_" -Level "ERROR"
        & $WriteLog "$($_.ScriptStackTrace)" -Level "ERROR"
        throw $_ # Rethrow to allow Start-Processor.ps1 to catch it
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
