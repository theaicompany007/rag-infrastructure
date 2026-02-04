# Verification Checklist

Use this checklist to verify that Celery integration is working correctly after setup.

## Pre-Verification

- [ ] Repository cloned from `postgres@chroma-vm:~/rag-infrastructure`
- [ ] Template files merged with actual files:
  - [ ] `docker-compose.yml` includes `celery-worker` service
  - [ ] `manage-infra.sh` includes Celery commands
  - [ ] `.env.example` includes Celery variables
- [ ] `.env.local` created and configured
- [ ] VANI project is accessible at `../vani`

## Infrastructure Verification

### 1. Network Setup
- [ ] `shared-infra-network` exists:
  ```bash
  docker network ls | grep shared-infra-network
  ```
- [ ] All services are on the network:
  ```bash
  docker network inspect shared-infra-network
  ```

### 2. Service Status
- [ ] Redis is running:
  ```bash
  docker ps | grep redis
  docker exec redis redis-cli ping  # Should return PONG
  ```
- [ ] Celery worker is running:
  ```bash
  docker ps | grep celery-worker
  ./manage-infra.sh celery-status
  ```

### 3. Celery Worker Health
- [ ] Celery worker can ping:
  ```bash
  docker exec celery-worker celery -A app.config.celery_config.celery_app inspect ping
  ```
- [ ] Celery worker can import VANI modules:
  ```bash
  docker exec celery-worker python -c "from app.config.celery_config import celery_app; print('OK')"
  ```
- [ ] Queues are registered:
  ```bash
  docker exec celery-worker celery -A app.config.celery_config.celery_app inspect active_queues
  ```
  Should show: `campaigns`, `crm_sync`, `workflows`

## VANI Integration Verification

### 4. VANI Connection
- [ ] VANI can connect to Redis:
  ```bash
  # From VANI container or local environment
  python -c "import redis; r = redis.from_url('redis://redis:6379/0'); print(r.ping())"
  ```
- [ ] VANI can enqueue Celery tasks:
  ```python
  # Test in VANI Python shell
  from app.tasks.campaign_tasks import enqueue_campaign_batch
  result = enqueue_campaign_batch.delay('test-run-id', 10)
  print(result.id)  # Should return task ID
  ```

### 5. Task Processing
- [ ] Create a test campaign in VANI
- [ ] Verify task appears in Celery:
  ```bash
  docker exec celery-worker celery -A app.config.celery_config.celery_app inspect active
  ```
- [ ] Check task execution in logs:
  ```bash
  docker logs celery-worker --tail=50
  ```

### 6. Enable/Disable Functionality
- [ ] Disable Celery:
  ```bash
  ./manage-infra.sh disable-celery
  docker ps | grep celery-worker  # Should not show running
  ```
- [ ] VANI falls back to sync mode (check VANI logs)
- [ ] Enable Celery:
  ```bash
  ./manage-infra.sh enable-celery
  docker ps | grep celery-worker  # Should show running
  ```
- [ ] VANI uses async mode again

## Queue Verification

### 7. Queue Processing
- [ ] Campaign tasks go to `campaigns` queue
- [ ] CRM tasks go to `crm_sync` queue
- [ ] Workflow tasks go to `workflows` queue
- [ ] Tasks are processed successfully (check logs)

## Performance Verification

### 8. Load Testing (Optional)
- [ ] Enqueue multiple campaign tasks
- [ ] Verify tasks are processed in parallel
- [ ] Check Redis queue depth:
  ```bash
  docker exec redis redis-cli LLEN celery  # Check queue length
  ```
- [ ] Monitor Celery worker resource usage:
  ```bash
  docker stats celery-worker
  ```

## Troubleshooting Commands

If verification fails, use these commands:

```bash
# Check all container status
docker ps -a

# Check network connectivity
docker network inspect shared-infra-network

# Check Redis connectivity from Celery
docker exec celery-worker python -c "import redis; r = redis.from_url('redis://redis:6379/0'); print(r.ping())"

# Check Celery worker logs
docker logs celery-worker --tail=100

# Check VANI logs for Celery connection
docker logs vani --tail=100 | grep -i celery

# Test Celery task manually
docker exec celery-worker celery -A app.config.celery_config.celery_app inspect registered

# Check environment variables
docker exec celery-worker env | grep -E "(CELERY|REDIS)"
```

## Success Criteria

All checks should pass:
- ✅ Infrastructure services running
- ✅ Celery worker healthy and processing tasks
- ✅ VANI can enqueue tasks
- ✅ Tasks are processed in correct queues
- ✅ Enable/disable functionality works
- ✅ VANI fallback to sync mode works when Celery disabled
