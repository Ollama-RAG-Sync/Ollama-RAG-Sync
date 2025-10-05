# Test-Reranking.ps1
# Test script to demonstrate reranking functionality in Query-VectorChunks

param(
    [Parameter(Mandatory=$false)]
    [string]$InstallPath = "C:\RAG2",
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaUrl = "http://localhost:11434",
    
    [Parameter(Mandatory=$false)]
    [string]$EmbeddingModel = "mxbai-embed-large:latest",
    
    [Parameter(Mandatory=$false)]
    [string]$RerankModel = "",
    
    [Parameter(Mandatory=$false)]
    [string]$CollectionName = "default",
    
    [Parameter(Mandatory=$false)]
    [string]$QueryText = "How do I implement RAG?",
    
    [Parameter(Mandatory=$false)]
    [string]$LogLevel = "Info"
)

# Import required modules
$scriptsPath = Split-Path -Parent $PSScriptRoot
Import-Module "$scriptsPath\Modules\Vectors-Core.psm1" -Force
Import-Module "$scriptsPath\Modules\Vectors-Database.psm1" -Force

Write-Host "=== Testing Query-VectorChunks with Reranking ===" -ForegroundColor Cyan
Write-Host ""

# Initialize configuration
$config = Initialize-VectorsConfig -ConfigOverrides @{
    ChromaDbPath = Join-Path -Path $InstallPath -ChildPath "Chroma.db"
    OllamaUrl = $OllamaUrl
    EmbeddingModel = $EmbeddingModel
    LogLevel = $LogLevel
}

Write-Host "Configuration:" -ForegroundColor Yellow
$config | Format-Table -AutoSize
Write-Host ""

Write-Host "Test Query: '$QueryText'" -ForegroundColor Yellow
Write-Host ""

# Test 1: Query without reranking
Write-Host "=== Test 1: Query WITHOUT Reranking ===" -ForegroundColor Green
Write-Host "Retrieving top 5 chunks..." -ForegroundColor Gray
$resultsNoRerank = Query-VectorChunks -QueryText $QueryText -MaxResults 5 -CollectionName $CollectionName

if ($resultsNoRerank -and $resultsNoRerank.Count -gt 0) {
    Write-Host "Results (without reranking):" -ForegroundColor Yellow
    for ($i = 0; $i -lt $resultsNoRerank.Count; $i++) {
        $result = $resultsNoRerank[$i]
        Write-Host "`n[$($i+1)] Similarity: $([math]::Round($result.similarity, 4))" -ForegroundColor Cyan
        Write-Host "    Source: $($result.source)" -ForegroundColor Gray
        Write-Host "    Chunk Preview: $($result.chunk.Substring(0, [Math]::Min(150, $result.chunk.Length)))..." -ForegroundColor Gray
    }
} else {
    Write-Host "No results found (database may be empty or not initialized)" -ForegroundColor Red
}

Write-Host "`n`n=== Test 2: Query WITH Reranking ===" -ForegroundColor Green
Write-Host "Retrieving top 15 chunks, then reranking to top 5..." -ForegroundColor Gray

# Test 2: Query with reranking
$rerankParams = @{
    QueryText = $QueryText
    MaxResults = 5
    CollectionName = $CollectionName
    EnableReranking = $true
    RerankTopK = 15
}

if (-not [string]::IsNullOrEmpty($RerankModel)) {
    $rerankParams.RerankModel = $RerankModel
}

$resultsWithRerank = Query-VectorChunks @rerankParams

if ($resultsWithRerank -and $resultsWithRerank.Count -gt 0) {
    Write-Host "Results (with reranking):" -ForegroundColor Yellow
    for ($i = 0; $i -lt $resultsWithRerank.Count; $i++) {
        $result = $resultsWithRerank[$i]
        Write-Host "`n[$($i+1)] Combined Score: $([math]::Round($result.similarity, 4))" -ForegroundColor Cyan
        
        if ($result.PSObject.Properties['rerank_score']) {
            Write-Host "    Rerank Score: $([math]::Round($result.rerank_score, 4))" -ForegroundColor Magenta
            Write-Host "    Original Similarity: $([math]::Round($result.original_similarity, 4))" -ForegroundColor DarkGray
        }
        
        Write-Host "    Source: $($result.source)" -ForegroundColor Gray
        Write-Host "    Chunk Preview: $($result.chunk.Substring(0, [Math]::Min(150, $result.chunk.Length)))..." -ForegroundColor Gray
    }
} else {
    Write-Host "No results found (database may be empty or not initialized)" -ForegroundColor Red
}

Write-Host "`n`n=== Test 3: Query with Reranking and Aggregation ===" -ForegroundColor Green
Write-Host "Retrieving and reranking, then aggregating by document..." -ForegroundColor Gray

# Test 3: Query with reranking and aggregation
$aggregateParams = @{
    QueryText = $QueryText
    MaxResults = 3
    CollectionName = $CollectionName
    EnableReranking = $true
    RerankTopK = 20
    AggregateByDocument = $true
}

if (-not [string]::IsNullOrEmpty($RerankModel)) {
    $aggregateParams.RerankModel = $RerankModel
}

$resultsAggregated = Query-VectorChunks @aggregateParams

if ($resultsAggregated -and $resultsAggregated.Count -gt 0) {
    Write-Host "Results (aggregated by document with reranking):" -ForegroundColor Yellow
    for ($i = 0; $i -lt $resultsAggregated.Count; $i++) {
        $doc = $resultsAggregated[$i]
        Write-Host "`n[$($i+1)] Source: $($doc.source)" -ForegroundColor Cyan
        Write-Host "    Average Similarity: $([math]::Round($doc.avg_similarity, 4))" -ForegroundColor Magenta
        Write-Host "    Total Chunks: $($doc.chunk_count)" -ForegroundColor Gray
        Write-Host "    Top Chunks:" -ForegroundColor Yellow
        
        for ($j = 0; $j -lt [Math]::Min(3, $doc.chunks.Count); $j++) {
            $chunk = $doc.chunks[$j]
            Write-Host "      [$($j+1)] Score: $([math]::Round($chunk.similarity, 4))" -ForegroundColor DarkCyan
            if ($chunk.PSObject.Properties['rerank_score']) {
                Write-Host "          Rerank: $([math]::Round($chunk.rerank_score, 4)) | Original: $([math]::Round($chunk.original_similarity, 4))" -ForegroundColor DarkGray
            }
            Write-Host "          Preview: $($chunk.chunk.Substring(0, [Math]::Min(100, $chunk.chunk.Length)))..." -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "No results found (database may be empty or not initialized)" -ForegroundColor Red
}

Write-Host "`n`n=== Test 4: Document Query WITHOUT Reranking ===" -ForegroundColor Green
Write-Host "Retrieving top 3 full documents..." -ForegroundColor Gray

# Test 4: Document query without reranking
$docsNoRerank = Query-VectorDocuments -QueryText $QueryText -MaxResults 3 -CollectionName $CollectionName

if ($docsNoRerank -and $docsNoRerank.Count -gt 0) {
    Write-Host "Results (documents without reranking):" -ForegroundColor Yellow
    for ($i = 0; $i -lt $docsNoRerank.Count; $i++) {
        $doc = $docsNoRerank[$i]
        Write-Host "`n[$($i+1)] Similarity: $([math]::Round($doc.similarity, 4))" -ForegroundColor Cyan
        Write-Host "    Source: $($doc.source)" -ForegroundColor Gray
        Write-Host "    ID: $($doc.id)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "No results found (database may be empty or not initialized)" -ForegroundColor Red
}

Write-Host "`n`n=== Test 5: Document Query WITH Reranking ===" -ForegroundColor Green
Write-Host "Retrieving top 10 documents, then reranking to top 3..." -ForegroundColor Gray

# Test 5: Document query with reranking
$docRerankParams = @{
    QueryText = $QueryText
    MaxResults = 3
    CollectionName = $CollectionName
    EnableReranking = $true
    RerankTopK = 10
}

if (-not [string]::IsNullOrEmpty($RerankModel)) {
    $docRerankParams.RerankModel = $RerankModel
}

$docsWithRerank = Query-VectorDocuments @docRerankParams

if ($docsWithRerank -and $docsWithRerank.Count -gt 0) {
    Write-Host "Results (documents with reranking):" -ForegroundColor Yellow
    for ($i = 0; $i -lt $docsWithRerank.Count; $i++) {
        $doc = $docsWithRerank[$i]
        Write-Host "`n[$($i+1)] Combined Score: $([math]::Round($doc.similarity, 4))" -ForegroundColor Cyan
        
        if ($doc.PSObject.Properties['rerank_score']) {
            Write-Host "    Rerank Score: $([math]::Round($doc.rerank_score, 4))" -ForegroundColor Magenta
            Write-Host "    Original Similarity: $([math]::Round($doc.original_similarity, 4))" -ForegroundColor DarkGray
        }
        
        Write-Host "    Source: $($doc.source)" -ForegroundColor Gray
        Write-Host "    ID: $($doc.id)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "No results found (database may be empty or not initialized)" -ForegroundColor Red
}

Write-Host "`n`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "- Without reranking (chunks): Retrieved $($resultsNoRerank.Count) chunks" -ForegroundColor Gray
Write-Host "- With reranking (chunks): Retrieved $($resultsWithRerank.Count) chunks with improved relevance" -ForegroundColor Gray
Write-Host "- With aggregation (chunks): Retrieved $($resultsAggregated.Count) documents with top chunks" -ForegroundColor Gray
Write-Host "- Without reranking (docs): Retrieved $($docsNoRerank.Count) documents" -ForegroundColor Gray
Write-Host "- With reranking (docs): Retrieved $($docsWithRerank.Count) documents with improved relevance" -ForegroundColor Gray
Write-Host ""
Write-Host "Reranking uses LLM-based scoring to improve relevance:" -ForegroundColor Green
Write-Host "  - Retrieves more initial candidates (RerankTopK)" -ForegroundColor Gray
Write-Host "  - Scores each chunk/document's relevance to the query using an LLM" -ForegroundColor Gray
Write-Host "  - Combines vector similarity (30%) with rerank score (70%)" -ForegroundColor Gray
Write-Host "  - Returns the top MaxResults after reranking" -ForegroundColor Gray
