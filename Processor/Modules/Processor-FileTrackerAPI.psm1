# Processor-API.psm1
# Contains functions for interacting with the FileTracker API

function Get-Collections {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        $uri = "$FileTrackerBaseUrl/collections"
        
        $response = Invoke-RestMethod -Uri $uri -Method Get
        
        if ($response.success) {
            return $response.collections
        }
        else {
            & $WriteLog "Error fetching collections: $($response.error)" -Level "ERROR"
            return $null
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API $uri to get collections: $_" -Level "ERROR"
        return $null
    }
}

function Get-CollectionIdByName {
    param (
        [Parameter(Mandatory=$true)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    try {
        # Get all collections
        $collections = Get-Collections -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
        
        if ($null -eq $collections) {
            & $WriteLog "Failed to retrieve collections" -Level "ERROR"
            return $null
        }
        
        # Find collection by name
        $collection = $collections | Where-Object { $_.name -eq $CollectionName }
        
        if ($null -eq $collection) {
            & $WriteLog "Collection with name '$CollectionName' not found" -Level "ERROR"
            return $null
        }
        
        return $collection.id
    }
    catch {
        & $WriteLog "Error finding collection ID by name: $_" -Level "ERROR"
        return $null
    }
}

function Get-CollectionDirtyFiles {
    param (
        [Parameter(Mandatory=$false)]
        [int]$CollectionId,
        
        [Parameter(Mandatory=$false)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    # Ensure either CollectionId or CollectionName is provided
    if (-not $CollectionId -and -not $CollectionName) {
        & $WriteLog "Either CollectionId or CollectionName must be provided" -Level "ERROR"
        return $null
    }
    
    # If CollectionId is not provided but CollectionName is, get the ID from name
    if (-not $CollectionId -and $CollectionName) {
        $CollectionId = Get-CollectionIdByName -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
        
        if (-not $CollectionId) {
            return $null
        }
    }
    
    try {
        $uri = "$FileTrackerBaseUrl/collections/$CollectionId/files?dirty=true"
        
        $response = Invoke-RestMethod -Uri $uri -Method Get
        
        if ($response.success) {
            return $response.files
        }
        else {
            & $WriteLog "Error fetching dirty files for collection $CollectionId`: $($response.error)" -Level "ERROR"
            return $null
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API to get dirty files: $_" -Level "ERROR"
        return $null
    }
}

function Get-CollectionDeletedFiles {
    param (
        [Parameter(Mandatory=$false)]
        [int]$CollectionId,
        
        [Parameter(Mandatory=$false)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    # Ensure either CollectionId or CollectionName is provided
    if (-not $CollectionId -and -not $CollectionName) {
        & $WriteLog "Either CollectionId or CollectionName must be provided" -Level "ERROR"
        return $null
    }
    
    # If CollectionId is not provided but CollectionName is, get the ID from name
    if (-not $CollectionId -and $CollectionName) {
        $CollectionId = Get-CollectionIdByName -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
        
        if (-not $CollectionId) {
            return $null
        }
    }
    
    try {
        $uri = "$FileTrackerBaseUrl/collections/$CollectionId/files?deleted=true"
        
        $response = Invoke-RestMethod -Uri $uri -Method Get
        
        if ($response.success) {
            return $response.files
        }
        else {
            & $WriteLog "Error fetching deleted files for collection $CollectionId`: $($response.error)" -Level "ERROR"
            return $null
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API to get deleted files: $_" -Level "ERROR"
        return $null
    }
}

function Get-FileDetails {
    param (
        [Parameter(Mandatory=$false)]
        [int]$CollectionId,
        
        [Parameter(Mandatory=$false)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [int]$FileId,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    # Ensure either CollectionId or CollectionName is provided
    if (-not $CollectionId -and -not $CollectionName) {
        & $WriteLog "Either CollectionId or CollectionName must be provided" -Level "ERROR"
        return $null
    }
    
    # If CollectionId is not provided but CollectionName is, get the ID from name
    if (-not $CollectionId -and $CollectionName) {
        $CollectionId = Get-CollectionIdByName -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
        
        if (-not $CollectionId) {
            return $null
        }
    }
    
    try {
        $uri = "$FileTrackerBaseUrl/collections/$CollectionId/files/$FileId"
        $response = Invoke-RestMethod -Uri $uri -Method Get
        
        if ($response.success) {
            return $response.file
        }
        else {
            & $WriteLog "Error fetching file details: $($response.error)" -Level "ERROR"
            return $null
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API to get file details: $_" -Level "ERROR"
        return $null
    }
}

function Mark-FileAsProcessed {
    param (
        [Parameter(Mandatory=$false)]
        [int]$CollectionId,
        
        [Parameter(Mandatory=$false)]
        [string]$CollectionName,
        
        [Parameter(Mandatory=$true)]
        [int]$FileId,
        
        [Parameter(Mandatory=$true)]
        [string]$FileTrackerBaseUrl,
        
        [Parameter(Mandatory=$true)]
        [scriptblock]$WriteLog
    )
    
    # Ensure either CollectionId or CollectionName is provided
    if (-not $CollectionId -and -not $CollectionName) {
        & $WriteLog "Either CollectionId or CollectionName must be provided" -Level "ERROR"
        return $false
    }
    
    # If CollectionId is not provided but CollectionName is, get the ID from name
    if (-not $CollectionId -and $CollectionName) {
        $CollectionId = Get-CollectionIdByName -CollectionName $CollectionName -FileTrackerBaseUrl $FileTrackerBaseUrl -WriteLog $WriteLog
        
        if (-not $CollectionId) {
            return $false
        }
    }
    
    try {
        $uri = "$FileTrackerBaseUrl/collections/$CollectionId/files/$FileId"
        $body = @{
            dirty = $false
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $uri -Method Put -Body $body -ContentType "application/json"
        
        if ($response.success) {
            return $true
        }
        else {
            & $WriteLog "Error marking file $FileId as processed: $($response.error)" -Level "ERROR"
            return $false
        }
    }
    catch {
        & $WriteLog "Error calling FileTracker API to mark file as processed: $_" -Level "ERROR"
        return $false
    }
}

Export-ModuleMember -Function Get-Collections, Get-CollectionIdByName, Get-CollectionDirtyFiles, Get-CollectionDeletedFiles, Get-FileDetails, Mark-FileAsProcessed
