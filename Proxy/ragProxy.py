import chromadb
import json
import requests
import sys
import os
from chromadb.config import Settings
from chromadb.utils import embedding_functions

def get_models_from_ollama(base_url, include_details=False):
    """Get available models from Ollama API"""
    url = f"{base_url}/api/tags"
    
    try:
        response = requests.get(url)
        response.raise_for_status()
        result = response.json()
        
        if 'models' in result:
            models = result['models']
            
            # If include_details is False, just return model names
            if not include_details:
                model_names = [model['name'] for model in models]
                return {
                    "models": model_names,
                    "count": len(model_names)
                }
            else:
                return {
                    "models": models,
                    "count": len(models)
                }
        else:
            print(f"Error: Unexpected response format - {result}", file=sys.stderr)
            return {"error": "Unexpected response format"}
    except Exception as e:
        print(f"Error getting models: {str(e)}", file=sys.stderr)
        return {"error": f"Error getting models: {str(e)}"}
        
def get_embedding_from_ollama(text, model, base_url):
    """Get embeddings from Ollama API"""
    url = f"{base_url}/api/embeddings"
    
    data = {
        "model": model,
        "prompt": text
    }
    
    try:
        response = requests.post(url, json=data)
        response.raise_for_status()
        result = response.json()
        
        if 'embedding' in result:
            return result['embedding']
        else:
            print(f"Error: Unexpected response format - {result}", file=sys.stderr)
            return None
    except Exception as e:
        print(f"Error getting embedding: {str(e)}", file=sys.stderr)
        return None

def query_chroma(query_text, db_path, embedding_model, base_url, n_results=5, threshold=0.75, query_mode="both", chunk_weight=0.6, document_weight=0.4):
    """Query ChromaDB for relevant documents from both document and chunks collections
    
    Args:
        query_text (str): The query text to search for
        db_path (str): Path to the ChromaDB database
        embedding_model (str): The embedding model to use
        base_url (str): Ollama API base URL
        n_results (int): Maximum number of results to return
        threshold (float): Minimum similarity threshold (0-1)
        query_mode (str): Which collections to query: "chunks", "documents", or "both"
        chunk_weight (float): Weight to apply to chunk results (0-1) when in "both" mode
        document_weight (float): Weight to apply to document results (0-1) when in "both" mode
        
    Returns:
        dict: Dictionary containing results, count, and document names
    """
    try:
        # Get embedding for query
        query_embedding = get_embedding_from_ollama(query_text, embedding_model, base_url)
        if not query_embedding:
            return {"error": "Failed to get embedding for query"}
        
# Connect to ChromaDB
        client = chromadb.PersistentClient(path=db_path, settings=Settings(anonymized_telemetry=False))
        
        # Store doc and chunk results
        doc_results_list = []
        chunk_results_list = []
        full_doc_names = set()
        
        # Query document collection (full documents) if mode is "documents" or "both"
        if query_mode == "documents" or query_mode == "both":
            try:
                # Get or create document collection with proper distance metric
                doc_collection = client.get_collection("document_collection")
                doc_results = doc_collection.query(
                    query_embeddings=[query_embedding],
                    n_results=n_results,  # Get more results for filtering
                    include=["documents", "metadatas", "distances"]
                )
                if doc_results["distances"] and doc_results["distances"][0]:
                    # Convert cosine distances to similarity scores (1 - distance)
                    # This ensures values between 0 and 1 since cosine distance = 1 - cosine similarity
                    similarities = [1 - dist for dist in doc_results["distances"][0]]
                    for i, (doc, metadata, similarity) in enumerate(zip(doc_results["documents"][0], doc_results["metadatas"][0], similarities)):
                        if similarity >= threshold:
                            doc_name = metadata.get("source", "unknown")
                            if isinstance(doc_name, str):
                                full_doc_name = doc_name.split('/')[-1] if '/' in doc_name else doc_name.split('\\')[-1] if '\\' in doc_name else doc_name
                                full_doc_names.add(full_doc_name)
                            
                            # Apply document weight if we're in "both" mode
                            adjusted_similarity = similarity
                            if query_mode == "both":
                                adjusted_similarity = similarity * document_weight
                            
                            doc_results_list.append({
                                "document": doc,
                                "metadata": metadata,
                                "similarity": similarity,
                                "adjusted_similarity": adjusted_similarity,
                                "is_chunk": False
                            })
            except Exception as e:
                print(f"Warning: Could not query document collection: {str(e)}", file=sys.stderr)
        
        # Query chunks collection if mode is "chunks" or "both"
        if query_mode == "chunks" or query_mode == "both":
            try:
                # Get or create chunks collection with proper distance metric
                chunks_collection = client.get_collection(name="document_chunks_collection")
                chunk_results = chunks_collection.query(
                    query_embeddings=[query_embedding],
                    n_results=n_results,  # Get more results for filtering
                    include=["documents", "metadatas", "distances"]
                )
                if chunk_results["distances"] and chunk_results["distances"][0]:
                    # Convert cosine distances to similarity scores (1 - distance)
                    # This ensures values between 0 and 1 since cosine distance = 1 - cosine similarity
                    similarities = [1 - dist for dist in chunk_results["distances"][0]]
                    for i, (doc, metadata, similarity) in enumerate(zip(chunk_results["documents"][0], chunk_results["metadatas"][0], similarities)):
                        # Only include results above the threshold
                        if similarity >= threshold:
                            doc_name = metadata.get("source", "unknown")
                            if isinstance(doc_name, str):
                                full_doc_name = doc_name.split('/')[-1] if '/' in doc_name else doc_name.split('\\')[-1] if '\\' in doc_name else doc_name
                                full_doc_names.add(full_doc_name)
                            
                            # Apply chunk weight if we're in "both" mode
                            adjusted_similarity = similarity
                            if query_mode == "both":
                                adjusted_similarity = similarity * chunk_weight
                            
                            # Handle line_range for chunk data
                            # If metadata doesn't have line_range but has start_line and end_line, create it
                            updated_metadata = dict(metadata)
                            if 'line_range' not in updated_metadata and 'start_line' in updated_metadata and 'end_line' in updated_metadata:
                                updated_metadata['line_range'] = f"{updated_metadata['start_line']}-{updated_metadata['end_line']}"
                            # If neither exists, default to "unknown"
                            elif 'line_range' not in updated_metadata:
                                updated_metadata['line_range'] = "unknown"
                                
                            chunk_results_list.append({
                                "document": doc,
                                "metadata": updated_metadata,
                                "similarity": similarity,
                                "adjusted_similarity": adjusted_similarity,
                                "is_chunk": True
                            })
            except Exception as e:
                print(f"Warning: Could not query chunks collection: {str(e)}", file=sys.stderr)
        
        # Combine and process results based on query mode
        all_results = []
        
        if query_mode == "documents":
            all_results = doc_results_list
        elif query_mode == "chunks":
            all_results = chunk_results_list
        else:  # query_mode == "both"
            all_results = doc_results_list + chunk_results_list
        
        # When in "both" mode, sort by adjusted_similarity
        # Otherwise sort by the original similarity
        if query_mode == "both":
            processed_results = sorted(all_results, key=lambda x: x["adjusted_similarity"], reverse=True)
        else:
            processed_results = sorted(all_results, key=lambda x: x["similarity"], reverse=True)
        # If we have more results than requested, trim to n_results
        if len(processed_results) > n_results:
            processed_results = processed_results[:n_results]
        # Remove adjusted_similarity from final results to keep the API clean
        for result in processed_results:
            if "adjusted_similarity" in result:
                del result["adjusted_similarity"]
        return {
            "results": processed_results,
            "count": len(processed_results),
            "document_names": list(full_doc_names)
        }
    except Exception as e:
        exc_type, exc_obj, exc_tb = sys.exc_info()
        fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
        print(exc_type, fname, exc_tb.tb_lineno)
        return {"error": f"Error querying ChromaDB: {str(e)}"}

def create_collection_with_metric(client, name, embedding_function=None):
    """Helper function to create a collection with the proper distance metric
    
    Args:
        client: ChromaDB client
        name: Name of the collection
        embedding_function: Optional embedding function to use
        
    Returns:
        The created collection
    """
    try:
        # Check if collection exists
        collections = client.list_collections()
        if name in [c if isinstance(c, str) else c.name for c in collections]:
            # Get existing collection
            return client.get_collection(name=name, embedding_function=embedding_function)
        else:
            # Create new collection with cosine distance metric
            return client.create_collection(
                name=name,
                embedding_function=embedding_function,
                metadata={"hnsw:space": "cosine"}  # Explicitly set distance metric
            )
    except Exception as e:
        print(f"Error creating/getting collection: {str(e)}", file=sys.stderr)
        raise

def get_collection_stats(db_path):
    """Get statistics about collections in ChromaDB
    
    Args:
        db_path (str): Path to the ChromaDB database
        
    Returns:
        dict: Dictionary containing collection statistics
    """
    try:
        # Connect to ChromaDB
        client = chromadb.PersistentClient(path=db_path, settings=Settings(anonymized_telemetry=False))
        
        # Get list of all collection names (in Chroma v0.6.0+, list_collections only returns names)
        collection_names = client.list_collections()
        
        stats = {
            "total_collections": len(collection_names),
            "collections": []
        }
        
        total_items = 0
        
        # Get stats for each collection
        for collection_info in collection_names:
            # In v0.6.0+, each item in list_collections is just a collection name
            if isinstance(collection_info, str):
                coll_name = collection_info
            # For backward compatibility with older versions where it might be an object
            else:
                coll_name = collection_info.name
                
            coll = client.get_collection(name=coll_name)
            count = coll.count()
            total_items += count
            
            # Get sample metadata if available (for the first item)
            sample_metadata = None
            if count > 0:
                try:
                    sample = coll.get(limit=1, include=["metadatas"])
                    if sample and "metadatas" in sample and sample["metadatas"]:
                        sample_metadata = sample["metadatas"][0]
                except Exception as e:
                    print(f"Error getting sample metadata: {str(e)}", file=sys.stderr)
            
            stats["collections"].append({
                "name": coll_name,
                "count": count,
                "sample_metadata": sample_metadata
            })
        
        # Add total count
        stats["total_items"] = total_items
        
        return stats
    except Exception as e:
        exc_type, exc_obj, exc_tb = sys.exc_info()
        fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
        print(f"Error getting collection stats: {exc_type} {fname} {exc_tb.tb_lineno}", file=sys.stderr)
        return {"error": f"Error getting collection stats: {str(e)}"}

def send_chat_to_ollama(messages, model, context, base_url, temperature=0.7, num_ctx=40000, document_names=None):
    """Send chat completion request to Ollama API"""
    try:
        url = f"{base_url}/api/chat"
        
        # Prepare the request with context
        data = {
            "model": model,
            "messages": messages,
            "options": {
                "temperature": temperature,
                "num_ctx": num_ctx
            },
            "stream": False
        }
        
        # Add context if provided
        if context:
            data["context"] = context
        
        response = requests.post(url, json=data, stream=False)
        response.raise_for_status()
        result = response.json()
        return result
    except Exception as e:
        return {"error": f"Error sending chat to Ollama: {str(e)}"}

# Command handler
if __name__ == "__main__":
    command = sys.argv[1]
    
    if command == "stats":
        db_path = sys.argv[2]
        result = get_collection_stats(db_path)
        print(json.dumps(result))
    
    elif command == "query":
        query_text = sys.argv[2]
        db_path = sys.argv[3]
        embedding_model = sys.argv[4]
        base_url = sys.argv[5]
        n_results = int(sys.argv[6])
        threshold = float(sys.argv[7])
        query_mode = sys.argv[8] if len(sys.argv) > 8 else "both"
        chunk_weight = float(sys.argv[9]) if len(sys.argv) > 9 else 0.6
        document_weight = float(sys.argv[10]) if len(sys.argv) > 10 else 0.4
        
        result = query_chroma(query_text, db_path, embedding_model, base_url, n_results, threshold, 
                              query_mode, chunk_weight, document_weight)
        print(json.dumps(result))
     
    elif command == "chat":
        messages_json_path = sys.argv[2]
        model = sys.argv[3]
        context_json_path = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != "null" else None
        base_url = sys.argv[5]
        temperature = float(sys.argv[6]) if len(sys.argv) > 6 else 0.7
        num_ctx = int(sys.argv[7]) if len(sys.argv) > 7 else 40000
        
        # Read messages from file
        with open(messages_json_path, 'r', encoding='utf-8') as f:
            messages_json = f.read()
        
        messages = json.loads(messages_json)
        
        # Read context from file if provided
        context = None
        if context_json_path:
            try:
                with open(context_json_path, 'r', encoding='utf-8') as f:
                    context_json = f.read()
                context = json.loads(context_json) if context_json else None
            except Exception as e:
                print(f"Error reading context file: {str(e)}", file=sys.stderr)
       
        result = send_chat_to_ollama(messages, model, context, base_url, temperature, num_ctx)
        print(json.dumps(result))
    
    elif command == "models":
        base_url = sys.argv[2]
        include_details = sys.argv[3].lower() == "true" if len(sys.argv) > 3 else False
        
        result = get_models_from_ollama(base_url, include_details)
        print(json.dumps(result))
