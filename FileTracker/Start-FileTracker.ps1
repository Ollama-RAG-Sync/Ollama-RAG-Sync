param (
    [Parameter(Mandatory=$false)]
    [string]$ListenAddress = "localhost",
    
    [Parameter(Mandatory=$true)]
    [string]$InstallPath,
  
    [Parameter(Mandatory=$false)]
    [int]$Port = 10003,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiPath = "/api"
)

# Import Pode Module
Import-Module Pode -ErrorAction Stop

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
        [string]$ForegroundColor = "Green", # Default to Green for Pode logs
        
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
        Write-Host $logMessage -ForegroundColor $ForegroundColor # Use specified or default color
    }
    
    # Write to log file
    Add-Content -Path $logFilePath -Value $logMessage
}

# Compute DatabasePath from InstallationPath
$DatabasePath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"

# Import required modules
$fileTrackerSharedModulePath = Join-Path -Path $PSScriptRoot -ChildPath "FileTracker-Shared.psm1"
$databaseSharedModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Database-Shared.psm1"
Import-Module -Name $fileTrackerSharedModulePath -Force -Verbose
Import-Module -Name $databaseSharedModulePath -Force -Verbose

# Determine Database Path (using the imported function)
# $DatabasePath is already computed earlier in the script, just ensure it uses the function if needed
if (-not $DatabasePath) { # Check if it was already set by the initial logic
     $DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
}

# --- Start Pode Server ---
try {
    Write-Log "Starting FileTracker REST API server using Pode..."
    Write-Log "Installation directory: $InstallPath"
    Write-Log "Using database: $DatabasePath" # Log the determined/used path

    # Initialize SQLite Environment once before starting server (using the imported function)
    if (-not (Initialize-SqliteEnvironment -InstallPath $InstallPath)) {
         Write-Log "Failed to initialize SQLite environment. API cannot start." -Level "ERROR"
         exit 1
     }

    Start-PodeServer { 
        # Assign $using variables to local scope at the start of the server block
        $localInstallPath = $using:InstallPath
        $localDatabasePath = $using:DatabasePath
        
        # Pode logging setup
        New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging # Example, adjust as needed
        Add-PodeEndpoint -Address $ListenAddress -Port $Port -Protocol Http

        # --- API Routes ---

        Add-PodeRoute -Method Get -Path "/" -ScriptBlock {
            Write-PodeJsonResponse -Value @{
                status = "ok"
                message = "FileTracker API server running"
                routes = @(
                    "/api/health - GET: Health check",
                    "/api/collections - GET: Get collections list",
                    "/api/collections - POST: New collection",
                    "/api/collections/{id} - GET: Get collection by ID",
                    "/api/collections/{id} - PUT: Update collection by ID",
                    "/api/collections/{id} - DELETE: Delete collection by ID",
                    "/api/collections/{id}/settings - GET: Get collection settings",
                    "/api/collections/{id}/watch - POST: Start/stop watching collection",
                    "/api/collections/{id}/files - GET: Get files in collection",
                    "/api/collections/{id}/files - POST: Add file to collection",
                    "/api/collections/{id}/files - PUT: Update file status in collection",
                    "/api/collections/{id}/files/{fileId} - DELETE: Remove file from collection",
                    "/api/collections/{id}/files/{fileId} - PUT: Update file status in collection",
                    "/api/collections/{id}/update - POST: Update collection files"
                )
            }
        } 

        # GET /api/collections
        Add-PodeRoute -Method Get -Path "$ApiPath/collections" -ScriptBlock {
            try {
                # Use local variables
                $collectionsResult = Get-Collections -DatabasePath $localDatabasePath -InstallPath $localInstallPath 
                $result = @{
                    success = $true
                    collections = $collectionsResult
                    count = $collectionsResult.Count
                }
                Write-PodeJsonResponse -Value $result
            } catch {
                Write-Log "Error in GET /collections: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }   

        # POST /api/collections
        Add-PodeRoute -Method Post -Path "$ApiPath/collections" -ScriptBlock {
            try {
                $data = $WebEvent.Data
                if ($data.name -and $data.sourceFolder) { # Ensure sourceFolder is also provided
                    # Pass InstallPath and DatabasePath
                    # Use local variables
                    $newCollectionParams = @{
                        Name = $data.name
                        SourceFolder = $data.sourceFolder
                        InstallPath = $localInstallPath
                        DatabasePath = $localDatabasePath # Pass the determined path
                    }
                    if ($data.PSObject.Properties.Name -contains 'description') { $newCollectionParams.Description = $data.description }
                    if ($data.PSObject.Properties.Name -contains 'includeExtensions') { $newCollectionParams.IncludeExtensions = $data.includeExtensions } # Assuming comma-separated string
                    if ($data.PSObject.Properties.Name -contains 'excludeFolders') { $newCollectionParams.ExcludeFolders = $data.excludeFolders } # Assuming comma-separated string

                    $newCollection = New-Collection @newCollectionParams
                    
                    if ($newCollection) {
                        Set-PodeResponseStatus -Code 201 # Created
                        $result = @{
                            success = $true
                            message = "Collection created successfully"
                            collection = $newCollection
                        }
                    } else {
                        Set-PodeResponseStatus -Code 500 # Internal Server Error
                        $result = @{ success = $false; error = "Failed to create collection" }
                    }
                } else {
                    Set-PodeResponseStatus -Code 400 # Bad Request
                    $result = @{ success = $false; error = "Invalid request. Requires 'name' field." }
                }
                Write-PodeJsonResponse -Value $result
            } catch {
                Write-Log "Error in POST /collections: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }  

        # GET /api/collections/{id}
        Add-PodeRoute -Method Get -Path "$ApiPath/collections/:collectionId" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                # Use local variables
                $collection = Get-Collection -Id $collectionId -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                
                if ($collection) {
                    $result = @{ success = $true; collection = $collection }
                } else {
                    Set-PodeResponseStatus -Code 404 # Not Found
                    $result = @{ success = $false; error = "Collection not found" }
                }
                Write-PodeJsonResponse -Value $result
            } catch {
                Write-Log "Error in GET /collections/$($WebEvent.Parameters['collectionId']): $_" -Level "ERROR"
                Set-PodeResponseStatus -Code 500
                Write-PodeJsonResponse -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }  

        # PUT /api/collections/{id}
        Add-PodeRoute -Method Put -Path "$ApiPath/collections/:collectionId" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                $data = $WebEvent.Data
                # Pass InstallPath
                # Use local variables
                $updateParams = @{
                    Id = $collectionId
                    DatabasePath = $localDatabasePath
                    InstallPath = $localInstallPath # Pass InstallPath
                }
                
                # Check explicitly if properties exist before adding
                if ($data.PSObject.Properties.Contains('name')) { $updateParams.Name = $data.name }
                if ($data.PSObject.Properties.Contains('description')) { $updateParams.Description = $data.description }
                if ($data.PSObject.Properties.Contains('sourceFolder')) { $updateParams.SourceFolder = $data.sourceFolder }
                if ($data.PSObject.Properties.Contains('includeExtensions')) { $updateParams.IncludeExtensions = $data.includeExtensions }
                if ($data.PSObject.Properties.Contains('excludeFolders')) { $updateParams.ExcludeFolders = $data.excludeFolders }
                
                $success = Update-Collection @updateParams
                
                if ($success) {
                    # Use local variables
                    $updatedCollection = Get-Collection -Id $collectionId -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                    $result = @{ success = $true; message = "Collection updated successfully"; collection = $updatedCollection }
                } else {
                    Set-PodeResponseStatus -Code 500 # Internal Server Error
                    $result = @{ success = $false; error = "Failed to update collection" }
                }
                Write-PodeJsonResponse -Value $result
            } catch {
                Write-Log "Error in PUT /collections/$($WebEvent.Parameters['collectionId']): $_" -Level "ERROR"
                Set-PodeResponseStatus -Code 500
                Write-PodeJsonResponse -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }   

        # DELETE /api/collections/{id}
        Add-PodeRoute -Method Delete -Path "$ApiPath/collections/:collectionId" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                # Use local variables
                $success = Remove-Collection -Id $collectionId -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                
                if ($success) {
                    $result = @{ success = $true; message = "Collection deleted successfully" }
                } else {
                    Set-PodeResponseStatus -Code 500 # Internal Server Error
                    $result = @{ success = $false; error = "Failed to delete collection" }
                }
                Write-PodeJsonResponse -Value $result
            } catch {
                Write-Log "Error in DELETE /collections/$($WebEvent.Parameters['collectionId']): $_" -Level "ERROR"
                Set-PodeResponseStatus -Code 500
                Write-PodeJsonResponse -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }

        # GET /api/collections/{id}/settings
        Add-PodeRoute -Method Get -Path "$ApiPath/collections/:collectionId/settings" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                # Use local variables
                $collection = Get-Collection -Id $collectionId -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                
                if ($collection) {
                    # Get watch settings using the helper function (if moved to shared module) or direct DB access
                    # Assuming direct DB access for now, needs InstallPath for connection
                    $watchSettings = $null
                    try {
                         # Use local variables
                         $conn = Get-DatabaseConnection -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                         $cmd = $conn.CreateCommand()
                         $cmd.CommandText = "SELECT value FROM settings WHERE key = @Key"
                         $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Key", "collection_${collectionId}_watch")))
                         $settingsJson = $cmd.ExecuteScalar()
                         if ($settingsJson) { $watchSettings = ConvertFrom-Json $settingsJson }
                         $conn.Close()
                    } catch { Write-Log "Could not read watch settings for collection $collectionId: $_" -Level "WARNING" }

                    $watchStatus = $false
                    $watchJob = Get-Job -Name "Watch_Collection_$collectionId" -ErrorAction SilentlyContinue
                    if ($watchJob) { $watchStatus = $true }
                    
                    $result = @{
                        success = $true
                        collection = $collection
                        settings = @{ isWatching = $watchStatus; watchJobId = if ($watchStatus) { $watchJob.Id } else { $null } }
                    }
                } else {
                    Set-PodeResponseStatus -Code 404 # Not Found
                    $result = @{ success = $false; error = "Collection not found" }
                }
                Write-PodeJsonResponse -Value $result
            } catch {
                Write-Log "Error in GET /collections/$($WebEvent.Parameters['collectionId'])/settings: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }  

        # POST /api/collections/{id}/watch
        Add-PodeRoute -Method Post -Path "$ApiPath/collections/:collectionId/watch" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                $data = $WebEvent.Data
                $action = $data.action
                # Use local variables
                $collection = Get-Collection -Id $collectionId -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                if (-not $collection) {
                    Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return
                }
                
                # Use Start-CollectionWatch script for consistency? Or replicate logic here?
                # Replicating logic for now, but using Start-CollectionWatch might be better
                if ($action -eq "start") {
                    $watchJob = Get-Job -Name "Watch_Collection_$collectionId" -ErrorAction SilentlyContinue
                    if ($watchJob) {
                        Set-PodeResponseStatus -Code 409; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection is already being watched"; job_id = $watchJob.Id }; return
                    }
                    # Save settings first (requires InstallPath for DB connection)
                    $watchSettingsToSave = @{
                        enabled = $true
                        watchCreated = [bool]($data.watchCreated ?? $false)
                        watchModified = [bool]($data.watchModified ?? $false)
                        watchDeleted = [bool]($data.watchDeleted ?? $false)
                        watchRenamed = [bool]($data.watchRenamed ?? $false)
                        includeSubdirectories = [bool]($data.includeSubdirectories ?? $false)
                        watchInterval = [int]($data.processInterval ?? 15)
                        omitFolders = $data.omitFolders ?? @()
                    }
                    # Need a Save-WatchSettings function or direct DB access here
                    # Assuming direct DB access for now
                    try {
                         # Use local variables
                         $conn = Get-DatabaseConnection -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                         $cmd = $conn.CreateCommand()
                         $cmd.CommandText = "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (@Key, @Value, @UpdatedAt)"
                         $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Key", "collection_${collectionId}_watch")))
                         $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Value", (ConvertTo-Json $watchSettingsToSave -Compress))))
                         $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", [DateTime]::UtcNow.ToString("o"))))
                         $cmd.ExecuteNonQuery()
                         $conn.Close()
                         Write-Log "Saved watch settings for collection $collectionId"
                    } catch { Write-Log "Failed to save watch settings for collection $collectionId: $_" -Level "ERROR"; throw }


                    # Prepare params for Start-Job -> Watch-FileTracker.ps1
                    # Use local variables
                    $watchParams = @{
                        DirectoryToWatch = $collection.source_folder
                        ProcessInterval = $watchSettingsToSave.watchInterval
                        InstallPath = $localInstallPath # Pass InstallPath
                        CollectionId = $collectionId # Pass CollectionId
                    }
                    if ($data.fileFilter) { $watchParams["FileFilter"] = $data.fileFilter } # Use provided filter or default in script
                    if ($watchSettingsToSave.watchCreated) { $watchParams["WatchCreated"] = $true }
                    if ($watchSettingsToSave.watchModified) { $watchParams["WatchModified"] = $true }
                    if ($watchSettingsToSave.watchDeleted) { $watchParams["WatchDeleted"] = $true }
                    if ($watchSettingsToSave.watchRenamed) { $watchParams["WatchRenamed"] = $true }
                    if ($watchSettingsToSave.includeSubdirectories) { $watchParams["IncludeSubdirectories"] = $true }
                    if ($watchSettingsToSave.omitFolders) { $watchParams["OmitFolders"] = $watchSettingsToSave.omitFolders } # Pass the array

                    $watchScriptPath = Join-Path $PSScriptRoot "Watch-FileTracker.ps1"
                    $job = Start-Job -Name "Watch_Collection_$collectionId" -ScriptBlock {
                        param($scriptPath, $params)
                        # Ensure modules are available if needed by the script directly
                        # Import-Module -Name $using:databaseSharedModulePath -Force
                        # Import-Module -Name $using:fileTrackerSharedModulePath -Force
                        & $scriptPath @params
                    } -ArgumentList $watchScriptPath, $watchParams
                    
                    $result = @{ success = $true; message = "File watching started"; collection_id = $collectionId; job_id = $job.Id; parameters = $watchParams }
                    
                } elseif ($action -eq "stop") {
                    # Stop the job
                    $watchJob = Get-Job -Name "Watch_Collection_$collectionId" -ErrorAction SilentlyContinue
                    if ($watchJob) {
                        Stop-Job -Id $watchJob.Id; Remove-Job -Id $watchJob.Id
                        Write-Log "Stopped watch job for collection $collectionId"
                        # Update settings in DB to disabled
                         try {
                             # Use local variables
                             $conn = Get-DatabaseConnection -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                             $cmd = $conn.CreateCommand()
                             # Get current settings first to preserve other values
                             $cmd.CommandText = "SELECT value FROM settings WHERE key = @Key"
                             $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Key", "collection_${collectionId}_watch")))
                             $settingsJson = $cmd.ExecuteScalar()
                             $currentSettings = if ($settingsJson) { ConvertFrom-Json $settingsJson } else { @{} }
                             $currentSettings.enabled = $false # Set to disabled
                             
                             $cmd.CommandText = "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (@Key, @Value, @UpdatedAt)"
                             $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Value", (ConvertTo-Json $currentSettings -Compress))))
                             $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", [DateTime]::UtcNow.ToString("o"))))
                             $cmd.ExecuteNonQuery()
                             $conn.Close()
                             Write-Log "Updated watch settings to disabled for collection $collectionId"
                        } catch { Write-Log "Failed to update watch settings to disabled for collection $collectionId: $_" -Level "ERROR" }

                        $result = @{ success = $true; message = "File watching stopped"; collection_id = $collectionId }
                    } else {
                         Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection is not being watched" }; return
                    }
                } else {
                    Set-PodeResponseStatus -Code 400; Write-PodeJsonResponse -Value @{ success = $false; error = "Invalid action. Use 'start' or 'stop'." }; return
                }
                Write-PodeJsonResponse -Value $result
                
            } catch {
                Write-Log "Error in POST /collections/$($WebEvent.Parameters['collectionId'])/watch: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }  

        # GET /api/collections/{id}/files
        Add-PodeRoute -Method Get -Path "$ApiPath/collections/:collectionId/files" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                $dirty = $false
                $processed = $false
                $deleted = $false

                if ($null -ne $WebEvent.Query) {
                    $dirtyRaw = $WebEvent.Query["dirty"]
                    $dirty = ($null -ne $dirtyRaw) -and ($dirtyRaw -eq "true")
                    $processedRaw = $WebEvent.Query["processed"]
                    $processed = ($null -ne $processedRaw) -and ($processedRaw -eq "true")
                    $deletedRaw = $WebEvent.Query["deleted"]
                    $deleted = ($null -ne $deletedRaw) -and ($deletedRaw -eq "true")
                }
                
                # Use local variables
                $params = @{ 
                    CollectionId = $collectionId 
                    DatabasePath = $localDatabasePath 
                    InstallPath = $localInstallPath # Pass InstallPath
                }
                # Add switches based on query params
                if ($dirty) { $params.DirtyOnly = $true }
                if ($processed) { $params.ProcessedOnly = $true }
                if ($deleted) { $params.DeletedOnly = $true }
                
                # If no specific filter is set, maybe default to DirtyOnly? Or return all non-deleted?
                # Current Get-CollectionFiles returns all non-deleted if no flags set. Let's keep that.
                
                $files = Get-CollectionFiles @params
                $result = @{ success = $true; files = $files; count = $files.Count; collection_id = $collectionId }
                Write-PodeJsonResponse -Value $result
                
            } catch {
                Write-Log "Error in GET /collections/$($WebEvent.Parameters['collectionId'])/files: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.ScriptStackTrace)" }
            }
        }  

        # POST /api/collections/{id}/files
        Add-PodeRoute -Method Post -Path "$ApiPath/collections/:collectionId/files" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                $data = $WebEvent.Data
                
                if ($data.filePath) {
                    # Use local variables
                    $params = @{ 
                        CollectionId = $collectionId 
                        FilePath = $data.filePath 
                        DatabasePath = $localDatabasePath 
                        InstallPath = $localInstallPath # Pass InstallPath
                    }
                    if ($data.PSObject.Properties.Contains('originalUrl')) { $params.OriginalUrl = $data.originalUrl }
                    if ($data.PSObject.Properties.Contains('dirty')) { $params.Dirty = [bool]$data.dirty } # Default is true in function
                    
                    $addResult = Add-FileToCollection @params
                    
                    if ($addResult) {
                        $result = @{ success = $true; message = if ($addResult.updated) { "File updated" } else { "File added" }; file = $addResult }
                    } else {
                        Set-PodeResponseStatus -Code 500; $result = @{ success = $false; error = "Failed to add/update file" }
                    }
                } else {
                    Set-PodeResponseStatus -Code 400; $result = @{ success = $false; error = "Invalid request. Requires 'filePath' field." }
                }
                Write-PodeJsonResponse -Value $result
                
            } catch {
                Write-Log "Error in POST /collections/$($WebEvent.Parameters['collectionId'])/files: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }  

        # PUT /api/collections/{id}/files (Update status for ALL files in collection)
        Add-PodeRoute -Method Put -Path "$ApiPath/collections/:collectionId/files" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                $data = $WebEvent.Data
                
                if ($null -ne $data.dirty) {
                    # Call the shared function now
                    # Ensure FileTracker-Shared.psm1 is imported earlier in the script
                    # Use local variables
                    $success = Update-FileProcessingStatus -All -CollectionId $collectionId -Dirty $data.dirty -InstallPath $localInstallPath # DatabasePath determined by function
                    if ($success) {
                        $result = @{ success = $true; message = "All files in collection $collectionId status updated"; dirty = $data.dirty }
                    } else {
                        Set-PodeResponseStatus -Code 500; $result = @{ success = $false; error = "Failed to update files" }
                    }
                } else {
                    Set-PodeResponseStatus -Code 400; $result = @{ success = $false; error = "Invalid request. Requires 'dirty' field." }
                }
                Write-PodeJsonResponse -Value $result
                
            } catch {
                Write-Log "Error in PUT /collections/$($WebEvent.Parameters['collectionId'])/files: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }   

        # DELETE /api/collections/{id}/files/{fileId}
        Add-PodeRoute -Method Delete -Path "$ApiPath/collections/:collectionId/files/:fileId" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId'] # Get collection ID for context/logging
                $fileId = [int]$WebEvent.Parameters['fileId']
                # Use local variables
                $success = Remove-FileFromCollection -FileId $fileId -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                
                if ($success) {
                    $result = @{ success = $true; message = "File (ID: $fileId) removed from collection (ID: $collectionId)" }
                } else {
                    Set-PodeResponseStatus -Code 500; $result = @{ success = $false; error = "Failed to remove file" }
                }
                Write-PodeJsonResponse -Value $result
                
            } catch {
                Write-Log "Error in DELETE /collections/.../files/$($WebEvent.Parameters['fileId']): $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }  

        # PUT /api/collections/{id}/files/{fileId}
        Add-PodeRoute -Method Put -Path "$ApiPath/collections/:collectionId/files/:fileId" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                $fileId = [int]$WebEvent.Parameters['fileId']
                $fileId = [int]$WebEvent.Parameters['fileId']
                $data = $WebEvent.Data
                
                if ($null -ne $data.dirty) {
                    # 1. Get the FilePath from the database using FileId and CollectionId
                    $filePathToUpdate = $null
                    $fileFound = $false
                    try {
                        # Use local variables
                        $conn = Get-DatabaseConnection -DatabasePath $localDatabasePath -InstallPath $localInstallPath
                        $cmd = $conn.CreateCommand()
                        $cmd.CommandText = "SELECT FilePath FROM files WHERE id = @FileId AND collection_id = @CollectionId"
                        $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FileId", $fileId)))
                        $cmd.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
                        $filePathToUpdate = $cmd.ExecuteScalar()
                        $conn.Close()
                        $fileFound = ($null -ne $filePathToUpdate)
                    } catch {
                        Write-Log "Error fetching file path for ID $fileId in collection $collectionId: $_" -Level "ERROR"
                        Set-PodeResponseStatus -Code 500; Write-PodeJsonResponse -Value @{ success = $false; error = "Internal server error checking file existence" }; return
                    }

                    if (-not $fileFound) {
                        Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "File with ID $fileId not found in collection $collectionId" }; return
                    }

                    # 2. Call Update-FileProcessingStatus using the SingleFile parameter set with the retrieved FilePath
                    # Use local variables
                    $success = Update-FileProcessingStatus -FilePath $filePathToUpdate -Dirty $data.dirty -InstallPath $localInstallPath -DatabasePath $localDatabasePath # Use SingleFile set implicitly
                    
                    if ($success) {
                        $result = @{ success = $true; message = "File status updated"; file_id = $fileId; file_path = $filePathToUpdate; collection_id = $collectionId; dirty = $data.dirty }
                    } else {
                         # The shared function writes specific errors
                         Set-PodeResponseStatus -Code 500 
                         $result = @{ success = $false; error = "Failed to update file status for '$filePathToUpdate' (check server logs)" }
                    }
                } else {
                    Set-PodeResponseStatus -Code 400; $result = @{ success = $false; error = "Invalid request. Requires 'dirty' field." }
                }
                Write-PodeJsonResponse -Value $result
                
            } catch {
                Write-Log "Error in PUT /collections/.../files/$($WebEvent.Parameters['fileId']): $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }  

        # GET /health
        Add-PodeRoute -Method Get -Path "/health" -ScriptBlock {
            Write-PodeJsonResponse -Value @{ status = "OK" } -StatusCode 200
        }
        # GET /api/status
        Add-PodeRoute -Method Get -Path "$ApiPath/status" -ScriptBlock {
            try {
                # Call the function directly (it's imported)
                # Use local variable
                $status = Get-FileTrackerStatus -InstallPath $localInstallPath # Function is imported
                $result = @{ success = $true; status = $status }
                Write-PodeJsonResponse -Value $result
            } catch {
                Write-Log "Error in GET /status: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" } # Corrected --StatusCode
            }
        }
    }

    Write-Log "FileTracker REST API server running at http://localhost:$Port"
    Write-Log "Swagger UI available at http://localhost:$Port/swagger"
    Write-Log "Press Ctrl+C to stop the server."

} catch {
    Write-Log "Fatal error starting Pode server: $_" -Level "ERROR"
    Write-Log "$($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}
