param (
    [Parameter(Mandatory=$true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory=$false)]
    [string[]]$OmitFolders = @('.git', 'node_modules', 'bin', 'obj'),
    
    [Parameter(Mandatory=$true)]
    [int]$Port,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiPath = "/api"
)

$TempDir = Join-Path -Path $InstallPath -ChildPath "Temp"
if (-not (Test-Path -Path $TempDir)) 
{ 
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null 
}

$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "FileTracker_$logDate.log"
$logFilePath = Join-Path -Path $TempDir -ChildPath "$logFileName"

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
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
        Write-Host $logMessage -ForegroundColor Green
    }
    
    # Write to log file
    Add-Content -Path $logFilePath -Value $logMessage
}


# Compute DatabasePath from InstallationPath
$DatabasePath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"

# Import required modules
Import-Module -Name "$PSScriptRoot\FileTracker-Shared.psm1" -Force -Verbose
Import-Module -Name "$PSScriptRoot\Database-Shared.psm1" -Force -Verbose

$sqliteAssemblyPath = "$InstallPath\Microsoft.Data.Sqlite.dll"
$sqliteAssemblyPath2 = "$InstallPath\SQLitePCLRaw.core.dll"
$sqliteAssemblyPath3 = "$InstallPath\SQLitePCLRaw.provider.e_sqlite3.dll"

# Load SQLite assembly
Add-Type -Path $sqliteAssemblyPath
Add-Type -Path $sqliteAssemblyPath2
Add-Type -Path $sqliteAssemblyPath3


# Set up HTTP listener
$prefix = "http://localhost:$Port$ApiPath"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix + "/")

# API request handling function
function Process-Request {
    param (
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )
    
    # Parse the URL path to determine the endpoint
    $endpoint = $Request.Url.LocalPath.Substring($ApiPath.Length)
    
    # Setup response headers
    $Response.ContentType = "application/json"
    $Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    $Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    
    # Handle OPTIONS requests (CORS preflight)
    if ($Request.HttpMethod -eq "OPTIONS") {
        $Response.StatusCode = 200
        $Response.Close()
        return
    }

    try {
        # Parse collection ID if present in the endpoint path
        $collectionId = $null
        $collectionMatch = $endpoint -match "^/collections/(\d+)"
        if ($collectionMatch) {
            $collectionId = [int]$Matches[1]
        }
        
        # Match the endpoint against patterns and handle accordingly
        switch -regex ($endpoint) {
            # Collections endpoints
            "^/collections$" {
                if ($Request.HttpMethod -eq "GET") {
                    # Get all collections
                    $collectionsResult = Get-Collections -DatabasePath $DatabasePath
                    $result = @{
                        success = $true
                        collections = $collectionsResult
                        count = $collectionsResult.Count
                    }
                    $Response.StatusCode = 200
                }
                elseif ($Request.HttpMethod -eq "POST") {
                    # Create a new collection
                    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $data = ConvertFrom-Json $body
                    
                    if ($data.name) {
                        $newCollection = New-Collection -Name $data.name -Description $data.description -SourceFolder $data.sourceFolder -InstallPath $InstallPath
                        
                        if ($newCollection) {
                            $Response.StatusCode = 201 # Created
                            $result = @{
                                success = $true
                                message = "Collection created successfully"
                                collection = $newCollection
                            }
                        }
                        else {
                            $Response.StatusCode = 500 # Internal Server Error
                            $result = @{
                                success = $false
                                error = "Failed to create collection"
                            }
                        }
                    }
                    else {
                        $Response.StatusCode = 400 # Bad Request
                        $result = @{
                            success = $false
                            error = "Invalid request. Requires 'name' field."
                        }
                    }
                }
                else {
                    $Response.StatusCode = 405 # Method Not Allowed
                    $result = @{
                        success = $false
                        error = "Method not allowed. Use GET or POST."
                    }
                }
                break
            }
            
            # Specific collection endpoint
            "^/collections/\d+$" {
                if ($Request.HttpMethod -eq "GET") {
                    # Get collection by ID
                    $collection = Get-Collection -Id $collectionId -DatabasePath $DatabasePath
                    
                    if ($collection) {
                        $Response.StatusCode = 200
                        $result = @{
                            success = $true
                            collection = $collection
                        }
                    }
                    else {
                        $Response.StatusCode = 404 # Not Found
                        $result = @{
                            success = $false
                            error = "Collection not found"
                        }
                    }
                }
                elseif ($Request.HttpMethod -eq "PUT") {
                    # Update collection
                    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $data = ConvertFrom-Json $body
                    
                    $updateParams = @{
                        Id = $collectionId
                        DatabasePath = $DatabasePath
                    }
                    
                    if ($data.name) {
                        $updateParams["Name"] = $data.name
                    }
                    
                    if ($PSBoundParameters.ContainsKey('Description')) {
                        $updateParams["Description"] = $data.description
                    }
                    
                    $success = Update-Collection @updateParams
                    
                    if ($success) {
                        $Response.StatusCode = 200
                        $updatedCollection = Get-Collection -Id $collectionId -DatabasePath $DatabasePath
                        $result = @{
                            success = $true
                            message = "Collection updated successfully"
                            collection = $updatedCollection
                        }
                    }
                    else {
                        $Response.StatusCode = 500 # Internal Server Error
                        $result = @{
                            success = $false
                            error = "Failed to update collection"
                        }
                    }
                }
                elseif ($Request.HttpMethod -eq "DELETE") {
                    # Delete collection
                    $success = Remove-Collection -Id $collectionId -DatabasePath $DatabasePath
                    
                    if ($success) {
                        $Response.StatusCode = 200
                        $result = @{
                            success = $true
                            message = "Collection deleted successfully"
                        }
                    }
                    else {
                        $Response.StatusCode = 500 # Internal Server Error
                        $result = @{
                            success = $false
                            error = "Failed to delete collection"
                        }
                    }
                }
                else {
                    $Response.StatusCode = 405 # Method Not Allowed
                    $result = @{
                        success = $false
                        error = "Method not allowed. Use GET, PUT, or DELETE."
                    }
                }
                break
            }
            
            # Collection settings endpoint
            "^/collections/\d+/settings$" {
                if ($Request.HttpMethod -eq "GET") {
                    # Get collection settings
                    $collection = Get-Collection -Id $collectionId -DatabasePath $DatabasePath
                    
                    if ($collection) {
                        # Get additional settings like watch status if applicable
                        $watchStatus = $false
                        $watchJob = Get-Job -Name "Watch_Collection_$collectionId" -ErrorAction SilentlyContinue
                        if ($watchJob) {
                            $watchStatus = $true
                        }
                        
                        $Response.StatusCode = 200
                        $result = @{
                            success = $true
                            collection = $collection
                            settings = @{
                                isWatching = $watchStatus
                                watchJob = if ($watchStatus) { $watchJob.Id } else { $null }
                            }
                        }
                    }
                    else {
                        $Response.StatusCode = 404 # Not Found
                        $result = @{
                            success = $false
                            error = "Collection not found"
                        }
                    }
                }
                else {
                    $Response.StatusCode = 405 # Method Not Allowed
                    $result = @{
                        success = $false
                        error = "Method not allowed. Use GET."
                    }
                }
                break
            }
            
            # Collection watch endpoint
            "^/collections/\d+/watch$" {
                if ($Request.HttpMethod -eq "POST") {
                    # Start or stop watching collection
                    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $data = ConvertFrom-Json $body
                    
                    # Get collection info first
                    $collection = Get-Collection -Id $collectionId -DatabasePath $DatabasePath
                    if (-not $collection) {
                        $Response.StatusCode = 404 # Not Found
                        $result = @{
                            success = $false
                            error = "Collection not found"
                        }
                        break
                    }
                    
                    # Check if we need to start or stop watching
                    $action = $data.action
                    if ($action -eq "start") {
                        # Check if already watching
                        $watchJob = Get-Job -Name "Watch_Collection_$collectionId" -ErrorAction SilentlyContinue
                        if ($watchJob) {
                            $Response.StatusCode = 409 # Conflict
                            $result = @{
                                success = $false
                                error = "Collection is already being watched"
                                job = $watchJob.Id
                            }
                            break
                        }
                        
                        # Determine watch parameters
                        $watchParams = @{
                            DirectoryToWatch = $collection.source_folder
                            ProcessInterval = $data.processInterval ?? 15
                            DatabasePath = $DatabasePath
                            CollectionId = $collectionId
                        }
                        
                        if ($data.fileFilter) {
                            $watchParams["FileFilter"] = $data.fileFilter
                        }
                        
                        if ($data.watchCreated -eq $true) {
                            $watchParams["WatchCreated"] = $true
                        }
                        
                        if ($data.watchModified -eq $true) {
                            $watchParams["WatchModified"] = $true
                        }
                        
                        if ($data.watchDeleted -eq $true) {
                            $watchParams["WatchDeleted"] = $true
                        }
                        
                        if ($data.watchRenamed -eq $true) {
                            $watchParams["WatchRenamed"] = $true
                        }
                        
                        if ($data.includeSubdirectories -eq $true) {
                            $watchParams["IncludeSubdirectories"] = $true
                        }
                        
                        if ($data.omitFolders -and $data.omitFolders.Count -gt 0) {
                            $watchParams["OmitFolders"] = $data.omitFolders
                        }
                        else {
                            $watchParams["OmitFolders"] = $OmitFolders
                        }
                        
                        # Start watch job
                        try {
                            $watchScriptPath = Join-Path $PSScriptRoot "Watch-FileTracker.ps1"
                            $job = Start-Job -Name "Watch_Collection_$collectionId" -ScriptBlock {
                                param($scriptPath, $params)
                                & $scriptPath @params
                            } -ArgumentList $watchScriptPath, $watchParams
                            
                            $Response.StatusCode = 200
                            $result = @{
                                success = $true
                                message = "File watching started for collection"
                                collection_id = $collectionId
                                job_id = $job.Id
                                parameters = $watchParams
                            }
                        }
                        catch {
                            $Response.StatusCode = 500 # Internal Server Error
                            $result = @{
                                success = $false
                                error = "Failed to start watching: $_"
                            }
                        }
                    }
                    elseif ($action -eq "stop") {
                        # Check if actually watching
                        $watchJob = Get-Job -Name "Watch_Collection_$collectionId" -ErrorAction SilentlyContinue
                        if (-not $watchJob) {
                            $Response.StatusCode = 404 # Not Found
                            $result = @{
                                success = $false
                                error = "Collection is not being watched"
                            }
                            break
                        }
                        
                        # Stop the job
                        try {
                            Stop-Job -Id $watchJob.Id
                            Remove-Job -Id $watchJob.Id
                            
                            $Response.StatusCode = 200
                            $result = @{
                                success = $true
                                message = "File watching stopped for collection"
                                collection_id = $collectionId
                            }
                        }
                        catch {
                            $Response.StatusCode = 500 # Internal Server Error
                            $result = @{
                                success = $false
                                error = "Failed to stop watching: $_"
                            }
                        }
                    }
                    else {
                        $Response.StatusCode = 400 # Bad Request
                        $result = @{
                            success = $false
                            error = "Invalid action. Use 'start' or 'stop'."
                        }
                    }
                }
                else {
                    $Response.StatusCode = 405 # Method Not Allowed
                    $result = @{
                        success = $false
                        error = "Method not allowed. Use POST."
                    }
                }
                break
            }
            
            # Collection files endpoint
            "^/collections/\d+/files$" {
                if ($Request.HttpMethod -eq "GET") {
                    # Get files in collection
                    $dirty = $Request.QueryString["dirty"] -eq "true"
                    $processed = $Request.QueryString["processed"] -eq "true"
                    $deleted = $Request.QueryString["deleted"] -eq "true"
                    
                    $params = @{
                        CollectionId = $collectionId
                        DatabasePath = $DatabasePath
                    }
                    
                    if ($dirty) {
                        $params["DirtyOnly"] = $true
                    }
                    elseif ($processed) {
                        $params["ProcessedOnly"] = $true
                    }
                    
                    if ($deleted) {
                        $params["DeletedOnly"] = $true
                    }
                    
                    $files = Get-CollectionFiles @params
                    
                    $Response.StatusCode = 200
                    $result = @{
                        success = $true
                        files = $files
                        count = $files.Count
                        collection_id = $collectionId
                    }
                }
                elseif ($Request.HttpMethod -eq "POST") {
                    # Add a file to the collection
                    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $data = ConvertFrom-Json $body
                    
                    if ($data.filePath) {
                        $params = @{
                            CollectionId = $collectionId
                            FilePath = $data.filePath
                            DatabasePath = $DatabasePath
                        }
                        
                        if ($data.originalUrl) {
                            $params["OriginalUrl"] = $data.originalUrl
                        }
                        
                        if ($null -ne $data.dirty) {
                            $params["Dirty"] = $data.dirty
                        }
                        
                        $result = Add-FileToCollection @params
                        
                        if ($result) {
                            $Response.StatusCode = 200
                            $result = @{
                                success = $true
                                message = if ($result.updated) { "File updated in collection" } else { "File added to collection" }
                                file = $result
                            }
                        }
                        else {
                            $Response.StatusCode = 500 # Internal Server Error
                            $result = @{
                                success = $false
                                error = "Failed to add file to collection"
                            }
                        }
                    }
                    else {
                        $Response.StatusCode = 400 # Bad Request
                        $result = @{
                            success = $false
                            error = "Invalid request. Requires 'filePath' field."
                        }
                    }
                }
                elseif ($Request.HttpMethod -eq "PUT") {
                    # Mark all files in collection as dirty or processed
                    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $data = ConvertFrom-Json $body
                    
                    if ($null -ne $data.dirty) {
                        $success = Update-AllFilesStatus -Dirty $data.dirty -DatabasePath $DatabasePath -CollectionId $collectionId
                        
                        if ($success) {
                            $Response.StatusCode = 200
                            $result = @{
                                success = $true
                                message = "All files in collection updated successfully"
                                dirty = $data.dirty
                            }
                        }
                        else {
                            $Response.StatusCode = 500 # Internal Server Error
                            $result = @{
                                success = $false
                                error = "Failed to update files in collection"
                            }
                        }
                    }
                    else {
                        $Response.StatusCode = 400 # Bad Request
                        $result = @{
                            success = $false
                            error = "Invalid request. Requires 'dirty' field."
                        }
                    }
                }
                else {
                    $Response.StatusCode = 405 # Method Not Allowed
                    $result = @{
                        success = $false
                        error = "Method not allowed. Use GET, POST, or PUT."
                    }
                }
                break
            }
            
            # Remove file from collection endpoint
            "^/collections/\d+/files/(\d+)$" {
                $fileId = [int]$Matches[1]
                
                if ($Request.HttpMethod -eq "DELETE") {
                    # Remove file from collection
                    $success = Remove-FileFromCollection -FileId $fileId -DatabasePath $DatabasePath
                    
                    if ($success) {
                        $Response.StatusCode = 200
                        $result = @{
                            success = $true
                            message = "File removed from collection"
                        }
                    }
                    else {
                        $Response.StatusCode = 500 # Internal Server Error
                        $result = @{
                            success = $false
                            error = "Failed to remove file from collection"
                        }
                    }
                }
                elseif ($Request.HttpMethod -eq "PUT") {
                    # Update file status
                    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $data = ConvertFrom-Json $body
                    
                    if ($null -ne $data.dirty) {
                        # First get the file path
                        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
                        $command = $connection.CreateCommand()
                        $command.CommandText = "SELECT FilePath FROM files WHERE id = @FileId AND collection_id = @CollectionId"
                        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FileId", $fileId)))
                        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
                        
                        $filePath = $command.ExecuteScalar()
                        $connection.Close()
                        
                        if ($filePath) {
                            $success = Update-FileStatus -FileId $fileId -Dirty $data.dirty -DatabasePath $DatabasePath -CollectionId $collectionId
                            
                            if ($success) {
                                $Response.StatusCode = 200
                                $result = @{
                                    success = $true
                                    message = "File status updated successfully"
                                    file_id = $fileId
                                    dirty = $data.dirty
                                }
                            }
                            else {
                                $Response.StatusCode = 500 # Internal Server Error
                                $result = @{
                                    success = $false
                                    error = "Failed to update file status"
                                }
                            }
                        }
                        else {
                            $Response.StatusCode = 404 # Not Found
                            $result = @{
                                success = $false
                                error = "File not found in collection"
                            }
                        }
                    }
                    else {
                        $Response.StatusCode = 400 # Bad Request
                        $result = @{
                            success = $false
                            error = "Invalid request. Requires 'dirty' field."
                        }
                    }
                }
                else {
                    $Response.StatusCode = 405 # Method Not Allowed
                    $result = @{
                        success = $false
                        error = "Method not allowed. Use DELETE or PUT."
                    }
                }
                break
            }
            
            # Update collection files - scan for changes
            "^/collections/\d+/update$" {
                if ($Request.HttpMethod -eq "POST") {
                    # Get collection source folder
                    $collection = Get-Collection -Id $collectionId -DatabasePath $DatabasePath
                    
                    if (-not $collection -or -not $collection.source_folder) {
                        $Response.StatusCode = 400 # Bad Request
                        $result = @{
                            success = $false
                            error = "Collection source folder not defined"
                        }
                        break
                    }
                    
                    # Get custom omit folders from query string or body
                    $customOmitFolders = $OmitFolders
                    
                    # Check for body content with custom omit folders
                    if ($Request.HasEntityBody) {
                        $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                        $body = $reader.ReadToEnd()
                        if ($body) {
                            try {
                                $data = ConvertFrom-Json $body
                                if ($data.omitFolders -and $data.omitFolders.Count -gt 0) {
                                    $customOmitFolders = $data.omitFolders
                                }
                            }
                            catch {
                                # Just use default omit folders if JSON parsing fails
                                Write-Verbose "Error parsing request body: $_"
                            }
                        }
                    }
                    
                    # Run the update operation for the specific collection
                    $updateResult = Update-FileTracker -FolderPath $collection.source_folder -DatabasePath $DatabasePath -OmitFolders $customOmitFolders -CollectionId $collectionId
                    
                    if ($updateResult.success) {
                        $Response.StatusCode = 200
                        $result = @{
                            success = $true
                            message = "Collection files updated successfully"
                            summary = @{
                                newFiles = $updateResult.newFiles
                                modifiedFiles = $updateResult.modifiedFiles
                                unchangedFiles = $updateResult.unchangedFiles
                                removedFiles = $updateResult.removedFiles
                                filesToProcess = $updateResult.filesToProcess
                                filesToDelete = $updateResult.filesToDelete
                            }
                            collection_id = $collectionId
                            omittedFolders = $customOmitFolders
                        }
                    }
                    else {
                        $Response.StatusCode = 500 # Internal Server Error
                        $result = @{
                            success = $false
                            error = $updateResult.error
                        }
                    }
                }
                else {
                    $Response.StatusCode = 405 # Method Not Allowed
                    $result = @{
                        success = $false
                        error = "Method not allowed. Use POST."
                    }
                }
                break
            }
            
            # Get overall status (works for both legacy and collection mode)
            "^/status$" {
                if ($Request.HttpMethod -eq "GET") {
                    $statusScript = Join-Path $PSScriptRoot "Get-FileTrackerStatus.ps1"

                    $status = & $statusScript -InstallPath $InstallPath
                    $result = @{
                        success = $true
                        status = $status
                    }
                    
                    $Response.StatusCode = 200
                }
                else {
                    $Response.StatusCode = 405 # Method Not Allowed
                    $result = @{
                        success = $false
                        error = "Method not allowed. Use GET."
                    }
                }
                break
            }
            
            # Default case - endpoint not found
            default {
                $Response.StatusCode = 404 # Not Found
                $result = @{
                    success = $false
                    error = "Endpoint not found: $endpoint"
                    availableEndpoints = @(
                        # Collection endpoints
                        "$ApiPath/collections",
                        "$ApiPath/collections/{id}",
                        "$ApiPath/collections/{id}/settings",
                        "$ApiPath/collections/{id}/watch",
                        "$ApiPath/collections/{id}/files",
                        "$ApiPath/collections/{id}/files/{fileId}",
                        "$ApiPath/collections/{id}/update",
                        # Common endpoints
                        "$ApiPath/status"
                    )
                }
                break
            }
        }
        
        # Convert result to JSON and write to response
        $jsonResult = ConvertTo-Json $result -Depth 10
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResult)
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    }
    catch {
        # Handle any exceptions
        $Response.StatusCode = 500 # Internal Server Error
        $errorResult = @{
            success = $false
            error = $_.ToString()
        }
        
        $jsonError = ConvertTo-Json $errorResult
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonError)
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    }
    finally {
        # Close the response
        $Response.Close()
    }
}

# Set up cancellation token for graceful termination
$cancelSource = New-Object System.Threading.CancellationTokenSource
$cancelToken = $cancelSource.Token

# Handle CTRL+C
[Console]::TreatControlCAsInput = $false

# Start the HTTP listener
try {
    $listener.Start()
    Write-Log "FileTracker REST API server started at $prefix" -ForegroundColor Green
    Write-Log "Installation directory: $InstallationPath" -ForegroundColor Green
    Write-Log "Using database: $DatabasePath" -ForegroundColor Cyan
    Write-Log "Press Ctrl+C to stop the server" -ForegroundColor Yellow
    
    # Available endpoints
    Write-Log "=="
    Write-Log "Available API Endpoints:" 
    Write-Log "Collection Management:"
    Write-Log "  GET  $prefix/collections              - Get all collections" -ForegroundColor White
    Write-Log "  POST $prefix/collections              - Create a new collection" -ForegroundColor White
    Write-Log "    Payload: { 'name': 'Collection Name', 'description': 'Optional description', 'source_folder': 'Optional path' }" -ForegroundColor Gray
    Write-Log "  GET  $prefix/collections/{id}         - Get a specific collection" -ForegroundColor White
    Write-Log "  PUT  $prefix/collections/{id}         - Update a collection" -ForegroundColor White
    Write-Log "    Payload: { 'name': 'New Name', 'description': 'New description' }" -ForegroundColor Gray
    Write-Log "  DELETE $prefix/collections/{id}       - Delete a collection" -ForegroundColor White
    
    Write-Log "Collection Files Management:" -ForegroundColor White
    Write-Log "  GET  $prefix/collections/{id}/settings - Get collection settings and watch status" -ForegroundColor White
    Write-Log "  POST $prefix/collections/{id}/watch   - Start or stop live file watching" -ForegroundColor White
    Write-Log "    Payload: { 'action': 'start|stop', 'fileFilter': '*.*', 'watchCreated': true, 'watchModified': true, 'watchDeleted': true, 'watchRenamed': true, 'includeSubdirectories': true, 'processInterval': 15, 'omitFolders': ['folder1'] }" -ForegroundColor Gray
    Write-Log "  GET  $prefix/collections/{id}/files   - Get files in a collection" -ForegroundColor White
    Write-Log "  POST $prefix/collections/{id}/files   - Add a file to a collection" -ForegroundColor White
    Write-Log "    Payload: { 'filePath': 'path/to/file', 'originalUrl': 'http://source.com/file', 'dirty': true|false }" -ForegroundColor Gray
    Write-Log "  PUT  $prefix/collections/{id}/files   - Mark all files in collection as dirty/processed" -ForegroundColor White
    Write-Log "    Payload: { 'dirty': true|false }" -ForegroundColor Gray
    Write-Log "  DELETE $prefix/collections/{id}/files/{fileId} - Remove a file from a collection" -ForegroundColor White
    Write-Log "  PUT  $prefix/collections/{id}/files/{fileId} - Update a file's status" -ForegroundColor White
    Write-Log "    Payload: { 'dirty': true|false }" -ForegroundColor Gray
    Write-Log "  POST $prefix/collections/{id}/update  - Scan folder for changes and update collection" -ForegroundColor White
    Write-Log "    Payload (optional): { 'omitFolders': ['folder1', 'folder2'] }" -ForegroundColor Gray
    
    Write-Log "Common Endpoints:" -ForegroundColor White
    Write-Log "  GET  $prefix/status                   - Get overall tracking status" -ForegroundColor White
    Write-Log "=="
    
    # Handle incoming requests
    while ($listener.IsListening -and -not $cancelToken.IsCancellationRequested) {
        try
        {
            # Use GetContextAsync with a 1-second timeout to allow checking for cancellation
            $task = $listener.GetContextAsync()
            $context = $task.GetAwaiter().GetResult()
            Process-Request -Request $context.Request -Response $context.Response
        }
        catch [System.Threading.Tasks.TaskCanceledException] {
            # This is expected during cancellation
            continue
        }
        catch {
            if (-not $cancelToken.IsCancellationRequested) {
                Write-Error "Error processing request: $_"
            }
        }
    }
}
catch {
    if (-not $cancelToken.IsCancellationRequested) {
        Write-Error "Error in HTTP listener: $_`n$($_.ScriptStackTrace)"
    }
}
finally {
    # Clean up resources
    if ($listener.IsListening) {
        $listener.Stop()
        Write-Log "HTTP listener stopped." -ForegroundColor Green
    }
    
    # Dispose cancellation token source
    $cancelSource.Dispose()
    
    # Unsubscribe from event handler
    if ($handler) {
        $handler.Dispose()
    }
    
    Write-Log "FileTracker REST API server shutdown complete." -ForegroundColor Green
}
