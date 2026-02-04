# RAG Infrastructure

Shared infrastructure services for VANI and other projects, including RAG service, ChromaDB, Redis, and Ngrok.

## Services

- **rag-service**: RAG API service (Docker)
- **chroma**: ChromaDB vector database (Docker)
- **redis**: Redis message broker and cache (Docker)
- **ngrok**: Ngrok tunnel service for exposing services publicly (systemd service on host)

**Note:** Celery Worker and Celery Beat run in the VANI project (not here).

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

### Docker Services (RAG/ChromaDB/Redis)
```bash
./manage-infra.sh start          # Start all Docker services
./manage-infra.sh stop           # Stop all Docker services
./manage-infra.sh restart        # Restart all Docker services
./manage-infra.sh status         # Show status of all services (Docker + Ngrok)
```

**Note:** Celery management commands are in VANI project (`./manage-vani.sh enable-celery`, etc.)

### Ngrok Service (Host/Systemd)
```bash
./manage-infra.sh enable-ngrok   # Enable ngrok service (systemd)
./manage-infra.sh disable-ngrok  # Disable ngrok service (systemd)
./manage-infra.sh ngrok-status   # Check ngrok status and active tunnels
```

## Ngrok Configuration

**⚠️ IMPORTANT: Ngrok is for DEVELOPMENT ONLY**

Ngrok runs as a systemd service on the host (not in Docker) to expose services publicly:
- **Development**: Exposes Docker services (RAG, ChromaDB) via public URLs for testing
- **Production**: Use load balancer URLs instead (set `ENABLE_NGROK=false` in `.env.local`)
- Required for webhook services during development (Resend, Twilio, Cal.com)
- Can expose multiple services via tunnel configuration

**Environment Variable:**
```bash
# Development
ENABLE_NGROK=true

# Production (default)
ENABLE_NGROK=false
```

### Ngrok Service Management

**Check Status:**
```bash
./manage-infra.sh ngrok-status
```

**Enable Ngrok:**
```bash
./manage-infra.sh enable-ngrok
```

**Disable Ngrok:**
```bash
./manage-infra.sh disable-ngrok
```

**Manual Commands:**
```bash
# Check service status
sudo systemctl status onlyne-ngrok.service

# Stop service
sudo systemctl stop onlyne-ngrok.service

# Disable from boot
sudo systemctl disable onlyne-ngrok.service

# Check active tunnels
curl http://localhost:4040/api/tunnels
```

### Ngrok Configuration

Ngrok configuration is typically in:
- `~/.config/ngrok/ngrok.yml` (user config)
- `/home/postgres/.config/ngrok/ngrok.yml` (postgres user)

Example config:
```yaml
version: "2"
authtoken: YOUR_AUTH_TOKEN
tunnels:
  vani:
    proto: http
    addr: 5000
    domain: ngrok-dev.ngrok.app
  rag:
    proto: http
    addr: 8001
    domain: rag-dev.ngrok.app
```

## Integration with VANI

VANI connects to this infrastructure via `shared-infra-network`:
- Redis: `redis://redis:6379/0` (used by VANI's Celery Worker and Celery Beat)
- RAG Service: `http://rag-service:8000` (or configured URL)
- ChromaDB: `chroma:8000`
- Ngrok: Exposes services publicly (managed separately as systemd service)

**Note:** VANI's Celery Worker and Celery Beat run in the VANI project and connect to Redis here via `shared-infra-network`.
