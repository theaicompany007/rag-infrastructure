"""
Configuration settings for RAG Service
"""
import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables"""
    
    # ChromaDB connection settings
    chroma_host: str = os.getenv("CHROMA_HOST", "chroma")
    chroma_port: int = int(os.getenv("CHROMA_PORT", "8000"))
    
    # API server settings
    api_host: str = os.getenv("API_HOST", "0.0.0.0")
    api_port: int = int(os.getenv("API_PORT", "8001"))
    
    # Embedding model settings
    embedding_model: str = os.getenv("EMBEDDING_MODEL", "all-MiniLM-L6-v2")
    
    # RAG query settings
    top_k_results: int = int(os.getenv("TOP_K_RESULTS", "5"))
    
    class Config:
        env_file = ".env.local"
        case_sensitive = False


# Create a singleton settings instance
settings = Settings()
