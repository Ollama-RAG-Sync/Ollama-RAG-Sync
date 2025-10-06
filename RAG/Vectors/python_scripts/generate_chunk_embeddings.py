#!/usr/bin/env python3
"""
Chunk Embeddings Generator
Chunks document content and generates embeddings for each chunk using Ollama.
Supports concurrent processing for improved performance.
"""

import sys
import json
import urllib.request
import urllib.error
import time
import datetime
import os
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed


def validate_parameters(args):
    """Validate command-line parameters and return error messages if any.
    
    Args:
        args: Parsed command-line arguments
        
    Returns:
        list: List of error messages (empty if all valid)
    """
    errors = []
    
    # Validate content file
    if not args.content_file:
        errors.append("Content file path is required")
    elif not os.path.exists(args.content_file):
        errors.append(f"Content file does not exist: {args.content_file}")
    elif not os.path.isfile(args.content_file):
        errors.append(f"Content file path is not a file: {args.content_file}")
    elif os.path.getsize(args.content_file) == 0:
        errors.append(f"Content file is empty: {args.content_file}")
    
    # Validate chunk_size
    if args.chunk_size <= 0:
        errors.append(f"chunk-size must be positive, got: {args.chunk_size}")
    elif args.chunk_size > 10000:
        errors.append(f"chunk-size is too large (max 10000), got: {args.chunk_size}")
    
    # Validate chunk_overlap
    if args.chunk_overlap < 0:
        errors.append(f"chunk-overlap cannot be negative, got: {args.chunk_overlap}")
    elif args.chunk_overlap >= args.chunk_size:
        errors.append(f"chunk-overlap ({args.chunk_overlap}) must be less than chunk-size ({args.chunk_size})")
    
    # Validate max_workers
    if args.max_workers <= 0:
        errors.append(f"max-workers must be positive, got: {args.max_workers}")
    elif args.max_workers > 50:
        errors.append(f"max-workers is too large (max 50), got: {args.max_workers}")
    
    # Validate model name
    if not args.model or not args.model.strip():
        errors.append("model name cannot be empty")
    
    # Validate base_url
    if not args.base_url or not args.base_url.strip():
        errors.append("base-url cannot be empty")
    elif not (args.base_url.startswith('http://') or args.base_url.startswith('https://')):
        errors.append(f"base-url must start with http:// or https://, got: {args.base_url}")
    
    # Validate log_path if provided
    if args.log_path:
        log_dir = os.path.dirname(args.log_path)
        if log_dir and not os.path.exists(log_dir):
            try:
                os.makedirs(log_dir, exist_ok=True)
            except Exception as e:
                errors.append(f"Cannot create log directory: {e}")
    
    return errors


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


def get_embedding_from_ollama(text, model="embeddinggemma", base_url="http://localhost:11434", log_path=None, timeout=60):
    """
    Get embeddings from Ollama API
    
    Args:
        text (str): The text to get embeddings for
        model (str): The model to use (default: "embeddinggemma")
        base_url (str): The base URL for Ollama API (default: "http://localhost:11434")
        log_path (str): Path to log file (optional)
        timeout (int): Request timeout in seconds (default: 60)
        
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
        with urllib.request.urlopen(req, timeout=timeout) as response:
            response_text = response.read().decode('utf-8')
            end_time = time.time()
            duration = end_time - start_time
            
            # Parse JSON response
            try:
                response_data = json.loads(response_text)
            except json.JSONDecodeError:
                log_to_file(f"ERROR:Failed to parse JSON response: {response_text}", log_path)
                return {"embedding": None, "duration": duration, "created_at": datetime.datetime.now().isoformat()}
            
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
            
    except urllib.error.HTTPError as e:
        end_time = time.time()
        duration = end_time - start_time
        log_to_file(f"ERROR:HTTP error {e.code} connecting to Ollama: {e.reason}", log_path)
        return {
            "embedding": None, 
            "duration": duration, 
            "created_at": datetime.datetime.now().isoformat()
        }
    except urllib.error.URLError as e:
        end_time = time.time()
        duration = end_time - start_time
        log_to_file(f"ERROR:Error connecting to Ollama: {e.reason}", log_path)
        return {
            "embedding": None, 
            "duration": duration, 
            "created_at": datetime.datetime.now().isoformat()
        }
    except Exception as e:
        end_time = time.time()
        duration = end_time - start_time
        log_to_file(f"ERROR:Unexpected error: {str(e)}", log_path)
        return {
            "embedding": None, 
            "duration": duration, 
            "created_at": datetime.datetime.now().isoformat()
        }


def generate_chunk_embeddings(text, chunk_size, chunk_overlap, model, base_url, log_path=None, max_workers=5, include_text=True):
    """
    Generate embeddings for text chunks using parallel processing.
    
    Args:
        text (str): The document text
        chunk_size (int): Number of lines per chunk
        chunk_overlap (int): Number of lines to overlap between chunks
        model (str): The embedding model to use
        base_url (str): The Ollama API base URL
        log_path (str): Optional log file path
        max_workers (int): Maximum number of concurrent workers (default: 5)
        include_text (bool): Whether to include chunk text in output (default: True)
        
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
    log_to_file(f"INFO:Processing chunks with {max_workers} concurrent workers", log_path)
    
    # Initialize result array with None values (to preserve order)
    chunk_embeddings = [None] * len(chunks)
    
    # Process chunks in parallel using ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all chunk processing tasks
        future_to_index = {
            executor.submit(
                get_embedding_from_ollama,
                chunk_data["text"],
                model,
                base_url,
                log_path
            ): (i, chunk_data)
            for i, chunk_data in enumerate(chunks)
        }
        
        # Collect results as they complete
        completed_count = 0
        for future in as_completed(future_to_index):
            i, chunk_data = future_to_index[future]
            completed_count += 1
            
            try:
                embedding_result = future.result()
                
                if embedding_result is None or embedding_result["embedding"] is None:
                    log_to_file(f"ERROR:Failed to get embedding for chunk {i+1}", log_path)
                    return None
                
                chunk_embedding = {
                    'chunk_id': i,
                    'start_line': chunk_data["start_line"],
                    'end_line': chunk_data["end_line"],
                    'embedding': embedding_result["embedding"],
                    'duration': embedding_result["duration"],
                    'created_at': embedding_result["created_at"]
                }
                
                # Include text only if requested (reduces JSON size significantly)
                if include_text:
                    chunk_embedding['text'] = chunk_data["text"]
                
                chunk_embeddings[i] = chunk_embedding
                
                log_to_file(f"INFO:Chunk {completed_count} / {len(chunks)} embeddings created", log_path)
                
            except Exception as e:
                log_to_file(f"ERROR:Exception processing chunk {i+1}: {str(e)}", log_path)
                return None
    
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
        default="embeddinggemma",
        help="Embedding model to use (default: embeddinggemma)"
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
    parser.add_argument(
        "--max-workers",
        type=int,
        default=5,
        help="Maximum number of concurrent workers for parallel processing (default: 5)"
    )
    parser.add_argument(
        "--exclude-text",
        action="store_true",
        help="Exclude chunk text from output to reduce JSON size (default: include text)"
    )
    
    args = parser.parse_args()
    
    # Validate parameters
    validation_errors = validate_parameters(args)
    if validation_errors:
        print("ERROR:Parameter validation failed:", file=sys.stderr)
        for error in validation_errors:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)
    
    # Read the document content from file
    try:
        with open(args.content_file, 'r', encoding='utf-8') as file:
            text = file.read()
        
        # Validate that file has content after reading
        if not text or not text.strip():
            print(f"ERROR:File contains no readable text: {args.content_file}", file=sys.stderr)
            sys.exit(1)
            
    except UnicodeDecodeError as e:
        print(f"ERROR:File encoding error (not valid UTF-8): {args.content_file} - {e}", file=sys.stderr)
        sys.exit(1)
    except PermissionError as e:
        print(f"ERROR:Permission denied reading file: {args.content_file} - {e}", file=sys.stderr)
        sys.exit(1)
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
        log_path=args.log_path,
        max_workers=args.max_workers,
        include_text=not args.exclude_text
    )
    
    if result is None:
        print(f"FAILED:Could not generate embedding", file=sys.stderr)    
        sys.exit(1)
    
    # Return as JSON with compact serialization for better performance
    # Use separators to minimize whitespace, ensure_ascii=False for better Unicode handling
    print(f"SUCCESS:{json.dumps(result, separators=(',', ':'), ensure_ascii=False)}")
    sys.exit(0)


if __name__ == "__main__":
    main()
