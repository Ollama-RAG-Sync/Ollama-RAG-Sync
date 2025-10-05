<#
.SYNOPSIS
    Updates a file's status in the FileTracker database.
.DESCRIPTION
    This function updates a file's status (dirty or processed) in the FileTracker database.
.PARAMETER FileId
    The ID of the file to update.
.PARAMETER Dirty
    Boolean value indicating whether to mark the file as dirty/to process (true) or as processed (false).
.PARAMETER DatabasePath
    The path to the SQLite database file.
.PARAMETER CollectionId
    The ID of the collection the file belongs to.
.EXAMPLE
    Update-FileStatus -FileId 123 -Dirty $true -DatabasePath "C:\FileTracker\FileTracker.db" -CollectionId 1
    Marks the file with ID 123 in collection 1 as dirty (needs processing).
.EXAMPLE
    Update-FileStatus -FileId 123 -Dirty $false -DatabasePath "C:\FileTracker\FileTracker.db" -CollectionId 1
    Marks the file with ID 123 in collection 1 as processed.
#>
param (
    [Parameter(Mandatory = $true)]
    [int]$FileId,
    
    [Parameter(Mandatory = $true)]
    [bool]$Dirty,
    
    [Parameter(Mandatory = $true)]
    [string]$DatabasePath,
    
    [Parameter(Mandatory = $true)]
    [int]$CollectionId
)

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedModulePath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedModulePath -Force -Global

try {
    # Create connection to SQLite database
    $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
    
    # Check if the file exists in the collection
    $checkCommand = $connection.CreateCommand()
    $checkCommand.CommandText = "SELECT id, Dirty FROM files WHERE id = @FileId AND collection_id = @CollectionId"
    $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FileId", $FileId)))
    $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
    
    $reader = $checkCommand.ExecuteReader()
    
    if (-not $reader.Read()) {
        $reader.Close()
        Write-Error "File with ID $FileId not found in collection $CollectionId"
        return $false
    }
    
    $currentStatus = $reader.GetBoolean(1)
    $reader.Close()
    
    # Convert boolean to integer for SQLite
    $newStatus = [int]$Dirty
    
    # Check if the file already has the target status
    if ($currentStatus -eq $Dirty) {
        $statusText = if ($Dirty) { "already marked as dirty (to process)" } else { "already marked as processed" }
        Write-Verbose "File is $statusText"
        return $true
    }
    
    # Update the file status
    $updateCommand = $connection.CreateCommand()
    $updateCommand.CommandText = "UPDATE files SET Dirty = @NewStatus WHERE id = @FileId AND collection_id = @CollectionId"
    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FileId", $FileId)))
    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
    $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@NewStatus", $newStatus)))
    
    $rowsAffected = $updateCommand.ExecuteNonQuery()
    
    $actionText = if ($Dirty) { "marked as dirty (to process)" } else { "marked as processed" }
    Write-Verbose "File $actionText"
    
    return $rowsAffected -gt 0
}
catch {
    Write-Error "Error updating file status: $_"
    return $false
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
