# VM Disk Full – Free Space on /mnt/chroma-data

When `df -h` shows:
```text
/dev/sdb   49G  48G    0 100% /mnt/chroma-data
```
the data disk is full. Redis AOF/ChromaDB can fail with "No space left on device".

## 1. See what is using space

```bash
# Option A: One directory at a time (always works)
sudo du -sh /mnt/chroma-data/docker
sudo du -sh /mnt/chroma-data/chroma-data
sudo du -sh /mnt/chroma-data/chroma-data-v0424
sudo du -sh /mnt/chroma-data/c1feb291-866c-4e96-ae84-843be7044eb2

# Option B: All subdirs (if your sort supports -h)
sudo du -sh /mnt/chroma-data/* | sort -hr

# Option C: All subdirs, numeric sort (works everywhere)
sudo du -s /mnt/chroma-data/* | sort -rn
# (Numbers are in KB; divide by 1024 for GB)

# Option D: Total for the mount
sudo du -sh /mnt/chroma-data
```

## 2. Free space – safe options

### A. Docker system prune (removes unused images/containers/networks)

```bash
docker system prune -f
docker volume prune -f   # optional: remove unused volumes (only if you don’t need them)
```

### B. Old ChromaDB data (if you have multiple versions)

```bash
# List and pick old dirs to remove (replace with your real paths)
ls -la /mnt/chroma-data/
# Example: remove an old backup or old chroma dir you don’t need
# sudo rm -rf /mnt/chroma-data/old-backup
```

### C. Logs and temp files

```bash
# Docker container logs
sudo sh -c 'truncate -s 0 /var/lib/docker/containers/*/*-json.log'

# System logs (optional)
sudo journalctl --vacuum-size=100M
```

### D. Redis persistence (temporary – allows Redis to run while you free space)

If Redis is failing because of disk full:

```bash
# Disable AOF so Redis stops writing to disk (data stays in memory only until restart)
docker exec redis redis-cli CONFIG SET appendonly no
docker exec redis redis-cli CONFIG SET stop-writes-on-bgsave-error no
```

After freeing space, re-enable AOF:

```bash
docker exec redis redis-cli CONFIG SET appendonly yes
```

## 3. Check where Docker stores Redis/Chroma data

```bash
docker volume inspect infra_redis-data 2>/dev/null || true
docker volume inspect $(docker volume ls -q | head -20) 2>/dev/null
```

If Redis or Chroma volumes are on `/mnt/chroma-data`, freeing space there (steps 2A–2C) will fix the "No space left" issue.

## 4. After freeing space

- Re-enable Redis AOF if you turned it off:  
  `docker exec redis redis-cli CONFIG SET appendonly yes`
- Restart infrastructure if needed:  
  `cd ~/rag-infrastructure && ./manage-infra.sh restart`
