# Reranking in Query Functions

## Overview

Reranking is an advanced feature that improves the relevance of search results by applying a secondary scoring mechanism after the initial vector similarity search. This two-stage approach combines the efficiency of vector search with the semantic understanding of Large Language Models (LLMs).

**Available in both:**
- `Query-VectorChunks` - For searching document chunks
- `Query-VectorDocuments` - For searching full documents

## How It Works

### Stage 1: Vector Similarity Search
1. The query text is converted to an embedding vector
2. ChromaDB performs a fast vector similarity search
3. Returns the top K candidates (where K > desired final results)

### Stage 2: LLM-Based Reranking
1. Each candidate chunk is evaluated by an LLM
2. The LLM scores how relevant the chunk is to the query (0.0 to 1.0)
3. A combined score is calculated:
   - **30% Vector Similarity** (from Stage 1)
   - **70% Rerank Score** (from LLM evaluation)
4. Results are re-sorted by combined score
5. Top N results are returned

## Benefits

- **Improved Relevance**: LLM-based scoring captures semantic relevance better than vector similarity alone
- **Context-Aware**: The LLM understands query intent and can identify truly relevant passages
- **Flexibility**: Can retrieve more candidates initially and refine to the most relevant ones
- **Better User Experience**: Users get more accurate and useful search results

## Usage

### Basic Usage - Chunks

```powershell
# Query chunks with reranking enabled
$results = Query-VectorChunks `
    -QueryText "How do I implement RAG?" `
    -MaxResults 5 `
    -EnableReranking
```

### Basic Usage - Documents

```powershell
# Query full documents with reranking enabled
$results = Query-VectorDocuments `
    -QueryText "How do I implement RAG?" `
    -MaxResults 5 `
    -EnableReranking
```

### Advanced Usage - Chunks

```powershell
# Query chunks with custom reranking parameters
$results = Query-VectorChunks `
    -QueryText "How do I implement RAG?" `
    -MaxResults 5 `
    -EnableReranking `
    -RerankTopK 20 `
    -RerankModel "llama3"
```

### Advanced Usage - Documents

```powershell
# Query documents with custom reranking parameters
$results = Query-VectorDocuments `
    -QueryText "How do I implement RAG?" `
    -MaxResults 5 `
    -EnableReranking `
    -RerankTopK 15 `
    -RerankModel "llama3" `
    -ReturnSourceContent
```

### With Aggregation (Chunks Only)

```powershell
# Query chunks with reranking and document aggregation
$results = Query-VectorChunks `
    -QueryText "How do I implement RAG?" `
    -MaxResults 3 `
    -EnableReranking `
    -RerankTopK 30 `
    -AggregateByDocument
```

### Using the Wrapper Functions

```powershell
# Using Get-ChunksByQuery wrapper with reranking
$results = .\Get-ChunksByQuery.ps1 `
    -QueryText "How do I implement RAG?" `
    -MaxResults 5 `
    -EnableReranking `
    -RerankTopK 15 `
    -ChromaDbPath "C:\RAG\VectorStore"

# Using Get-DocumentsByQuery wrapper with reranking
$results = .\Get-DocumentsByQuery.ps1 `
    -QueryText "How do I implement RAG?" `
    -MaxResults 5 `
    -EnableReranking `
    -RerankTopK 10 `
    -ChromaDbPath "C:\RAG\VectorStore"
```

## Parameters

### EnableReranking
- **Type**: Switch
- **Default**: False
- **Description**: Enables LLM-based reranking of search results

### RerankModel
- **Type**: String
- **Default**: Uses the embedding model from config
- **Description**: The Ollama model to use for reranking
- **Recommended**: "llama3", "mistral", or other instruction-following models

### RerankTopK
- **Type**: Integer
- **Default**: MaxResults * 3
- **Description**: Number of candidates to retrieve before reranking
- **Recommendation**: Should be 2-5x larger than MaxResults for best results

## Result Format

When reranking is enabled, each result includes additional fields:

```powershell
@{
    id = "chunk_id"
    source = "path/to/document.md"
    chunk = "...chunk content..."
    metadata = @{ ... }
    similarity = 0.85              # Combined score (30% vector + 70% rerank)
    rerank_score = 0.92            # LLM relevance score (0.0-1.0)
    original_similarity = 0.78     # Original vector similarity score
}
```

## Performance Considerations

### Latency
- **Vector Search Only**: ~50-200ms
- **With Reranking**: ~2-5 seconds (depends on RerankTopK and model)
- Each candidate chunk requires an LLM inference call

### Optimization Tips

1. **Adjust RerankTopK**: Start with 2-3x MaxResults
2. **Use Faster Models**: Smaller models like "llama3" are faster than larger ones
3. **Batch When Possible**: If searching multiple queries, consider running them sequentially
4. **Cache Results**: Cache frequently accessed queries

### When to Use Reranking

**✅ Use Reranking When:**
- Accuracy is more important than speed
- Query is complex or ambiguous
- Initial results need refinement
- Working with diverse document types

**❌ Skip Reranking When:**
- Speed is critical
- Vector similarity is already accurate
- Queries are simple keyword matches
- Working with large result sets (>50 items)

## Configuration

Default reranking behavior can be configured in `Vectors-Core.psm1`:

```powershell
$script:DefaultConfig = @{
    # ... existing config ...
    RerankingEnabled = $false
    DefaultRerankModel = "llama3"
    DefaultRerankMultiplier = 3  # RerankTopK = MaxResults * Multiplier
}
```

## Examples

### Example 1: Simple Comparison (Chunks)

```powershell
# Without reranking
$basic = Query-VectorChunks -QueryText "RAG implementation" -MaxResults 5

# With reranking
$reranked = Query-VectorChunks -QueryText "RAG implementation" -MaxResults 5 -EnableReranking

# Compare results
Write-Host "Basic Results:"
$basic | ForEach-Object { Write-Host "  [$($_.similarity)] $($_.source)" }

Write-Host "`nReranked Results:"
$reranked | ForEach-Object { 
    Write-Host "  [Combined: $($_.similarity), Rerank: $($_.rerank_score)] $($_.source)" 
}
```

### Example 2: Simple Comparison (Documents)

```powershell
# Without reranking
$basicDocs = Query-VectorDocuments -QueryText "RAG implementation" -MaxResults 5

# With reranking
$rerankedDocs = Query-VectorDocuments -QueryText "RAG implementation" -MaxResults 5 -EnableReranking

# Compare results
Write-Host "Basic Document Results:"
$basicDocs | ForEach-Object { Write-Host "  [$($_.similarity)] $($_.source)" }

Write-Host "`nReranked Document Results:"
$rerankedDocs | ForEach-Object { 
    Write-Host "  [Combined: $($_.similarity), Rerank: $($_.rerank_score)] $($_.source)" 
}
```

### Example 3: Finding the Best Document

```powershell
# Retrieve many chunks, rerank, and aggregate by document
$bestDocs = Query-VectorChunks `
    -QueryText "How does the FileTracker system work?" `
    -MaxResults 5 `
    -EnableReranking `
    -RerankTopK 50 `
    -AggregateByDocument

# Display the best document with its top chunks
$topDoc = $bestDocs[0]
Write-Host "Best Document: $($topDoc.source)"
Write-Host "Average Score: $($topDoc.avg_similarity)"
Write-Host "Top Chunks:"
$topDoc.chunks | Select-Object -First 3 | ForEach-Object {
    Write-Host "  [Score: $($_.similarity)] $($_.chunk.Substring(0, 100))..."
}
```

### Example 4: Testing Different Models

```powershell
$query = "Explain vector embeddings"
$models = @("llama3", "mistral", "phi3")

foreach ($model in $models) {
    Write-Host "`nTesting with $model..."
    
    # Test with chunks
    $chunkResults = Query-VectorChunks `
        -QueryText $query `
        -MaxResults 5 `
        -EnableReranking `
        -RerankModel $model
    
    # Test with documents
    $docResults = Query-VectorDocuments `
        -QueryText $query `
        -MaxResults 5 `
        -EnableReranking `
        -RerankModel $model
    
    Write-Host "Chunks - Top result score: $($chunkResults[0].similarity)"
    Write-Host "Documents - Top result score: $($docResults[0].similarity)"
}
```

## Troubleshooting

### Slow Performance
- Reduce `RerankTopK` value
- Use a faster/smaller model
- Check Ollama server performance

### Poor Reranking Quality
- Try a different model (some models are better at relevance scoring)
- Increase `RerankTopK` to give more candidates
- Check that your query is clear and specific

### Timeout Errors
- Increase timeout in Python code (currently 30 seconds)
- Reduce `RerankTopK`
- Ensure Ollama server has sufficient resources

## Technical Details

### Scoring Algorithm

```python
# Original vector similarity (cosine similarity)
original_similarity = 1 - distance

# LLM relevance score (0.0 to 1.0)
rerank_score = llm_evaluate(query, chunk)

# Combined score (weighted average)
combined_score = (original_similarity * 0.3) + (rerank_score * 0.7)
```

### Prompt Template

The LLM prompt for reranking:

```
On a scale of 0.0 to 1.0, rate how relevant the following text passage is to answering this query.
Respond with ONLY a number between 0.0 and 1.0, nothing else.

Query: {query}

Passage: {chunk_text}

Relevance score:
```

## Future Enhancements

Potential improvements to reranking:

1. **Batch Reranking**: Evaluate multiple chunks in a single LLM call
2. **Custom Weights**: Allow users to adjust the 30/70 weight split
3. **Multiple Models**: Use different models for different document types
4. **Caching**: Cache rerank scores to avoid redundant LLM calls
5. **Adaptive Reranking**: Automatically adjust RerankTopK based on query complexity

## References

- [Vector Search Best Practices](https://www.pinecone.io/learn/vector-search/)
- [Reranking in Information Retrieval](https://arxiv.org/abs/2104.08663)
- [Ollama API Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)
