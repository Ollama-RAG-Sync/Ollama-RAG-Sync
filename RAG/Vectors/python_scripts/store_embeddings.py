#!/usr/bin/env python3
"""
Vector Store Manager
Stores document and chunk embeddings in ChromaDB vector database.
"""

import os
import sys
import json
import argparse
import chromadb
import unicodedata
import datetime
from chromadb.config import Settings


def log_to_file(message, log_path):
    """Log message to file with timestamp"""
    if log_path and log_path != "()":
        try:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_entry = f"[{timestamp}] {message}\n"
            
            # Ensure directory exists
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(log_entry)
        except Exception:
            pass  # Silent fail for logging errors


def normalize_text(text):
    """Normalize text using Unicode NFKD normalization"""
    normalized = unicodedata.normalize('NFKD', text)
    return normalized


def store_embeddings_in_chromadb(
    document_embedding,
    chunks_data,
    source_path,
    document_id,
    collection_name,
    chroma_db_path,
    log_path=None
):
    """
    Store document and chunk embeddings in ChromaDB.
    
    Args:
        document_embedding (dict): Document embedding data
        chunks_data (list): List of chunk embedding data
        source_path (str): Source file path
        document_id (str): Unique document identifier
        collection_name (str): Collection name to store in
        chroma_db_path (str): Path to ChromaDB storage
        log_path (str): Optional log file path
        
    Returns:
        tuple: (success: bool, collections_used: list)
    """
    try:
        # Setup ChromaDB client
        if not os.path.exists(chroma_db_path):
            os.makedirs(chroma_db_path)
        
        chroma_client = chromadb.PersistentClient(
            path=chroma_db_path, 
            settings=Settings(anonymized_telemetry=False)
        )
        
        # Always use both "default" and the specified collection
        collection_names_to_use = ["default"]
        if collection_name and collection_name.lower() != "default":
            collection_names_to_use.append(collection_name)
        
        # Iterate through each collection to store in
        for coll_name in collection_names_to_use:
            # Get collections with dynamic names
            doc_collection_name = f"{coll_name}_documents"
            
            doc_collection = chroma_client.get_or_create_collection(
                name=doc_collection_name,
                metadata={
                    "hnsw:space": "cosine",
                    "hnsw:search_ef": 100
                }
            )
            
            chunks_collection_name = f"{coll_name}_chunks"
         
            chunks_collection = chroma_client.get_or_create_collection(
                name=chunks_collection_name,
                metadata={
                    "hnsw:space": "cosine",
                    "hnsw:search_ef": 100
                }
            )
            
            # Remove existing document
            try:
                doc_collection.delete(ids=[document_id])
                log_to_file(f"INFO:Removed existing document with ID: {document_id} from {coll_name}", log_path)
            except:
                pass
            
            try:
                doc_collection.delete(where={"source": source_path})
                log_to_file(f"INFO:Removed existing document with source: {source_path} from {coll_name}", log_path)
            except:
                pass
            
            # Remove any existing chunks for this document
            try:
                chunks_collection.delete(where={"source": source_path})
                log_to_file(f"INFO:Removed existing chunks for source: {source_path} from {coll_name}", log_path)
            except:
                pass
            
            # Add document to collection
            doc_metadata = {
                "source": source_path, 
                "collection": coll_name,
                "created_at": document_embedding.get("created_at", None)
            }
            
            if "duration" in document_embedding:
                doc_metadata["duration"] = document_embedding["duration"]

            doc_collection.add(
                documents=[normalize_text(document_embedding["text"])], 
                embeddings=[document_embedding["embedding"]],
                metadatas=[doc_metadata],
                ids=[document_id]
            )
            log_to_file(f"INFO:Added document to {coll_name} collection with ID: {document_id}", log_path)
            
            # Add chunks to collection
            documents = []
            embeddings = []
            metadatas = []
            ids = []
            
            for chunk_data in chunks_data:
                chunk_id = chunk_data["chunk_id"]
                doc_id = f"{document_id}_chunk_{chunk_id}"
                
                chunk_metadata = {
                    "source": source_path,
                    "collection": coll_name,
                    "source_id": document_id,
                    "chunk_id": chunk_id,
                    "total_chunks": len(chunks_data),
                    "start_line": chunk_data.get("start_line", 1),
                    "end_line": chunk_data.get("end_line", 1),
                    "line_range": f"{chunk_data.get('start_line', 1)}-{chunk_data.get('end_line', 1)}",
                    "created_at": chunk_data.get("created_at", None)
                }
                
                if "duration" in chunk_data:
                    chunk_metadata["duration"] = chunk_data["duration"]
                
                documents.append(normalize_text(chunk_data["text"]))
                embeddings.append(chunk_data["embedding"])
                metadatas.append(chunk_metadata)
                ids.append(doc_id)
            
            # Add all chunks to collection
            if documents:
                chunks_collection.add(
                    documents=documents,
                    embeddings=embeddings,
                    metadatas=metadatas,
                    ids=ids
                )
                log_to_file(f"INFO:Added {len(chunks_data)} chunks to {coll_name} collection", log_path)
            else:
                log_to_file(f"INFO:No chunks to add for document ID: {document_id} in {coll_name}", log_path)
        
        return True, collection_names_to_use
        
    except Exception as e:
        log_to_file(f"ERROR:{str(e)}", log_path)
        return False, []


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Store document and chunk embeddings in ChromaDB"
    )
    parser.add_argument(
        "doc_embedding_file",
        help="Path to JSON file containing document embedding"
    )
    parser.add_argument(
        "chunk_embeddings_file",
        help="Path to JSON file containing chunk embeddings"
    )
    parser.add_argument(
        "source_path",
        help="Source file path or identifier"
    )
    parser.add_argument(
        "document_id",
        help="Unique document identifier"
    )
    parser.add_argument(
        "chroma_db_path",
        help="Path to ChromaDB storage directory"
    )
    parser.add_argument(
        "--collection-name",
        default="default",
        help="Collection name (default: default)"
    )
    parser.add_argument(
        "--log-path",
        help="Path to log file"
    )
    
    args = parser.parse_args()
    
    # Read the document embedding and chunk embeddings from files
    try:
        with open(args.doc_embedding_file, 'r', encoding='utf-8') as file:
            document_embedding = json.load(file)
        
        with open(args.chunk_embeddings_file, 'r', encoding='utf-8') as file:
            chunks_data = json.load(file)
    except Exception as e:
        print(f"ERROR:Failed to read embedding files: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Store embeddings
    success, collections_used = store_embeddings_in_chromadb(
        document_embedding=document_embedding,
        chunks_data=chunks_data,
        source_path=args.source_path,
        document_id=args.document_id,
        collection_name=args.collection_name,
        chroma_db_path=args.chroma_db_path,
        log_path=args.log_path
    )
    
    if not success:
        sys.exit(1)
    
    print(f"SUCCESS:Added document to vector store with ID: {args.document_id} in collections: {', '.join(collections_used)}")
    sys.exit(0)


if __name__ == "__main__":
    main()
