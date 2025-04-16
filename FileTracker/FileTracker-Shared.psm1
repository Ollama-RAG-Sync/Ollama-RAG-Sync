function Update-FileProcessingStatus {
    <#
    .SYNOPSIS
        Updates a file's processing status in the SQLite database.
    .DESCRIPTION
        This function updates a file's status in the SQLite database by setting its "Dirty" flag.
    .PARAMETER FilePath
        The full path of the file to update (used in SingleFile mode).
    .PARAMETER InstallPath
        The installation path containing the database and assemblies.
    .PARAMETER DatabasePath
        Optional path to the SQLite database file. If not provided, it's derived from InstallPath.
    .PARAMETER All
        If specified, updates all files in the specified CollectionId.
    .PARAMETER CollectionId
        The ID of the collection to update when using -All. Mandatory for AllFiles set.
    .PARAMETER Dirty
        Boolean value indicating whether to mark the file(s) as dirty/to process (true) or as processed (false).
    #>
    [CmdletBinding(DefaultParameterSetName = "SingleFile")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "SingleFile")]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,

        [Parameter(Mandatory = $false)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true, ParameterSetName = "AllFiles")]
        [switch]$All,

        [Parameter(Mandatory = $true, ParameterSetName = "AllFiles")]
        [int]$CollectionId,
        
        [Parameter(Mandatory = $true)]
        [bool]$Dirty
    )
    
    # Import the shared database module - needed for DB functions
    Import-Module "Database-Shared.psm1" -Force

    # Determine new and old status values
    $newStatus = [int]$Dirty
    $oldStatus = [int](-not $Dirty) # The status we are changing FROM
    $actionText = if ($Dirty) { "as dirty (to process)" } else { "as processed" }
    
    # Determine Database Path
    if (-not $DatabasePath) {
        $DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
        Write-Verbose "Using determined database path: $DatabasePath"
    } else {
         Write-Verbose "Using provided database path: $DatabasePath"
    }

    # Ensure database exists (Initialization should happen elsewhere)
    if (-not (Test-Path -Path $DatabasePath)) {
        Write-Error "Database not found at $DatabasePath. Please initialize it first."
        return $false
    }

    try {
        # Get connection (this also initializes SQLite environment if needed)
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath -InstallPath $InstallPath
        
        # Begin transaction for better performance
        $transaction = $connection.BeginTransaction()
        
        if ($PSCmdlet.ParameterSetName -eq "SingleFile") {
            # Check if the file exists in the database (Note: FilePath might not be unique across collections)
            # This function might need CollectionId even for single file if uniqueness isn't guaranteed by FilePath alone.
            # Assuming FilePath IS unique for now, but this is a potential issue.
            $checkCommand = $connection.CreateCommand()
            $checkCommand.CommandText = "SELECT id, Dirty, Deleted, collection_id FROM files WHERE FilePath = @FilePath" # Also get collection_id
            $null = $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
            $checkCommand.Transaction = $transaction # Assign transaction
            
            $reader = $checkCommand.ExecuteReader()
            
            if (-not $reader.Read()) {
                $reader.Close()
                Write-Error "File not found in the database: $FilePath"
                return $false
            }
            $fileId = $reader.GetInt32(0)
            $currentStatus = $reader.GetInt32(1)
            $isDeleted = $reader.GetBoolean(2)
            $fileCollectionId = $reader.GetInt32(3)
            $null = $reader.Close()
            
            # If file is marked for deletion, report this
            if ($isDeleted) {
                Write-Host "Warning: File (ID: $fileId, Collection: $fileCollectionId) is marked as deleted: $FilePath" -ForegroundColor Yellow
            }
            
            # Check if the file already has the target status
            if ($currentStatus -eq $newStatus) {
                $statusText = if ($Dirty) { "already marked as dirty (to process)" } else { "already marked as processed" }
                Write-Host "File is $statusText`: $FilePath" -ForegroundColor Yellow
                return $true
            }
            # Update the file status using FileId for uniqueness
            $updateCommand = $connection.CreateCommand()
            $updateCommand.CommandText = "UPDATE files SET Dirty = @NewStatus WHERE id = @FileId" # Use ID now
            $null = $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FileId", $fileId))) # Use ID
            $null = $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@NewStatus", $newStatus)))
            $updateCommand.Transaction = $transaction # Assign transaction
            $null = $updateCommand.ExecuteNonQuery()
            
            Write-Host "File (ID: $fileId, Collection: $fileCollectionId) marked $actionText`: $FilePath" -ForegroundColor Green
        }
        else { # AllFiles parameter set
            # Count files with the old status within the specified collection
            $countCommand = $connection.CreateCommand()
            $countCommand.CommandText = "SELECT COUNT(*) FROM files WHERE Dirty = @OldStatus AND collection_id = @CollectionId"
            $countCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@OldStatus", $oldStatus)))
            $countCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
            $countCommand.Transaction = $transaction # Assign transaction
            $filesToUpdateCount = [int]$countCommand.ExecuteScalar()
            
            if ($filesToUpdateCount -eq 0) {
                Write-Host "No files found in Collection $CollectionId with status '$oldStatus' that need updating." -ForegroundColor Yellow
                $transaction.Commit() # Commit even if nothing changed
                return $true
            }
            
            Write-Host "Found $filesToUpdateCount files to mark $actionText in Collection $CollectionId."
            
            # Get list of files to update (optional, for reporting)
            # Consider performance impact for very large collections if reporting individual files
            $selectCommand = $connection.CreateCommand()
            $selectCommand.CommandText = "SELECT id, FilePath, Deleted FROM files WHERE Dirty = @OldStatus AND collection_id = @CollectionId"
            $selectCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@OldStatus", $oldStatus)))
            $selectCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
            $selectCommand.Transaction = $transaction # Assign transaction
            $reader = $selectCommand.ExecuteReader()
            
            $filesToReport = [System.Collections.Generic.List[object]]::new()
            while ($reader.Read()) {
                 $filesToReport.Add( @{ Id = $reader.GetInt32(0); Path = $reader.GetString(1); IsDeleted = $reader.GetBoolean(2) } )
            }
            $reader.Close()
            
            # Update all files in the specified collection
            $updateCommand = $connection.CreateCommand()
            $updateCommand.CommandText = "UPDATE files SET Dirty = @NewStatus WHERE Dirty = @OldStatus AND collection_id = @CollectionId"
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@NewStatus", $newStatus)))
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@OldStatus", $oldStatus)))
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
            $updateCommand.Transaction = $transaction # Assign transaction
            $processed = $updateCommand.ExecuteNonQuery()
            
            # Report updated files (consider limiting output for large counts)
            $reportLimit = 50 
            $reportedCount = 0
            foreach ($file in $filesToReport) {
                 if ($reportedCount -lt $reportLimit) {
                    $deleteWarning = if ($file.IsDeleted) { " (Note: File is also marked as deleted)" } else { "" }
                    Write-Host "File (ID: $($file.Id)) marked $actionText`: $($file.Path)$deleteWarning" -ForegroundColor Green
                    $reportedCount++
                 } else {
                     Write-Host "...and $($filesToReport.Count - $reportLimit) more files." -ForegroundColor Gray
                     break
                 }
            }
            
            Write-Host "Marked $processed files $actionText in Collection $CollectionId." -ForegroundColor Green
        }
        
        # Commit transaction
        $transaction.Commit()
        return $true
    }
    catch {
        if ($transaction) {
            $transaction.Rollback()
        }
        Write-Error "Error updating database: $_"
        return $false
    }
    finally {
        # Close the database connection
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

Export-ModuleMember -Function Update-FileProcessingStatus
