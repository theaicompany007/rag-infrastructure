# VM Architecture (chroma-vm)

This document describes the complete architecture of the VM: what runs where, why, and how the pieces connect.

---

## 1. High-level layout

On the VM you have **three main application projects**, plus **shared infrastructure**:

```
~/rag-infrastructure/     →  Shared infra (RAG, Chroma, Redis, Celery worker, Celery Beat)
~/vani/                   →  VANI Outreach (Django app only; worker + Beat run in infra)
~/theaicompany-web/       →  The AI Company website (Next.js or similar)
```

All Docker services that need to talk to each other use the same bridge network: **`shared-infra-network`**.

---

## 2. What runs where (Celery)

| Component | Where it runs | Role |
|-----------|----------------|------|
| **Celery worker** | rag-infrastructure (`celery-worker`) | Runs VANI tasks (campaigns, CRM, workflows) from Redis. |
| **Celery Beat** | rag-infrastructure (`celery-beat`) | Schedules VANI periodic tasks; enqueues to Redis. |
| **vani** (Django) | VANI (`vani`) | Web app; enqueues tasks to Redis. |

So **VANI only needs one container** (the Django app). Worker and Beat both run in rag-infrastructure. In VANI’s compose you can remove both vani-celery-worker and vani-celery-beat (see §6).

---

## 3. Full VM architecture (containers and network)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  shared-infra-network (Docker bridge)                                        │
│                                                                              │
│  ┌─────────────────── RAG INFRASTRUCTURE (~/rag-infrastructure) ─────────┐ │
│  │                                                                         │ │
│  │  rag-service    chroma      redis    celery-worker   celery-beat         │ │
│  │  (RAG :8001)    (:8000)     (:6379)  (VANI tasks)    (VANI scheduler)   │ │
│  │       │                    │                 │                  │       │ │
│  │       └────────────────────┘                 │                  │       │ │
│  │              (vector DB)                     │                  │       │ │
│  │                                              │                  │       │ │
│  └──────────────────────────────────────────────┼──────────────────┼───────┘ │
│                                                 │                  │         │
│  ┌─────────────────── VANI (~/vani) ──────────────────────────────┼───────┐ │
│  │                                                                 │       │ │
│  │  vani (Django app only; worker + Beat run in infra)                     │ │
│  │       │                                                                  │ │
│  │       └── Redis (broker) ◄── celery-worker, celery-beat (in infra)      │ │
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

- **Infra** provides: RAG API, ChromaDB, Redis, and one Celery worker (for VANI queues: campaigns, crm_sync, workflows).
- **VANI** provides: the Django app only; Celery worker and Beat run in infra.
- **theaicompany-web** is the public site; it can call rag-service if the app needs RAG.

---

## 4. What each project runs (summary)

| Project              | Containers | Purpose |
|----------------------|------------|---------|
| **rag-infrastructure** | rag-service, chroma, redis, celery-worker, celery-beat | Shared RAG, Chroma, Redis, and VANI’s Celery worker + Beat. |
| **vani**             | vani (Django app only) | VANI app; worker and Beat run in infra. |
| **theaicompany-web** | web-app-1 | The AI Company website. |

---

## 5. Start and stop order

**Start (infra first, then apps that use it):**

1. `~/rag-infrastructure` → `./manage-infra.sh start` (or `rebuild`)
2. `~/vani` → `./manage-vani.sh start`
3. `~/theaicompany-web` → `./manage-web.sh start`

**Stop (reverse: apps first, infra last):**

1. `~/theaicompany-web` → `./manage-web.sh stop`
2. `~/vani` → `./manage-vani.sh stop`
3. `~/rag-infrastructure` → `./manage-infra.sh stop`

This way nothing tries to use Redis, Chroma, or RAG after they’re stopped.

---

## 6. Do you need vani-celery-worker? (Use the infra worker instead)

**You do not need vani-celery-worker** if rag-infrastructure is running. The **infra celery-worker** already runs the same VANI code and the same queues (campaigns, crm_sync, workflows). One worker is enough.

**Recommended:** Use only the **infra celery-worker**. Then VANI needs only two containers:

- **vani** – Django app (enqueues tasks to Redis)
- **vani-celery-beat** – Scheduler (enqueues periodic tasks to Redis)

Tasks are executed by **rag-infrastructure’s celery-worker**; no duplicate worker in VANI.

### How to stop using vani-celery-worker

In the **VANI** project (`~/vani` on the VM):

1. **Option A – Remove the service from VANI’s docker-compose**  
   In `vani/docker-compose.yml` (or whatever file `manage-vani.sh` uses), remove or comment out the `celery-worker` service. Keep the `vani` and `celery-beat` services. Ensure both use `shared-infra-network` and the same Redis URL (e.g. `redis://redis:6379/0`) so Beat and the app talk to the same Redis the infra worker uses.

2. **Option B – Don’t start it**  
   If your `manage-vani.sh start` explicitly starts only certain services, start only the app and beat, not the worker. For example:
   ```bash
   docker compose up -d vani vani-celery-beat
   ```
   (exact service names may differ in your compose file)

3. **Restart order**  
   Start infra first (so Redis and infra celery-worker are up), then VANI (vani + beat). The infra worker will consume tasks from Redis; Beat will schedule; the app will enqueue.

After this, VANI runs 2 containers (vani + vani-celery-beat) and the infra runs the single shared Celery worker.

---

## 7. Optional: ngrok

Ngrok runs as a **systemd service on the host** (not in Docker). It exposes local services (e.g. RAG, VANI, web) via public URLs for development and webhooks. Production should use proper load balancers instead.

---

**Summary:**  
RAG-infrastructure runs **celery-worker** and **celery-beat** for VANI. VANI can run **one container** (the Django app). See §6 for removing worker and Beat from VANI’s compose. Together with theaicompany-web, they form the full VM architecture on `shared-infra-network`.
