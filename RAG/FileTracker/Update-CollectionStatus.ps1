<#
.SYNOPSIS
    Updates the dirty status of files in a collection.
.DESCRIPTION
    This script allows you to mark all files in a collection as dirty or not dirty.
    You can specify the collection by ID or by name.
.PARAMETER CollectionId
    The ID of the collection to update.
.PARAMETER CollectionName
    The name of the collection to update.
.PARAMETER Dirty
    Set to $true to mark files as dirty, $false to mark as clean.
.PARAMETER InstallPath
    The installation path for the FileTracker system.
.EXAMPLE
    .\Update-CollectionStatus.ps1 -CollectionName "Documents" -Dirty $true -InstallPath "C:\FileTracker"
    # Marks all files in the "Documents" collection as dirty
.EXAMPLE
    .\Update-CollectionStatus.ps1 -CollectionId 1 -Dirty $false -InstallPath "C:\FileTracker"
    # Marks all files in collection ID 1 as clean (not dirty)
#>

param (
    [Parameter(Mandatory = $false, ParameterSetName = "ById")]
    [int]$CollectionId,
    
    [Parameter(Mandatory = $false, ParameterSetName = "ByName")]
    [string]$CollectionName,
    
    [Parameter(Mandatory = $true)]
    [bool]$Dirty,
    
    [Parameter(Mandatory = $true)]
    [string]$InstallPath
)

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedModulePath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedModulePath -Force

# Validate that either CollectionId or CollectionName is provided
if (-not $CollectionId -and -not $CollectionName) {
    Write-Error "Either CollectionId or CollectionName must be specified."
    exit 1
}

try {
    # Get database connection
    $DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
    $connection = Get-DatabaseConnection -DatabasePath $DatabasePath -InstallPath $InstallPath
    
    # Determine the collection ID if name was provided
    $targetCollectionId = $CollectionId
    if ($CollectionName) {
        $getIdCommand = $connection.CreateCommand()
        $getIdCommand.CommandText = "SELECT id FROM collections WHERE name = @CollectionName"
        $null = $getIdCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionName", $CollectionName)))
        
        $result = $getIdCommand.ExecuteScalar()
        if ($null -eq $result) {
            Write-Error "Collection with name '$CollectionName' not found."
            exit 1
        }
        $targetCollectionId = [int]$result
        $getIdCommand.Dispose()
    }
    
    # Verify the collection exists if ID was provided directly
    if ($CollectionId) {
        $verifyCommand = $connection.CreateCommand()
        $verifyCommand.CommandText = "SELECT name FROM collections WHERE id = @CollectionId"
        $null = $verifyCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $targetCollectionId)))
        
        $collectionNameResult = $verifyCommand.ExecuteScalar()
        if ($null -eq $collectionNameResult) {
            Write-Error "Collection with ID '$CollectionId' not found."
            exit 1
        }
        $CollectionName = $collectionNameResult
        $verifyCommand.Dispose()
    }
    
    # Count files in the collection
    $countCommand = $connection.CreateCommand()
    $countCommand.CommandText = "SELECT COUNT(*) FROM files WHERE collection_id = @CollectionId AND Deleted = 0"
    $null = $countCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $targetCollectionId)))
    $fileCount = [int]$countCommand.ExecuteScalar()
    $countCommand.Dispose()
    
    if ($fileCount -eq 0) {
        Write-Warning "No files found in collection '$CollectionName' (ID: $targetCollectionId)."
        return
    }
    
    # Update the dirty status of all files in the collection
    $updateCommand = $connection.CreateCommand()
    $updateCommand.CommandText = @"
UPDATE files 
SET Dirty = @Dirty 
WHERE collection_id = @CollectionId AND Deleted = 0
"@
    $null = $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Dirty", [int]$Dirty)))
    $null = $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $targetCollectionId)))
    
    $affectedRows = $updateCommand.ExecuteNonQuery()
    $updateCommand.Dispose()
    
    # Report results
    $statusText = if ($Dirty) { "dirty" } else { "clean" }
    Write-Host "Successfully marked $affectedRows files as $statusText in collection '$CollectionName' (ID: $targetCollectionId)." -ForegroundColor Green
    
    # Show summary of collection status
    $dirtyCountCommand = $connection.CreateCommand()
    $dirtyCountCommand.CommandText = "SELECT COUNT(*) FROM files WHERE collection_id = @CollectionId AND Deleted = 0 AND Dirty = 1"
    $null = $dirtyCountCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $targetCollectionId)))
    $dirtyCount = [int]$dirtyCountCommand.ExecuteScalar()
    $dirtyCountCommand.Dispose()
    
    $cleanCount = $fileCount - $dirtyCount
    Write-Host "Collection Status:" -ForegroundColor Cyan
    Write-Host "  - Total files: $fileCount" -ForegroundColor White
    Write-Host "  - Dirty files: $dirtyCount" -ForegroundColor Yellow
    Write-Host "  - Clean files: $cleanCount" -ForegroundColor Green
}
catch {
    Write-Error "Error updating collection status: $_"
    exit 1
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}