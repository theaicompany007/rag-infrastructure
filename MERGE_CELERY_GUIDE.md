# Guide to Merge Celery Configuration

After cloning the files from the remote server, follow these steps to add Celery support.

## Step 1: Review Cloned Files

You should now have:
- `docker-compose.yml` (from remote)
- `manage-infra.sh` (from remote)
- `.env.local` (from remote)
- `workers/` directory with all files

## Step 2: Merge Celery Service into docker-compose.yml

1. Open `docker-compose.yml` (the one you cloned)
2. Open `docker-compose.yml.template` (the template I created)
3. Copy the `celery-worker` service from the template (lines 42-83)
4. Add it to your `docker-compose.yml` under the `services:` section
5. Ensure `shared-infra-network` is defined in the `networks:` section (it should already be there)
6. Ensure `redis-data` volume is defined in the `volumes:` section (add if missing)

### Example merge:

Your `docker-compose.yml` should have something like:
```yaml
services:
  rag-service:
    # ... your existing config ...
  
  chroma:
    # ... your existing config ...
  
  redis:
    # ... your existing config (may need to add healthcheck) ...
  
  celery-worker:  # ADD THIS SERVICE
    build:
      context: ../vani
      dockerfile: Dockerfile
    container_name: celery-worker
    env_file:
      - ../vani/.env.local
    environment:
      - CELERY_BROKER_URL=${CELERY_BROKER_URL:-redis://redis:6379/0}
      - CELERY_RESULT_BACKEND=${CELERY_RESULT_BACKEND:-redis://redis:6379/0}
      - REDIS_URL=${REDIS_URL:-redis://redis:6379/0}
      - CELERY_ENABLED=${CELERY_ENABLED:-true}
      - DOCKER_CONTAINER=true
    networks:
      - shared-infra-network
    volumes:
      - ../vani:/app/vani:ro
    working_dir: /app/vani
    command: >
      sh -c "
        if [ \"$$CELERY_ENABLED\" = \"true\" ]; then
          celery -A app.config.celery_config.celery_app worker 
            --loglevel=info 
            --queues=campaigns,crm_sync,workflows
            --hostname=celery-worker@%h
        else
          echo 'Celery worker disabled (CELERY_ENABLED=false)'
          sleep infinity
        fi
      "
    depends_on:
      redis:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "celery -A app.config.celery_config.celery_app inspect ping -d celery-worker@$$(hostname) || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  shared-infra-network:
    name: shared-infra-network
    driver: bridge

volumes:
  redis-data:  # ADD IF MISSING
    driver: local
```

## Step 3: Merge Celery Commands into manage-infra.sh

1. Open `manage-infra.sh` (the one you cloned)
2. Open `manage-infra.sh.template` (the template I created)
3. Add these three functions to your script:
   - `cmd_enable_celery()` (lines 125-144)
   - `cmd_disable_celery()` (lines 146-165)
   - `cmd_celery_status()` (lines 167-193)
4. Add these cases to the command dispatcher at the end:
   ```bash
   enable-celery)
       cmd_enable_celery
       ;;
   disable-celery)
       cmd_disable_celery
       ;;
   celery-status)
       cmd_celery_status
       ;;
   ```

### Update cmd_status() function

Also update the `cmd_status()` function to include `celery-worker` in the service check loop (around line 112 in template).

## Step 4: Update Environment Variables

1. Open `.env.local` (the one you cloned)
2. Add these variables if they don't exist:
   ```bash
   # Celery Configuration
   CELERY_BROKER_URL=redis://redis:6379/0
   CELERY_RESULT_BACKEND=redis://redis:6379/0
   CELERY_ENABLED=true
   REDIS_URL=redis://redis:6379/0
   ```

## Step 5: Verify Redis Healthcheck

Ensure your Redis service in `docker-compose.yml` has a healthcheck (needed for `depends_on`):
```yaml
redis:
  # ... your existing config ...
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
    interval: 10s
    timeout: 5s
    retries: 5
```

## Step 6: Test the Configuration

1. Make `manage-infra.sh` executable:
   ```bash
   chmod +x manage-infra.sh
   ```

2. Start infrastructure:
   ```bash
   ./manage-infra.sh start
   ```

3. Check status:
   ```bash
   ./manage-infra.sh status
   ```

4. Check Celery status:
   ```bash
   ./manage-infra.sh celery-status
   ```

## Troubleshooting

### If Celery worker fails to start:
- Check that VANI directory exists at `../vani`
- Verify VANI's `.env.local` has required variables
- Check Docker logs: `docker logs celery-worker`

### If Celery can't connect to Redis:
- Verify Redis is running: `docker ps | grep redis`
- Check network: `docker network inspect shared-infra-network`
- Verify Redis URL uses `redis://redis:6379/0` (not `localhost`)

### If tasks aren't processing:
- Check Celery worker logs: `docker logs celery-worker --tail=50`
- Verify queues: `docker exec celery-worker celery -A app.config.celery_config.celery_app inspect active_queues`
- Check VANI can enqueue tasks
