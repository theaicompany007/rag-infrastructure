# Disk cleanup for RAG infrastructure VM

This document describes **safe** disk cleanup that does **not** stop or delete running containers for **rag-infrastructure**, **vani**, or **theaicompany-web**. It only removes unused Docker resources and an obsolete directory.

---

## One-time manual cleanup (run on the VM)

Run these commands once to reclaim space immediately.

### 1. Inspect usage under `/mnt/chroma-data`

```bash
cd /mnt/chroma-data
sudo du -sh docker/*
```

This shows which subdirectories under `docker/` use space. The `docker/` directory is Docker daemon data (often large); the prune script and optional steps below reduce it.

### 2. Remove the old Chroma directory (no longer used)

The directory `/mnt/chroma-data/chroma-data` is obsolete; Chroma now uses `/mnt/chroma-data-v0424` (mounted in compose). Safe to remove:

```bash
sudo rm -rf /mnt/chroma-data/chroma-data
```

### 3. Run the prune script once manually

After installing the script (see **Cron job setup** below):

```bash
sudo /usr/local/bin/docker-prune-safe.sh
```

This removes unused containers, networks, dangling images, then all unused images and volumes. **It does not stop or remove anything used by running containers.**

---

## Cron job setup (daily automated cleanup)

Install the script and daily cron job from the **repo root** on the VM (e.g. `/home/postgres/rag-infrastructure`):

```bash
sudo cp scripts/docker-prune-safe.sh /usr/local/bin/docker-prune-safe.sh
sudo chmod +x /usr/local/bin/docker-prune-safe.sh
sudo tee /etc/cron.daily/docker-prune-safe >/dev/null <<'EOF'
#!/bin/sh
/usr/local/bin/docker-prune-safe.sh >> /var/log/docker-prune-safe.log 2>&1
EOF
sudo chmod +x /etc/cron.daily/docker-prune-safe
```

- **Script:** `/usr/local/bin/docker-prune-safe.sh`
- **Cron file:** `/etc/cron.daily/docker-prune-safe` (run by cron daily)
- **Log:** `/var/log/docker-prune-safe.log` (stdout and stderr)

---

## What is safe

- **Unused** containers, networks, images, and volumes are removed.
- **In-use** resources (images/volumes referenced by running containers) are **kept**.
- Removing `/mnt/chroma-data/chroma-data` does not affect the running Chroma service (which uses `/mnt/chroma-data-v0424`).
- rag-infrastructure, vani, and theaicompany-web are **not** stopped or deleted.

---

## Optional: extra image prune

The script comments out `docker image prune -a -f`. That command also does not touch images used by running containers. If you want it, uncomment the optional block in `/usr/local/bin/docker-prune-safe.sh`.
