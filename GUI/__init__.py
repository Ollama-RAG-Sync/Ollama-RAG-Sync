"""
Ollama-RAG-Sync GUI Package
A comprehensive PyQt6-based graphical interface for RAG management
"""

__version__ = "1.0.0"
__author__ = "Ollama-RAG-Sync Team"

# Make main components easily importable
from .api_client import APIClient, APIClientException

__all__ = ['APIClient', 'APIClientException']
