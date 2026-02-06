"""
RAG Engine - Semantic search over company knowledge base using ChromaDB
"""
import chromadb
from chromadb.config import Settings as ChromaSettings
from sentence_transformers import SentenceTransformer
from typing import List, Dict, Any, Optional
import logging

from config import settings

logger = logging.getLogger(__name__)


class RAGEngine:
    """Retrieval-Augmented Generation engine for company knowledge"""
    
    def __init__(self):
        self.chroma_url = f"http://{settings.chroma_host}:{settings.chroma_port}"
        logger.info(f"Connecting to ChromaDB at {self.chroma_url}")
        
        # Initialize ChromaDB client
        self.client = chromadb.HttpClient(
            host=settings.chroma_host,
            port=settings.chroma_port,
            settings=ChromaSettings(anonymized_telemetry=False)
        )
        
        # Initialize embedding model
        logger.info(f"Loading embedding model: {settings.embedding_model}")
        self.embedding_model = SentenceTransformer(settings.embedding_model)
        
        # Collection names
        self.collections = {
            "case_studies": None,
            "services": None,
            "faqs": None,
            "company_info": None,
            # Add reputation_signals collection used by the app/scripts
            "reputation_signals": None
        }
        
        self._initialize_collections()
    
    def _initialize_collections(self):
        """Get or create ChromaDB collections"""
        for collection_name in self.collections.keys():
            try:
                col = self.client.get_or_create_collection(
                    name=collection_name,
                    metadata={"description": f"OnlyneReputation {collection_name}"}
                )

                # Diagnostic logging: capture the raw return value to help
                # debug client/server shape mismatches (some chromadb HTTP
                # clients return dict-like responses while older clients
                # return a Collection object with methods).
                try:
                    raw_repr = repr(col)
                except Exception:
                    raw_repr = "<unrepr-able>"

                # Truncate to avoid extremely long logs
                truncated = raw_repr[:1000] + ("..." if len(raw_repr) > 1000 else "")
                logger.debug(f"Raw collection returned for '{collection_name}': type={type(col)}, repr={truncated}")
                if isinstance(col, dict):
                    try:
                        logger.debug(f"Collection dict keys for '{collection_name}': {list(col.keys())}")
                    except Exception:
                        logger.debug(f"Collection for '{collection_name}' is a dict but keys could not be listed")

                # chromadb client versions differ in what they return here:
                # - older clients return a Collection object with .query/.add/.count methods
                # - newer clients (0.5.x HTTP client) may return a plain dict or proxy
                # Detect and normalize: if returned object exposes query(), store it
                # otherwise store the collection name and let higher-level methods
                # call client-level APIs.
                if hasattr(col, "query") and callable(getattr(col, "query")):
                    self.collections[collection_name] = col
                else:
                    # store the name as a signal to use client-level calls
                    self.collections[collection_name] = collection_name

                logger.info(f"Collection '{collection_name}' initialized (stored={type(self.collections[collection_name])})")
            except Exception as e:
                logger.error(f"Failed to initialize collection '{collection_name}': {e}")
    
    def query(
        self,
        query_text: str,
        collection_names: Optional[List[str]] = None,
        top_k: int = None,
        filter_metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Query ChromaDB collections for relevant documents
        
        Args:
            query_text: Search query (e.g., "healthcare case studies")
            collection_names: List of collections to search (default: all)
            top_k: Number of results per collection (default: settings.top_k_results)
            filter_metadata: Metadata filters (e.g., {"industry": "healthcare"})
        
        Returns:
            Dict with results per collection
        """
        if top_k is None:
            top_k = settings.top_k_results
        
        if collection_names is None:
            collection_names = list(self.collections.keys())
        
        # Generate embedding for query
        query_embedding = self.embedding_model.encode(query_text).tolist()
        
        results = {}
        
        for collection_name in collection_names:
            # Ensure collection exists (create on-demand if needed)
            collection = self.collections.get(collection_name)
            if not collection:
                # try to create/get it now
                try:
                    col = self.client.get_or_create_collection(
                        name=collection_name,
                        metadata={"description": f"OnlyneReputation {collection_name}"}
                    )
                    if hasattr(col, "query") and callable(getattr(col, "query")):
                        self.collections[collection_name] = col
                        collection = col
                    else:
                        self.collections[collection_name] = collection_name
                        collection = collection_name
                    logger.info(f"On-demand collection '{collection_name}' created/initialized")
                except Exception as e:
                    logger.error(f"Failed to create collection '{collection_name}' on-demand: {e}")
                    collection = None
            if not collection:
                logger.warning(f"Collection '{collection_name}' not found")
                continue
            
            try:
                # Two supported modes:
                # 1) collection is an object with .query()
                # 2) collection is a stored name -> use client.query() and request that collection
                if hasattr(collection, "query") and callable(getattr(collection, "query")):
                    query_result = collection.query(
                        query_embeddings=[query_embedding],
                        n_results=top_k,
                        where=filter_metadata,
                        include=["documents", "metadatas", "distances"],
                    )
                else:
                    # collection is a name (str)
                    query_result = self.client.query(
                        collection_names=[collection_name],
                        query_embeddings=[query_embedding],
                        n_results=top_k,
                        where=filter_metadata,
                        include=["documents", "metadatas", "distances"],
                    )
                
                # Format results
                # Normalize different return shapes. Two common shapes observed:
                # - {'documents': [[...]], 'metadatas': [[...]], 'distances': [[...]]}
                # - {'results': [{'documents': [...], 'metadatas': [...], 'distances': [...]}]} (per-collection)
                formatted_results = []

                # Helper to extract lists for the first (and only) query
                docs_list = []
                metas_list = []
                dists_list = []

                if not query_result:
                    docs_list = []
                elif "documents" in query_result:
                    # documents is a list-of-lists
                    docs_list = query_result.get("documents", [[]])[0] if isinstance(query_result.get("documents"), list) else []
                    metas_list = (query_result.get("metadatas") or [[]])[0] if isinstance(query_result.get("metadatas"), list) else []
                    dists_list = (query_result.get("distances") or [[]])[0] if isinstance(query_result.get("distances"), list) else []
                elif "results" in query_result and isinstance(query_result["results"], list):
                    # client.query may return per-collection results
                    first = query_result["results"][0]
                    docs_list = first.get("documents", [])
                    metas_list = first.get("metadatas", [])
                    dists_list = first.get("distances", [])
                else:
                    # unknown shape - try to be defensive
                    docs_list = []

                for i, doc in enumerate(docs_list):
                    meta = metas_list[i] if i < len(metas_list) else {}
                    dist = dists_list[i] if i < len(dists_list) else None
                    formatted_results.append({
                        "document": doc,
                        "metadata": meta,
                        "distance": dist,
                        "relevance_score": 1 - (dist if dist is not None else 1)
                    })
                
                results[collection_name] = formatted_results
                logger.info(f"Found {len(formatted_results)} results in '{collection_name}'")
                
            except Exception as e:
                logger.error(f"Error querying collection '{collection_name}': {e}")
                results[collection_name] = []
        
        return results
    
    def add_documents(
        self,
        collection_name: str,
        documents: List[str],
        metadatas: List[Dict[str, Any]],
        ids: Optional[List[str]] = None
    ) -> bool:
        """
        Add documents to a ChromaDB collection
        
        Args:
            collection_name: Target collection
            documents: List of text documents
            metadatas: List of metadata dicts (one per document)
            ids: Optional list of document IDs
        
        Returns:
            True if successful
        """
        collection = self.collections.get(collection_name)
        # If collection not found, create/get it on-demand
        if not collection:
            try:
                col = self.client.get_or_create_collection(
                    name=collection_name,
                    metadata={"description": f"OnlyneReputation {collection_name}"}
                )
                if hasattr(col, "add") and callable(getattr(col, "add")):
                    self.collections[collection_name] = col
                    collection = col
                else:
                    self.collections[collection_name] = collection_name
                    collection = collection_name
                logger.info(f"On-demand collection '{collection_name}' created/initialized for add")
            except Exception as e:
                logger.error(f"Collection '{collection_name}' not found and failed to create: {e}")
                return False
        
        try:
            # Generate embeddings
            embeddings = self.embedding_model.encode(documents).tolist()
            
            # Generate IDs if not provided
            if ids is None:
                ids = [f"{collection_name}_{i}" for i in range(len(documents))]
            
            # Sanitize metadatas: Chroma client rejects None values in metadata
            sanitized_metadatas = []
            for md in metadatas:
                if not isinstance(md, dict):
                    sanitized_metadatas.append({})
                    continue
                clean = {}
                for k, v in md.items():
                    # Only allow primitive types: str, int, float, bool
                    if v is None:
                        clean[k] = ""
                    elif isinstance(v, (str, int, float, bool)):
                        clean[k] = v
                    else:
                        # Fallback to string representation for complex types
                        try:
                            clean[k] = str(v)
                        except Exception:
                            clean[k] = ""
                sanitized_metadatas.append(clean)

            # Add to ChromaDB
            if hasattr(collection, "add") and callable(getattr(collection, "add")):
                collection.add(
                    documents=documents,
                    embeddings=embeddings,
                    metadatas=sanitized_metadatas,
                    ids=ids,
                )
            else:
                # fall back to client-level add
                # note: different client versions may accept slightly different param names
                try:
                    self.client.add(
                        collection_name=collection_name,
                        documents=documents,
                        embeddings=embeddings,
                        metadatas=sanitized_metadatas,
                        ids=ids,
                    )
                except TypeError:
                    # some clients expect 'collection' instead of 'collection_name'
                    self.client.add(
                        collection=collection_name,
                        documents=documents,
                        embeddings=embeddings,
                        metadatas=metadatas,
                        ids=ids,
                    )
            
            logger.info(f"Added {len(documents)} documents to '{collection_name}'")
            return True
            
        except Exception as e:
            logger.error(f"Error adding documents to '{collection_name}': {e}")
            return False
    
    def list_all_collection_names(self) -> List[str]:
        """List all collection names from ChromaDB (including on-demand ones e.g. xxx_company_profile)."""
        try:
            raw = self.client.list_collections()
            names = []
            for c in raw:
                if hasattr(c, "name"):
                    names.append(c.name)
                elif isinstance(c, dict) and "name" in c:
                    names.append(c["name"])
                else:
                    names.append(str(c))
            return names
        except Exception as e:
            logger.error(f"list_all_collection_names failed: {e}")
            return list(self.collections.keys())

    def get_collection_count(self, collection_name: str) -> int:
        """Get number of documents in a collection (works for any collection in Chroma, not only pre-initialized)."""
        try:
            collection = self.collections.get(collection_name)
            if collection and hasattr(collection, "count") and callable(getattr(collection, "count")):
                return collection.count()
            col = self.client.get_collection(name=collection_name)
            return col.count() if hasattr(col, "count") and callable(getattr(col, "count")) else 0
        except Exception as e:
            logger.debug(f"get_collection_count '{collection_name}': {e}")
            return 0

    def delete_documents(
        self,
        collection_name: str,
        ids: Optional[List[str]] = None,
        delete_all: bool = False,
    ) -> Dict[str, Any]:
        """
        Delete documents from a ChromaDB collection.

        Args:
            collection_name: Target collection name.
            ids: Optional list of document IDs to delete.
            delete_all: If True, delete the entire collection (all documents).

        Returns:
            Dict with success, deleted_count, and optional error.
        """
        try:
            if delete_all:
                count_before = 0
                try:
                    count_before = self.get_collection_count(collection_name)
                except Exception:
                    pass
                try:
                    self.client.delete_collection(name=collection_name)
                except Exception as del_err:
                    # Collection may not exist
                    logger.warning(f"delete_collection '{collection_name}': {del_err}")
                    return {"success": False, "error": str(del_err), "deleted_count": 0}
                self.collections.pop(collection_name, None)
                logger.info(f"Deleted collection '{collection_name}' ({count_before} documents)")
                return {"success": True, "deleted_count": count_before}
            if ids:
                col = self.client.get_or_create_collection(
                    name=collection_name,
                    metadata={"description": f"OnlyneReputation {collection_name}"},
                )
                col.delete(ids=ids)
                self.collections[collection_name] = col if hasattr(col, "query") and callable(getattr(col, "query")) else collection_name
                logger.info(f"Deleted {len(ids)} document(s) from '{collection_name}'")
                return {"success": True, "deleted_count": len(ids)}
            return {"success": False, "error": "Must provide ids or delete_all=True"}
        except Exception as e:
            logger.error(f"Error deleting from '{collection_name}': {e}")
            return {"success": False, "error": str(e), "deleted_count": 0}

    def health_check(self) -> Dict[str, Any]:
        """Check health of RAG engine and ChromaDB connection"""
        status = {
            "chroma_url": self.chroma_url,
            "chroma_connected": False,
            "collections": {},
            "embedding_model": settings.embedding_model
        }
        
        try:
            # Test ChromaDB connection
            self.client.heartbeat()
            status["chroma_connected"] = True
            
            # Get collection counts
            for name, collection in self.collections.items():
                if collection:
                    status["collections"][name] = self.get_collection_count(name)
        
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            status["error"] = str(e)
        
        return status


# Global instance
rag_engine = None

def get_rag_engine() -> RAGEngine:
    """Get or create RAG engine instance"""
    global rag_engine
    if rag_engine is None:
        rag_engine = RAGEngine()
    return rag_engine
