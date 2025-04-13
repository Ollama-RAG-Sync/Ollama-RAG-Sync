<#
.SYNOPSIS
    Updates the status of all files in a collection.
.DESCRIPTION
    This function updates the status (dirty or processed) of all files in a collection within the FileTracker database.
.PARAMETER Dirty
    Boolean value indicating whether to mark the files as dirty/to process (true) or as processed (false).
.PARAMETER DatabasePath
    The path to the SQLite database file.
.PARAMETER CollectionId
    The ID of the collection whose files should be updated.
.EXAMPLE
    Update-AllFilesStatus -Dirty $true -DatabasePath "C:\FileTracker\FileTracker.db" -CollectionId 1
    Marks all files in collection 1 as dirty (needs processing).
.EXAMPLE
    Update-AllFilesStatus -Dirty $false -DatabasePath "C:\FileTracker\FileTracker.db" -CollectionId 1
    Marks all files in collection 1 as processed.
#>
param (
    [Parameter(Mandatory = $true)]
    [bool]$Dirty,
    
    [Parameter(Mandatory = $true)]
    [string]$DatabasePath,
    
    [Parameter(Mandatory = $true)]
    [int]$CollectionId
)

try {
    # Create connection to SQLite database
    $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
    
    # Convert boolean to integer for SQLite
    $newStatus = [int]$Dirty
    
    # Begin transaction for better performance
    $transaction = $connection.BeginTransaction()
    
    try {
        # Count files in the collection
        $countCommand = $connection.CreateCommand()
        $countCommand.CommandText = "SELECT COUNT(*) FROM files WHERE collection_id = @CollectionId"
        $countCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
        $countCommand.Transaction = $transaction
        
        $fileCount = [int]$countCommand.ExecuteScalar()
        
        if ($fileCount -eq 0) {
            Write-Verbose "No files found in collection $CollectionId"
            return $true
        }
        
        # Update all files in the collection
        $updateCommand = $connection.CreateCommand()
        $updateCommand.CommandText = "UPDATE files SET Dirty = @NewStatus WHERE collection_id = @CollectionId"
        $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@NewStatus", $newStatus)))
        $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
        $updateCommand.Transaction = $transaction
        
        $rowsAffected = $updateCommand.ExecuteNonQuery()
        
        # Commit transaction
        $transaction.Commit()
        
        $actionText = if ($Dirty) { "marked as dirty (to process)" } else { "marked as processed" }
        Write-Verbose "$rowsAffected files in collection $CollectionId $actionText"
        
        return $rowsAffected -gt 0 -or $fileCount -eq 0
    }
    catch {
        # Rollback transaction on error
        $transaction.Rollback()
        throw
    }
}
catch {
    Write-Error "Error updating file statuses: $_"
    return $false
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
