# Common logging module for Ollama-RAG-Sync
# Provides centralized logging functionality with multiple output levels and formats

<#
.SYNOPSIS
    Writes a log message with timestamp and level.

.DESCRIPTION
    Writes a formatted log message to the console with timestamp, level, and optional color coding.
    Messages can be filtered by log level.

.PARAMETER Message
    The message to log.

.PARAMETER Level
    The log level: DEBUG, INFO, WARNING, ERROR, or CRITICAL.

.PARAMETER Component
    Optional component name to include in the log message.

.EXAMPLE
    Write-Log -Message "Processing started" -Level "INFO"

.EXAMPLE
    Write-Log -Message "Failed to connect" -Level "ERROR" -Component "VectorsAPI"
#>
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory = $false)]
        [string]$Component
    )
    
    # Get minimum log level from environment (defaults to INFO)
    $minLevel = $env:OLLAMA_RAG_LOG_LEVEL ?? "INFO"
    $levelOrder = @{
        "DEBUG" = 0
        "INFO" = 1
        "WARNING" = 2
        "ERROR" = 3
        "CRITICAL" = 4
    }
    
    # Skip if message level is below minimum level
    if ($levelOrder[$Level] -lt $levelOrder[$minLevel]) {
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Build log message
    $logMessage = "[$timestamp] [$Level]"
    if ($Component) {
        $logMessage += " [$Component]"
    }
    $logMessage += " $Message"
    
    # Determine color based on level
    $color = switch ($Level) {
        "DEBUG" { "Gray" }
        "INFO" { "White" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "CRITICAL" { "Magenta" }
        default { "White" }
    }
    
    # Write to console
    Write-Host $logMessage -ForegroundColor $color
    
    # Optionally write to log file if path is configured
    $logFile = $env:OLLAMA_RAG_LOG_FILE
    if ($logFile) {
        try {
            Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
        }
        catch {
            # Silently fail if we can't write to log file
        }
    }
}

<#
.SYNOPSIS
    Writes a debug log message.

.DESCRIPTION
    Convenience function for writing DEBUG level log messages.

.PARAMETER Message
    The message to log.

.PARAMETER Component
    Optional component name.

.EXAMPLE
    Write-LogDebug -Message "Variable value: $myVar"
#>
function Write-LogDebug {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Component
    )
    
    Write-Log -Message $Message -Level "DEBUG" -Component $Component
}

<#
.SYNOPSIS
    Writes an info log message.

.DESCRIPTION
    Convenience function for writing INFO level log messages.

.PARAMETER Message
    The message to log.

.PARAMETER Component
    Optional component name.

.EXAMPLE
    Write-LogInfo -Message "Operation completed successfully"
#>
function Write-LogInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Component
    )
    
    Write-Log -Message $Message -Level "INFO" -Component $Component
}

<#
.SYNOPSIS
    Writes a warning log message.

.DESCRIPTION
    Convenience function for writing WARNING level log messages.

.PARAMETER Message
    The message to log.

.PARAMETER Component
    Optional component name.

.EXAMPLE
    Write-LogWarning -Message "Configuration value not found, using default"
#>
function Write-LogWarning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Component
    )
    
    Write-Log -Message $Message -Level "WARNING" -Component $Component
}

<#
.SYNOPSIS
    Writes an error log message.

.DESCRIPTION
    Convenience function for writing ERROR level log messages.

.PARAMETER Message
    The message to log.

.PARAMETER Component
    Optional component name.

.PARAMETER Exception
    Optional exception object to include in the log.

.EXAMPLE
    Write-LogError -Message "Failed to connect to database" -Exception $_.Exception
#>
function Write-LogError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Component,
        
        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception
    )
    
    $fullMessage = $Message
    if ($Exception) {
        $fullMessage += "`nException: $($Exception.Message)"
        if ($Exception.InnerException) {
            $fullMessage += "`nInner Exception: $($Exception.InnerException.Message)"
        }
    }
    
    Write-Log -Message $fullMessage -Level "ERROR" -Component $Component
}

<#
.SYNOPSIS
    Writes a critical log message.

.DESCRIPTION
    Convenience function for writing CRITICAL level log messages.

.PARAMETER Message
    The message to log.

.PARAMETER Component
    Optional component name.

.EXAMPLE
    Write-LogCritical -Message "System failure, shutting down"
#>
function Write-LogCritical {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$Component
    )
    
    Write-Log -Message $Message -Level "CRITICAL" -Component $Component
}

# Export functions
Export-ModuleMember -Function Write-Log, Write-LogDebug, Write-LogInfo, Write-LogWarning, Write-LogError, Write-LogCritical
