"""
REST API Client for Ollama-RAG-Sync
Provides a clean interface to interact with FileTracker and Vectors APIs
"""

import requests
from typing import Dict, List, Optional, Any
import json


class APIClientException(Exception):
    """Custom exception for API client errors"""
    pass


class APIClient:
    """
    Client for interacting with Ollama-RAG-Sync REST APIs
    """
    
    def __init__(self, filetracker_url: str = "http://localhost:10003", 
                 vectors_url: str = "http://localhost:10001",
                 timeout: int = 30):
        """
        Initialize the API client
        
        Args:
            filetracker_url: Base URL for FileTracker API (default: http://localhost:10003)
            vectors_url: Base URL for Vectors API (default: http://localhost:10001)
            timeout: Request timeout in seconds (default: 30)
        """
        self.filetracker_url = filetracker_url.rstrip('/')
        self.vectors_url = vectors_url.rstrip('/')
        self.timeout = timeout
        
    def _request(self, method: str, url: str, **kwargs) -> Dict[str, Any]:
        """
        Make an HTTP request and handle errors
        
        Args:
            method: HTTP method (GET, POST, PUT, DELETE)
            url: Full URL to request
            **kwargs: Additional arguments to pass to requests
            
        Returns:
            Response JSON as dictionary
            
        Raises:
            APIClientException: If request fails
        """
        try:
            kwargs.setdefault('timeout', self.timeout)
            response = requests.request(method, url, **kwargs)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise APIClientException(f"API request failed: {str(e)}")
        except json.JSONDecodeError as e:
            raise APIClientException(f"Failed to parse API response: {str(e)}")
    
    # ========== FileTracker API Methods ==========
    
    def get_collections(self) -> List[Dict[str, Any]]:
        """Get all collections"""
        url = f"{self.filetracker_url}/api/collections"
        result = self._request('GET', url)
        if result.get('success'):
            return result.get('collections', [])
        raise APIClientException(f"Failed to get collections: {result.get('error')}")
    
    def get_collection(self, collection_id: int) -> Dict[str, Any]:
        """Get collection by ID"""
        url = f"{self.filetracker_url}/api/collections/{collection_id}"
        result = self._request('GET', url)
        if result.get('success'):
            return result.get('collection', {})
        raise APIClientException(f"Failed to get collection: {result.get('error')}")
    
    def create_collection(self, name: str, source_folder: str, 
                         description: str = "", 
                         include_extensions: str = "",
                         exclude_folders: str = "") -> Dict[str, Any]:
        """
        Create a new collection
        
        Args:
            name: Collection name
            source_folder: Path to source folder
            description: Collection description
            include_extensions: Comma-separated file extensions (e.g., ".txt,.md,.pdf")
            exclude_folders: Comma-separated folder names to exclude
            
        Returns:
            Created collection data
        """
        url = f"{self.filetracker_url}/api/collections"
        data = {
            "name": name,
            "sourceFolder": source_folder,
            "description": description,
            "includeExtensions": include_extensions,
            "excludeFolders": exclude_folders
        }
        result = self._request('POST', url, json=data)
        if result.get('success'):
            return result.get('collection', {})
        raise APIClientException(f"Failed to create collection: {result.get('error')}")
    
    def update_collection(self, collection_id: int, **kwargs) -> Dict[str, Any]:
        """
        Update a collection
        
        Args:
            collection_id: Collection ID
            **kwargs: Fields to update (name, description, sourceFolder, includeExtensions, excludeFolders)
            
        Returns:
            Updated collection data
        """
        url = f"{self.filetracker_url}/api/collections/{collection_id}"
        result = self._request('PUT', url, json=kwargs)
        if result.get('success'):
            return result.get('collection', {})
        raise APIClientException(f"Failed to update collection: {result.get('error')}")
    
    def delete_collection(self, collection_id: int) -> bool:
        """Delete a collection"""
        url = f"{self.filetracker_url}/api/collections/{collection_id}"
        result = self._request('DELETE', url)
        return result.get('success', False)
    
    def get_collection_files(self, collection_id: int, 
                            dirty: Optional[bool] = None,
                            processed: Optional[bool] = None,
                            deleted: Optional[bool] = None) -> List[Dict[str, Any]]:
        """
        Get files in a collection
        
        Args:
            collection_id: Collection ID
            dirty: Filter for dirty files (unprocessed)
            processed: Filter for processed files
            deleted: Filter for deleted files
            
        Returns:
            List of files
        """
        url = f"{self.filetracker_url}/api/collections/{collection_id}/files"
        params = {}
        if dirty is not None:
            params['dirty'] = 'true' if dirty else 'false'
        if processed is not None:
            params['processed'] = 'true' if processed else 'false'
        if deleted is not None:
            params['deleted'] = 'true' if deleted else 'false'
            
        result = self._request('GET', url, params=params)
        if result.get('success'):
            return result.get('files', [])
        raise APIClientException(f"Failed to get files: {result.get('error')}")
    
    def add_file_to_collection(self, collection_id: int, file_path: str,
                               original_url: str = "", dirty: bool = True) -> Dict[str, Any]:
        """Add a file to a collection"""
        url = f"{self.filetracker_url}/api/collections/{collection_id}/files"
        data = {
            "filePath": file_path,
            "originalUrl": original_url,
            "dirty": dirty
        }
        result = self._request('POST', url, json=data)
        if result.get('success'):
            return result.get('file', {})
        raise APIClientException(f"Failed to add file: {result.get('error')}")
    
    def update_file_status(self, collection_id: int, file_id: int, dirty: bool) -> bool:
        """Update file processing status"""
        url = f"{self.filetracker_url}/api/collections/{collection_id}/files/{file_id}"
        data = {"dirty": dirty}
        result = self._request('PUT', url, json=data)
        return result.get('success', False)
    
    def update_all_files_status(self, collection_id: int, dirty: bool) -> bool:
        """Update all files status in a collection"""
        url = f"{self.filetracker_url}/api/collections/{collection_id}/files"
        data = {"dirty": dirty}
        result = self._request('PUT', url, json=data)
        return result.get('success', False)
    
    def delete_file_from_collection(self, collection_id: int, file_id: int) -> bool:
        """Remove a file from a collection"""
        url = f"{self.filetracker_url}/api/collections/{collection_id}/files/{file_id}"
        result = self._request('DELETE', url)
        return result.get('success', False)
    
    def get_file_metadata(self, file_id: int) -> Dict[str, Any]:
        """Get file metadata"""
        url = f"{self.filetracker_url}/api/files/{file_id}/metadata"
        result = self._request('GET', url)
        if result.get('success'):
            return result
        raise APIClientException(f"Failed to get file metadata: {result.get('error')}")
    
    def start_collection_watcher(self, collection_id: int, 
                                 watch_created: bool = True,
                                 watch_modified: bool = True,
                                 watch_deleted: bool = True,
                                 watch_renamed: bool = True,
                                 include_subdirectories: bool = True,
                                 process_interval: int = 15,
                                 omit_folders: List[str] = None) -> Dict[str, Any]:
        """
        Start watching a collection for file changes
        
        Args:
            collection_id: Collection ID
            watch_created: Watch for created files
            watch_modified: Watch for modified files
            watch_deleted: Watch for deleted files
            watch_renamed: Watch for renamed files
            include_subdirectories: Include subdirectories
            process_interval: Processing interval in seconds
            omit_folders: List of folder names to omit
            
        Returns:
            Watch job information
        """
        url = f"{self.filetracker_url}/api/collections/{collection_id}/watch"
        data = {
            "action": "start",
            "watchCreated": watch_created,
            "watchModified": watch_modified,
            "watchDeleted": watch_deleted,
            "watchRenamed": watch_renamed,
            "includeSubdirectories": include_subdirectories,
            "processInterval": process_interval,
            "omitFolders": omit_folders or []
        }
        result = self._request('POST', url, json=data)
        if result.get('success'):
            return result
        raise APIClientException(f"Failed to start watcher: {result.get('error')}")
    
    def stop_collection_watcher(self, collection_id: int) -> bool:
        """Stop watching a collection"""
        url = f"{self.filetracker_url}/api/collections/{collection_id}/watch"
        data = {"action": "stop"}
        result = self._request('POST', url, json=data)
        return result.get('success', False)
    
    def get_collection_settings(self, collection_id: int) -> Dict[str, Any]:
        """Get collection settings including watch status"""
        url = f"{self.filetracker_url}/api/collections/{collection_id}/settings"
        result = self._request('GET', url)
        if result.get('success'):
            return result
        raise APIClientException(f"Failed to get settings: {result.get('error')}")
    
    def get_filetracker_status(self) -> Dict[str, Any]:
        """Get FileTracker system status"""
        url = f"{self.filetracker_url}/status"
        result = self._request('GET', url)
        if result.get('success'):
            return result.get('status', {})
        raise APIClientException(f"Failed to get status: {result.get('error')}")
    
    def get_filetracker_statistics(self) -> Dict[str, Any]:
        """
        Get FileTracker statistics
        
        Note: This endpoint can be slow for large databases.
        Uses a shorter timeout (10s) to fail fast if server is overloaded.
        """
        url = f"{self.filetracker_url}/api/statistics"
        # Use shorter timeout for statistics since it can be slow
        result = self._request('GET', url, timeout=10)
        if result.get('success'):
            return result.get('statistics', {})
        raise APIClientException(f"Failed to get statistics: {result.get('error')}")
    
    def get_processing_status(self) -> List[Dict[str, Any]]:
        """Get status of all processing jobs"""
        url = f"{self.filetracker_url}/api/processing/status"
        result = self._request('GET', url)
        if result.get('success'):
            return result.get('jobs', [])
        raise APIClientException(f"Failed to get processing status: {result.get('error')}")
    
    def check_filetracker_health(self) -> bool:
        """Check if FileTracker API is healthy"""
        try:
            url = f"{self.filetracker_url}/health"
            result = self._request('GET', url)
            return result.get('status') == 'OK'
        except (APIClientException, requests.exceptions.RequestException):
            # Return False for all HTTP errors including 404, connection errors, timeouts, etc.
            return False
    
    # ========== Vectors API Methods ==========
    
    def add_document(self, file_path: str, original_file_path: str = "",
                    file_id: int = 0, chunk_size: int = 20,
                    chunk_overlap: int = 2, max_workers: int = 5,
                    content_type: str = "Text",
                    collection_name: str = "default") -> Dict[str, Any]:
        """
        Add a document to the vector database
        
        Args:
            file_path: Path to the document file
            original_file_path: Original source file path
            file_id: File ID from FileTracker
            chunk_size: Number of lines per chunk
            chunk_overlap: Number of lines to overlap
            max_workers: Number of concurrent workers
            content_type: Content type (Text, PDF, etc.)
            collection_name: Collection name in vector database
            
        Returns:
            Add document result
        """
        url = f"{self.vectors_url}/documents"
        data = {
            "filePath": file_path,
            "originalFilePath": original_file_path or file_path,
            "fileId": file_id,
            "chunkSize": chunk_size,
            "chunkOverlap": chunk_overlap,
            "maxWorkers": max_workers,
            "contentType": content_type,
            "collectionName": collection_name
        }
        result = self._request('POST', url, json=data)
        if result.get('success'):
            return result
        raise APIClientException(f"Failed to add document: {result.get('error')}")
    
    def remove_document(self, file_path: str, file_id: int = 0,
                       collection_name: str = "default") -> bool:
        """Remove a document from the vector database"""
        url = f"{self.vectors_url}/documents"
        data = {
            "filePath": file_path,
            "fileId": file_id,
            "collectionName": collection_name
        }
        result = self._request('DELETE', url, json=data)
        return result.get('success', False)
    
    def search_chunks(self, query: str, max_results: int = 10,
                     threshold: float = 0.0,
                     aggregate_by_document: bool = False,
                     collection_name: str = "default",
                     filter_dict: Optional[Dict] = None) -> List[Dict[str, Any]]:
        """
        Search for relevant chunks
        
        Args:
            query: Search query text
            max_results: Maximum number of results
            threshold: Minimum similarity score (0.0-1.0)
            aggregate_by_document: Aggregate results by document
            collection_name: Collection to search in
            filter_dict: Optional metadata filter
            
        Returns:
            List of matching chunks
        """
        url = f"{self.vectors_url}/api/search/chunks"
        data = {
            "query": query,
            "max_results": max_results,
            "threshold": threshold,
            "aggregateByDocument": aggregate_by_document,
            "collectionName": collection_name,
            "filter": filter_dict or {}
        }
        result = self._request('POST', url, json=data)
        if result.get('success'):
            return result.get('results', [])
        raise APIClientException(f"Search failed: {result.get('error')}")
    
    def search_documents(self, query: str, max_results: int = 10,
                        threshold: float = 0.5,
                        return_content: bool = False,
                        collection_name: str = "default",
                        filter_dict: Optional[Dict] = None) -> List[Dict[str, Any]]:
        """
        Search for relevant documents
        
        Args:
            query: Search query text
            max_results: Maximum number of results
            threshold: Minimum similarity score (0.0-1.0)
            return_content: Include document content in results
            collection_name: Collection to search in
            filter_dict: Optional metadata filter
            
        Returns:
            List of matching documents
        """
        url = f"{self.vectors_url}/api/search/documents"
        data = {
            "query": query,
            "max_results": max_results,
            "threshold": threshold,
            "return_content": return_content,
            "collectionName": collection_name,
            "filter": filter_dict or {}
        }
        result = self._request('POST', url, json=data)
        if result.get('success'):
            return result.get('results', [])
        raise APIClientException(f"Search failed: {result.get('error')}")
    
    def get_vector_collections(self) -> List[str]:
        """Get list of collections in vector database"""
        url = f"{self.vectors_url}/api/collections"
        result = self._request('GET', url)
        if result.get('success'):
            return result.get('collections', [])
        return []
    
    def get_vectors_status(self) -> Dict[str, Any]:
        """Get Vectors API status"""
        url = f"{self.vectors_url}/status"
        result = self._request('GET', url)
        return result
    
    def get_vectors_statistics(self) -> Dict[str, Any]:
        """Get Vectors API statistics"""
        url = f"{self.vectors_url}/api/statistics"
        result = self._request('GET', url)
        if result.get('success'):
            return result.get('statistics', {})
        raise APIClientException(f"Failed to get statistics: {result.get('error')}")
    
    def check_vectors_health(self) -> bool:
        """Check if Vectors API is healthy"""
        try:
            url = f"{self.vectors_url}/health"
            result = self._request('GET', url)
            return result.get('status') == 'OK'
        except (APIClientException, requests.exceptions.RequestException):
            # Return False for all HTTP errors including 404, connection errors, timeouts, etc.
            return False
