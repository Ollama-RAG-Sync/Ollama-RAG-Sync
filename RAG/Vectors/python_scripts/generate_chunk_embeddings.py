#!/usr/bin/env python3
"""
Chunk Embeddings Generator
Chunks document content and generates embeddings for each chunk using Ollama.
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


def chunk_text(text, chunk_size=20, chunk_overlap=2):
    """
    Split a text into chunks by fixed number of lines.
    Each chunk contains exactly chunk_size lines, except the last chunk which contains remaining lines.
    
    Args:
        text (str): The text to split into chunks
        chunk_size (int): The number of lines per chunk (default: 20)
        chunk_overlap (int): The number of lines to overlap between chunks (default: 2)
        
    Returns:
        list: A list of dictionaries containing:
            - text: The chunk text
            - start_line: The starting line number (1-based)
            - end_line: The ending line number (1-based)
    """
    # Handle empty text
    if not text or not text.strip():
        return [{"text": text, "start_line": 1, "end_line": 1}]
    
    # Split text by newlines
    lines = text.split('\n')
    total_lines = len(lines)
    
    # Handle case where text has fewer lines than chunk_size
    if total_lines <= chunk_size:
        return [{"text": text, "start_line": 1, "end_line": total_lines}]
    
    chunks = []
    current_line_index = 0
    
    while current_line_index < total_lines:
        # Calculate the end index for this chunk
        end_line_index = min(current_line_index + chunk_size, total_lines)
        
        # Extract lines for this chunk
        chunk_lines = lines[current_line_index:end_line_index]
        chunk_text = '\n'.join(chunk_lines)
        
        # Create chunk info (1-based line numbering)
        chunk_info = {
            "text": chunk_text,
            "start_line": current_line_index + 1,
            "end_line": end_line_index
        }
        
        chunks.append(chunk_info)
        
        # Move to next chunk position, accounting for overlap
        # If this is the last chunk (end_line_index == total_lines), break to avoid infinite loop
        if end_line_index == total_lines:
            break
            
        # Move forward by chunk_size minus overlap
        current_line_index += max(1, chunk_size - chunk_overlap)
    
    return chunks


def get_embedding_from_ollama(text, model="llama3", base_url="http://localhost:11434", log_path=None):
    """
    Get embeddings from Ollama API
    
    Args:
        text (str): The text to get embeddings for
        model (str): The model to use (default: "llama3")
        base_url (str): The base URL for Ollama API (default: "http://localhost:11434")
        log_path (str): Path to log file (optional)
        
    Returns:
        dict: A dictionary with "embedding" (list) and "duration" (float), or None if error.
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


def generate_chunk_embeddings(text, chunk_size, chunk_overlap, model, base_url, log_path=None):
    """
    Generate embeddings for text chunks.
    
    Args:
        text (str): The document text
        chunk_size (int): Number of lines per chunk
        chunk_overlap (int): Number of lines to overlap between chunks
        model (str): The embedding model to use
        base_url (str): The Ollama API base URL
        log_path (str): Optional log file path
        
    Returns:
        list: List of chunk embeddings with metadata
    """
    # Skip empty input
    if not text or not text.strip():
        log_to_file("ERROR:Empty input", log_path)
        return None
    
    # Split content into chunks
    chunks = chunk_text(text, chunk_size, chunk_overlap)
    log_to_file(f"INFO:Split document into {len(chunks)} chunks", log_path)
    
    # Get embeddings for each chunk
    chunk_embeddings = []
    for i, chunk_data in enumerate(chunks):
        embedding_result = get_embedding_from_ollama(
            chunk_data["text"], 
            model, 
            base_url, 
            log_path
        )
        
        if embedding_result is None or embedding_result["embedding"] is None:
            log_to_file(f"ERROR:Failed to get embedding for chunk {i+1}", log_path)
            return None
        
        chunk_embeddings.append({
            'chunk_id': i,
            'text': chunk_data["text"],
            'start_line': chunk_data["start_line"],
            'end_line': chunk_data["end_line"],
            'embedding': embedding_result["embedding"],
            'duration': embedding_result["duration"],
            'created_at': embedding_result["created_at"]
        })
        
        log_to_file(f"INFO:Chunk {i+1} / {len(chunks)} embeddings created", log_path)
    
    return chunk_embeddings


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Generate chunk embeddings using Ollama"
    )
    parser.add_argument(
        "content_file",
        help="Path to file containing document text"
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=20,
        help="Number of lines per chunk (default: 20)"
    )
    parser.add_argument(
        "--chunk-overlap",
        type=int,
        default=2,
        help="Number of lines to overlap between chunks (default: 2)"
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
    
    # Generate chunk embeddings
    result = generate_chunk_embeddings(
        text=text,
        chunk_size=args.chunk_size,
        chunk_overlap=args.chunk_overlap,
        model=args.model,
        base_url=args.base_url,
        log_path=args.log_path
    )
    
    if result is None:
        sys.exit(1)
    
    # Return as JSON
    print(f"SUCCESS:{json.dumps(result)}")
    sys.exit(0)


if __name__ == "__main__":
    main()
