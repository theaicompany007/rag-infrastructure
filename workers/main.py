"""
FastAPI Application - RAG Service for OnlyneReputation
"""
from fastapi import FastAPI, HTTPException, Query, Body, Request
from fastapi.responses import StreamingResponse
import os
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
import logging
from contextlib import asynccontextmanager
import httpx
from datetime import datetime
from urllib.parse import urlsplit

from config import settings
from rag_engine import get_rag_engine
from cron_scheduler import get_cron_scheduler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Upstream Langflow URL can be overridden via environment for local development.
# Set LANGFLOW_URL to e.g. http://localhost:7860 or http://host.docker.internal:7860
LANGFLOW_URL = os.getenv("LANGFLOW_URL", "http://langflow:7860")
logger.info(f"Langflow upstream URL set to: {LANGFLOW_URL}")

# In-memory store for client-side error reports (kept short-lived)
_client_error_reports: List[Dict[str, Any]] = []


# Pydantic models
class RAGQueryRequest(BaseModel):
    """Request model for RAG queries"""
    query: str = Field(..., description="Search query text")
    collections: Optional[List[str]] = Field(None, description="Collections to search (default: all)")
    top_k: Optional[int] = Field(None, description="Number of results per collection")
    contact_context: Optional[Dict[str, Any]] = Field(None, description="Contact context for filtering")
    
    class Config:
        json_schema_extra = {
            "example": {
                "query": "case studies for healthcare industry",
                "collections": ["case_studies"],
                "top_k": 3,
                "contact_context": {
                    "industry": "Healthcare",
                    "company_size": "enterprise"
                }
            }
        }


class RAGQueryResponse(BaseModel):
    """Response model for RAG queries"""
    query: str
    results: Dict[str, List[Dict[str, Any]]]
    total_results: int


class HealthCheckResponse(BaseModel):
    """Health check response"""
    status: str
    rag_engine: Dict[str, Any]
    cron_scheduler: Dict[str, Any]


# Lifespan context manager
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events"""
    # Startup
    logger.info("🚀 Starting RAG Service...")
    
    # Initialize RAG engine
    logger.info("Initializing RAG engine...")
    rag = get_rag_engine()
    logger.info("✅ RAG engine initialized")
    
    # Start CRON scheduler
    logger.info("Starting CRON scheduler...")
    scheduler = get_cron_scheduler()
    scheduler.start()
    logger.info("✅ CRON scheduler started")
    
    yield
    
    # Shutdown
    logger.info("🛑 Shutting down RAG Service...")
    scheduler.stop()
    logger.info("✅ Shutdown complete")


# FastAPI app
app = FastAPI(
    title="OnlyneReputation RAG Service",
    description="Retrieval-Augmented Generation API for personalized email campaigns",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
# Build allow_origins from RAG_TRUSTED_ORIGIN env var (comma-separated). Defaults to localhost for dev.
trusted_origins_env = os.getenv("RAG_TRUSTED_ORIGIN", "")
if trusted_origins_env:
    allow_origins_list = [o.strip() for o in trusted_origins_env.split(",") if o.strip()]
else:
    allow_origins_list = ["http://localhost:3000"]

logger.info(f"CORS allow_origins set to: {allow_origins_list}")

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Simple API-key middleware: when RAG_API_KEY is set in the environment,
# require callers to send header `x-api-key: <value>`. If RAG_API_KEY is not
# set, requests are allowed (useful for local testing).
RAG_API_KEY = os.getenv("RAG_API_KEY")

# Create a separate router for Langflow that bypasses middleware
from fastapi import APIRouter
langflow_router = APIRouter(prefix="/langflow", tags=["Langflow"])

@app.middleware("http")
async def api_key_middleware(request: Request, call_next):
    # Get request path
    path = request.url.path
    
    # Always exempt health and root endpoints FIRST
    if path in ["/health", "/healthy", "/"]:
        return await call_next(request)
    
    # CRITICAL: Exempt Langflow paths (before API key check)
    # This ensures browser access to Langflow works without authentication
    if path == "/langflow" or path.startswith("/langflow/"):
        logger.info(f"🔓 Langflow path exempted from auth: {path}")
        return await call_next(request)

    # For all other paths, require API key if configured
    if RAG_API_KEY:
        key = request.headers.get("x-api-key")
        if not key or key != RAG_API_KEY:
            logger.warning(f"🚫 Unauthorized access attempted to: {path}")
            from fastapi.responses import JSONResponse
            return JSONResponse(status_code=401, content={"detail": "Unauthorized - missing or invalid API key"})

    return await call_next(request)


@app.get("/", tags=["Root"])
async def root():
    """Root endpoint"""
    return {
        "service": "OnlyneReputation RAG Service",
        "version": "1.0.0",
        "status": "running"
    }


# Langflow routes using separate router (bypasses main app middleware)
@langflow_router.get("/")
async def langflow_home():
    """Access Langflow home page via internal Docker network"""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{LANGFLOW_URL}/", timeout=10.0)

            # For HTML responses, we need to modify the content to fix asset and API paths
            content = response.content
            if response.headers.get("content-type", "").startswith("text/html"):
                # Decode and patch HTML
                html_content = content.decode('utf-8')

                # Replace relative asset paths with proxy prefixed ones
                html_content = html_content.replace('href="/', 'href="/langflow/')
                html_content = html_content.replace('src="/', 'src="/langflow/')
                html_content = html_content.replace("'/", "'/langflow/")

                # Fix relative API calls to go through the proxy
                html_content = html_content.replace('"/api/', '"/langflow/api/')
                html_content = html_content.replace("'/api/", "'/langflow/api/")

                # Ensure base href is present
                if '<head>' in html_content and '<base' not in html_content:
                    base_tag = '<base href="/langflow/" />'
                    html_content = html_content.replace('<head>', f'<head>{base_tag}')

                # Inject a tiny client-side error reporter to capture runtime errors
                reporter_script = r"""
<script>
(function(){
  if(window.__langflow_client_reporter_installed) return;
  window.__langflow_client_reporter_installed = true;
  function send(payload){
    try{
      if(navigator.sendBeacon){
        navigator.sendBeacon('/langflow/_client_errors', JSON.stringify(payload));
        return;
      }
    }catch(e){}
    try{fetch('/langflow/_client_errors',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});}catch(e){}
  }
  window.addEventListener('error', function(e){
    try{ send({type:'error',message:e.message,filename:e.filename,lineno:e.lineno,colno:e.colno,stack:(e.error&&e.error.stack)||null,href:location.href,userAgent:navigator.userAgent,t:new Date().toISOString()}); }catch(_){}
  });
  window.addEventListener('unhandledrejection', function(e){
    try{ var r = e.reason; send({type:'unhandledrejection',message:(r&&r.message)||String(r),stack:(r&&r.stack)||null,href:location.href,userAgent:navigator.userAgent,t:new Date().toISOString()}); }catch(_){}
  });
})();
</script>
"""

                if '</body>' in html_content:
                    html_content = html_content.replace('</body>', reporter_script + '</body>')

                # Rewrite common absolute dev URLs that would cause browsers to jump
                # to the local workstation (and thus produce SSL errors). Convert
                # them to proxy-relative paths so the browser stays on the public host.
                try:
                    before = html_content
                    html_content = html_content.replace('http://localhost:3000', '/')
                    html_content = html_content.replace('https://localhost:3000', '/')
                    html_content = html_content.replace('http://127.0.0.1:3000', '/')
                    html_content = html_content.replace('https://127.0.0.1:3000', '/')
                    if before != html_content:
                        logger.info("Rewrote absolute dev-host URLs in Langflow HTML response")
                except Exception:
                    # Best-effort; if replacement fails, continue without crashing
                    pass

                content = html_content.encode('utf-8')

            # Filter out problematic headers
            filtered_headers = {}
            for key, value in response.headers.items():
                k = key.lower()
                if k in ['content-encoding', 'content-length', 'transfer-encoding']:
                    continue
                # Rewrite any upstream Location headers into relative paths so
                # browsers aren't redirected to internal http:// URLs (like
                # http://localhost:3000). We parse and extract the path+query.
                if k == 'location':
                    try:
                        parts = urlsplit(value)
                        new_loc = parts.path or '/'
                        if parts.query:
                            new_loc = new_loc + '?' + parts.query
                        filtered_headers[key] = new_loc
                        logger.info(f"Rewrote upstream Location header from '{value}' to '{new_loc}'")
                        continue
                    except Exception:
                        # fallback to original value
                        filtered_headers[key] = value
                        logger.exception("Failed to parse upstream Location header; leaving as-is")
                        continue

                filtered_headers[key] = value

            # Update content-length after modification for HTML
            if response.headers.get("content-type", "").startswith("text/html"):
                filtered_headers["content-length"] = str(len(content))

            return StreamingResponse(
                content=iter([content]),
                status_code=response.status_code,
                headers=filtered_headers,
                media_type=response.headers.get("content-type", "text/html")
            )
    except Exception as e:
        logger.error(f"Langflow connection error: {e}")
        raise HTTPException(status_code=502, detail=f"Langflow connection error: {str(e)}")


# ALSO handle the no-trailing-slash path explicitly to avoid Starlette's
# automatic redirect that emits an absolute Location header using the
# server's (possibly http) scheme. This prevents clients from being sent
# a 'http://' redirect when they hit '/langflow' (no slash).
@langflow_router.get("")
async def langflow_home_no_slash(request: Request):
    # Delegate to the main handler which returns the proxied HTML/content.
    # We pass through the request in case future logic needs it.
    return await langflow_home()

@langflow_router.get("/status")
async def langflow_status():
    """Check if Langflow is accessible via internal Docker network (no auth required)"""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{LANGFLOW_URL}/health", timeout=5.0)
            return {
                "status": "success", 
                "langflow_status": response.status_code,
                "langflow_accessible": True,
                "message": "Langflow is accessible via internal Docker network",
                "langflow_health": response.text if response.status_code == 200 else "Not available"
            }
    except Exception as e:
        logger.error(f"Langflow status check error: {e}")
        return {
            "status": "error",
            "langflow_accessible": False,
            "error": str(e),
            "message": "Langflow not accessible via internal Docker network"
        }

# Specific API proxy route (must come before catch-all)
@langflow_router.api_route("/api/{path:path}", methods=["GET", "HEAD", "POST", "PUT", "DELETE", "PATCH"])
async def langflow_api_proxy(request: Request, path: str):
    """Proxy Langflow API requests (JSON responses)"""
    langflow_internal_url = LANGFLOW_URL
    target_url = f"{langflow_internal_url}/api/{path}"

    if request.url.query:
        target_url += f"?{request.url.query}"

    try:
        async with httpx.AsyncClient() as client:
            headers = dict(request.headers)
            # Remove problematic headers
            for header in ['host', 'content-length', 'transfer-encoding']:
                headers.pop(header, None)

            # Local handling for the injected client error endpoint to avoid
            # the catch-all proxy swallowing it. This must be checked before
            # proxying to the upstream Langflow service.
            if path.strip('/') == '_client_errors':
                from fastapi.responses import JSONResponse
                if request.method == 'POST':
                    try:
                        payload = await request.json()
                    except Exception:
                        raw = await request.body()
                        try:
                            payload = raw.decode('utf-8', errors='ignore')
                        except Exception:
                            payload = {"raw": str(raw)}

                    logger.error(f"Langflow client error reported via /api: {payload}")
                    try:
                        _client_error_reports.append({"t": datetime.utcnow().isoformat(), "payload": payload})
                        while len(_client_error_reports) > 50:
                            _client_error_reports.pop(0)
                    except Exception:
                        logger.exception("Failed to store client error report")

                    return JSONResponse(content={"status": "received", "stored": len(_client_error_reports)})

                if request.method == 'GET':
                    from fastapi.responses import JSONResponse
                    return JSONResponse(content={"errors": _client_error_reports})

                return JSONResponse(status_code=405, content={"detail": "Method not allowed"})

            response = await client.request(
                method=request.method,
                url=target_url,
                headers=headers,
                content=await request.body(),
                timeout=60.0
            )

            # For API responses, return JSON directly without HTML modification
            filtered_headers = {}
            for key, value in response.headers.items():
                if key.lower() not in ['content-encoding', 'content-length', 'transfer-encoding']:
                    filtered_headers[key] = value

            return StreamingResponse(
                content=iter([response.content]),
                status_code=response.status_code,
                headers=filtered_headers,
                media_type=response.headers.get("content-type")
            )

    except Exception as e:
        logger.error(f"Langflow API proxy error: {e}")
        raise HTTPException(status_code=502, detail=f"Langflow API proxy error: {str(e)}")
# Endpoint to receive client-side error reports posted from the injected reporter
@langflow_router.post("/_client_errors")
async def receive_client_error(request: Request):
    try:
        payload = await request.json()
    except Exception:
        raw = await request.body()
        try:
            payload = raw.decode('utf-8', errors='ignore')
        except Exception:
            payload = {"raw": str(raw)}

    logger.error(f"Langflow client error reported: {payload}")
    try:
        _client_error_reports.append({"t": datetime.utcnow().isoformat(), "payload": payload})
        # keep only the most recent 50 reports
        while len(_client_error_reports) > 50:
            _client_error_reports.pop(0)
    except Exception as e:
        logger.exception("Failed to store client error report")

    return {"status": "received", "stored": len(_client_error_reports)}


@langflow_router.get("/_client_errors")
async def get_client_errors():
    """Return recent client-side error reports collected from browsers."""
    return {"errors": _client_error_reports}


# Catch-all route for static assets and other non-API requests
@langflow_router.api_route("/{path:path}", methods=["GET", "HEAD", "POST", "PUT", "DELETE", "PATCH"])
async def langflow_proxy_all(request: Request, path: str):
    """Proxy all Langflow requests with smart content handling"""
    langflow_internal_url = LANGFLOW_URL
    target_url = f"{langflow_internal_url}/{path}"

    if request.url.query:
        target_url += f"?{request.url.query}"

    try:
        async with httpx.AsyncClient() as client:
            headers = dict(request.headers)
            # Remove problematic headers
            for header in ['host', 'content-length', 'transfer-encoding']:
                headers.pop(header, None)

            response = await client.request(
                method=request.method,
                url=target_url,
                headers=headers,
                content=await request.body(),
                timeout=60.0
            )

            # Filter response headers and rewrite Location headers when present
            filtered_headers = {}
            for key, value in response.headers.items():
                k = key.lower()
                if k in ['content-encoding', 'content-length', 'transfer-encoding']:
                    continue
                if k == 'location':
                    try:
                        parts = urlsplit(value)
                        new_loc = parts.path or '/'
                        if parts.query:
                            new_loc = new_loc + '?' + parts.query
                        filtered_headers[key] = new_loc
                        logger.info(f"Rewrote upstream Location header from '{value}' to '{new_loc}'")
                        continue
                    except Exception:
                        filtered_headers[key] = value
                        logger.exception("Failed to parse upstream Location header; leaving as-is")
                        continue

                filtered_headers[key] = value

            # For HTML responses, modify content to fix asset paths
            content = response.content
            if path == "" and response.headers.get("content-type", "").startswith("text/html"):
                # Only modify the root HTML page to fix asset paths
                html_content = content.decode('utf-8')
                html_content = html_content.replace('href="/', 'href="/langflow/')
                html_content = html_content.replace('src="/', 'src="/langflow/')
                html_content = html_content.replace('action="/', 'action="/langflow/')

                # Insert base tag
                if '<head>' in html_content and '<base' not in html_content:
                    html_content = html_content.replace('<head>', '<head><base href="/langflow/" />')
                # Also rewrite absolute dev hostnames if present in the HTML
                try:
                    before = html_content
                    html_content = html_content.replace('http://localhost:3000', '/')
                    html_content = html_content.replace('https://localhost:3000', '/')
                    html_content = html_content.replace('http://127.0.0.1:3000', '/')
                    html_content = html_content.replace('https://127.0.0.1:3000', '/')
                    if before != html_content:
                        logger.info("Rewrote absolute dev-host URLs in Langflow root HTML response")
                except Exception:
                    pass

                content = html_content.encode('utf-8')
                filtered_headers['content-length'] = str(len(content))

            return StreamingResponse(
                content=iter([content]),
                status_code=response.status_code,
                headers=filtered_headers,
                media_type=response.headers.get("content-type")
            )

    except Exception as e:
        logger.error(f"Langflow proxy error: {e}")
        raise HTTPException(status_code=502, detail=f"Langflow proxy error: {str(e)}")


# NOTE: router will be included after all route definitions so that
# locally-defined langflow routes (for client error collection) are
# registered before the router is attached to the app.


# Endpoint to receive client-side error reports posted from the injected reporter
@langflow_router.post("/_client_errors")
async def receive_client_error(request: Request):
    try:
        payload = await request.json()
    except Exception:
        raw = await request.body()
        try:
            payload = raw.decode('utf-8', errors='ignore')
        except Exception:
            payload = {"raw": str(raw)}

    logger.error(f"Langflow client error reported: {payload}")
    try:
        _client_error_reports.append({"t": datetime.utcnow().isoformat(), "payload": payload})
        # keep only the most recent 50 reports
        while len(_client_error_reports) > 50:
            _client_error_reports.pop(0)
    except Exception as e:
        logger.exception("Failed to store client error report")

    return {"status": "received", "stored": len(_client_error_reports)}


@langflow_router.get("/_client_errors")
async def get_client_errors():
    """Return recent client-side error reports collected from browsers."""
    return {"errors": _client_error_reports}


# Now include the langflow router so all langflow routes (including the
# client error endpoints) are registered on the main app.
from fastapi.responses import JSONResponse

# As a reliable fallback (and to avoid any router-ordering/caching edge cases
# in frontends), expose a top-level app route for client errors at
# /langflow/_client_errors. This ensures GET/POST to that exact path always
# returns JSON from this process even if router registration order changes.
@app.post("/langflow/_client_errors")
async def app_receive_client_error(request: Request):
    try:
        payload = await request.json()
    except Exception:
        raw = await request.body()
        try:
            payload = raw.decode('utf-8', errors='ignore')
        except Exception:
            payload = {"raw": str(raw)}

    logger.error(f"[app route] Langflow client error reported: {payload}")
    try:
        _client_error_reports.append({"t": datetime.utcnow().isoformat(), "payload": payload})
        while len(_client_error_reports) > 50:
            _client_error_reports.pop(0)
    except Exception:
        logger.exception("Failed to store client error report")

    return JSONResponse(content={"status": "received", "stored": len(_client_error_reports)}, headers={"Cache-Control": "no-store, max-age=0"})


@app.get("/langflow/_client_errors")
async def app_get_client_errors():
    return JSONResponse(content={"errors": _client_error_reports}, headers={"Cache-Control": "no-store, max-age=0"})


app.include_router(langflow_router)


@app.get("/health", response_model=HealthCheckResponse, tags=["Health"])
async def health_check():
    """Health check endpoint"""
    rag = get_rag_engine()
    scheduler = get_cron_scheduler()
    
    return {
        "status": "healthy",
        "rag_engine": rag.health_check(),
        "cron_scheduler": scheduler.get_status()
    }


@app.get("/healthy", response_model=HealthCheckResponse, tags=["Health"])
async def healthy():
    """Alias route for `/health` kept for backwards compatibility or caller typos."""
    return await health_check()


@app.post("/rag/query", response_model=RAGQueryResponse, tags=["RAG"])
async def query_rag(request: RAGQueryRequest):
    """
    Query RAG engine for relevant documents
    
    Use this endpoint to get case studies, FAQs, and company info
    relevant to a specific contact or query.
    """
    try:
        rag = get_rag_engine()
        
        # Build metadata filter from contact context
        filter_metadata = None
        if request.contact_context:
            filter_metadata = {}
            if "industry" in request.contact_context:
                filter_metadata["industry"] = request.contact_context["industry"]
        
        # Query RAG engine
        results = rag.query(
            query_text=request.query,
            collection_names=request.collections,
            top_k=request.top_k,
            filter_metadata=filter_metadata
        )
        
        # Count total results
        total_results = sum(len(docs) for docs in results.values())
        
        return {
            "query": request.query,
            "results": results,
            "total_results": total_results
        }
    
    except Exception as e:
        logger.error(f"RAG query error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/rag/collections", tags=["RAG"])
async def get_collections():
    """Get list of available collections with document counts"""
    rag = get_rag_engine()
    
    collections = {}
    for name in rag.collections.keys():
        collections[name] = {
            "count": rag.get_collection_count(name)
        }
    
    return {
        "collections": collections,
        "total_collections": len(collections)
    }


@app.post("/rag/add", tags=["RAG"])
async def add_documents(
    collection: str = Query(..., description="Collection name"),
    documents: List[str] = Body(..., description="List of documents"),
    metadatas: List[Dict[str, Any]] = Body(..., description="List of metadata")
):
    """
    Add documents to a collection
    
    This endpoint is used by data loaders to populate ChromaDB.
    """
    try:
        rag = get_rag_engine()
        
        if len(documents) != len(metadatas):
            raise HTTPException(
                status_code=400,
                detail="documents and metadatas must have the same length"
            )
        
        success = rag.add_documents(
            collection_name=collection,
            documents=documents,
            metadatas=metadatas
        )
        
        if not success:
            raise HTTPException(status_code=500, detail="Failed to add documents")
        
        return {
            "collection": collection,
            "documents_added": len(documents),
            "success": True
        }
    
    except Exception as e:
        logger.error(f"Add documents error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


class RAGDeleteRequest(BaseModel):
    """Request model for RAG delete (collection or documents by ids)"""
    collection: str = Field(..., description="Collection name")
    delete_all: Optional[bool] = Field(False, description="If true, delete entire collection")
    delete_collection: Optional[bool] = Field(False, description="Alias for delete_all (Co-Pilot compatibility)")
    ids: Optional[List[str]] = Field(None, description="Document IDs to delete (optional)")


@app.post("/rag/delete", tags=["RAG"])
async def delete_documents(request: RAGDeleteRequest):
    """
    Delete documents or an entire collection from ChromaDB.

    - Pass delete_all=true (or delete_collection=true) to remove the whole collection.
    - Pass ids=[...] to delete specific documents by ID.
    """
    try:
        rag = get_rag_engine()
        delete_all = request.delete_all or request.delete_collection
        if delete_all:
            result = rag.delete_documents(collection_name=request.collection, delete_all=True)
        elif request.ids:
            result = rag.delete_documents(
                collection_name=request.collection,
                ids=request.ids,
            )
        else:
            raise HTTPException(
                status_code=400,
                detail="Provide delete_all=true (or delete_collection=true) or ids=[...]",
            )
        if not result.get("success"):
            raise HTTPException(
                status_code=400,
                detail=result.get("error", "Delete failed"),
            )
        return {
            "success": True,
            "message": f"Deleted {result.get('deleted_count', 0)} document(s)",
            "deleted_count": result.get("deleted_count", 0),
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"RAG delete error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/cron/status", tags=["CRON"])
async def cron_status():
    """Get CRON scheduler status"""
    scheduler = get_cron_scheduler()
    return scheduler.get_status()


@app.post("/cron/trigger", tags=["CRON"])
async def trigger_cron():
    """Manually trigger CRON job (for testing)"""
    try:
        scheduler = get_cron_scheduler()
        scheduler.promote_scheduled_drafts()
        return {
            "success": True,
            "message": "CRON job triggered manually"
        }
    except Exception as e:
        logger.error(f"Manual CRON trigger error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# Langflow routes are now handled by the separate router above


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=False,
        log_level="info"
    )
