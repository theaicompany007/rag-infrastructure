# RAG Infrastructure

Shared infrastructure services for VANI and other projects, including RAG service, ChromaDB, Redis, and Celery.

## Services

- **rag-service**: RAG API service
- **chroma**: ChromaDB vector database
- **redis**: Redis message broker and cache
- **celery-worker**: Celery worker for processing VANI campaign/CRM/workflow tasks (NEW)

## Setup

### 1. Clone from Remote Server

If you haven't already cloned the repository, run:

```powershell
.\clone-from-vm.ps1
```

Or manually:
```bash
scp -r postgres@chroma-vm:~/rag-infrastructure/* .
```

### 2. Start Infrastructure

```bash
./manage-infra.sh start
```

### 3. Verify Services

```bash
./manage-infra.sh status
```

## Docker Network

All services run on `shared-infra-network` which allows other projects (like VANI) to connect and access these services.

## Celery Configuration

The Celery worker processes tasks from the VANI project:
- Campaign tasks (campaigns queue)
- CRM sync tasks (crm_sync queue)  
- Workflow tasks (workflows queue)

### Enable/Disable Celery

```bash
# Enable Celery worker
./manage-infra.sh enable-celery

# Disable Celery worker
./manage-infra.sh disable-celery

# Check Celery status
./manage-infra.sh celery-status
```

## Environment Variables

See `.env.example` for required environment variables.

Key variables:
- `REDIS_URL`: Redis connection URL (default: `redis://redis:6379/0`)
- `CELERY_BROKER_URL`: Celery broker URL (defaults to REDIS_URL)
- `CELERY_RESULT_BACKEND`: Celery result backend (defaults to REDIS_URL)
- `CELERY_ENABLED`: Enable/disable Celery worker (default: `true`)

## Management Commands

```bash
./manage-infra.sh start          # Start all services
./manage-infra.sh stop           # Stop all services
./manage-infra.sh restart        # Restart all services
./manage-infra.sh status         # Show status of all services
./manage-infra.sh enable-celery  # Enable Celery worker
./manage-infra.sh disable-celery # Disable Celery worker
./manage-infra.sh celery-status  # Check Celery worker status
```

## Integration with VANI

VANI connects to this infrastructure via `shared-infra-network`:
- Redis: `redis://redis:6379/0`
- RAG Service: `http://rag-service:8000` (or configured URL)
- ChromaDB: `chroma:8000`
- Celery: Tasks are processed by celery-worker service

VANI can fall back to sync mode (`USE_SYNC_MODE=true`) if Celery is unavailable.
