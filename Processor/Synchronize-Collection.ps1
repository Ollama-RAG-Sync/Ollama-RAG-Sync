# Synchronize-Collection.ps1
# Retrieves dirty files from FileTracker and sends them to Vectors subsystem via REST API

param(
    [Parameter(Mandatory=$true)]
    [string]$CollectionName,
    
    [Parameter(Mandatory=$true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory=$false)]
    [string]$VectorsApiUrl = "http://localhost:11092",
    
    [Parameter(Mandatory=$false)]
    [string]$FileTrackerApiUrl = "http://localhost:11090/api",
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 1000,
    
    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 200,
    
    [Parameter(Mandatory=$false)]
    [switch]$Continuous = $false,
    
    [Parameter(Mandatory=$false)]
    [int]$ProcessInterval = 5,
    
    [Parameter(Mandatory=$false)]
    [string]$StopFilePath = ".stop_synchronization"
)

# Import required modules
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path -Path $scriptPath -ChildPath "Modules"
$TempDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $TempDir)) 
{ 
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null 
}

$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "SynchronizeCollection_${CollectionName}_$logDate.log"
$logFilePath = Join-Path -Path $TempDir -ChildPath "$logFileName"

# Import modules
Import-Module "$modulesPath\Processor-FileTrackerAPI.psm1" -Force
Import-Module "$modulesPath\Processor-HTTP.psm1" -Force
Import-Module "$modulesPath\Processor-Logging.psm1" -Force


# Define WriteLog script block for passing to module functions
$WriteLog = {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    Write-Log -Message $Message -Level $Level -LogFilePath $logFilePath
}

function Invoke-VectorsRestAPI {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Endpoint,
        
        [Parameter(Mandatory=$true)]
        [string]$Method,
        
        [Parameter(Mandatory=$false)]
        [object]$Body = $null,
        
        [Parameter(Mandatory=$false)]
        [string]$ApiUrl = $VectorsApiUrl
    )
    
    try {
        $uri = "$ApiUrl/$Endpoint"
        
        $params = @{
            Uri = $uri
            Method = $Method
            ContentType = "application/json"
        }
        
        if ($Body -ne $null) {
            $jsonBody = $Body | ConvertTo-Json -Depth 10
            $params.Body = $jsonBody
        }
        
        & $WriteLog "Calling Vectors API: $Method $uri" -Level "INFO"
        
        $response = Invoke-RestMethod @params
        
        return $response
    }
    catch {
        & $WriteLog "Error calling Vectors API ($Endpoint): $_" -Level "ERROR"
        return $null
    }
}

function Get-FileContentType {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    $textExtensions = @(".txt", ".md", ".html", ".csv", ".json", ".js", ".ts", ".ps1", ".psm1", ".py", ".cs", ".java")
    $pdfExtension = ".pdf"
    
    if ($textExtensions -contains $extension) {
        return "Text"
    }
    elseif ($extension -eq $pdfExtension) {
        return "PDF"
    }
    else {
        return "Unknown"
    }
}

function Add-DocumentToVectors {
    param (
        [Parameter(Mandatory=$true)]
        [object]$FileInfo,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkSize = 1000,
        
        [Parameter(Mandatory=$false)]
        [int]$ChunkOverlap = 200
    )
    
    $filePath = $FileInfo.FilePath
    $fileId = $FileInfo.Id
    
    try {
        # Verify file exists
        if (-not (Test-Path -Path $filePath)) {
            & $WriteLog "File no longer exists: $filePath" -Level "WARNING"
            return $false
        }
        
        # Get file type
        $contentType = Get-FileContentType -FilePath $filePath
        
        # Prepare request body for Vectors REST API
        $requestBody = @{
            filePath = $filePath
            fileId = $fileId
            chunkSize = $ChunkSize
            chunkOverlap = $ChunkOverlap
            contentType = $contentType
        }
        
        # Call the Vectors REST API directly
        & $WriteLog "Calling Vectors REST API to add document: $filePath" -Level "INFO"
        $uri = "$VectorsApiUrl/documents"
        
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body ($requestBody | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop
        
        if ($response.success) {
            & $WriteLog "Successfully added document to Vectors via REST API: $filePath" -Level "INFO"
            return $true
        }
        else {
            & $WriteLog "Vectors REST API returned error: $($response.error). Response: $($response | ConvertTo-Json -Depth 1)" -Level "ERROR"
            return $false
        }
    }
    catch {
        & $WriteLog "Error calling Vectors REST API: $_" -Level "ERROR"
        return $false
    }
}

function Process-DirtyFile {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$FileInfo
    )

    $filePath = $FileInfo.FilePath
    $fileId = $FileInfo.Id
    $collectionId = $FileInfo.CollectionId
    
    & $WriteLog "Processing dirty file: $filePath (ID: $fileId) in collection: $CollectionName"
    
    # Add document to Vectors
    $success = Add-DocumentToVectors -FileInfo $FileInfo -ChunkSize $ChunkSize -ChunkOverlap $ChunkOverlap
    
    if ($success) {
        # Mark file as processed in FileTracker
        $markProcessed = Mark-FileAsProcessed -CollectionId $collectionId -FileId $fileId -FileTrackerBaseUrl $FileTrackerApiUrl -WriteLog $WriteLog
        
        if ($markProcessed) {
            & $WriteLog "Marked file as processed: $filePath (ID: $fileId)"
            return $true
        }
        else {
            & $WriteLog "Failed to mark file as processed: $filePath (ID: $fileId)" -Level "ERROR"
            return $false
        }
    }
    else {
        & $WriteLog "Skipping marking file as processed due to Vector processing failure: $filePath" -Level "WARNING"
        return $false
    }
}

# Function to check if a stop file exists
function Test-StopFile {
    param (
        [string]$StopFilePath
    )
    
    if (-not [string]::IsNullOrEmpty($StopFilePath) -and (Test-Path -Path $StopFilePath)) {
        & $WriteLog "Stop file detected at: $StopFilePath. Stopping synchronization." -Level "WARNING"
        return $true
    }
    
    return $false
}

# Function to process a single batch of dirty files
function Synchronize-CollectionBatch {
    param(
        [string]$CollectionName,
        [string]$FileTrackerBaseUrl
    )
    
    try {
        & $WriteLog "Starting synchronization for collection: $CollectionName"
        
        # Get list of dirty files from the collection
        & $WriteLog "Fetching list of dirty files from collection..."
        $dirtyFiles = Get-CollectionDirtyFiles -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
        
        if (-not $dirtyFiles -or $dirtyFiles.Count -eq 0) {
            & $WriteLog "No dirty files found in collection."
            return $true
        }
        
        & $WriteLog "Found $($dirtyFiles.Count) dirty files to process in collection '$CollectionName'."
        
        # Process each dirty file
        $processedCount = 0
        $errorCount = 0
        
        foreach ($file in $dirtyFiles) {
            $success = Process-DirtyFile -FileInfo $file
            
            if ($success) {
                $processedCount++
            }
            else {
                $errorCount++
            }
            
            # Check for stop file after each file in case we need to abort mid-batch
            if (Test-StopFile -StopFilePath $StopFilePath) {
                return $false
            }
        }
        
        & $WriteLog "Completed synchronization batch for collection '$CollectionName'. Processed: $processedCount, Errors: $errorCount"
        
        return $true
    }
    catch {
        & $WriteLog "Error in synchronization batch: $_" -Level "ERROR"
        return $false
    }
}

# Main Process
try {
    & $WriteLog "Starting Synchronize-Collection script for collection: $CollectionName"
    
    # If running in continuous mode, set up a loop
    if ($Continuous) {
        & $WriteLog "Starting continuous synchronization mode for collection '$CollectionName'. Polling every $ProcessInterval minutes."
        & $WriteLog "To stop synchronization, create a stop file at: $StopFilePath" -Level "WARNING"
        
        $keepRunning = $true
        $iteration = 0
        
        while ($keepRunning) {
            $iteration++
            & $WriteLog "Starting iteration $iteration..."
            
            # Check for stop file at the beginning of each loop
            if (Test-StopFile -StopFilePath $StopFilePath) {
                $keepRunning = $false
                break
            }
            
            # Process the current batch of dirty files
            $success = Synchronize-CollectionBatch -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerApiUrl
            
            # Check if we should continue
            if (-not $success) {
                & $WriteLog "Batch synchronization failed or was interrupted. Checking whether to continue..." -Level "WARNING"
                
                if (Test-StopFile -StopFilePath $StopFilePath) {
                    $keepRunning = $false
                    break
                }
            }
            
            # If we're still running, wait for the next interval
            if ($keepRunning) {
                $nextRun = (Get-Date).AddMinutes($ProcessInterval)
                & $WriteLog "Next synchronization run scheduled at: $nextRun"
                
                # Sleep in smaller increments to check for stop file periodically
                $sleepIntervalSeconds = 30
                $totalSleepSeconds = $ProcessInterval * 60
                $sleepCount = [math]::Ceiling($totalSleepSeconds / $sleepIntervalSeconds)
                
                for ($i = 0; $i -lt $sleepCount; $i++) {
                    if (Test-StopFile -StopFilePath $StopFilePath) {
                        $keepRunning = $false
                        break
                    }
                    
                    # Calculate remaining sleep time
                    $remainingSeconds = $totalSleepSeconds - ($i * $sleepIntervalSeconds)
                    $sleepTime = [math]::Min($sleepIntervalSeconds, $remainingSeconds)
                    
                    if ($sleepTime -gt 0) {
                        Start-Sleep -Seconds $sleepTime
                    }
                }
            }
        }
        
        & $WriteLog "Continuous synchronization has been stopped."
    }
    # Otherwise, just run once
    else {
        $success = Synchronize-CollectionBatch -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerApiUrl
        if (-not $success) {
            exit 1
        }
    }
}
catch {
    & $WriteLog "Critical error in main process: $_" -Level "ERROR"
    exit 1
}

& $WriteLog "Script execution completed successfully."
& $WriteLog "Log file created at: $logFilePath"
