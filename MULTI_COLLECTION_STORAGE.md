# Multi-Collection Storage Implementation

## Overview

Documents are now automatically stored in **both** the "default" collection and any specifically named collection when added to the vector store. This ensures documents are always available in the default collection while also being organized in named collections.

## Changes Made

### 1. Modified `Vectors-Embeddings.psm1`

The `Add-DocumentToVectorStore` function now:
- Always creates/uses a "default" collection
- If a collection name is specified (and it's not "default"), also stores in that named collection
- Loops through both collections and stores the document + chunks in each
- Updates metadata to reflect the correct collection name for each storage location

**Key Implementation:**
```python
# Always use both "default" and the specified collection
collection_names_to_use = ["default"]
if collection_name and collection_name.lower() != "default":
    collection_names_to_use.append(collection_name)

# Iterate through each collection to store in
for coll_name in collection_names_to_use:
    # Create/get collections: {coll_name}_documents and {coll_name}_chunks
    # Store document and chunks in each collection
```

### 2. Modified `Add-DocumentToVectors.ps1`

Removed the automatic concatenation of embedding model to collection name:
- **Before:** `CollectionName = $CollectionName + "_" + $EmbeddingModel`
- **After:** `CollectionName = $CollectionName`

This allows clean collection naming without model suffixes.

## Behavior

### Example 1: Default Collection Only
```powershell
Add-DocumentToVectors.ps1 -FilePath "doc.txt" -CollectionName "default"
```
**Result:** Document stored in `default_documents` and `default_chunks` collections (once)

### Example 2: Named Collection
```powershell
Add-DocumentToVectors.ps1 -FilePath "doc.txt" -CollectionName "technical"
```
**Result:** Document stored in:
- `default_documents` and `default_chunks` collections
- `technical_documents` and `technical_chunks` collections

### Example 3: Querying
```powershell
# Query default collection (all documents)
Query-VectorChunks -QueryText "search term" -CollectionName "default"

# Query specific collection (subset of documents)
Query-VectorChunks -QueryText "search term" -CollectionName "technical"
```

## Benefits

1. **Universal Access:** All documents are always available in the "default" collection
2. **Organization:** Documents can be organized into topic-specific collections
3. **Flexibility:** Query either the full dataset (default) or specific subsets (named collections)
4. **Consistency:** No duplicate document IDs - same document appears in multiple collections with same ID
5. **Metadata Tracking:** Each instance includes the correct collection name in metadata

## Collection Structure

For a document added with `CollectionName = "technical"`:

```
ChromaDB
├── default_documents     (contains the document)
├── default_chunks        (contains all chunks)
├── technical_documents   (contains the document)
└── technical_chunks      (contains all chunks)
```

## Migration Notes

- Existing documents in single collections are not automatically migrated
- New documents will be stored in both default and named collections
- Old queries will continue to work with their specified collection names
- To consolidate, re-process existing documents through the updated system

## Performance Considerations

- Storage space: Documents are duplicated across collections (minimal overhead for embeddings)
- Write time: Slightly longer due to multiple collection writes (typically negligible)
- Query time: No impact - queries target specific collections as before
- Recommended: Use default collection for broad searches, named collections for filtered searches

## Technical Details

- Document IDs remain consistent across all collections
- Metadata includes `"collection": "{coll_name}"` to track which collection each instance belongs to
- Deletion from one collection does not affect other collections
- Each collection maintains independent HNSW indices for optimal search performance
