param 
(    
    [Parameter(Mandatory=$true)]
    [string]$ChromaDbPath
)

    # Use Python to initialize the database
    $tempPythonScript = [System.IO.Path]::GetTempFileName() + ".py"

    $pythonCode = @"
import os
import sys
import chromadb
from chromadb.config import Settings

try:
    # Create output directory if it doesn't exist
    output_folder = r'$ChromaDbPath'
    if not os.path.exists(output_folder):
        os.makedirs(output_folder)
        print(f"SUCCESS:Created ChromaDB directory: {output_folder}")
    
    # Setup ChromaDB client
    chroma_client = chromadb.PersistentClient(
        path=output_folder, 
        settings=Settings(anonymized_telemetry=False)
    )
    
    # Get or create document collection
    doc_collection = chroma_client.get_or_create_collection(
        name="default_collection",
        metadata={
            "hnsw:space": "cosine",
            "hnsw:search_ef": 100
        }
    )
    print(f"SUCCESS:Initialized document_collection")
    
    # Get or create chunks collection
    chunks_collection = chroma_client.get_or_create_collection(
        name="default_chunks_collection",
        metadata={
            "hnsw:space": "cosine",
            "hnsw:search_ef": 100
        }
    )
    print(f"SUCCESS:Initialized document_chunks_collection")
    
    # Count documents in collections
    doc_count = doc_collection.count()
    chunks_count = chunks_collection.count()
    print(f"INFO:document_collection contains {doc_count} documents")
    print(f"INFO:document_chunks_collection contains {chunks_count} chunks")
    
except Exception as e:
    print(f"ERROR:{str(e)}")
    sys.exit(1)
"@

    $pythonCode | Out-File -FilePath $tempPythonScript -Encoding utf8
    Write-Host -Message "Initializing ChromaDB collections at $ChromaDbPath" 
    
    # Execute the Python script
    try {
        $results = python $tempPythonScript 2>&1
        
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
        
        # Clean up
        Remove-Item -Path $tempPythonScript -Force
        
        return $true
    }
    catch {
        Write-Host -Message "Failed to initialize vector database: $($_.Exception.Message)" 
        
        # Clean up
        if (Test-Path -Path $tempPythonScript) {
            Remove-Item -Path $tempPythonScript -Force
        }
        
        return $false
    }
