# Database-Shared.psm1
# This module contains shared functions for interacting with the FileTracker database

function Get-DatabaseConnection {
    <#
    .SYNOPSIS
        Returns a connection to the FileTracker SQLite database.
    .DESCRIPTION
        This function creates and returns a connection to the FileTracker SQLite database.
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )

    try {
        # Set SQLitePCLRaw provider if not already set
        try {
            [SQLitePCL.raw]::SetProvider([SQLitePCL.SQLite3Provider_e_sqlite3]::new())
        }
        catch {
            # Provider might already be set, which is fine
        }

        # Create connection to SQLite database
        $connectionString = "Data Source=$DatabasePath"
        $connection = New-Object Microsoft.Data.Sqlite.SqliteConnection($connectionString)
        $connection.Open()
        
        return $connection
    }
    catch {
        Write-Error "Error connecting to database: $_"
        throw
    }
}

function Get-DefaultDatabasePath {
    <#
    .SYNOPSIS
        Returns the default path for the FileTracker database.
    .DESCRIPTION
        This function returns the default path for the FileTracker database, which is in a dedicated folder.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory
    )
    
    # Create the dedicated FileTracker database directory in the user's AppData folder
    return Join-Path -Path $InstallDirectory -ChildPath "FileTracker.db"
}

function Get-CollectionDatabasePath {
    <#
    .SYNOPSIS
        Returns the path for a specific collection's database file.
    .DESCRIPTION
        This function returns the path for a specific collection's database file in the dedicated folder.
    .PARAMETER CollectionName
        The name of the collection.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,

        [Parameter(Mandatory = $true)]
        [string]$CollectionName
    )
    
    # Create the dedicated FileTracker database directory in the user's AppData folder
    $fileTrackerDir = Join-Path -Path $InstallPath -ChildPath "FileTracker"
    return Join-Path -Path $fileTrackerDir -ChildPath "Collection_$safeCollectionName.db"
}

# Collection management functions

function Get-Collections {
    <#
    .SYNOPSIS
        Gets a list of all collections from the FileTracker database.
    .DESCRIPTION
        This function retrieves all collections from the FileTracker database.
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath
    )
    
    try {

        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT id, name, description, source_folder, include_extensions, exclude_folders, created_at, updated_at FROM collections ORDER BY name"
        
        $reader = $command.ExecuteReader()
        
        $collections = [System.Collections.ArrayList]::new()
        
        while ($reader.Read()) {
            $collection = @{
                id = $reader.GetInt32(0)
                name = $reader.GetString(1)
                description = if ($reader.IsDBNull(2)) { $null } else { $reader.GetString(2) }
                source_folder = $reader.GetString(3)
                include_extensions = if ($reader.IsDBNull(4)) { $null } else { $reader.GetString(4) }
                exclude_folders = if ($reader.IsDBNull(5)) { $null } else { $reader.GetString(5) }
                created_at = $reader.GetString(6)
                updated_at = $reader.GetString(7)
            }
            
            $null = $collections.Add($collection)
        }
        
        $null = $reader.Close()

        return ,$collections
    }
    catch {
        Write-Error "Error getting collections: $_"
        return @()
    }
    finally {
        if ($connection) {
            $null = $connection.Close()
            $null = $connection.Dispose()
        }
    }
}

function Get-Collection {
    <#
    .SYNOPSIS
        Gets a specific collection from the FileTracker database.
    .DESCRIPTION
        This function retrieves a specific collection from the FileTracker database.
    .PARAMETER Id
        The ID of the collection to retrieve.
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [int]$Id,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT id, name, description, source_folder, include_extensions, exclude_folders, created_at, updated_at FROM collections WHERE id = @Id"
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $Id)))
        
        $reader = $command.ExecuteReader()
        
        if ($reader.Read()) {
            $collection = @{
                id = $reader.GetInt32(0)
                name = $reader.GetString(1)
                description = if ($reader.IsDBNull(2)) { $null } else { $reader.GetString(2) }
                source_folder = $reader.GetString(3)
                include_extensions = if ($reader.IsDBNull(4)) { $null } else { $reader.GetString(4) }
                exclude_folders = if ($reader.IsDBNull(5)) { $null } else { $reader.GetString(5) }
                created_at = $reader.GetString(6)
                updated_at = $reader.GetString(7)
            }
            
            $reader.Close()
            return $collection
        }
        else {
            $reader.Close()
            return $null
        }
    }
    catch {
        Write-Error "Error getting collection: $_"
        return $null
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

function New-Collection {
    <#
    .SYNOPSIS
        Creates a new collection in the FileTracker database.
    .DESCRIPTION
        This function creates a new collection in the FileTracker database.
    .PARAMETER Name
        The name of the collection.
    .PARAMETER Description
        Optional description of the collection.
    .PARAMETER SourceFolder
        The path to the folder to monitor for this collection.
    .PARAMETER IncludeExtensions
        List of file extensions to include (comma-separated string). E.g. ".docx,.pdf,.txt"
    .PARAMETER ExcludeFolders
        List of folders to exclude (comma-separated string). E.g. ".git,.ai,node_modules"
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [string]$Description,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,
        
        [Parameter(Mandatory = $false)]
        [string]$IncludeExtensions,
        
        [Parameter(Mandatory = $false)]
        [string]$ExcludeFolders,
        
        [Parameter(Mandatory = $false)]
        [string]$InstallPath
    )
    
    try {
        # Validate that the source folder exists
        if (-not (Test-Path -Path $SourceFolder -PathType Container)) {
            Write-Error "Source folder does not exist: $SourceFolder"
            return $null
        }

        $DatabasePath = Join-Path -Path $InstallPath -ChildPath "FileTracker.db"
        
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Check if a collection with this name already exists
        $checkCommand = $connection.CreateCommand()
        $checkCommand.CommandText = "SELECT COUNT(*) FROM collections WHERE name = @Name"
        $null = $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Name", $Name)))
        
        $exists = [int]$checkCommand.ExecuteScalar() -gt 0
        
        if ($exists) {
            Write-Error "A collection with the name '$Name' already exists."
            return $null
        }
        
        # Create the new collection
        $currentTime = [DateTime]::UtcNow.ToString("o") # ISO 8601 format
        
        $command = $connection.CreateCommand()
        $command.CommandText = "INSERT INTO collections (name, description, source_folder, include_extensions, exclude_folders, created_at, updated_at) VALUES (@Name, @Description, @SourceFolder, @IncludeExtensions, @ExcludeFolders, @CreatedAt, @UpdatedAt); SELECT last_insert_rowid();"
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Name", $Name)))
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Description", [DBNull]::Value)))
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@SourceFolder", $SourceFolder)))
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@IncludeExtensions", [DBNull]::Value)))
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@ExcludeFolders", [DBNull]::Value)))
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CreatedAt", $currentTime)))
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", $currentTime)))
        
        if ($Description) {
            $command.Parameters["@Description"].Value = $Description
        }
        
        if ($IncludeExtensions) {
            $command.Parameters["@IncludeExtensions"].Value = $IncludeExtensions
        }
        
        if ($ExcludeFolders) {
            $command.Parameters["@ExcludeFolders"].Value = $ExcludeFolders
        }
        
        $collectionId = $command.ExecuteScalar()
        
        return @{
            id = $collectionId
            name = $Name
            description = $Description
            source_folder = $SourceFolder
            include_extensions = $IncludeExtensions
            exclude_folders = $ExcludeFolders
            created_at = $currentTime
            updated_at = $currentTime
        }
    }
    catch {
        Write-Error "Error creating collection: $_"
        return $null
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

function Update-Collection {
    <#
    .SYNOPSIS
        Updates an existing collection in the FileTracker database.
    .DESCRIPTION
        This function updates an existing collection in the FileTracker database.
    .PARAMETER Id
        The ID of the collection to update.
    .PARAMETER Name
        The new name for the collection. If not provided, the name will not be changed.
    .PARAMETER Description
        The new description for the collection. If not provided, the description will not be changed.
    .PARAMETER SourceFolder
        The new source folder for the collection. If not provided, the source folder will not be changed.
    .PARAMETER IncludeExtensions
        The new list of file extensions to include (comma-separated string). If not provided, the include extensions will not be changed.
    .PARAMETER ExcludeFolders
        The new list of folders to exclude (comma-separated string). If not provided, the exclude folders will not be changed.
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [int]$Id,
        
        [Parameter(Mandatory = $false)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [string]$Description,
        
        [Parameter(Mandatory = $false)]
        [string]$SourceFolder,
        
        [Parameter(Mandatory = $false)]
        [string]$IncludeExtensions,
        
        [Parameter(Mandatory = $false)]
        [string]$ExcludeFolders,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath 
    )
    
    try {
        # Validate that the source folder exists if provided
        if ($SourceFolder -and -not (Test-Path -Path $SourceFolder -PathType Container)) {
            Write-Error "Source folder does not exist: $SourceFolder"
            return $false
        }
        
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Check if the collection exists
        $checkCommand = $connection.CreateCommand()
        $checkCommand.CommandText = "SELECT COUNT(*) FROM collections WHERE id = @Id"
        $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $Id)))
        
        $exists = [int]$checkCommand.ExecuteScalar() -gt 0
        
        if (-not $exists) {
            Write-Error "Collection with ID $Id not found."
            return $false
        }
        
        # If a new name is provided, check if it would create a duplicate
        if ($Name) {
            $nameCheckCommand = $connection.CreateCommand()
            $nameCheckCommand.CommandText = "SELECT COUNT(*) FROM collections WHERE name = @Name AND id != @Id"
            $nameCheckCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Name", $Name)))
            $nameCheckCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $Id)))
            
            $nameExists = [int]$nameCheckCommand.ExecuteScalar() -gt 0
            
            if ($nameExists) {
                Write-Error "A different collection with the name '$Name' already exists."
                return $false
            }
        }
        
        # Get current collection data
        $getCommand = $connection.CreateCommand()
        $getCommand.CommandText = "SELECT name, description, source_folder, include_extensions, exclude_folders FROM collections WHERE id = @Id"
        $getCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $Id)))
        
        $reader = $getCommand.ExecuteReader()
        $reader.Read()
        
        $currentName = $reader.GetString(0)
        $currentDescription = if ($reader.IsDBNull(1)) { $null } else { $reader.GetString(1) }
        $currentSourceFolder = $reader.GetString(2)
        $currentIncludeExtensions = if ($reader.IsDBNull(3)) { $null } else { $reader.GetString(3) }
        $currentExcludeFolders = if ($reader.IsDBNull(4)) { $null } else { $reader.GetString(4) }
        
        $reader.Close()
        
        # Prepare update command
        $updateCommand = $connection.CreateCommand()
        $updateCommand.CommandText = "UPDATE collections SET updated_at = @UpdatedAt"
        $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@UpdatedAt", [DateTime]::UtcNow.ToString("o"))))
        
        # Add name parameter if provided
        if ($Name) {
            $updateCommand.CommandText += ", name = @Name"
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Name", $Name)))
        }
        
        # Add description parameter if provided
        if ($PSBoundParameters.ContainsKey('Description')) {
            $updateCommand.CommandText += ", description = @Description"
            if ($Description) {
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Description", $Description)))
            } else {
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Description", [DBNull]::Value)))
            }
        }
        
        # Add source_folder parameter if provided
        if ($SourceFolder) {
            $updateCommand.CommandText += ", source_folder = @SourceFolder"
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@SourceFolder", $SourceFolder)))
        }
        
        # Add include_extensions parameter if provided
        if ($PSBoundParameters.ContainsKey('IncludeExtensions')) {
            $updateCommand.CommandText += ", include_extensions = @IncludeExtensions"
            if ($IncludeExtensions) {
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@IncludeExtensions", $IncludeExtensions)))
            } else {
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@IncludeExtensions", [DBNull]::Value)))
            }
        }
        
        # Add exclude_folders parameter if provided
        if ($PSBoundParameters.ContainsKey('ExcludeFolders')) {
            $updateCommand.CommandText += ", exclude_folders = @ExcludeFolders"
            if ($ExcludeFolders) {
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@ExcludeFolders", $ExcludeFolders)))
            } else {
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@ExcludeFolders", [DBNull]::Value)))
            }
        }
        
        # Complete the command
        $updateCommand.CommandText += " WHERE id = @Id"
        $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $Id)))
        
        # Execute update
        $rowsAffected = $updateCommand.ExecuteNonQuery()
        
        return $rowsAffected -gt 0
    }
    catch {
        Write-Error "Error updating collection: $_"
        return $false
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

function Remove-Collection {
    <#
    .SYNOPSIS
        Removes a collection from the FileTracker database.
    .DESCRIPTION
        This function removes a collection from the FileTracker database.
    .PARAMETER Id
        The ID of the collection to remove.
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [int]$Id,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Begin transaction
        $transaction = $connection.BeginTransaction()
        
        try {
            # Delete files associated with the collection
            $deleteFilesCommand = $connection.CreateCommand()
            $deleteFilesCommand.CommandText = "DELETE FROM files WHERE collection_id = @CollectionId"
            $null = $deleteFilesCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $Id)))
            $filesDeleted = $deleteFilesCommand.ExecuteNonQuery()
            
            # Delete the collection
            $deleteCollectionCommand = $connection.CreateCommand()
            $deleteCollectionCommand.CommandText = "DELETE FROM collections WHERE id = @Id"
            $null = $deleteCollectionCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $Id)))
            $collectionDeleted = $deleteCollectionCommand.ExecuteNonQuery()
            
            # Commit transaction
            $transaction.Commit()
            
            return $collectionDeleted -gt 0
        }
        catch {
            $transaction.Rollback()
            throw
        }
    }
    catch {
        Write-Error "Error removing collection: $_"
        return $false
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

# File management functions

function Get-CollectionFiles {
    <#
    .SYNOPSIS
        Gets all files in a collection.
    .DESCRIPTION
        This function retrieves all files in a specific collection.
    .PARAMETER CollectionId
        The ID of the collection.
    .PARAMETER DirtyOnly
        If specified, returns only files marked as dirty.
    .PARAMETER ProcessedOnly
        If specified, returns only files marked as processed.
    .PARAMETER DeletedOnly
        If specified, returns only files marked as deleted.
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [int]$CollectionId,
        
        [Parameter(Mandatory = $false)]
        [switch]$DirtyOnly,
        
        [Parameter(Mandatory = $false)]
        [switch]$ProcessedOnly,
        
        [Parameter(Mandatory = $false)]
        [switch]$DeletedOnly,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Build query based on parameters
        $query = "SELECT id, FilePath, OriginalUrl, LastModified, Dirty, Deleted FROM files WHERE collection_id = @CollectionId"
        $whereClauses = @()
        
        if ($DirtyOnly) {
            $whereClauses += "Dirty = 1"
        }
        elseif ($ProcessedOnly) {
            $whereClauses += "Dirty = 0"
        }
        
        if ($DeletedOnly) {
            $whereClauses += "Deleted = 1"
        }
        
        if ($whereClauses.Count -gt 0) {
            $query += " AND " + ($whereClauses -join " AND ")
        }
        
        # Execute query
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        $null = $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
        
        $reader = $command.ExecuteReader()
        
        $files = @()
        
        while ($reader.Read()) {
            $file = @{
                id = $reader.GetInt32(0)
                filePath = $reader.GetString(1)
                originalUrl = if ($reader.IsDBNull(2)) { $null } else { $reader.GetString(2) }
                lastModified = $reader.GetString(3)
                dirty = $reader.GetBoolean(4)
                deleted = $reader.GetBoolean(5)
            }
            
            $files += $file
        }
        
        $reader.Close()
        return ,$files
    }
    catch {
        Write-Error "Error getting collection files: $_"
        return @()
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

function Add-FileToCollection {
    <#
    .SYNOPSIS
        Adds a file to a collection.
    .DESCRIPTION
        This function adds a file to a specific collection in the FileTracker database.
    .PARAMETER CollectionId
        The ID of the collection.
    .PARAMETER FilePath
        The path to the file.
    .PARAMETER OriginalUrl
        The original URL of the file (optional).
    .PARAMETER Dirty
        Whether the file should be marked as dirty (needing processing).
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [int]$CollectionId,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$OriginalUrl,
        
        [Parameter(Mandatory = $false)]
        [bool]$Dirty = $true,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Check if the collection exists
        $checkCollectionCommand = $connection.CreateCommand()
        $checkCollectionCommand.CommandText = "SELECT COUNT(*) FROM collections WHERE id = @CollectionId"
        $checkCollectionCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
        
        $collectionExists = [int]$checkCollectionCommand.ExecuteScalar() -gt 0
        
        if (-not $collectionExists) {
            Write-Error "Collection with ID $CollectionId not found."
            return $null
        }
        
        # Check if the file exists
        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            Write-Error "File not found at path: $FilePath"
            return $null
        }
        
        # Check if the file is already in the collection
        $checkFileCommand = $connection.CreateCommand()
        $checkFileCommand.CommandText = "SELECT id FROM files WHERE FilePath = @FilePath AND collection_id = @CollectionId"
        $checkFileCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
        $checkFileCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
        
        $existingFileId = $checkFileCommand.ExecuteScalar()
        
        if ($existingFileId) {
            Write-Warning "File is already in the collection. Updating metadata."
            
            # Update the existing file
            $updateCommand = $connection.CreateCommand()
            $updateCommand.CommandText = "UPDATE files SET LastModified = @LastModified, Dirty = @Dirty, Deleted = 0"
            
            if ($OriginalUrl) {
                $updateCommand.CommandText += ", OriginalUrl = @OriginalUrl"
                $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@OriginalUrl", $OriginalUrl)))
            }
            
            $updateCommand.CommandText += " WHERE id = @Id"
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $existingFileId)))
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", (Get-Item $FilePath).LastWriteTime.ToString("o"))))
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Dirty", [int]$Dirty)))
            
            $updateCommand.ExecuteNonQuery()
            
            return @{
                id = $existingFileId
                filePath = $FilePath
                originalUrl = $OriginalUrl
                lastModified = (Get-Item $FilePath).LastWriteTime.ToString("o")
                dirty = $Dirty
                deleted = $false
                collection_id = $CollectionId
                updated = $true
            }
        }
        else {
            # Insert the new file
            $insertCommand = $connection.CreateCommand()
            $insertCommand.CommandText = "INSERT INTO files (FilePath, OriginalUrl, LastModified, Dirty, Deleted, collection_id) VALUES (@FilePath, @OriginalUrl, @LastModified, @Dirty, 0, @CollectionId); SELECT last_insert_rowid();"
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FilePath", $FilePath)))
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@OriginalUrl", [DBNull]::Value)))
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@LastModified", (Get-Item $FilePath).LastWriteTime.ToString("o"))))
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Dirty", [int]$Dirty)))
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
            
            if ($OriginalUrl) {
                $insertCommand.Parameters["@OriginalUrl"].Value = $OriginalUrl
            }
            
            $fileId = $insertCommand.ExecuteScalar()
            
            return @{
                id = $fileId
                filePath = $FilePath
                originalUrl = $OriginalUrl
                lastModified = (Get-Item $FilePath).LastWriteTime.ToString("o")
                dirty = $Dirty
                deleted = $false
                collection_id = $CollectionId
                updated = $false
            }
        }
    }
    catch {
        Write-Error "Error adding file to collection: $_"
        return $null
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

function Remove-FileFromCollection {
    <#
    .SYNOPSIS
        Removes a file from a collection.
    .DESCRIPTION
        This function removes a file from a collection in the FileTracker database.
    .PARAMETER FileId
        The ID of the file to remove.
    .PARAMETER DatabasePath
        The path to the SQLite database file.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [int]$FileId,
        
        [Parameter(Mandatory = $false)]
        [string]$DatabasePath
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Delete the file
        $deleteCommand = $connection.CreateCommand()
        $deleteCommand.CommandText = "DELETE FROM files WHERE id = @FileId"
        $deleteCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@FileId", $FileId)))
        
        $rowsAffected = $deleteCommand.ExecuteNonQuery()
        
        return $rowsAffected -gt 0
    }
    catch {
        Write-Error "Error removing file from collection: $_"
        return $false
    }
    finally {
        if ($connection) {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

# Export functions to make them available to other scripts
Export-ModuleMember -Function Get-DatabaseConnection, 
                              Get-DefaultDatabasePath,
                              Get-CollectionDatabasePath,
                              Get-Collections,
                              Get-Collection,
                              New-Collection,
                              Update-Collection,
                              Remove-Collection,
                              Get-CollectionFiles,
                              Add-FileToCollection,
                              Remove-FileFromCollection
