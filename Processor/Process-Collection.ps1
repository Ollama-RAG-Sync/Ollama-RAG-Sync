# Process-Collection.ps1
# Retrieves dirty files from FileTracker for a given collection, processes them (adds to Vectors),
# and updates their status in FileTracker. Replaces the previous multi-file Processor system.

param(
    [Parameter(Mandatory=$true)]
    [string]$CollectionName,

    [Parameter(Mandatory=$true)]
    [string]$InstallPath,

    [Parameter(Mandatory=$false)]
    [string]$VectorsApiUrl = "http://localhost:10001",

    [Parameter(Mandatory=$false)]
    [string]$FileTrackerApiUrl = "http://localhost:10003/api",

    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 1000,

    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 200,

    [Parameter(Mandatory=$false)]
    [switch]$Continuous = $false,

    [Parameter(Mandatory=$false)]
    [int]$ProcessInterval = 5, # Interval in minutes for continuous mode

    [Parameter(Mandatory=$false)]
    [string]$StopFileName = ".stop_processing", # File name to signal stop in continuous mode

    [Parameter(Mandatory=$true)]
    [ValidateSet("marker", "tesseract", "ocrmypdf", "pymupdf")]
    [string]$OcrTool
)

# --- Logging Functions (from Processor-Logging.psm1) ---

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [string]$LogFilePath
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Write to console with appropriate color
    if ($Level -eq "ERROR") {
        Write-Host $logMessage -ForegroundColor Red
    }
    elseif ($Level -eq "WARNING") {
        Write-Host $logMessage -ForegroundColor Yellow
    }
    else {
        Write-Host $logMessage
    }

    # Write to log file if path provided
    if ($LogFilePath -and (-not [string]::IsNullOrWhiteSpace($LogFilePath))) {
        try {
            # Ensure log directory exists
            $logDir = Split-Path -Path $LogFilePath -Parent
            if (-not (Test-Path -Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Add-Content -Path $LogFilePath -Value $logMessage -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "[$timestamp] [ERROR] Failed to write to log file '$LogFilePath': $_" -ForegroundColor Red
        }
    }
}

# --- FileTracker API Functions (from Processor-FileTrackerAPI.psm1) ---

function Get-Collections {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl
        # Removed WriteLog parameter, uses the script-scoped $WriteLog
    )

    try {
        $uri = "$FileTrackerBaseUrl/collections"
        & $WriteLog "Fetching collections from $uri" -Level "DEBUG"
        $response = Invoke-RestMethod -Uri $uri -Method Get

        if ($response.success) {
            return $response.collections
        }
        else {
            & $WriteLog "Error fetching collections: $($response.error)" -Level "ERROR"
            return $null
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API $uri to get collections: $_" -Level "ERROR"
        return $null
    }
}

function Get-CollectionIdByName {
    param (
        [Parameter(Mandatory=$true)]
        [string]$CollectionNameParam, # Renamed to avoid conflict with script param

        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl
        # Removed WriteLog parameter
    )

    try {
        # Get all collections
        $collections = Get-Collections -FileTrackerBaseUrl $FileTrackerBaseUrl

        if ($null -eq $collections) {
            & $WriteLog "Failed to retrieve collections" -Level "ERROR"
            return $null
        }

        # Find collection by name
        $collection = $collections | Where-Object { $_.name -eq $CollectionNameParam }

        if ($null -eq $collection) {
            & $WriteLog "Collection with name '$CollectionNameParam' not found" -Level "ERROR"
            return $null
        }

        return $collection.id
    }
    catch {
        & $WriteLog "Error finding collection ID by name '$CollectionNameParam': $_" -Level "ERROR"
        return $null
    }
}

function Get-CollectionDirtyFiles {
    param (
        [Parameter(Mandatory=$false)]
        [int]$CollectionId,

        [Parameter(Mandatory=$false)]
        [string]$CollectionNameParam, # Renamed

        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl
        # Removed WriteLog parameter
    )

    # Ensure either CollectionId or CollectionName is provided
    if (-not $CollectionId -and -not $CollectionNameParam) {
        & $WriteLog "Either CollectionId or CollectionName must be provided to Get-CollectionDirtyFiles" -Level "ERROR"
        return $null
    }

    # If CollectionId is not provided but CollectionName is, get the ID from name
    if (-not $CollectionId -and $CollectionNameParam) {
        $CollectionId = Get-CollectionIdByName -CollectionNameParam $CollectionNameParam -FileTrackerBaseUrl $FileTrackerBaseUrl

        if (-not $CollectionId) {
            return $null # Error already logged by Get-CollectionIdByName
        }
    }

    try {
        $uri = "$FileTrackerBaseUrl/collections/$CollectionId/files?dirty=true"
        & $WriteLog "Fetching dirty files from $uri" -Level "DEBUG"
        $response = Invoke-RestMethod -Uri $uri -Method Get

        if ($response.success) {
            & $WriteLog "Success fetching dirty files for collection $CollectionId (Length = $($response.files.Length))" -Level "DEBUG"
            return ,$response.files
        }
        else {
            & $WriteLog "Error fetching dirty files for collection $CollectionId : $($response.error)" -Level "ERROR"
            return $null
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API to get dirty files for collection $CollectionId : $_" -Level "ERROR"
        return $null
    }
}

function Mark-FileAsProcessed {
    param (
        [Parameter(Mandatory=$false)]
        [int]$CollectionId,

        [Parameter(Mandatory=$false)]
        [string]$CollectionNameParam, # Renamed

        [Parameter(Mandatory=$true)]
        [int]$FileId,

        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl
        # Removed WriteLog parameter
    )

    # Ensure either CollectionId or CollectionName is provided
    if (-not $CollectionId -and -not $CollectionNameParam) {
        & $WriteLog "Either CollectionId or CollectionName must be provided to Mark-FileAsProcessed" -Level "ERROR"
        return $false
    }

    # If CollectionId is not provided but CollectionName is, get the ID from name
    if (-not $CollectionId -and $CollectionNameParam) {
        $CollectionId = Get-CollectionIdByName -CollectionNameParam $CollectionNameParam -FileTrackerBaseUrl $FileTrackerBaseUrl

        if (-not $CollectionId) {
            return $false # Error already logged
        }
    }

    try {
        $uri = "$FileTrackerBaseUrl/collections/$CollectionId/files/$FileId"
        $body = @{
            dirty = $false
        } | ConvertTo-Json

        & $WriteLog "Marking file $FileId in collection $CollectionId as processed via $uri" -Level "DEBUG"
        $response = Invoke-RestMethod -Uri $uri -Method Put -Body $body -ContentType "application/json"

        if ($response.success) {
            return $true
        }
        else {
            & $WriteLog "Error marking file $FileId as processed: $($response.error)" -Level "ERROR"
            return $false
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API to mark file $FileId as processed: $_" -Level "ERROR"
        return $false
    }
}

# --- Core Processing Logic (from Start-Processor.ps1) ---

# Setup Logging
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$logsDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $logsDir))
{
    New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
}
$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "ProcessCollection_${CollectionName}_$logDate.log"
$script:LogFilePath = Join-Path -Path $logsDir -ChildPath $logFileName # Set the script-scoped LogFilePath

# Define WriteLog script block for passing to module functions (now local functions)
# This needs to be defined *after* Write-Log itself is defined and *after* $script:LogFilePath is set.
$WriteLog = {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    # Use the script-scoped LogFilePath
    Write-Log -Message $Message -Level $Level -LogFilePath $script:LogFilePath
}

# Define Stop File Path (relative to script location)
$StopFilePath = Join-Path -Path $scriptPath -ChildPath $StopFileName

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

        if ($null -ne $Body) {
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

    # Add more extensions as needed
    $textExtensions = @(".txt", ".md", ".html", ".csv", ".json", ".js", ".ts", ".ps1", ".psm1", ".py", ".cs", ".java", ".xml", ".yaml", ".yml", ".log")
    $pdfExtension = ".pdf"
    $docxExtension = ".docx" # Example: Add DOCX support if needed later

    if ($textExtensions -contains $extension) {
        return "Text"
    }
    elseif ($extension -eq $pdfExtension) {
        return "PDF"
    }
    elseif ($extension -eq $docxExtension) {
        return "DOCX"
    }
    else {
        & $WriteLog "Unknown file type for extension '$extension' in file: $FilePath" -Level "WARNING"
        return "Unknown"
    }
}

function Add-DocumentToVectors {
    param (
        [Parameter(Mandatory=$true)]
        [object]$FileInfo,

        [Parameter(Mandatory=$false)]
        [int]$LocalChunkSize = $ChunkSize, # Use script param default

        [Parameter(Mandatory=$false)]
        [int]$LocalChunkOverlap = $ChunkOverlap, # Use script param default,

        [Parameter(Mandatory=$true)]
        [string]$OcrTool
    )

    $originalFilePath = $FileInfo.FilePath # Store original path
    $filePath = $originalFilePath # Use this variable for processing
    $fileId = $FileInfo.Id
    $temporaryMarkdownPath = $null # To track temporary files

    try {
        # Verify file exists
        if (-not (Test-Path -Path $filePath)) {
            & $WriteLog "File no longer exists: $filePath. Skipping vector addition." -Level "WARNING"
            return $false
        }

        # Get file type
        $contentType = Get-FileContentType -FilePath $filePath
        if ($contentType -eq "Unknown") {
             & $WriteLog "Skipping vector addition for file with unknown content type: $filePath" -Level "WARNING"
             return $true # Mark as processed
        }

        # --- PDF Conversion Start ---
        if ($contentType -eq "PDF") {
            & $WriteLog "Detected PDF file: $filePath. Attempting conversion to Markdown." -Level "INFO"
            # Use PSScriptRoot for robustness in finding the conversion script relative to this script
            $conversionScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "Conversion\Convert-PDFToMarkdown.ps1"

            if (-not (Test-Path -Path $conversionScriptPath)) {
                & $WriteLog "Conversion script not found at: $conversionScriptPath. Skipping PDF conversion." -Level "ERROR"
                # Decide how to handle: skip processing, process as PDF anyway? Let's skip processing.
                return $false # Indicate failure
            }

            try {
                # Execute the conversion script, capture output (assuming it outputs the MD path)
                # Add -ErrorAction Stop to catch script errors
                # Ensure the conversion script handles its own output path logic (e.g., placing MD next to PDF)
                & $WriteLog "Executing conversion script: '$conversionScriptPath' with PdfPath: '$filePath'" -Level "DEBUG" # Corrected logging format
                & $conversionScriptPath -PdfFilePath $filePath -OutputFilePath ($filePath + ".md") -LogFile $script:LogFilePath -OcrTool $OcrTool -ErrorAction Stop
                # Trim potential whitespace from output

                $markdownOutputPath = $filePath + ".md"
                $markdownOutputPath.Trim()

                if ([string]::IsNullOrWhiteSpace($markdownOutputPath) -or (-not (Test-Path -Path $markdownOutputPath))) {
                    & $WriteLog "PDF conversion failed or did not produce a valid output path for: $filePath. Script output: '$markdownOutputPath'" -Level "ERROR"
                    return $false # Indicate failure
                }

                & $WriteLog "Successfully converted PDF to Markdown: $markdownOutputPath" -Level "INFO"
                $filePath = $markdownOutputPath # Use the Markdown file for vectorization
                $contentType = "Text" # Treat the converted file as text
                $temporaryMarkdownPath = $filePath # Mark this file for potential cleanup later

            } catch {
                & $WriteLog "Error executing PDF conversion script '$conversionScriptPath' for '$filePath': $_" -Level "ERROR"
                return $false # Indicate failure
            }
        }
        # --- PDF Conversion End ---


        # Prepare request body for Vectors REST API
        $requestBody = @{
            # Use originalFilePath for metadata if needed, but filePath for content processing
            filePath = $filePath # This is now the MD path for PDFs
            fileId = $fileId
            chunkSize = $LocalChunkSize
            chunkOverlap = $LocalChunkOverlap
            contentType = $contentType # Now "Text" for converted PDFs
            collectionName = $CollectionName # Pass collection name to Vectors API
            # Optional: Add original file path if Vectors API needs it
            # originalFilePath = $originalFilePath
        }

        # Call the Vectors REST API directly
        & $WriteLog "Calling Vectors REST API to add document content from: $filePath (Original: $originalFilePath, ID: $fileId)" -Level "INFO"
        $uri = "$VectorsApiUrl/documents"

        $response = Invoke-RestMethod -Uri $uri -Method Post -Body ($requestBody | ConvertTo-Json -Depth 5) -ContentType "application/json" -ErrorAction Stop

        if ($response.success) {
            & $WriteLog "Successfully added document to Vectors via REST API: $filePath (Original: $originalFilePath)" -Level "INFO"
            return $true
        }
        else {
            & $WriteLog "Vectors REST API returned error for file $filePath (Original: $originalFilePath, ID: $fileId): $($response.error). Response: $($response | ConvertTo-Json -Depth 1)" -Level "ERROR"
            return $false
        }
    }
    catch {
        & $WriteLog "Error calling Vectors REST API for file $filePath (Original: $originalFilePath, ID: $fileId): $_" -Level "ERROR"
        return $false
    }
    finally {
        # --- Cleanup Temporary Markdown File ---
        # Only remove if it was actually created and is different from the original path
        #if ($null -ne $temporaryMarkdownPath -and ($temporaryMarkdownPath -ne $originalFilePath) -and (Test-Path -Path $temporaryMarkdownPath)) {
        #    & $WriteLog "Cleaning up temporary Markdown file: $temporaryMarkdownPath" -Level "DEBUG"
        #    try {
        #        Remove-Item -Path $temporaryMarkdownPath -Force -ErrorAction SilentlyContinue
        #    } catch {
        #        & $WriteLog "Failed to remove temporary Markdown file '$temporaryMarkdownPath': $_" -Level "WARNING"
        #    }
        #}
        # --- Cleanup End ---
    }
}

function Process-DirtyFile {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$FileInfo,

        [Parameter(Mandatory=$true)]
        [string]$OcrTool
    )

    $filePath = $FileInfo.FilePath
    $fileId = $FileInfo.Id
    $collectionId = $FileInfo.CollectionId # Needed for Mark-FileAsProcessed

    & $WriteLog "Processing dirty file: $filePath (ID: $fileId) in collection: $CollectionName"

    # Add document to Vectors
    $success = Add-DocumentToVectors -FileInfo $FileInfo -OcrTool $OcrTool

    if ($success) {
        # Mark file as processed in FileTracker
        # Pass CollectionId directly, no need to look it up again
        $markProcessed = Mark-FileAsProcessed -CollectionId $collectionId -FileId $fileId -FileTrackerBaseUrl $FileTrackerApiUrl

        if ($markProcessed) {
            & $WriteLog "Marked file as processed: $filePath (ID: $fileId)"
            return $true
        }
        else {
            & $WriteLog "Failed to mark file as processed: $filePath (ID: $fileId)" -Level "ERROR"
            return $false # Failed to mark, counts as error
        }
    }
    else {
        & $WriteLog "Skipping marking file as processed due to Vector processing failure: $filePath (ID: $fileId)" -Level "WARNING"
        return $false # Failed to process, counts as error
    }
}

# Function to check if a stop file exists
function Test-StopFile {
    param (
        [string]$PathToCheck
    )

    if (-not [string]::IsNullOrEmpty($PathToCheck) -and (Test-Path -Path $PathToCheck)) {
        & $WriteLog "Stop file detected at: $PathToCheck. Stopping processing." -Level "WARNING"
        return $true
    }

    return $false
}

# Function to process a single batch of dirty files
function Process-CollectionBatch {
    param(
        [string]$CollectionNameParam, # Renamed
        [string]$FileTrackerBaseUrl,
        [string]$OcrTool
    )

    try {
        & $WriteLog "Starting processing batch for collection: $CollectionNameParam"

        # Get list of dirty files from the collection using the name
        & $WriteLog "Fetching list of dirty files from collection '$CollectionNameParam'..."
        $dirtyFiles = Get-CollectionDirtyFiles -CollectionNameParam $CollectionNameParam -FileTrackerBaseUrl $FileTrackerBaseUrl

        if ($null -eq $dirtyFiles) {
             & $WriteLog "Failed to retrieve dirty files for collection '$CollectionNameParam'. Check previous errors." -Level "ERROR"
             return $false # Indicate failure
        }

        if ($dirtyFiles.Count -eq 0) {
            & $WriteLog "No dirty files found in collection '$CollectionNameParam'."
            return $true # Indicate success (nothing to do)
        }

        & $WriteLog "Found $($dirtyFiles.Count) dirty files to process in collection '$CollectionNameParam'."

        # Process each dirty file
        $processedCount = 0
        $errorCount = 0

        foreach ($file in $dirtyFiles) {
            $success = Process-DirtyFile -FileInfo $file -OcrTool $OcrTool

            if ($success) {
                $processedCount++
            }
            else {
                $errorCount++
            }

            # Check for stop file after each file in case we need to abort mid-batch
            if (Test-StopFile -PathToCheck $StopFilePath) {
                return $false # Indicate interruption
            }
        }

        & $WriteLog "Completed processing batch for collection '$CollectionNameParam'. Processed: $processedCount, Errors: $errorCount"

        # Return true if no errors occurred during processing (ignoring stop file interruption)
        return ($errorCount -eq 0)
    }
    catch {
        & $WriteLog "Error in processing batch for collection '$CollectionNameParam': $_" -Level "ERROR"
        return $false # Indicate failure
    }
}

# --- Main Process ---
try {
    & $WriteLog "Starting Process-Collection script for collection: $CollectionName"
    & $WriteLog "Log file: $script:LogFilePath"
    & $WriteLog "FileTracker API: $FileTrackerApiUrl"
    & $WriteLog "Vectors API: $VectorsApiUrl"
    & $WriteLog "Chunk Size: $ChunkSize, Overlap: $ChunkOverlap"

    # If running in continuous mode, set up a loop
    if ($Continuous) {
        & $WriteLog "Starting continuous processing mode for collection '$CollectionName'. Polling every $ProcessInterval minutes."
        & $WriteLog "To stop processing, create a file named '$StopFileName' in the script directory ($scriptPath)." -Level "WARNING"

        # Remove stop file if it exists from a previous run
        if (Test-Path -Path $StopFilePath) {
            & $WriteLog "Removing existing stop file: $StopFilePath" -Level "INFO"
            Remove-Item -Path $StopFilePath -Force -ErrorAction SilentlyContinue
        }

        $keepRunning = $true
        $iteration = 0

        while ($keepRunning) {
            $iteration++
            & $WriteLog "Starting iteration $iteration..."

            # Check for stop file at the beginning of each loop
            if (Test-StopFile -PathToCheck $StopFilePath) {
                $keepRunning = $false
                break
            }

            # Process the current batch of dirty files
            $batchSuccess = Process-CollectionBatch -CollectionNameParam $CollectionName -FileTrackerBaseUrl $FileTrackerApiUrl -OcrTool $OcrTool

            # Check if we should continue (batchSuccess being false could mean errors or stop file)
            if (-not $batchSuccess) {
                & $WriteLog "Batch processing reported failure or interruption. Checking stop file..." -Level "WARNING"
                if (Test-StopFile -PathToCheck $StopFilePath) {
                    $keepRunning = $false
                    break # Exit loop if stop file found
                }
                 & $WriteLog "Stop file not found, but errors occurred in the batch. Continuing loop." -Level "WARNING"
            }

            # If we're still running, wait for the next interval
            if ($keepRunning) {
                $nextRun = (Get-Date).AddMinutes($ProcessInterval)
                & $WriteLog "Next processing run scheduled at: $nextRun. Sleeping for $ProcessInterval minutes."

                # Sleep in smaller increments to check for stop file periodically
                $sleepIntervalSeconds = 15 # Check every 15 seconds
                $totalSleepSeconds = $ProcessInterval * 60
                $sleepCount = [math]::Ceiling($totalSleepSeconds / $sleepIntervalSeconds)

                for ($i = 0; $i -lt $sleepCount; $i++) {
                    if (Test-StopFile -PathToCheck $StopFilePath) {
                        $keepRunning = $false
                        break
                    }

                    # Calculate remaining sleep time in this chunk
                    $remainingTotalSeconds = $totalSleepSeconds - ($i * $sleepIntervalSeconds)
                    $sleepTime = [math]::Min($sleepIntervalSeconds, $remainingTotalSeconds)

                    if ($sleepTime -gt 0) {
                        Start-Sleep -Seconds $sleepTime
                    }
                }
                 if (-not $keepRunning) { break } # Exit outer loop if stop file found during sleep
            }
        }

        & $WriteLog "Continuous processing has been stopped."
        # Clean up stop file
        if (Test-Path -Path $StopFilePath) {
            & $WriteLog "Removing stop file: $StopFilePath" -Level "INFO"
            Remove-Item -Path $StopFilePath -Force -ErrorAction SilentlyContinue
        }
    }
    # Otherwise, just run once
    else {
        $batchSuccess = Process-CollectionBatch -CollectionNameParam $CollectionName -FileTrackerBaseUrl $FileTrackerApiUrl -OcrTool $OcrTool
        if (-not $batchSuccess) {
             & $WriteLog "Single batch processing run completed with errors." -Level "ERROR"
            exit 1 # Exit with error code if the single run had errors
        } else {
             & $WriteLog "Single batch processing run completed successfully." -Level "INFO"
        }
    }
}
catch {
    & $WriteLog "Critical error in main process: $_" -Level "CRITICAL" # Changed level for emphasis
    exit 1
}

& $WriteLog "Script execution completed."
exit 0 # Explicitly exit with success code
