# Processor-Database.psm1
# Contains database functions for the processor

function Initialize-ProcessorDatabase {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        & $WriteLog "Initializing processor database..."
        
        # Create the processor database connection
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Create collection_handlers table if it doesn't exist
        $createTableCommand = $connection.CreateCommand()
        $createTableCommand.CommandText = @"
CREATE TABLE IF NOT EXISTS collection_handlers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    collection_id INTEGER NOT NULL,
    collection_name TEXT NOT NULL,
    handler_script TEXT NOT NULL,
    handler_params TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
"@
        $null = $createTableCommand.ExecuteNonQuery()
        
        $connection.Close()
        $connection.Dispose()
        
        & $WriteLog "Processor database initialized successfully."
        return $true
    }
    catch {
        & $WriteLog "Error initializing processor database: $_" -Level "ERROR"
        return $false
    }
}

function Get-CollectionHandler {
    param (
        [Parameter(Mandatory=$true)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT * FROM collection_handlers WHERE collection_name = @CollectionName"
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionName", $CollectionName)))
        
        $reader = $command.ExecuteReader()
        
        $processor = $null
        if ($reader.Read()) {
            $processor = [PSCustomObject]@{
                Id = $reader["id"]
                CollectionId = $reader["collection_id"]
                CollectionName = $reader["collection_name"]
                HandlerScript = $reader["handler_script"]
                HandlerParams = $reader["handler_params"]
                CreatedAt = $reader["created_at"]
                UpdatedAt = $reader["updated_at"]
            }
            
            # Parse the processor params if they exist
            if ($processor.HandlerParams) {
                try {
                    $processor.HandlerParams = ConvertFrom-Json $processor.HandlerParams -AsHashtable
                }
                catch {
                    & $WriteLog "Error parsing processor params for collection '$CollectionName': $_" -Level "WARNING"
                    $processor.HandlerParams = @{}
                }
            }
            else {
                $processor.HandlerParams = @{}
            }
        }
        
        $reader.Close()
        $connection.Close()
        $connection.Dispose()
        
        return $processor
    }
    catch {
        & $WriteLog "Error getting collection processor: $_" -Level "ERROR"
        return $null
    }
}

function Set-CollectionHandler {
    param (
        [Parameter(Mandatory=$true)]
        [int]$CollectionId,
        
        [Parameter(Mandatory=$true)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [string]$HandlerScript,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$HandlerParams = @{},
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        # Check if a processor already exists for this collection
        $checkCommand = $connection.CreateCommand()
        $checkCommand.CommandText = "SELECT id FROM collection_handlers WHERE collection_name = @CollectionName"
        $checkCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionName", $CollectionName)))
        
        $existingId = $checkCommand.ExecuteScalar()
        $paramsJson = (ConvertTo-Json $HandlerParams -Depth 10 -Compress)
        
        if ($existingId) {
            # Update existing processor
            $updateCommand = $connection.CreateCommand()
            $updateCommand.CommandText = @"
UPDATE collection_handlers 
SET handler_script = @HandlerScript, 
    handler_params = @HandlerParams,
    updated_at = CURRENT_TIMESTAMP
WHERE id = @Id
"@
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@Id", $existingId)))
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@HandlerScript", $HandlerScript)))
            $updateCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@HandlerParams", $paramsJson)))
            
            $updateCommand.ExecuteNonQuery()
            & $WriteLog "Updated processor for collection '$CollectionName'."
        }
        else {
            # Insert new processor
            $insertCommand = $connection.CreateCommand()
            $insertCommand.CommandText = @"
INSERT INTO collection_handlers 
(collection_id, collection_name, handler_script, handler_params) 
VALUES 
(@CollectionId, @CollectionName, @HandlerScript, @HandlerParams)
"@
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionId", $CollectionId)))
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionName", $CollectionName)))
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@HandlerScript", $HandlerScript)))
            $insertCommand.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@HandlerParams", $paramsJson)))
            
            $insertCommand.ExecuteNonQuery()
            & $WriteLog "Added new processor for collection '$CollectionName'."
        }
        
        $connection.Close()
        $connection.Dispose()
        
        return $true
    }
    catch {
        & $WriteLog "Error setting collection processor: $_" -Level "ERROR"
        return $false
    }
}

function Remove-CollectionHandler {
    param (
        [Parameter(Mandatory=$true)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        
        $command = $connection.CreateCommand()
        $command.CommandText = "DELETE FROM collection_handlers WHERE collection_name = @CollectionName"
        $command.Parameters.Add((New-Object Microsoft.Data.Sqlite.SqliteParameter("@CollectionName", $CollectionName)))
        
        $rowsAffected = $command.ExecuteNonQuery()
        
        $connection.Close()
        $connection.Dispose()
        
        if ($rowsAffected -gt 0) {
            & $WriteLog "Removed processor for collection '$CollectionName'."
            return $true
        }
        else {
            & $WriteLog "No processor found for collection '$CollectionName'." -Level "WARNING"
            return $false
        }
    }
    catch {
        & $WriteLog "Error removing collection processor: $_" -Level "ERROR"
        return $false
    }
}

function Get-ProcessorScriptsCount {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        $connection = Get-DatabaseConnection -DatabasePath $DatabasePath
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT COUNT(*) FROM collection_handlers"
        $count = $command.ExecuteScalar()
        $connection.Close()
        $connection.Dispose()
        return $count
    }
    catch {
        & $WriteLog "Error getting processor scripts count: $_" -Level "ERROR"
        return 0
    }
}

Export-ModuleMember -Function Initialize-ProcessorDatabase, Get-CollectionHandler, Set-CollectionHandler, Remove-CollectionHandler, Get-ProcessorScriptsCount
