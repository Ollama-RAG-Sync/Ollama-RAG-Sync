param (
    [Parameter(Mandatory=$false)]
    [string]$ListenAddress = "localhost",
    
    [Parameter(Mandatory=$true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory=$false)]
    [string[]]$OmitFolders = @('.git', 'node_modules', 'bin', 'obj'),
    
    [Parameter(Mandatory=$true)]
    [int]$Port,
    
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
Import-Module -Name "$PSScriptRoot\FileTracker-Shared.psm1" -Force -Verbose
Import-Module -Name "$PSScriptRoot\Database-Shared.psm1" -Force -Verbose

$sqliteAssemblyPath = "$InstallPath\Microsoft.Data.Sqlite.dll"
$sqliteAssemblyPath2 = "$InstallPath\SQLitePCLRaw.core.dll"
$sqliteAssemblyPath3 = "$InstallPath\SQLitePCLRaw.provider.e_sqlite3.dll"

# Load SQLite assembly
try {
    Add-Type -Path $sqliteAssemblyPath
    Add-Type -Path $sqliteAssemblyPath2
    Add-Type -Path $sqliteAssemblyPath3
} catch {
    Write-Log "Error loading SQLite assemblies: $_" -Level "ERROR"
    Write-Log "Please ensure required DLLs are in $InstallPath" -Level "ERROR"
    exit 1
}

# --- Start Pode Server ---
try {
    Write-Log "Starting FileTracker REST API server using Pode..."
    Write-Log "Installation directory: $InstallPath"
    Write-Log "Using database: $DatabasePath"

    Start-PodeServer { # Assuming Start-PodeServer still needs to be called to run the server block
        New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging
        Add-PodeEndpoint -Address $ListenAddress -Port $Port -Protocol Http

        # --- API Routes ---
        # GET /api/collections
        Add-PodeRoute -Method Get -Path "$ApiPath/collections" -ScriptBlock {
            try {
                $collectionsResult = Get-Collections -DatabasePath $using:DatabasePath
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
                if ($data.name) {
                    $newCollection = New-Collection -Name $data.name -Description $data.description -SourceFolder $data.sourceFolder -InstallPath $using:InstallPath
                    
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
                $collection = Get-Collection -Id $collectionId -DatabasePath $using:DatabasePath
                
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
                
                $updateParams = @{
                    Id = $collectionId
                    DatabasePath = $using:DatabasePath
                }
                
                if ($data.PSObject.Properties.Name -contains 'name') { $updateParams["Name"] = $data.name }
                if ($data.PSObject.Properties.Name -contains 'description') { $updateParams["Description"] = $data.description }
                
                $success = Update-Collection @updateParams
                
                if ($success) {
                    $updatedCollection = Get-Collection -Id $collectionId -DatabasePath $using:DatabasePath
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
                $success = Remove-Collection -Id $collectionId -DatabasePath $using:DatabasePath
                
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
                $collection = Get-Collection -Id $collectionId -DatabasePath $using:DatabasePath
                
                if ($collection) {
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
                
                $collection = Get-Collection -Id $collectionId -DatabasePath $using:DatabasePath
                if (-not $collection) {
                    Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection not found" }; return
                }
                
                if ($action -eq "start") {
                    $watchJob = Get-Job -Name "Watch_Collection_$collectionId" -ErrorAction SilentlyContinue
                    if ($watchJob) {
                        Set-PodeResponseStatus -Code 409; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection is already being watched"; job_id = $watchJob.Id }; return
                    }
                    
                    $watchParams = @{
                        DirectoryToWatch = $collection.source_folder
                        ProcessInterval = $data.processInterval ?? 15
                        DatabasePath = $using:DatabasePath
                        CollectionId = $collectionId
                    }
                    if ($data.fileFilter) { $watchParams["FileFilter"] = $data.fileFilter }
                    if ($data.watchCreated -eq $true) { $watchParams["WatchCreated"] = $true }
                    if ($data.watchModified -eq $true) { $watchParams["WatchModified"] = $true }
                    if ($data.watchDeleted -eq $true) { $watchParams["WatchDeleted"] = $true }
                    if ($data.watchRenamed -eq $true) { $watchParams["WatchRenamed"] = $true }
                    if ($data.includeSubdirectories -eq $true) { $watchParams["IncludeSubdirectories"] = $true }
                    $watchParams["OmitFolders"] = if ($data.omitFolders -and $data.omitFolders.Count -gt 0) { $data.omitFolders } else { $using:OmitFolders }
                    
                    $watchScriptPath = Join-Path $PSScriptRoot "Watch-FileTracker.ps1"
                    $job = Start-Job -Name "Watch_Collection_$collectionId" -ScriptBlock {
                        param($scriptPath, $params)
                        & $scriptPath @params
                    } -ArgumentList $watchScriptPath, $watchParams
                    
                    $result = @{ success = $true; message = "File watching started"; collection_id = $collectionId; job_id = $job.Id; parameters = $watchParams }
                    
                } elseif ($action -eq "stop") {
                    $watchJob = Get-Job -Name "Watch_Collection_$collectionId" -ErrorAction SilentlyContinue
                    if (-not $watchJob) {
                        Set-PodeResponseStatus -Code 404; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection is not being watched" }; return
                    }
                    Stop-Job -Id $watchJob.Id; Remove-Job -Id $watchJob.Id
                    $result = @{ success = $true; message = "File watching stopped"; collection_id = $collectionId }
                    
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
                
                $params = @{ CollectionId = $collectionId; DatabasePath = $using:DatabasePath }
                $params["DirtyOnly"] = $dirty
                $params["ProcessedOnly"] = $processed
                $params["DeletedOnly"] = $deleted
                
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
                    $params = @{ CollectionId = $collectionId; FilePath = $data.filePath; DatabasePath = $using:DatabasePath }
                    if ($data.originalUrl) { $params["OriginalUrl"] = $data.originalUrl }
                    if ($null -ne $data.dirty) { $params["Dirty"] = $data.dirty }
                    
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

        # PUT /api/collections/{id}/files
        Add-PodeRoute -Method Put -Path "$ApiPath/collections/:collectionId/files" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                $data = $WebEvent.Data
                
                if ($null -ne $data.dirty) {
                    $success = Update-AllFilesStatus -Dirty $data.dirty -DatabasePath $using:DatabasePath -CollectionId $collectionId
                    if ($success) {
                        $result = @{ success = $true; message = "All files updated"; dirty = $data.dirty }
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
                # $collectionId = [int]$WebEvent.Parameters['collectionId'] # Not needed for Remove-FileFromCollection
                $fileId = [int]$WebEvent.Parameters['fileId']
                $success = Remove-FileFromCollection -FileId $fileId -DatabasePath $using:DatabasePath
                
                if ($success) {
                    $result = @{ success = $true; message = "File removed from collection" }
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
                $data = $WebEvent.Data
                
                if ($null -ne $data.dirty) {
                    # Update-FileStatus.ps1 is not directly available, call the function from the imported module
                    $success = Update-FileStatus -FileId $fileId -Dirty $data.dirty -DatabasePath $using:DatabasePath -CollectionId $collectionId
                    
                    if ($success) {
                        $result = @{ success = $true; message = "File status updated"; file_id = $fileId; dirty = $data.dirty }
                    } else {
                        # Check if file exists before declaring internal error
                        $connection = Get-DatabaseConnection -DatabasePath $using:DatabasePath
                        $command = $connection.CreateCommand()
                        $command.CommandText = "SELECT 1 FROM files WHERE id = @FileId AND collection_id = @CollectionId"
                        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FileId", $fileId)))
                        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $collectionId)))
                        $fileExists = $command.ExecuteScalar()
                        $connection.Close()

                        if ($fileExists) {
                             Set-PodeResponseStatus -Code 500; $result = @{ success = $false; error = "Failed to update file status" }
                        } else {
                             Set-PodeResponseStatus -Code 404; $result = @{ success = $false; error = "File not found in collection" }
                        }
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

        # POST /api/collections/{id}/update
        Add-PodeRoute -Method Post -Path "$ApiPath/collections/:collectionId/update" -ScriptBlock {
            try {
                $collectionId = [int]$WebEvent.Parameters['collectionId']
                $collection = Get-Collection -Id $collectionId -DatabasePath $using:DatabasePath
                
                if (-not $collection -or -not $collection.source_folder) {
                    Set-PodeResponseStatus -Code 400; Write-PodeJsonResponse -Value @{ success = $false; error = "Collection source folder not defined" }; return
                }
                
                $customOmitFolders = $using:OmitFolders
                if ($WebEvent.Data -and $WebEvent.Data.omitFolders -and $WebEvent.Data.omitFolders.Count -gt 0) {
                    $customOmitFolders = $WebEvent.Data.omitFolders
                }
                
                $updateResult = Update-FileTracker -FolderPath $collection.source_folder -DatabasePath $using:DatabasePath -OmitFolders $customOmitFolders -CollectionId $collectionId
                
                if ($updateResult.success) {
                    $result = @{
                        success = $true; message = "Collection files updated successfully"
                        summary = @{
                            newFiles = $updateResult.newFiles; modifiedFiles = $updateResult.modifiedFiles
                            unchangedFiles = $updateResult.unchangedFiles; removedFiles = $updateResult.removedFiles
                            filesToProcess = $updateResult.filesToProcess; filesToDelete = $updateResult.filesToDelete
                        }
                        collection_id = $collectionId; omittedFolders = $customOmitFolders
                    }
                } else {
                    Set-PodeResponseStatus -Code 500; $result = @{ success = $false; error = $updateResult.error }
                }
                Write-PodeJsonResponse -Value $result
                
            } catch {
                Write-Log "Error in POST /collections/$($WebEvent.Parameters['collectionId'])/update: $_" -Level "ERROR"
                Write-PodeJsonResponse -StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }  

        # GET /health
        Add-PodeRoute -Method Get -Path "/health" -ScriptBlock {
            Write-PodeJsonResponse -Value @{ status = "OK" } -StatusCode 200
        }
        # GET /api/status
        Add-PodeRoute -Method GET -Path "$ApiPath/status" -ScriptBlock {
            try {
                # Get-FileTrackerStatus.ps1 is not directly available, call the function from the imported module
                $status = .\Get-FileTrackerStatus.ps1 -InstallPath  $using:InstallPath
                $result = @{ success = $true; status = $status }
                Write-PodeJsonResponse -Value $result
            } catch {
                Write-Log "Error in GET /status: $_" -Level "ERROR"
                Write-PodeJsonResponse --StatusCode 500 -Value @{ success = $false; error = "Internal Server Error: $($_.Exception.Message)" }
            }
        }

 
        # Default route for 404
        #Add-PodeRoute -Method * -Path * -ScriptBlock {
        #    Write-PodeJsonResponse -Value @{ error = "Not found" } -StatusCode 404
        #}
    }

    Write-Log "FileTracker REST API server running at http://localhost:$Port"
    Write-Log "Swagger UI available at http://localhost:$Port/swagger"
    Write-Log "Press Ctrl+C to stop the server."

} catch {
    Write-Log "Fatal error starting Pode server: $_" -Level "ERROR"
    Write-Log "$($_.ScriptStackTrace)" -Level "ERROR"
    exit 1
}
