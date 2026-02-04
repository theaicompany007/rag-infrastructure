# Setup Instructions for RAG Infrastructure with Celery

## Prerequisites

1. **Clone the repository from remote server:**
   ```powershell
   cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\rag-infrastructure
   .\clone-from-vm.ps1
   ```
   
   Or manually:
   ```bash
   scp -r postgres@chroma-vm:~/rag-infrastructure/* .
   ```

2. **Merge template files with actual files:**
   - `docker-compose.yml.template` → Merge Celery service into your `docker-compose.yml`
   - `manage-infra.sh.template` → Merge Celery commands into your `manage-infra.sh`
   - `.env.example` → Add Celery variables to your `.env.example`

## Adding Celery to Existing docker-compose.yml

1. Open your existing `docker-compose.yml`
2. Add the `celery-worker` service from `docker-compose.yml.template`
3. Ensure the `shared-infra-network` is defined
4. Make sure Redis service is configured (it should already be there)

## Adding Celery Commands to manage-infra.sh

1. Open your existing `manage-infra.sh`
2. Add the Celery command functions from `manage-infra.sh.template`:
   - `cmd_enable_celery()`
   - `cmd_disable_celery()`
   - `cmd_celery_status()`
3. Add these cases to the command dispatcher:
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

## Environment Variables

1. Copy `.env.example` to `.env.local`:
   ```bash
   cp .env.example .env.local
   ```

2. Update `.env.local` with your actual values:
   - `REDIS_URL`: Should be `redis://redis:6379/0` (for Docker network)
   - `CELERY_BROKER_URL`: Same as REDIS_URL
   - `CELERY_RESULT_BACKEND`: Same as REDIS_URL
   - `CELERY_ENABLED`: Set to `true` to enable, `false` to disable

3. Ensure VANI's `.env.local` has the required variables for Celery tasks:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_KEY` or `SUPABASE_KEY`
   - Other VANI environment variables as needed

## Celery Worker Configuration

The Celery worker:
- Builds from VANI's Dockerfile (mounts VANI code)
- Connects to Redis in `shared-infra-network`
- Processes three queues: `campaigns`, `crm_sync`, `workflows`
- Can be enabled/disabled via `CELERY_ENABLED` environment variable

## Testing

1. **Start infrastructure:**
   ```bash
   ./manage-infra.sh start
   ```

2. **Check status:**
   ```bash
   ./manage-infra.sh status
   ```

3. **Check Celery status:**
   ```bash
   ./manage-infra.sh celery-status
   ```

4. **Test enable/disable:**
   ```bash
   ./manage-infra.sh disable-celery
   ./manage-infra.sh enable-celery
   ```

5. **Verify from VANI:**
   - Start VANI application
   - Create a campaign
   - Check if tasks are processed by Celery worker
   - Check VANI logs for task execution

## Troubleshooting

### Celery worker can't import VANI modules

- Ensure VANI code is mounted correctly in docker-compose.yml
- Check that `working_dir` is set to `/app/vani`
- Verify Python path includes VANI modules

### Celery can't connect to Redis

- Check Redis is running: `docker ps | grep redis`
- Verify `shared-infra-network` exists: `docker network ls | grep shared-infra-network`
- Check Redis URL in environment: `redis://redis:6379/0` (not `localhost`)

### Tasks not processing

- Check Celery worker is running: `./manage-infra.sh celery-status`
- Verify `CELERY_ENABLED=true` in `.env.local`
- Check Celery worker logs: `docker logs celery-worker`
- Verify queues are correct: `campaigns`, `crm_sync`, `workflows`

### VANI falls back to sync mode

- This is expected if Celery is unavailable
- Set `USE_SYNC_MODE=false` in VANI's `.env.local` to require Celery
- Check Redis connectivity from VANI container
