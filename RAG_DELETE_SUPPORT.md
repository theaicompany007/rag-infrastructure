# RAG Collection/Document Delete Support

The RAG service can support **deleting collections or documents** so that Co-Pilot "Delete collection" works.

## What Was Added

- **`POST /rag/delete`** – Accepts JSON:
  - `{ "collection": "<name>", "delete_all": true }` or `"delete_collection": true` → deletes the entire collection in ChromaDB.
  - `{ "collection": "<name>", "ids": ["id1", "id2"] }` → deletes only those document IDs.

## Where the Code Lives

The implementation is in **`onlynereputation-agentic-app/workers`**:

- **`rag_engine.py`** – `delete_documents(collection_name, ids=None, delete_all=False)` using ChromaDB `delete_collection` and `collection.delete(ids=...)`.
- **`main.py`** – `POST /rag/delete` endpoint and `RAGDeleteRequest` model.

## Deploying Delete Support

1. **If your RAG service runs from rag-infrastructure** (e.g. on chroma-vm):
   - Copy the updated `main.py` and `rag_engine.py` from `onlynereputation-agentic-app/workers/` into `rag-infrastructure/workers/` (or onto the VM at `~/rag-infrastructure/workers/`).
   - Rebuild and restart the rag-service container:
     ```bash
     docker compose build rag-service && docker compose up -d rag-service
     ```

2. **If you clone workers from the VM** with `clone-files.ps1`:
   - First push the updated `main.py` and `rag_engine.py` to the VM’s `~/rag-infrastructure/workers/`, then rebuild the container on the VM. Future clones will include the delete support.

After deployment, Co-Pilot’s "Delete collection" (and the Next.js API `POST /api/vani/rag/delete` with `delete_all: true`) will work against this RAG service.
