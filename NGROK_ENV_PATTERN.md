# Ngrok Environment Pattern: Development Only

## Pattern Overview

Following the same pattern as VANI and theaicompany-web projects:
- **Development**: Uncomment ngrok settings, set `ENABLE_NGROK=true`
- **Production**: Comment out ngrok settings, set `ENABLE_NGROK=false`, use load balancer URLs

## .env.local Pattern

### Development Configuration

```bash
# Development environment - UNCOMMENT these
ENABLE_NGROK=true
NGROK_DOMAIN=rag-dev.ngrok.app
WEBHOOK_BASE_URL=https://rag-dev.ngrok.app
VANI_ENVIRONMENT=dev

# Production environment - COMMENT these out in development
# ENABLE_NGROK=false
# WEBHOOK_BASE_URL=https://vani.theaicompany.co
# VANI_ENVIRONMENT=prod
```

### Production Configuration

```bash
# Development environment - COMMENT these out in production
# ENABLE_NGROK=true
# NGROK_DOMAIN=rag-dev.ngrok.app
# WEBHOOK_BASE_URL=https://rag-dev.ngrok.app
# VANI_ENVIRONMENT=dev

# Production environment - UNCOMMENT these
ENABLE_NGROK=false
WEBHOOK_BASE_URL=https://vani.theaicompany.co
VANI_ENVIRONMENT=prod
```

## Management Commands

### Enable Ngrok (Development)

```bash
# 1. Update .env.local (uncomment development section)
ENABLE_NGROK=true

# 2. Enable service
cd /home/postgres/rag-infrastructure
./manage-infra.sh enable-ngrok
```

### Disable Ngrok (Production)

```bash
# 1. Update .env.local (comment out development, uncomment production)
ENABLE_NGROK=false

# 2. Disable service
cd /home/postgres/rag-infrastructure
./manage-infra.sh disable-ngrok
```

## Consistency with Other Projects

This pattern matches:
- ✅ **VANI**: Comments/uncomments ngrok URLs based on environment
- ✅ **theaicompany-web**: Same pattern - ngrok for dev only

## Checklist

### Before Development
- [ ] Uncomment development ngrok URLs in `.env.local`
- [ ] Set `ENABLE_NGROK=true`
- [ ] Comment out production URLs
- [ ] Run `./manage-infra.sh enable-ngrok`

### Before Production Deployment
- [ ] Comment out development ngrok URLs in `.env.local`
- [ ] Set `ENABLE_NGROK=false`
- [ ] Uncomment production load balancer URLs
- [ ] Run `./manage-infra.sh disable-ngrok`
- [ ] Verify: `./manage-infra.sh ngrok-status` shows disabled
