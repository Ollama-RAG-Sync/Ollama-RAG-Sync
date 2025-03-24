<#
.SYNOPSIS
    Marks a file to be processed in the SQLite database.
.DESCRIPTION
    This script updates a file's status in the SQLite database by setting its "ToProcess" flag to true,
    indicating that the file needs to be processed.
.PARAMETER FilePath
    The full path of the file to mark for processing.
.PARAMETER DatabasePath
    The path to the SQLite database. Either this or FolderPath must be specified.
.PARAMETER FolderPath
    The path to the monitored folder. If specified instead of DatabasePath, the script will
    automatically compute the database path as [FolderPath]\.ai\FileTracker.db.
.PARAMETER All
    If specified, marks all files currently not flagged for processing to be processed.
.EXAMPLE
    .\Mark-FileAsToProcess.ps1 -FilePath "D:\MyDocuments\document.txt" -DatabasePath "D:\FileTracker\FileTracker.db"
.EXAMPLE
    .\Mark-FileAsToProcess.ps1 -All -DatabasePath "D:\FileTracker\FileTracker.db"
.EXAMPLE
    .\Mark-FileAsToProcess.ps1 -FilePath "D:\MyDocuments\document.txt" -FolderPath "D:\MyDocuments"
    # This will use the database at "D:\MyDocuments\.ai\FileTracker.db"
.EXAMPLE
    .\Mark-FileAsToProcess.ps1 -All -FolderPath "D:\MyDocuments"
    # This will mark all files for processing using the database at "D:\MyDocuments\.ai\FileTracker.db"
#>

param (
    [Parameter(Mandatory = $true, ParameterSetName = "SingleFile")]
    [string]$FilePath,
    
    [Parameter(Mandatory = $false, ParameterSetName = "SingleFile")]
    [Parameter(Mandatory = $false, ParameterSetName = "AllFiles")]
    [string]$DatabasePath,
    
    [Parameter(Mandatory = $false, ParameterSetName = "SingleFile")]
    [Parameter(Mandatory = $false, ParameterSetName = "AllFiles")]
    [string]$FolderPath,
    
    [Parameter(Mandatory = $true, ParameterSetName = "AllFiles")]
    [switch]$All
)

# Import the shared module
$scriptPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
Import-Module -Name (Join-Path -Path $scriptPath -ChildPath "FileTracker-Shared.psm1") -Force

# Call the shared function with ToProcess = $true (marking for processing)
$params = @{
    Dirty = $true  # Mark for processing
}

# Add appropriate parameters based on what was provided
if ($PSCmdlet.ParameterSetName -eq "SingleFile") {
    $params.Add("FilePath", $FilePath)
}
else {
    $params.Add("All", $true)
}

if ($DatabasePath) {
    $params.Add("DatabasePath", $DatabasePath)
}

if ($FolderPath) {
    $params.Add("FolderPath", $FolderPath)
}

# Call the shared function
Update-FileProcessingStatus @params
