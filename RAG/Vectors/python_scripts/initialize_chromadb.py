#!/usr/bin/env python3
"""
ChromaDB Initialization Script
This script initializes ChromaDB collections for document and chunk storage.
"""

import os
import sys
import argparse
import chromadb
from chromadb.config import Settings


def initialize_chromadb(chroma_db_path: str) -> bool:
    """
    Initialize ChromaDB collections for document and chunk storage.
    
    Args:
        chroma_db_path: Path to the ChromaDB storage directory
        
    Returns:
        bool: True if initialization was successful, False otherwise
    """
    try:
        # Create output directory if it doesn't exist
        if not os.path.exists(chroma_db_path):
            os.makedirs(chroma_db_path)
            print(f"SUCCESS:Created ChromaDB directory: {chroma_db_path}")
        
        # Setup ChromaDB client
        chroma_client = chromadb.PersistentClient(
            path=chroma_db_path, 
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
        
        return True
        
    except Exception as e:
        print(f"ERROR:{str(e)}", file=sys.stderr)
        return False


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Initialize ChromaDB collections for document and chunk storage"
    )
    parser.add_argument(
        "chroma_db_path",
        help="Path to the ChromaDB storage directory"
    )
    
    args = parser.parse_args()
    
    # Perform initialization
    success = initialize_chromadb(args.chroma_db_path)
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
