# Processor-Logging.psm1
# Contains logging functions for the processor

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath,
        
        [Parameter(Mandatory=$false)]
        [bool]$Verbose = $false
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
    
    # Write to log file if path provided
    if ($LogFilePath) {
        Add-Content -Path $LogFilePath -Value $logMessage
    }
}

Export-ModuleMember -Function Write-Log
