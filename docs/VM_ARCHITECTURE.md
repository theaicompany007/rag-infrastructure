# VM Architecture (chroma-vm)

This document describes the complete architecture of the VM: what runs where, why, and how the pieces connect.

---

## 1. High-level layout

On the VM you have **three main application projects**, plus **shared infrastructure**:

```
~/rag-infrastructure/     →  Shared infra (RAG, Chroma, Redis)
~/vani/                   →  VANI Outreach (Flask app, Celery worker, Celery Beat)
~/theaicompany-web/       →  The AI Company website (Next.js or similar)
```

All Docker services that need to talk to each other use the same bridge network: **`shared-infra-network`**.

---

## 2. What runs where (Celery)

| Component | Where it runs | Role |
|-----------|----------------|------|
| **Celery worker** | VANI (`celery-worker`) | Runs VANI tasks (campaigns, CRM, workflows) from Redis. |
| **Celery Beat** | VANI (`celery-beat`) | Schedules VANI periodic tasks; enqueues to Redis. |
| **vani** (Flask) | VANI (`vani`) | Web app; enqueues tasks to Redis. |

So **VANI runs three containers**: the Flask app, Celery worker, and Celery Beat. All connect to Redis in rag-infrastructure via `shared-infra-network`.

---

## 3. Full VM architecture (containers and network)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  shared-infra-network (Docker bridge)                                        │
│                                                                              │
│  ┌─────────────────── RAG INFRASTRUCTURE (~/rag-infrastructure) ─────────┐ │
│  │                                                                         │ │
│  │  rag-service    chroma      redis                                       │ │
│  │  (RAG :8001)    (:8000)     (:6379)                                     │ │
│  │       │                    │                                            │ │
│  │       └────────────────────┘                                            │ │
│  │              (vector DB)                                                │ │
│  │                                                                         │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────── VANI (~/vani) ───────────────────────────────────────┐ │
│  │                                                                         │ │
│  │  vani          celery-worker    celery-beat                            │ │
│  │  (Flask app)   (VANI tasks)     (VANI scheduler)                        │ │
│  │       │              │                  │                               │ │
│  │       └──────────────┴──────────────────┘                               │ │
│  │                    │                                                    │ │
│  │                    └── Redis (broker in infra)                         │ │
│  │       └── RAG / Chroma via rag-service                                  │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────── THEAICOMPANY-WEB (~/theaicompany-web) ───────────────┐ │
│  │                                                                         │ │
│  │  web-app-1                                                              │ │
│  │  (Next.js / site)  ─── can use RAG/Chroma via rag-service if needed    │ │
│  │                                                                         │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

- **Infra** provides: RAG API, ChromaDB, and Redis (shared by all projects).
- **VANI** provides: Flask app, Celery worker, and Celery Beat (all connect to Redis in infra).
- **theaicompany-web** is the public site; it can call rag-service if the app needs RAG.

---

## 4. What each project runs (summary)

| Project              | Containers | Purpose |
|----------------------|------------|---------|
| **rag-infrastructure** | rag-service, chroma, redis | Shared RAG, Chroma, and Redis. |
| **vani**             | vani, celery-worker, celery-beat | VANI Flask app, Celery worker, and Celery Beat. |
| **theaicompany-web** | web-app-1 | The AI Company website. |

---

## 5. Start and stop order

**Start (infra first, then apps that use it):**

1. `~/rag-infrastructure` → `./manage-infra.sh start` (or `rebuild`)
   - Starts RAG service, ChromaDB, and Redis
2. `~/vani` → `./manage-vani.sh start`
   - Starts Flask app, Celery worker, and Celery Beat
   - Celery services connect to Redis in infrastructure
3. `~/theaicompany-web` → `./manage-web.sh start`

**Stop (reverse: apps first, infra last):**

1. `~/theaicompany-web` → `./manage-web.sh stop`
2. `~/vani` → `./manage-vani.sh stop`
   - Stops Flask app, Celery worker, and Celery Beat
3. `~/rag-infrastructure` → `./manage-infra.sh stop`
   - Stops RAG service, ChromaDB, and Redis

This way nothing tries to use Redis, Chroma, or RAG after they're stopped.

---

## 6. Optional: ngrok

Ngrok runs as a **systemd service on the host** (not in Docker). It exposes local services (e.g. RAG, VANI, web) via public URLs for development and webhooks. Production should use proper load balancers instead.

---

**Summary:**  
RAG-infrastructure provides **RAG service, ChromaDB, and Redis** (shared by all projects). VANI runs **three containers**: Flask app, Celery worker, and Celery Beat (all connect to Redis in infrastructure). Together with theaicompany-web, they form the full VM architecture on `shared-infra-network`.
