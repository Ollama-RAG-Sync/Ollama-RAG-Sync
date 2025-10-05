# Common validation module for Ollama-RAG-Sync
# Provides reusable validation functions for parameters and inputs

<#
.SYNOPSIS
    Validates that a path exists and creates it if needed.

.DESCRIPTION
    Checks if a directory exists and optionally creates it.

.PARAMETER Path
    The path to validate.

.PARAMETER Create
    Whether to create the path if it doesn't exist.

.PARAMETER ErrorMessage
    Custom error message if validation fails.

.RETURNS
    $true if path exists or was created successfully.

.EXAMPLE
    Test-PathExists -Path "C:\MyDir" -Create -ErrorMessage "Failed to create directory"
#>
function Test-PathExists {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [switch]$Create,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = "Path does not exist: $Path"
    )
    
    if (Test-Path -Path $Path) {
        return $true
    }
    
    if ($Create) {
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            return $true
        }
        catch {
            throw $ErrorMessage + " - $_"
        }
    }
    
    throw $ErrorMessage
}

<#
.SYNOPSIS
    Validates that a port number is in valid range.

.DESCRIPTION
    Checks if a port number is between 1 and 65535.

.PARAMETER Port
    The port number to validate.

.PARAMETER ErrorMessage
    Custom error message if validation fails.

.RETURNS
    $true if port is valid.

.EXAMPLE
    Test-PortValid -Port 10001
#>
function Test-PortValid {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$Port,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage
    )
    
    if ($Port -lt 1 -or $Port -gt 65535) {
        $msg = if ($ErrorMessage) { $ErrorMessage } else { "Port must be between 1 and 65535. Got: $Port" }
        throw $msg
    }
    
    return $true
}

<#
.SYNOPSIS
    Validates that required environment variables are set.

.DESCRIPTION
    Checks if one or more environment variables are set and not empty.

.PARAMETER VariableNames
    Array of environment variable names to check.

.PARAMETER Scope
    The scope to check: Process, User, or Machine.

.RETURNS
    Hashtable of variable names and their values.

.EXAMPLE
    Test-EnvironmentVariables -VariableNames @("OLLAMA_RAG_INSTALL_PATH", "OLLAMA_RAG_VECTORS_API_PORT")
#>
function Test-EnvironmentVariables {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$VariableNames,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Process", "User", "Machine")]
        [string]$Scope = "User"
    )
    
    $result = @{}
    $missing = @()
    
    foreach ($varName in $VariableNames) {
        $value = [System.Environment]::GetEnvironmentVariable($varName, $Scope)
        if ([string]::IsNullOrWhiteSpace($value)) {
            $missing += $varName
        }
        else {
            $result[$varName] = $value
        }
    }
    
    if ($missing.Count -gt 0) {
        throw "Missing required environment variables: $($missing -join ', '). Please run Setup-RAG.ps1 first."
    }
    
    return $result
}

<#
.SYNOPSIS
    Validates that a URL is well-formed.

.DESCRIPTION
    Checks if a URL string is valid and properly formatted.

.PARAMETER Url
    The URL to validate.

.PARAMETER RequireScheme
    Whether to require http or https scheme.

.RETURNS
    $true if URL is valid.

.EXAMPLE
    Test-UrlValid -Url "http://localhost:11434" -RequireScheme
#>
function Test-UrlValid {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,
        
        [Parameter(Mandatory = $false)]
        [switch]$RequireScheme
    )
    
    try {
        $uri = [System.Uri]$Url
        
        if ($RequireScheme -and ($uri.Scheme -ne "http" -and $uri.Scheme -ne "https")) {
            throw "URL must use http or https scheme. Got: $($uri.Scheme)"
        }
        
        return $true
    }
    catch {
        throw "Invalid URL format: $Url - $_"
    }
}

<#
.SYNOPSIS
    Validates that a value is within a specified range.

.DESCRIPTION
    Checks if a numeric value is between minimum and maximum values (inclusive).

.PARAMETER Value
    The value to validate.

.PARAMETER Minimum
    The minimum allowed value.

.PARAMETER Maximum
    The maximum allowed value.

.PARAMETER ParameterName
    The parameter name for error messages.

.RETURNS
    $true if value is in range.

.EXAMPLE
    Test-ValueInRange -Value 20 -Minimum 1 -Maximum 100 -ParameterName "ChunkSize"
#>
function Test-ValueInRange {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$Value,
        
        [Parameter(Mandatory = $true)]
        [int]$Minimum,
        
        [Parameter(Mandatory = $true)]
        [int]$Maximum,
        
        [Parameter(Mandatory = $false)]
        [string]$ParameterName = "Value"
    )
    
    if ($Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "$ParameterName must be between $Minimum and $Maximum. Got: $Value"
    }
    
    return $true
}

<#
.SYNOPSIS
    Sanitizes a file path to prevent directory traversal attacks.

.DESCRIPTION
    Validates and normalizes a file path to ensure it doesn't contain malicious patterns.

.PARAMETER Path
    The path to sanitize.

.PARAMETER BasePath
    Optional base path to restrict access to.

.RETURNS
    Sanitized absolute path.

.EXAMPLE
    $safePath = Get-SanitizedPath -Path "..\..\etc\passwd" -BasePath "C:\SafeDir"
#>
function Get-SanitizedPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        
        [Parameter(Mandatory = $false)]
        [string]$BasePath
    )
    
    # Convert to absolute path
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        throw "Invalid path format: $Path"
    }
    
    # If base path is provided, ensure the path is within it
    if ($BasePath) {
        $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
        if (-not $fullPath.StartsWith($baseFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Path '$Path' is outside the allowed base path '$BasePath'"
        }
    }
    
    return $fullPath
}

# Export functions
Export-ModuleMember -Function Test-PathExists, Test-PortValid, Test-EnvironmentVariables, Test-UrlValid, Test-ValueInRange, Get-SanitizedPath
