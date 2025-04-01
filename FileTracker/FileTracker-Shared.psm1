function Update-FileProcessingStatus {
    <#
    .SYNOPSIS
        Updates a file's processing status in the SQLite database.
    .DESCRIPTION
        This function updates a file's status in the SQLite database by setting its "Dirty" flag.
    .PARAMETER FilePath
        The full path of the file to update.
    .PARAMETER DatabasePath
        The path to the SQLite database.
    .PARAMETER FolderPath
        The path to the monitored folder. If specified instead of DatabasePath, the function will
        automatically compute the database path as [FolderPath]\.ai\FileTracker.db.
    .PARAMETER All
        If specified, updates all files with the opposite status.
    .PARAMETER Dirty
        Boolean value indicating whether to mark the file as dirty/to process (true) or as processed (false).
    #>
    [CmdletBinding(DefaultParameterSetName = "SingleFile")]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "SingleFile")]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $false)]
        [string]$FolderPath,
        
        [Parameter(Mandatory = $true, ParameterSetName = "AllFiles")]
        [switch]$All,
        
        [Parameter(Mandatory = $true)]
        [bool]$Dirty
    )

    # Determine new and old status values
    $newStatus = [int]$Dirty
    $oldStatus = [int](-not $Dirty)
    $actionText = if ($Dirty) { "as dirty (to process)" } else { "as processed" }
    
    # Validate that we have a DatabasePath
    if (-not $DatabasePath) {
        Write-Error "Either DatabasePath or FolderPath must be specified."
        return $false
    }

    $sqliteAssemblyPath = "$FolderPath\Microsoft.Data.Sqlite.dll"
    $sqliteAssemblyPath2 = "$FolderPah\SQLitePCLRaw.core.dll"
    $sqliteAssemblyPath3 = "$FolderPath\SQLitePCLRaw.provider.e_sqlite3.dll"

    # Load SQLite assembly
    Add-Type -Path $sqliteAssemblyPath
    Add-Type -Path $sqliteAssemblyPath2
    Add-Type -Path $sqliteAssemblyPath3

    # Create/Open the database
    try {
        # Set SQLitePCLRaw provider
        [SQLitePCL.raw]::SetProvider([SQLitePCL.SQLite3Provider_e_sqlite3]::new())
    
        # Create connection to SQLite database
        $connectionString = "Data Source=$DatabasePath"
        $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection($connectionString)
        $null = $connection.Open()
        
        # Begin transaction for better performance
        $transaction = $connection.BeginTransaction()
        
        if ($PSCmdlet.ParameterSetName -eq "SingleFile") {
            # Check if the file exists in the database
            $checkCommand = $connection.CreateCommand()
            $checkCommand.CommandText = "SELECT id, Dirty, Deleted FROM files WHERE FilePath = @FilePath"
            $null = $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
            
            $reader = $checkCommand.ExecuteReader()
            
            if (-not $reader.Read()) {
                $reader.Close()
                Write-Error "File not found in the database: $FilePath"
                return $false
            }
            
            $currentStatus = $reader.GetInt32(1)
            $toDeleteStatus = $reader.GetInt32(2)
            $null = $reader.Close()
            
            # If file is marked for deletion, report this
            if ($toDeleteStatus -eq 1) {
                Write-Host "Warning: File is marked for deletion (missing from folder): $FilePath" -ForegroundColor Yellow
            }
            
            # Check if the file already has the target status
            if ($currentStatus -eq $newStatus) {
                $statusText = if ($Dirty) { "already marked as dirty (to process)" } else { "already marked as processed" }
                Write-Host "File is $statusText`: $FilePath" -ForegroundColor Yellow
                return $true
            }
            
            # Update the file status
            $updateCommand = $connection.CreateCommand()
            $updateCommand.CommandText = "UPDATE files SET Dirty = @NewStatus WHERE FilePath = @FilePath"
            $null = $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
            $null = $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@NewStatus", $newStatus)))
            $null = $updateCommand.ExecuteNonQuery()
            
            Write-Host "File marked $actionText`: $FilePath" -ForegroundColor Green
        }
        else {
            # Count files with the old status
            $countCommand = $connection.CreateCommand()
            $countCommand.CommandText = "SELECT COUNT(*) FROM files WHERE Dirty = @OldStatus"
            $countCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@OldStatus", $oldStatus)))
            $filesToUpdateCount = $countCommand.ExecuteScalar()
            
            if ($filesToUpdateCount -eq 0) {
                Write-Host "No files found that need updating." -ForegroundColor Yellow
                return $true
            }
            
            # Get list of files to update
            $selectCommand = $connection.CreateCommand()
            $selectCommand.CommandText = "SELECT FilePath, Deleted FROM files WHERE Dirty = @OldStatus"
            $selectCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@OldStatus", $oldStatus)))
            $reader = $selectCommand.ExecuteReader()
            
            $filePaths = @()
            $deletedFilePaths = @()
            while ($reader.Read()) {
                $filePath = $reader["FilePath"]
                $toDelete = $reader.GetInt32(1)
                
                if ($toDelete -eq 1) {
                    $deletedFilePaths += $filePath
                } else {
                    $filePaths += $filePath
                }
            }
            $reader.Close()
            
            # Update all files
            $updateCommand = $connection.CreateCommand()
            $updateCommand.CommandText = "UPDATE files SET Dirty = @NewStatus WHERE Dirty = @OldStatus"
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@NewStatus", $newStatus)))
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@OldStatus", $oldStatus)))
            $processed = $updateCommand.ExecuteNonQuery()
            
            # Report updated files
            foreach ($filePath in $filePaths) {
                Write-Host "File marked $actionText`: $filePath" -ForegroundColor Green
            }
            
            # Report files marked for deletion
            if ($deletedFilePaths.Count -gt 0) {
                Write-Host "The following files were marked $actionText but are also marked for deletion (missing):" -ForegroundColor Yellow
                foreach ($filePath in $deletedFilePaths) {
                    Write-Host " - $filePath" -ForegroundColor Magenta
                }
            }
            
            Write-Host "Marked $processed files $actionText." -ForegroundColor Green
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
