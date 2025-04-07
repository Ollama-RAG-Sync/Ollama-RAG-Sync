# Vectors-Core.psm1
# Core functionality for the Vectors subsystem

# Import required modules for output formatting
using namespace System.Management.Automation
using namespace System.Collections.Generic

# Module version
$script:ModuleVersion = "1.0.0"

# Default configuration
$script:DefaultConfig = @{
    OllamaUrl = "http://localhost:11434"
    EmbeddingModel = "mxbai-embed-large:latest"
    ChunkSize = 1000
    ChunkOverlap = 200
    SupportedExtensions = ".txt,.md,.html,.csv,.json"
    LogLevel = "Info"  # Debug, Info, Warning, Error
}

# Current configuration (defaults plus any user overrides)
$script:Config = $script:DefaultConfig.Clone()

<#
.SYNOPSIS
    Initializes the Vectors subsystem configuration
.DESCRIPTION
    Sets up the configuration for the Vectors subsystem, optionally overriding defaults
.PARAMETER ConfigOverrides
    A hashtable containing configuration values to override defaults
.EXAMPLE
    Initialize-VectorsConfig -ConfigOverrides @{ ChunkSize = 500; ChunkOverlap = 100 }
#>
function Initialize-VectorsConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [hashtable]$ConfigOverrides = @{}
    )

    # Start with defaults
    $script:Config = $script:DefaultConfig.Clone()
    
    # Override with user configuration
    foreach ($key in $ConfigOverrides.Keys) {
        if ($script:Config.ContainsKey($key)) {
            $script:Config[$key] = $ConfigOverrides[$key]
            Write-VectorsLog -Message "Configuration override: $key = $($ConfigOverrides[$key])" -Level "Debug"
        } else {
            Write-VectorsLog -Message "Unknown configuration key: $key" -Level "Warning"
        }
    }

    # Ensure ChromaDB path exists
    if (-not (Test-Path -Path $script:Config.ChromaDbPath)) {
        New-Item -Path $script:Config.ChromaDbPath -ItemType Directory -Force | Out-Null
        Write-VectorsLog -Message "Created ChromaDB directory: $($script:Config.ChromaDbPath)" -Level "Info"
    }

    Write-VectorsLog -Message "Vectors configuration initialized" -Level "Info"
    
    # Return the config
    return $script:Config
}

<#
.SYNOPSIS
    Gets the current Vectors subsystem configuration
.DESCRIPTION
    Returns the current configuration for the Vectors subsystem
.EXAMPLE
    Get-VectorsConfig
#>
function Get-VectorsConfig {
    [CmdletBinding()]
    param ()
    
    return $script:Config
}

<#
.SYNOPSIS
    Logs messages for the Vectors subsystem
.DESCRIPTION
    Logs messages at different levels (Debug, Info, Warning, Error)
.PARAMETER Message
    The message to log
.PARAMETER Level
    The log level (Debug, Info, Warning, Error)
.EXAMPLE
    Write-VectorsLog -Message "Processing document" -Level "Info"
#>
function Write-VectorsLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string]$Level = "Info"
    )

    # Check if we should log this level
    $levelPriority = @{
        "Debug" = 0
        "Info" = 1
        "Warning" = 2
        "Error" = 3
    }
    
    $configLevelPriority = $levelPriority[$script:Config.LogLevel]
    $messageLevelPriority = $levelPriority[$Level]
    
    if ($messageLevelPriority -ge $configLevelPriority) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $levelString = $Level.ToUpper().PadRight(7)
        
        $color = switch($Level) {
            "Debug" { "Gray" }
            "Info" { "Cyan" }
            "Warning" { "Yellow" }
            "Error" { "Red" }
            default { "White" }
        }
        
        $formattedMessage = "[$timestamp] $levelString - $Message"
        Write-Host $formattedMessage -ForegroundColor $color
    }
}

<#
.SYNOPSIS
    Checks if all Vectors subsystem requirements are met
.DESCRIPTION
    Validates that all required dependencies are installed and accessible
.EXAMPLE
    Test-VectorsRequirements
#>
function Test-VectorsRequirements {
    [CmdletBinding()]
    param ()
    
    $requirements = @()
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    $isPSValid = $psVersion.Major -ge 7
    $requirements += [PSCustomObject]@{
        Name = "PowerShell 7+"
        Status = if ($isPSValid) { "Passed" } else { "Failed" }
        Details = "Version $psVersion detected"
    }
    
    # Check Python
    try {
        $pythonVersion = python --version 2>&1
        $isPythonValid = $true
        $requirements += [PSCustomObject]@{
            Name = "Python"
            Status = "Passed"
            Details = $pythonVersion
        }
    } catch {
        $isPythonValid = $false
        $requirements += [PSCustomObject]@{
            Name = "Python"
            Status = "Failed"
            Details = "Python not found or not in PATH"
        }
    }
    
    # Check Ollama availability
    try {
        $ollamaTest = Invoke-RestMethod -Uri "$($script:Config.OllamaUrl)/api/tags" -Method Get -ErrorAction Stop
        $isOllamaValid = $true
        $requirements += [PSCustomObject]@{
            Name = "Ollama API"
            Status = "Passed"
            Details = "Accessible at $($script:Config.OllamaUrl)"
        }

        # Check if embedding model is available
        $modelAvailable = $ollamaTest.models | Where-Object { $_.name -eq $script:Config.EmbeddingModel }
        if ($modelAvailable) {
            $requirements += [PSCustomObject]@{
                Name = "Embedding Model"
                Status = "Passed"
                Details = "$($script:Config.EmbeddingModel) is available"
            }
        } else {
            $modelNames = ($ollamaTest.models | ForEach-Object { $_.name }) -join ", "
            $requirements += [PSCustomObject]@{
                Name = "Embedding Model"
                Status = "Warning"
                Details = "$($script:Config.EmbeddingModel) not found. Available models: $modelNames"
            }
        }
    } catch {
        $isOllamaValid = $false
        $requirements += [PSCustomObject]@{
            Name = "Ollama API"
            Status = "Failed"
            Details = "Ollama not accessible at $($script:Config.OllamaUrl). Error: $($_.Exception.Message)"
        }
    }
    
    # Check ChromaDB Python package
    try {
        $chromaTest = python -c "import chromadb; print('ChromaDB version:', chromadb.__version__)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $isChromaValid = $true
            $requirements += [PSCustomObject]@{
                Name = "ChromaDB Package"
                Status = "Passed"
                Details = $chromaTest
            }
        } else {
            $isChromaValid = $false
            $requirements += [PSCustomObject]@{
                Name = "ChromaDB Package"
                Status = "Failed"
                Details = "ChromaDB Python package not installed"
            }
        }
    } catch {
        $isChromaValid = $false
        $requirements += [PSCustomObject]@{
            Name = "ChromaDB Package"
            Status = "Failed"
            Details = "Error checking ChromaDB: $($_.Exception.Message)"
        }
    }
    
    # Display results
    $requirements | Format-Table -AutoSize
    
    # Check if all critical requirements are met
    return ($isPSValid -and $isPythonValid -and $isChromaValid)
}

<#
.SYNOPSIS
    Gets the file content as text and validates it
.DESCRIPTION
    Reads a file, validates its extension, and returns its content as text
.PARAMETER FilePath
    Path to the file to read
.EXAMPLE
    Get-FileContent -FilePath "path/to/document.md"
#>
function Get-FileContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    # Verify the file path exists
    if (-not (Test-Path -Path $FilePath)) {
        Write-VectorsLog -Message "The specified file path does not exist: $FilePath" -Level "Error"
        return $null
    }
    
    # Check if file has a supported extension
    $fileExtension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $supportedExtensions = $script:Config.SupportedExtensions.Split(',') | ForEach-Object { $_.Trim().ToLower() }
    
    if (-not ($supportedExtensions -contains $fileExtension)) {
        Write-VectorsLog -Message "The file extension '$fileExtension' is not supported." -Level "Error"
        Write-VectorsLog -Message "Supported extensions: $($script:Config.SupportedExtensions)" -Level "Error"
        return $null
    }
    
    # Read the file content
    try {
        $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-VectorsLog -Message "The file is empty: $FilePath" -Level "Warning"
            return $null
        }
        return $content
    } catch {
        Write-VectorsLog -Message "Error reading file: $($_.Exception.Message)" -Level "Error"
        return $null
    }
}

# Export functions
Export-ModuleMember -Function Initialize-VectorsConfig, Get-VectorsConfig, Write-VectorsLog, Test-VectorsRequirements, Get-FileContent
