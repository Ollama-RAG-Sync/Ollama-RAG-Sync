#!/usr/bin/env python3
"""
Document Embedding Generator
Generates vector embeddings for entire documents using Ollama.
"""

import sys
import json
import urllib.request
import urllib.error
import time
import datetime
import os
import argparse


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


def get_embedding_from_ollama(text, model="llama3", base_url="http://localhost:11434", log_path=None):
    """
    Get embeddings from Ollama API
    
    Args:
        text (str): The text to get embeddings for
        model (str): The model to use (default: "llama3")
        base_url (str): The base URL for Ollama API (default: "http://localhost:11434")
        log_path (str): Path to log file (optional)
        
    Returns:
        dict: A dictionary with "embedding" (list), "duration" (float), and "created_at" (str), or None if error.
    """
    url = f"{base_url}/api/embeddings"
    
    # Prepare request data
    data = {
        "model": model,
        "prompt": text
    }
    
    # Convert data to JSON and encode as bytes
    data_bytes = json.dumps(data).encode('utf-8')
    
    # Set headers
    headers = {
        'Content-Type': 'application/json'
    }
    
    # Create request
    req = urllib.request.Request(url, data=data_bytes, headers=headers, method="POST")
    
    embedding = None
    duration = 0.0
    start_time = time.time()
    
    # Send request and get response
    try:
        with urllib.request.urlopen(req) as response:
            response_text = response.read().decode('utf-8')
            end_time = time.time()
            duration = end_time - start_time
            
            # Parse JSON response
            try:
                response_data = json.loads(response_text)
            except json.JSONDecodeError:
                log_to_file(f"ERROR:Failed to parse JSON response: {response_text}", log_path)
                return {"embedding": None, "duration": duration}
            
            # Handle different response formats
            if isinstance(response_data, dict):
                if 'embedding' in response_data:
                    embedding = response_data['embedding']
                elif 'embeddings' in response_data:
                    embeddings_val = response_data['embeddings']
                    if embeddings_val and isinstance(embeddings_val[0], list):
                        embedding = embeddings_val[0]
                    else:
                        embedding = embeddings_val
            elif isinstance(response_data, list) and response_data:
                if isinstance(response_data[0], dict):
                    first_item = response_data[0]
                    if 'embedding' in first_item:
                        embedding = first_item['embedding']
                    elif 'embeddings' in first_item:
                        embedding = first_item['embeddings']
                elif isinstance(response_data[0], (int, float)):
                    embedding = response_data
            
            if embedding is None:
                log_to_file(f"ERROR:Could not identify embedding format in response: {response_data}", log_path)
            
            return {
                "embedding": embedding, 
                "duration": duration, 
                "created_at": datetime.datetime.now().isoformat()
            }

    except urllib.error.URLError as e:
        end_time = time.time()
        duration = end_time - start_time
        log_to_file(f"ERROR:Error connecting to Ollama: {e}", log_path)
        return {
            "embedding": None, 
            "duration": duration, 
            "created_at": datetime.datetime.now().isoformat()
        }


def generate_document_embedding(text, model, base_url, log_path=None):
    """
    Generate embedding for a document.
    
    Args:
        text (str): The document text
        model (str): The embedding model to use
        base_url (str): The Ollama API base URL
        log_path (str): Optional log file path
        
    Returns:
        dict: Result with text, embedding, duration, and created_at
    """
    # Skip empty input
    if not text or not text.strip():
        log_to_file("ERROR:Empty input", log_path)
        return None

    # Generate embedding
    embedding_data = get_embedding_from_ollama(
        text,
        model=model,
        base_url=base_url,
        log_path=log_path
    )

    if embedding_data is None or embedding_data["embedding"] is None:
        log_to_file("ERROR:Failed to generate embedding", log_path)
        return None
    
    result = {
        "text": text,
        "embedding": embedding_data["embedding"],
        "duration": embedding_data["duration"],
        "created_at": embedding_data["created_at"]
    }
    
    return result


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Generate document embedding using Ollama"
    )
    parser.add_argument(
        "content_file",
        help="Path to file containing document text"
    )
    parser.add_argument(
        "--model",
        default="llama3",
        help="Embedding model to use (default: llama3)"
    )
    parser.add_argument(
        "--base-url",
        default="http://localhost:11434",
        help="Ollama API base URL (default: http://localhost:11434)"
    )
    parser.add_argument(
        "--log-path",
        help="Path to log file"
    )
    
    args = parser.parse_args()
    
    # Read the document content from file
    try:
        with open(args.content_file, 'r', encoding='utf-8') as file:
            text = file.read()
    except Exception as e:
        print(f"ERROR:Failed to read content file: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Generate embedding
    result = generate_document_embedding(
        text=text,
        model=args.model,
        base_url=args.base_url,
        log_path=args.log_path
    )
    
    if result is None:
        sys.exit(1)
    
    # Return embedding as JSON
    print(f"SUCCESS:{json.dumps(result)}")
    sys.exit(0)


if __name__ == "__main__":
    main()
