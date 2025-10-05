# TestHelpers.psm1
# Shared utilities for testing across all RAG components

<#
.SYNOPSIS
    Creates a temporary test database
.DESCRIPTION
    Sets up an isolated SQLite database for testing purposes
.EXAMPLE
    $testDb = New-TestDatabase
#>
function New-TestDatabase {
    [CmdletBinding()]
    param()
    
    $tempPath = [System.IO.Path]::GetTempPath()
    $testDbPath = Join-Path $tempPath "test_$(New-Guid).db"
    
    return [PSCustomObject]@{
        Path = $testDbPath
        Created = Get-Date
    }
}

<#
.SYNOPSIS
    Removes a test database and cleans up resources
.DESCRIPTION
    Safely removes test database files
.PARAMETER TestDatabase
    The test database object to clean up
.EXAMPLE
    Remove-TestDatabase -TestDatabase $testDb
#>
function Remove-TestDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$TestDatabase
    )
    
    if (Test-Path -Path $TestDatabase.Path) {
        try {
            Remove-Item -Path $TestDatabase.Path -Force -ErrorAction Stop
            Write-Verbose "Test database removed: $($TestDatabase.Path)"
        } catch {
            Write-Warning "Failed to remove test database: $_"
        }
    }
}

<#
.SYNOPSIS
    Creates a temporary test directory with sample files
.DESCRIPTION
    Sets up a test directory structure with various file types
.PARAMETER FileCount
    Number of test files to create
.PARAMETER FileTypes
    Array of file extensions to create
.EXAMPLE
    $testDir = New-TestDirectory -FileCount 5 -FileTypes @('.txt', '.md')
#>
function New-TestDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [int]$FileCount = 3,
        
        [Parameter(Mandatory=$false)]
        [string[]]$FileTypes = @('.txt', '.md', '.json')
    )
    
    $tempPath = [System.IO.Path]::GetTempPath()
    $testDirPath = Join-Path $tempPath "test_dir_$(New-Guid)"
    
    New-Item -Path $testDirPath -ItemType Directory -Force | Out-Null
    
    $createdFiles = @()
    
    for ($i = 1; $i -le $FileCount; $i++) {
        $extension = $FileTypes[($i - 1) % $FileTypes.Count]
        $fileName = "test_file_$i$extension"
        $filePath = Join-Path $testDirPath $fileName
        
        $content = "This is test file $i`nCreated at: $(Get-Date)`nContent type: $extension"
        Set-Content -Path $filePath -Value $content -Encoding UTF8
        
        $createdFiles += $filePath
    }
    
    return [PSCustomObject]@{
        Path = $testDirPath
        Files = $createdFiles
        Created = Get-Date
    }
}

<#
.SYNOPSIS
    Removes a test directory and all its contents
.DESCRIPTION
    Safely removes test directories
.PARAMETER TestDirectory
    The test directory object to clean up
.EXAMPLE
    Remove-TestDirectory -TestDirectory $testDir
#>
function Remove-TestDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$TestDirectory
    )
    
    if (Test-Path -Path $TestDirectory.Path) {
        try {
            Remove-Item -Path $TestDirectory.Path -Recurse -Force -ErrorAction Stop
            Write-Verbose "Test directory removed: $($TestDirectory.Path)"
        } catch {
            Write-Warning "Failed to remove test directory: $_"
        }
    }
}

<#
.SYNOPSIS
    Creates a mock Ollama API response
.DESCRIPTION
    Generates mock embedding data for testing
.PARAMETER Dimensions
    Number of dimensions in the embedding vector
.EXAMPLE
    $mockEmbedding = New-MockEmbedding -Dimensions 768
#>
function New-MockEmbedding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [int]$Dimensions = 768
    )
    
    $embedding = @()
    $random = New-Object System.Random
    
    for ($i = 0; $i -lt $Dimensions; $i++) {
        $embedding += $random.NextDouble() * 2 - 1  # Random between -1 and 1
    }
    
    return $embedding
}

<#
.SYNOPSIS
    Creates a test configuration object
.DESCRIPTION
    Generates a configuration object with test values and ensures SQLite is installed
.EXAMPLE
    $config = New-TestConfig
#>
function New-TestConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$InstallPath,
        
        [Parameter(Mandatory=$false)]
        [string]$OllamaUrl = "http://localhost:11434",
        
        [Parameter(Mandatory=$false)]
        [string]$EmbeddingModel = "mxbai-embed-large:latest"
    )
    
    if ([string]::IsNullOrEmpty($InstallPath)) {
        $tempPath = [System.IO.Path]::GetTempPath()
        $InstallPath = Join-Path $tempPath "test_install_$(New-Guid)"
        New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
    }

    # Ensure SQLite assemblies are installed for tests
    Write-Verbose "Installing SQLite assemblies for testing..."
    $installScript = Join-Path $PSScriptRoot "..\FileTracker\Install-FileTracker.ps1"
    if (Test-Path $installScript) {
        & $installScript -InstallPath $InstallPath | Out-Null
    } else {
        Write-Warning "Could not find Install-FileTracker.ps1 to install SQLite assemblies"
    }
    
    # Import Database-Shared module and initialize SQLite environment
    $databaseModulePath = Join-Path $PSScriptRoot "..\FileTracker\Database-Shared.psm1"
    if (Test-Path $databaseModulePath) {
        Import-Module $databaseModulePath -Force -Global
        
        # Initialize SQLite environment with the install path
        $initResult = Initialize-SqliteEnvironment -InstallPath $InstallPath
        if (-not $initResult) {
           Write-Warning "Failed to initialize SQLite environment in test configuration"
        }
    } else {
        Write-Warning "Could not find Database-Shared.psm1 to initialize SQLite environment"
    }

    
    return [PSCustomObject]@{
        InstallPath = $InstallPath
        OllamaUrl = $OllamaUrl
        EmbeddingModel = $EmbeddingModel
        ChunkSize = 20
        ChunkOverlap = 2
        FileTrackerPort = 19003
        VectorsPort = 19001
        IsTestConfig = $true
    }
}

<#
.SYNOPSIS
    Waits for an API endpoint to become available
.DESCRIPTION
    Polls an endpoint until it responds or timeout is reached
.PARAMETER Uri
    The URI to check
.PARAMETER TimeoutSeconds
    Maximum time to wait in seconds
.EXAMPLE
    Wait-ForEndpoint -Uri "http://localhost:10001/api/health" -TimeoutSeconds 30
#>
function Wait-ForEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,
        
        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 30
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try {
            $null = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 2 -ErrorAction Stop
            Write-Verbose "Endpoint available: $Uri"
            return $true
        } catch {
            Write-Verbose "Waiting for endpoint: $Uri"
            Start-Sleep -Milliseconds 500
        }
    }
    
    Write-Warning "Endpoint not available after $TimeoutSeconds seconds: $Uri"
    return $false
}

<#
.SYNOPSIS
    Asserts that two values are equal
.DESCRIPTION
    Throws an exception if values are not equal
.PARAMETER Expected
    The expected value
.PARAMETER Actual
    The actual value
.PARAMETER Message
    Optional message to display on failure
.EXAMPLE
    Assert-Equal -Expected 5 -Actual $result
#>
function Assert-Equal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Expected,
        
        [Parameter(Mandatory=$true)]
        $Actual,
        
        [Parameter(Mandatory=$false)]
        [string]$Message = "Values are not equal"
    )
    
    if ($Expected -ne $Actual) {
        throw "$Message. Expected: '$Expected', Actual: '$Actual'"
    }
}

<#
.SYNOPSIS
    Asserts that a value is not null or empty
.DESCRIPTION
    Throws an exception if value is null or empty
.PARAMETER Value
    The value to check
.PARAMETER Message
    Optional message to display on failure
.EXAMPLE
    Assert-NotNullOrEmpty -Value $result
#>
function Assert-NotNullOrEmpty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $Value,
        
        [Parameter(Mandatory=$false)]
        [string]$Message = "Value is null or empty"
    )
    
    if ([string]::IsNullOrEmpty($Value)) {
        throw $Message
    }
}

# Export all functions
Export-ModuleMember -Function New-TestDatabase, Remove-TestDatabase, 
                                New-TestDirectory, Remove-TestDirectory,
                                New-MockEmbedding, New-TestConfig,
                                Wait-ForEndpoint, Assert-Equal, 
                                Assert-NotNullOrEmpty
