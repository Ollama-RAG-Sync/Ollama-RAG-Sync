<#
.SYNOPSIS
    Lists files in a specific collection based on their status.
.DESCRIPTION
    This script queries the FileTracker database and returns a list of files from a specific collection
    based on their status. By default, it returns only dirty files (those marked for processing), but
    can also include deleted files and processed files based on the parameters provided.
.PARAMETER CollectionName
    The name of the collection to query.
.PARAMETER InstallPath
    The installation path where the FileTracker database is located.
.PARAMETER IncludeDirty
    If specified, includes files marked as dirty (needing processing). Default is true if no include parameters are specified.
.PARAMETER IncludeDeleted
    If specified, includes files marked as deleted.
.PARAMETER IncludeProcessed
    If specified, includes files that have been processed (not dirty).
.PARAMETER AsObject
    If specified, returns PowerShell objects instead of formatted output.
.EXAMPLE
    .\Get-CollectionDirtyFiles.ps1 -CollectionName "Documentation" -InstallPath "C:\FileTracker"
    # Lists only dirty files to process in the "Documentation" collection
.EXAMPLE
    .\Get-CollectionDirtyFiles.ps1 -CollectionName "Projects" -InstallPath "C:\FileTracker" -IncludeDeleted -AsObject
    # Returns both dirty and deleted files as objects for the "Projects" collection
.EXAMPLE
    .\Get-CollectionDirtyFiles.ps1 -CollectionName "Reports" -InstallPath "C:\FileTracker" -IncludeDirty -IncludeProcessed -IncludeDeleted
    # Returns all files (dirty, processed, and deleted) for the "Reports" collection
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$CollectionName,

    [Parameter(Mandatory = $false)]
    [int]$CollectionId,

    [Parameter(Mandatory = $true)]
    [string]$InstallPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDirty,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDeleted, 
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeProcessed,
    
    [Parameter(Mandatory = $false)]
    [switch]$AsObject
)

# Import the shared database module
$scriptParentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$databaseSharedModulePath = Join-Path -Path $scriptParentPath -ChildPath "Database-Shared.psm1"
Import-Module -Name $databaseSharedModulePath -Force

# Determine Database Path
# Note: This script doesn't accept $DatabasePath override, it relies solely on $InstallPath
$DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
Write-Verbose "Using database path: $DatabasePath"

# Get collection by name if needed
if ($CollectionName) {
    # Pass InstallPath to Get-Collections
    $collections = Get-Collections -DatabasePath $DatabasePath -InstallPath $InstallPath 
    $collection = $collections | Where-Object { $_.name -eq $CollectionName }
    
    if (-not $collection) {
        Write-Error "Collection with name '$CollectionName' not found."
        exit 1
    }
    
    $CollectionId = $collection.id # Get ID from found collection
    Write-Host "Found collection '$CollectionName' with ID: $CollectionId" -ForegroundColor Green
}
elseif ($CollectionId) {
    # If only ID is provided, get the collection name for reporting
    # Pass InstallPath to Get-Collection
    $collection = Get-Collection -Id $CollectionId -DatabasePath $DatabasePath -InstallPath $InstallPath
    if ($collection) {
        $CollectionName = $collection.name
        Write-Host "Using Collection ID: $CollectionId (Name: $CollectionName)" -ForegroundColor Green
    } else {
         Write-Error "Collection with ID '$CollectionId' not found."
         exit 1
    }
} else {
     Write-Error "Either -CollectionName or -CollectionId must be specified."
     exit 1
}


# If no include parameters are specified, default to showing dirty files only
if (-not $IncludeDirty -and -not $IncludeDeleted -and -not $IncludeProcessed) {
    $IncludeDirty = $true
}



try {
    # Get the connection to the database (pass InstallPath)
    $connection = Get-DatabaseConnection -DatabasePath $DatabasePath -InstallPath $InstallPath
    
    # Collection ID is already determined above, no need to query again by name
    
    # Build the WHERE clause dynamically based on parameters
    $whereConditions = @("collection_id = @CollectionIdParam") # Use a different parameter name to avoid conflict
    
    # Handle Dirty/Processed flags
    if ($IncludeDirty -and $IncludeProcessed) {
        # Include both dirty and processed files - no additional condition needed
    } 
    elseif ($IncludeDirty) {
        $whereConditions += "Dirty = 1"
    }
    elseif ($IncludeProcessed) {
        $whereConditions += "Dirty = 0"
    }
    
    # Handle Deleted flag
    if ($IncludeDeleted) {
        # If we include deleted files but also want non-deleted files, no condition needed
    }
    else {
        # Default - only include non-deleted files
        $whereConditions += "Deleted = 0"
    }
    
    $whereClause = $whereConditions -join " AND "
    
    # Create command to count files matching criteria
    $countCommand = $connection.CreateCommand()
    $countCommand.CommandText = "SELECT COUNT(*) FROM files WHERE $whereClause"
    $null = $countCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionIdParam", $CollectionId))) # Use the determined ID
    $filesCount = $countCommand.ExecuteScalar()
    
    if ($filesCount -eq 0) {
        $fileTypeMessage = "matching the criteria"
        Write-Host "No files found $fileTypeMessage in collection '$CollectionName'." -ForegroundColor Yellow
        if ($AsObject) {
            return @()
        }
        exit 0
    }
    
    # Create a results array
    $results = @()
    
    # Query for files matching criteria
    $selectCommand = $connection.CreateCommand()
    $selectCommand.CommandText = "SELECT id, FilePath, OriginalUrl, LastModified, Dirty, Deleted FROM files WHERE $whereClause"
    $null = $selectCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionIdParam", $CollectionId))) # Use the determined ID
    $reader = $selectCommand.ExecuteReader()
    
    # Process files
    while ($reader.Read()) {
        $id = $reader["id"]
        $filePath = $reader["FilePath"]
        $originalUrl = if ($reader.IsDBNull($reader.GetOrdinal("OriginalUrl"))) { $null } else { $reader["OriginalUrl"] }
        $lastModified = [DateTime]::Parse($reader["LastModified"])
        $isDirty = [bool]$reader["Dirty"]
        $isDeleted = [bool]$reader["Deleted"]
        
        $fileInfo = [PSCustomObject]@{
            Id = $id
            FilePath = $filePath
            OriginalUrl = $originalUrl
            LastModified = $lastModified
            IsDirty = $isDirty
            IsDeleted = $isDeleted
            Collection = $CollectionName # Use the determined name
            CollectionId = $CollectionId # Use the determined ID
        }
        
        $results += $fileInfo
        
        # If not returning objects, print info to console
        if (-not $AsObject) {
            $fileStatus = ""
            $foregroundColor = "White"
            
            if ($isDeleted) {
                $fileStatus = "DELETED"
                $foregroundColor = "Red"
            }
            elseif ($isDirty) {
                $fileStatus = "DIRTY"
                $foregroundColor = "Green"
            }
            else {
                $fileStatus = "PROCESSED"
                $foregroundColor = "Blue"
            }
            
            Write-Host "File ($fileStatus): $filePath" -ForegroundColor $foregroundColor
            if ($originalUrl) {
                Write-Host "  Original URL: $originalUrl" -ForegroundColor Cyan
            }
            Write-Host "  Last Modified: $lastModified" -ForegroundColor Gray
            Write-Host ""
        }
    }
    
    # Close the reader
    $reader.Close()
    
    if (-not $AsObject) {
        $fileTypes = @()
        if ($IncludeDirty) { $fileTypes += "dirty" }
        if ($IncludeProcessed) { $fileTypes += "processed" }
        if ($IncludeDeleted) { $fileTypes += "deleted" }
        
        $fileTypesString = if ($fileTypes.Count -gt 1) {
            ($fileTypes[0..($fileTypes.Count-2)] -join ", ") + " and " + $fileTypes[-1]
        } else {
            $fileTypes[0]
        }
        
        Write-Host "Found $($results.Count) $fileTypesString files in collection '$CollectionName'." -ForegroundColor Cyan
    } else {
        # Return objects if AsObject switch is used
        return $results
    }
}
catch {
    Write-Error "Error querying database: $_"
    if ($AsObject) {
        return @()
    }
}
finally {
    # Close the database connection
    if ($connection) {
        $connection.Close()
        $connection.Dispose()
    }
}
