# Init-ProcessorForCollection.ps1
# Sets up a collection handler with a given scriptblock and saves it into the database

#Requires -Version 7.0

param(
    [Parameter(Mandatory=$true)]
    [string]$CollectionName,
    
    [Parameter(Mandatory=$false)]
    [int]$CollectionId,
    
    [Parameter(Mandatory=$true)]
    [scriptblock]$HandlerScript,
    
    [Parameter(Mandatory=$false)]
    [hashtable]$HandlerParams = @{},
    
    [Parameter(Mandatory=$false)]
    [string]$DatabasePath
)

# Import required modules
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentPath = Split-Path -Parent $scriptPath
$databaseSharedModule = Join-Path -Path $parentPath -ChildPath "FileTracker\Database-Shared.psm1"

# Import FileTracker's shared database module
Import-Module $databaseSharedModule -Force

# Import processor database module
$processorDatabaseModule = Join-Path -Path $scriptPath -ChildPath "Modules\Processor-Database.psm1"
Import-Module $processorDatabaseModule -Force

# If DatabasePath is not provided, use the default path
if (-not $DatabasePath) {
    $DatabasePath = Get-DefaultDatabasePath -InstallPath $InstallPath
    Write-Host "Using default database path: $DatabasePath" -ForegroundColor Cyan
}

# Ensure temp directory exists for logs
$appDataDir = Join-Path -Path $env:APPDATA -ChildPath "FileTracker"
$TempDir = Join-Path -Path $appDataDir -ChildPath "temp"
if (-not (Test-Path -Path $TempDir)) {
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
}

# Initialize log file
$logDate = Get-Date -Format "yyyy-MM-dd"
$logFileName = "Init-ProcessorForCollection_$logDate.log"
$logFilePath = Join-Path -Path $TempDir -ChildPath $logFileName

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with appropriate color
    if ($Level -eq "ERROR") {
        Write-Host $logMessage -ForegroundColor Red
    }
    elseif ($Level -eq "WARNING") {
        Write-Host $logMessage -ForegroundColor Yellow
    }
    elseif ($Verbose -or $Level -eq "INFO") {
        Write-Host $logMessage -ForegroundColor Green
    }
    
    # Write to log file
    Add-Content -Path $logFilePath -Value $logMessage
}

# Create Write-Log scriptblock for passing to module functions
$WriteLogBlock = {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    Write-Log -Message $Message -Level $Level
}

# Initialize the database
Initialize-ProcessorDatabase -DatabasePath $DatabasePath -WriteLog $WriteLogBlock

try {
    Write-Log "Initializing collection processor for '$CollectionName' (ID: $CollectionId)..."
    
    # Convert the scriptblock to string for storage
    $handlerScriptString = $HandlerScript.ToString()
    
    Write-Log "Handler script parameters: $(ConvertTo-Json $HandlerParams -Compress)"
    
    # Set the collection handler in the database
    $result = Set-CollectionHandler -CollectionId $CollectionId -CollectionName $CollectionName `
        -HandlerScript $handlerScriptString -HandlerParams $HandlerParams -DatabasePath $DatabasePath -WriteLog $WriteLogBlock
    
    if ($result) {
        Write-Log "Collection processor successfully initialized for '$CollectionName'"
        Write-Host "Successfully set handler for collection '$CollectionName'" -ForegroundColor Green
    }
    else {
        Write-Log "Failed to initialize collection processor for '$CollectionName'" -Level "ERROR"
        Write-Host "Failed to set handler for collection '$CollectionName'" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Log "Error initializing collection processor: $_" -Level "ERROR"
    Write-Host "Error initializing collection processor: $_" -ForegroundColor Red
    exit 1
}

Write-Log "Script execution completed"
Write-Host "Script execution completed. Log file: $logFilePath" -ForegroundColor Cyan
