# Ngrok Management in RAG Infrastructure

## Overview

Ngrok is integrated into the RAG Infrastructure management system alongside Redis, Celery, RAG, and ChromaDB. Ngrok runs as a systemd service on the host (not in Docker) to expose infrastructure services publicly.

**⚠️ IMPORTANT: Ngrok is for DEVELOPMENT ONLY**
- Production uses load balancer URLs (e.g., `vani.theaicompany.co`)
- Set `ENABLE_NGROK=false` in `.env.local` for production
- Ngrok should only be enabled during development/testing

## Quick Reference

### Check Ngrok Status
```bash
./manage-infra.sh ngrok-status
```

### Enable Ngrok
```bash
./manage-infra.sh enable-ngrok
```

### Disable Ngrok
```bash
./manage-infra.sh disable-ngrok
```

### Check All Services (Including Ngrok)
```bash
./manage-infra.sh status
```

## Service Names

The system checks for multiple possible ngrok service names:
- `onlyne-ngrok.service` - For OnlyneReputation services (may run multiple tunnels)
- `vani-ngrok.service` - For VANI-specific service
- `ngrok-vani.service` - Alternative name
- `infra-ngrok.service` - Infrastructure-specific service (created by management script)

## Integration with Infrastructure

### Service Dependencies

Ngrok depends on:
- Docker services (rag-service, chroma, redis) - Waits for them to be ready
- Network connectivity - Requires internet access
- Ngrok configuration - Needs `~/.config/ngrok/ngrok.yml`

### What Ngrok Exposes

Ngrok can expose:
- **VANI Flask App**: Port 5000 → `ngrok-dev.ngrok.app` (or configured domain)
- **RAG Service**: Port 8001 → `rag-dev.ngrok.app` (if configured)
- **Other Services**: As configured in ngrok.yml

## Configuration

### Development Setup (Ngrok Enabled)

**For development only** - Set in `.env.local`:

```bash
# Enable ngrok for development
ENABLE_NGROK=true
NGROK_DOMAIN=rag-dev.ngrok.app  # or your dev domain
```

### Production Setup (Ngrok Disabled)

**For production** - Set in `.env.local`:

```bash
# Disable ngrok in production (use load balancer)
ENABLE_NGROK=false
# Production uses load balancer URLs, not ngrok
```

### 1. Install Ngrok

```bash
# Ubuntu/Debian
sudo apt-get install ngrok

# Or download from https://ngrok.com/download
```

### 2. Set Authtoken

```bash
ngrok config add-authtoken YOUR_AUTH_TOKEN
```

Get your token from: https://dashboard.ngrok.com/get-started/your-authtoken

### 3. Configure Tunnels

Edit `~/.config/ngrok/ngrok.yml`:

```yaml
version: "2"
authtoken: YOUR_AUTH_TOKEN
tunnels:
  # Development tunnels only
  rag:
    proto: http
    addr: 8001
    domain: rag-dev.ngrok.app  # Development domain
  chroma:
    proto: http
    addr: 8000
    domain: chroma-dev.ngrok.app  # Development domain
```

**Note**: Production should use load balancer URLs, not ngrok domains.

### 4. Enable Service (Development Only)

```bash
# Only enable for development
./manage-infra.sh enable-ngrok
```

**Remember**: Disable ngrok in production by setting `ENABLE_NGROK=false` in `.env.local`.

## Management Commands

### Using Management Script

```bash
# Check status (shows Docker services + Ngrok)
./manage-infra.sh status

# Check ngrok specifically
./manage-infra.sh ngrok-status

# Enable ngrok
./manage-infra.sh enable-ngrok

# Disable ngrok
./manage-infra.sh disable-ngrok
```

### Manual Systemd Commands

```bash
# Check service status
sudo systemctl status onlyne-ngrok.service

# Start service
sudo systemctl start onlyne-ngrok.service

# Stop service
sudo systemctl stop onlyne-ngrok.service

# Enable on boot
sudo systemctl enable onlyne-ngrok.service

# Disable on boot
sudo systemctl disable onlyne-ngrok.service

# View logs
sudo journalctl -u onlyne-ngrok.service -f
```

### Process Management

```bash
# Check running processes
ps aux | grep ngrok

# Stop all ngrok processes
pkill -f ngrok

# Check active tunnels
curl http://localhost:4040/api/tunnels
```

## Status Output

When running `./manage-infra.sh status`, you'll see:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Infrastructure Management (RAG/ChromaDB/Redis/Celery/Ngrok)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Service Containers:
✅ rag-service is running
✅ chroma is running
✅ redis is running
✅ celery-worker is running

Ngrok Service (Host):
  onlyne-ngrok.service: RUNNING
  Active tunnels:
    - https://ngrok-dev.ngrok.app → localhost:5000
```

## Troubleshooting

### Service Not Found

If `enable-ngrok` says "No ngrok systemd service found":
1. Check existing services: `sudo systemctl list-units | grep ngrok`
2. Use existing service: `./manage-infra.sh enable-ngrok` (will detect it)
3. Or create new: The script will create `infra-ngrok.service` if template exists

### Ngrok Not Starting

```bash
# Check logs
sudo journalctl -u onlyne-ngrok.service -n 50

# Verify ngrok is installed
which ngrok
ngrok version

# Check config
cat ~/.config/ngrok/ngrok.yml
```

### Domain Already in Use

```bash
# Check active tunnels
curl http://localhost:4040/api/tunnels

# Stop all ngrok processes
pkill -f ngrok

# Restart service
sudo systemctl restart onlyne-ngrok.service
```

### Multiple Services Conflict

If multiple ngrok services exist:
```bash
# List all
sudo systemctl list-units | grep ngrok

# Stop all
sudo systemctl stop onlyne-ngrok.service vani-ngrok.service ngrok-vani.service

# Use the one you want
sudo systemctl enable onlyne-ngrok.service
sudo systemctl start onlyne-ngrok.service
```

## Best Practices

1. **Use One Service**: Prefer `onlyne-ngrok.service` if it manages multiple tunnels
2. **Check Before Enabling**: Run `ngrok-status` before enabling to see what's running
3. **Monitor Logs**: Check logs if tunnels aren't working: `sudo journalctl -u onlyne-ngrok.service -f`
4. **Domain Management**: Reserve domains in ngrok dashboard before using them
5. **Configuration**: Keep ngrok config in `~/.config/ngrok/ngrok.yml` for easy management

## Integration with Other Projects

### VANI Project

VANI can use ngrok managed by infrastructure:
- Ngrok exposes VANI Flask app (port 5000)
- VANI webhooks use ngrok URL
- Managed via `./manage-infra.sh ngrok-status`

### RAG Service

RAG service can be exposed via ngrok:
- Add tunnel config in `ngrok.yml`
- Expose port 8001
- Accessible via `rag-dev.ngrok.app` (or configured domain)

## Environment Variables

Ngrok service reads from:
- `~/.config/ngrok/ngrok.yml` - Tunnel configuration
- Environment variables (if set in service file)
- Command-line arguments (if configured)

## Related Documentation

- [NGROK_VM_MANAGEMENT_GUIDE.md](../vani/NGROK_VM_MANAGEMENT_GUIDE.md) - Detailed ngrok management guide
- [NGROK_SERVICE_MANAGEMENT.md](../vani/NGROK_SERVICE_MANAGEMENT.md) - Ngrok service setup guide
