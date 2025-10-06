param 
(    
    [Parameter(Mandatory=$true)]
    [string]$ChromaDbPath
)

    # Get the path to the Python script
    $scriptDir = Split-Path -Parent $PSScriptRoot
    $pythonScriptPath = Join-Path $scriptDir "python_scripts\initialize_chromadb.py"
    
    if (-not (Test-Path -Path $pythonScriptPath)) {
        Write-Host -Message "Python script not found: $pythonScriptPath" 
        return $false
    }
    
    Write-Host -Message "Initializing ChromaDB collections at $ChromaDbPath" 
    
    # Execute the Python script
    try {
        $results = python $pythonScriptPath $ChromaDbPath 2>&1
        
        # Process the output
        foreach ($line in $results) {
            if ($line -match "^SUCCESS:(.*)$") {
                $successData = $Matches[1]
                Write-Host -Message $successData 
            }
            elseif ($line -match "^ERROR:(.*)$") {
                $errorData = $Matches[1]
                Write-Host -Message "ChromaDB error: $errorData" 
                return $false
            }
            elseif ($line -match "^INFO:(.*)$") {
                $infoData = $Matches[1]
                Write-Host -Message $infoData 
            }
        }
        
        return $true
    }
    catch {
        Write-Host -Message "Failed to initialize vector database: $($_.Exception.Message)" 
        return $false
    }
