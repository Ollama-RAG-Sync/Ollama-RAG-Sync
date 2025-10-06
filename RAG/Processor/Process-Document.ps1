# Process-Document.ps1
# Retrieves a specific file from FileTracker by ID or FilePath, processes it (adds to Vectors),
# and updates its status in FileTracker. Similar to Process-Collection.ps1 but for single documents.
# 
# The script can work in two modes:
# 1. By FileId: Processes a file identified by its database ID
# 2. By FilePath: Processes a file identified by its file path (must exist in FileTracker database)
#
# The script checks if the file is dirty (needs processing) and throws an exception if not,
# unless the -Force parameter is used to skip the dirty check.

[CmdletBinding(DefaultParameterSetName = "ById")]
param(
    [Parameter(Mandatory=$true, ParameterSetName="ById")]
    [int]$FileId,

    [Parameter(Mandatory=$true, ParameterSetName="ByPath")]
    [string]$FilePath,

    [Parameter(Mandatory=$false)]
    [string]$InstallPath,

    [Parameter(Mandatory=$false)]
    [int]$VectorsPort = 0,

    [Parameter(Mandatory=$false)]
    [int]$FileTrackerPort = 0,

    [Parameter(Mandatory=$false)]
    [int]$ChunkSize = 0,

    [Parameter(Mandatory=$false)]
    [int]$ChunkOverlap = 0,

    [Parameter(Mandatory=$false)]
    [ValidateSet("marker", "tesseract", "ocrmypdf", "pymupdf")]
    [string]$OcrTool = "pymupdf",

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Import environment helper
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$commonPath = Join-Path -Path (Split-Path -Parent $scriptPath) -ChildPath "Common"
Import-Module (Join-Path -Path $commonPath -ChildPath "EnvironmentHelper.psm1") -Force

# Get environment variables with cross-platform support
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_INSTALL_PATH"
}
if ($VectorsPort -eq 0) {
    $envPort = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_VECTORS_API_PORT" -DefaultValue "10001"
    $VectorsPort = [int]$envPort
}
if ($FileTrackerPort -eq 0) {
    $envPort = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_FILE_TRACKER_API_PORT" -DefaultValue "10003"
    $FileTrackerPort = [int]$envPort
}
if ($ChunkSize -eq 0) {
    $envChunkSize = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_CHUNK_SIZE" -DefaultValue "20"
    $ChunkSize = [int]$envChunkSize
}
if ($ChunkOverlap -eq 0) {
    $envChunkOverlap = Get-CrossPlatformEnvVar -Name "OLLAMA_RAG_CHUNK_OVERLAP" -DefaultValue "2"
    $ChunkOverlap = [int]$envChunkOverlap
}

# --- Logging Functions ---

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

# --- FileTracker API Functions ---

function Get-FileById {
    param (
        [Parameter(Mandatory=$true)]
        [int]$FileId,

        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl
    )

    try {
        # Use the direct file metadata endpoint
        $fileUri = "$FileTrackerBaseUrl/files/$FileId/metadata"
        & $WriteLog "Fetching file metadata from $fileUri" -Level "DEBUG"
        
        $response = Invoke-RestMethod -Uri $fileUri -Method Get

        if ($response.success) {
            & $WriteLog "Found file ID $($FileId): $($response.file_path)" -Level "INFO"
            & $WriteLog " with collection ID: $($response.collection_id)" -Level "INFO"
            & $WriteLog " with collection mame: $($response.collection_name)" -Level "INFO"
            & $WriteLog " with path: $($response.file_path)" -Level "INFO"

            $file = [PSCustomObject]@{
                Id = $response.file_id
                FilePath = $response.file_path
                CollectionId = $response.collection_id
                CollectionName = $response.collection_name
            }
            
            return $file
        } else {
            & $WriteLog "Error fetching file metadata: $($response.error)" -Level "ERROR"
            return $null
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API to get file by ID $($FileId): $_" -Level "ERROR"
        return $null
    }
}

function Set-FileProcessedStatus {
    param (
        [Parameter(Mandatory=$true)]
        [int]$CollectionId,

        [Parameter(Mandatory=$true)]
        [int]$FileId,

        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl
    )

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

function Get-FileByPath {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl
    )

    try {
        # Normalize the file path for comparison
        $normalizedFilePath = [System.IO.Path]::GetFullPath($FilePath)

        # First, get all collections to find which collection contains this file
        $collectionsUri = "$FileTrackerBaseUrl/collections"
        & $WriteLog "Fetching collections from $collectionsUri" -Level "DEBUG"
        $collectionsResponse = Invoke-RestMethod -Uri $collectionsUri -Method Get

        if (-not $collectionsResponse.success) {
            & $WriteLog "Error fetching collections: $($collectionsResponse.error)" -Level "ERROR"
            return $null
        }

        # Search through collections to find the file
        foreach ($collection in $collectionsResponse.collections) {
            try {
                $filesUri = "$FileTrackerBaseUrl/collections/$($collection.id)/files"
                & $WriteLog "Searching for file path '$normalizedFilePath' in collection $($collection.name) (ID: $($collection.id))" -Level "DEBUG"
                $filesResponse = Invoke-RestMethod -Uri $filesUri -Method Get

                if ($filesResponse.success) {
                    $file = $filesResponse.files | Where-Object { 
                        [System.IO.Path]::GetFullPath($_.FilePath) -eq $normalizedFilePath 
                    }
                    if ($file) {
                        & $WriteLog "Found file path '$normalizedFilePath' in collection $($collection.name): ID $($file.id)" -Level "INFO"
                        # Add collection information to the file object
                        $file | Add-Member -NotePropertyName "CollectionName" -NotePropertyValue $collection.name
                        $file | Add-Member -NotePropertyName "CollectionId" -NotePropertyValue $collection.id
                        return $file
                    }
                }
            }
            catch {
                & $WriteLog "Error searching collection $($collection.id): $_" -Level "WARNING"
                continue
            }
        }

        & $WriteLog "File with path '$normalizedFilePath' not found in any collection" -Level "ERROR"
        return $null
    }
    catch {
        & $WriteLog "Error calling FileTracker API to find file by path '$FilePath': $_" -Level "ERROR"
        return $null
    }
}

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    Write-Error "InstallPath is required. Please provide it as a parameter or set the OLLAMA_RAG_INSTALL_PATH environment variable."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($FileTrackerPort)) {
    Write-Log "FileTrackerPort is required. Please provide it as a parameter or set the OLLAMA_RAG_FILE_TRACKER_API_PORT environment variable." -Level "ERROR"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($VectorsPort)) {
    Write-Log "VectorsPort is required. Please provide it as a parameter or set the OLLAMA_RAG_VECTORS_API_PORT environment variable." -Level "ERROR"
    exit 1
}

$VectorsApiUrl = "http://localhost:$VectorsPort"
$FileTrackerApiUrl = "http://localhost:$FileTrackerPort/api"

# --- Core Processing Logic ---

# Setup Logging
$logsDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $logsDir))
{
    New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
}
$logDate = Get-Date -Format "yyyy-MM-dd"

# Create log filename based on parameter set
if ($PSCmdlet.ParameterSetName -eq "ById") {
    $logFileName = "ProcessDocument_ID${FileId}_$logDate.log"
} else {
    $safeFileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath) -replace '[<>:"/\\|?*]', '_'
    $logFileName = "ProcessDocument_Path${safeFileName}_$logDate.log"
}

$script:LogFilePath = Join-Path -Path $logsDir -ChildPath $logFileName

# Define WriteLog script block for passing to module functions
$WriteLog = {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    Write-Log -Message $Message -Level $Level -LogFilePath $script:LogFilePath
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

    if ($textExtensions -contains $extension) {
        return "Text"
    }
    elseif ($extension -eq $pdfExtension) {
        return "PDF"
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
        [int]$LocalChunkSize = $ChunkSize,

        [Parameter(Mandatory=$false)]
        [int]$LocalChunkOverlap = $ChunkOverlap,

        [Parameter(Mandatory=$true)]
        [string]$OcrTool
    )

    $originalFilePath = $FileInfo.FilePath
    $filePath = $originalFilePath
    $fileId = $FileInfo.Id
    $collectionName = $FileInfo.CollectionName

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
            $conversionScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "Conversion\Convert-PDFToMarkdown.ps1"

            if (-not (Test-Path -Path $conversionScriptPath)) {
                & $WriteLog "Conversion script not found at: $conversionScriptPath. Skipping PDF conversion." -Level "ERROR"
                return $false
            }

            try {
                & $WriteLog "Executing conversion script: '$conversionScriptPath' with PdfPath: '$filePath'" -Level "DEBUG"
                & $conversionScriptPath -PdfFilePath $filePath -OutputFilePath ($filePath + ".md") -LogFile $script:LogFilePath -OcrTool $OcrTool -ErrorAction Stop

                $markdownOutputPath = $filePath + ".md"
                $markdownOutputPath.Trim()

                if ([string]::IsNullOrWhiteSpace($markdownOutputPath) -or (-not (Test-Path -Path $markdownOutputPath))) {
                    & $WriteLog "PDF conversion failed or did not produce a valid output path for: $filePath. Script output: '$markdownOutputPath'" -Level "ERROR"
                    return $false
                }                & $WriteLog "Successfully converted PDF to Markdown: $markdownOutputPath" -Level "INFO"
                $filePath = $markdownOutputPath
                $contentType = "Text"

            } catch {
                & $WriteLog "Error executing PDF conversion script '$conversionScriptPath' for '$filePath': $_" -Level "ERROR"
                return $false
            }
        }
        # --- PDF Conversion End ---

        # Prepare request body for Vectors REST API
        $requestBody = @{
            filePath = $filePath
            fileId = $fileId
            chunkSize = $LocalChunkSize
            chunkOverlap = $LocalChunkOverlap
            contentType = $contentType
            collectionName = $collectionName
            originalFilePath = $originalFilePath # Pass original path for metadata
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
    }    finally {
        # --- Cleanup Temporary Markdown File (Optional) ---
        # Cleanup is intentionally disabled to preserve converted files for debugging/inspection
    }
}

function Invoke-DocumentProcessing {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$FileInfo,

        [Parameter(Mandatory=$true)]
        [string]$OcrTool,

        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    $filePath = $FileInfo.FilePath
    $fileId = $FileInfo.Id
    $collectionId = $FileInfo.CollectionId
    $collectionName = $FileInfo.CollectionName

    & $WriteLog "Processing document: $filePath (ID: $fileId) in collection: $collectionName (ID: $collectionId)"

    # Check if file is already processed (not dirty) and handle Force parameter
    if (-not $FileInfo.Dirty) {
        if (-not $Force) {
            $errorMessage = "File $filePath (ID: $fileId) is not dirty (already processed). Use -Force parameter to process anyway."
            & $WriteLog $errorMessage -Level "ERROR"
            throw $errorMessage
        } else {
            & $WriteLog "File $filePath (ID: $fileId) is not dirty, but processing anyway due to -Force parameter." -Level "WARNING"
        }
    }

    # Add document to Vectors
    $success = Add-DocumentToVectors -FileInfo $FileInfo -OcrTool $OcrTool    
    if ($success) {
        # Mark file as processed in FileTracker
        $markProcessed = Set-FileProcessedStatus -CollectionId $collectionId -FileId $fileId -FileTrackerBaseUrl $FileTrackerApiUrl

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
        & $WriteLog "Skipping marking file as processed due to Vector processing failure: $filePath (ID: $fileId)" -Level "WARNING"
        return $false
    }
}

# --- Main Process ---
try {
    # Log startup information based on parameter set
    if ($PSCmdlet.ParameterSetName -eq "ById") {
        & $WriteLog "Starting Process-Document script for file ID: $FileId"
    } else {
        & $WriteLog "Starting Process-Document script for file path: $FilePath"
    }
    
    & $WriteLog "Log file: $script:LogFilePath"
    & $WriteLog "FileTracker API: $FileTrackerApiUrl"
    & $WriteLog "Vectors API: $VectorsApiUrl"    
    & $WriteLog "Lines per chunk: $ChunkSize, Line overlap: $ChunkOverlap"
    & $WriteLog "OCR Tool: $OcrTool"
    & $WriteLog "Force mode: $($Force.IsPresent)"

    # Get file information from FileTracker based on parameter set
    if ($PSCmdlet.ParameterSetName -eq "ById") {
        & $WriteLog "Fetching file information for ID: $FileId..."
        $fileInfo = Get-FileById -FileId $FileId -FileTrackerBaseUrl $FileTrackerApiUrl
        
        if ($null -eq $fileInfo) {
            & $WriteLog "Failed to retrieve file information for ID: $FileId. Check previous errors." -Level "ERROR"
            exit 1
        }
        
        & $WriteLog "Found file: $($fileInfo.FilePath) in collection: $($fileInfo.CollectionName) (ID: $($fileInfo.CollectionId))"
    } else {
        # Check if file exists on disk first
        if (-not (Test-Path -Path $FilePath)) {
            & $WriteLog "File does not exist on disk: $FilePath. Cannot process." -Level "ERROR"
            exit 1
        }
        
        & $WriteLog "Fetching file information for path: $FilePath..."
        $fileInfo = Get-FileByPath -FilePath $FilePath -FileTrackerBaseUrl $FileTrackerApiUrl
        
        if ($null -eq $fileInfo) {
            & $WriteLog "File not found in FileTracker database: $FilePath. The file must exist in the FileTracker database to be processed." -Level "ERROR"
            exit 1
        }
        
        & $WriteLog "Found file in database: ID $($fileInfo.Id) in collection: $($fileInfo.CollectionName) (ID: $($fileInfo.CollectionId))"
    }
    
    # Check if file exists on disk (for ById case, or double-check for ByPath case)
    if (-not (Test-Path -Path $fileInfo.FilePath)) {
        & $WriteLog "File no longer exists on disk: $($fileInfo.FilePath). Cannot process." -Level "ERROR"
        exit 1
    }

    # Process the document
    $success = Invoke-DocumentProcessing -FileInfo $fileInfo -OcrTool $OcrTool -Force:$Force

    if ($success) {
        if ($PSCmdlet.ParameterSetName -eq "ById") {
            & $WriteLog "Document processing completed successfully for file ID: $FileId" -Level "INFO"
        } else {
            & $WriteLog "Document processing completed successfully for file: $FilePath (ID: $($fileInfo.Id))" -Level "INFO"
        }
        exit 0
    }
    else {
        if ($PSCmdlet.ParameterSetName -eq "ById") {
            & $WriteLog "Document processing failed for file ID: $FileId" -Level "ERROR"
        } else {
            & $WriteLog "Document processing failed for file: $FilePath (ID: $($fileInfo.Id))" -Level "ERROR"
        }
        exit 1
    }
}
catch {
    & $WriteLog "Critical error in main process: $_" -Level "ERROR"
    & $WriteLog "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}
