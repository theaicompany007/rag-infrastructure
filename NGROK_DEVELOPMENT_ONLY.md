# Ngrok: Development Only Usage Pattern

## Overview

Ngrok is used **exclusively for development** in this infrastructure. Production environments use load balancer URLs instead.

## Pattern

### Development Environment
```bash
# .env.local (Development)
ENABLE_NGROK=true
NGROK_DOMAIN=rag-dev.ngrok.app
WEBHOOK_BASE_URL=https://rag-dev.ngrok.app
```

### Production Environment
```bash
# .env.local (Production)
ENABLE_NGROK=false
# WEBHOOK_BASE_URL=https://vani.theaicompany.co  # Load balancer URL
```

## Usage

### Enable Ngrok (Development Only)

```bash
# Set in .env.local
ENABLE_NGROK=true

# Enable service
cd /home/postgres/rag-infrastructure
./manage-infra.sh enable-ngrok
```

### Disable Ngrok (Production)

```bash
# Set in .env.local
ENABLE_NGROK=false

# Disable service
cd /home/postgres/rag-infrastructure
./manage-infra.sh disable-ngrok
```

## Why Development Only?

1. **Production**: Uses load balancer URLs (`vani.theaicompany.co`, etc.)
2. **Development**: Needs public URLs for webhook testing (Resend, Twilio, Cal.com)
3. **Cost**: Ngrok paid domains have quotas - save for development
4. **Security**: Production should use proper load balancers with SSL certificates

## Best Practices

1. **Always set `ENABLE_NGROK=false` in production `.env.local`**
2. **Only enable ngrok when actively developing/testing**
3. **Use development domains** (`*-dev.ngrok.app`) for development
4. **Use production domains** (`*.theaicompany.co`) for production
5. **Check `ENABLE_NGROK` before enabling** - don't enable in production

## Checking Environment

```bash
# Check current ENABLE_NGROK setting
grep ENABLE_NGROK .env.local

# Check if ngrok is enabled
./manage-infra.sh ngrok-status

# Check environment
grep VANI_ENVIRONMENT .env.local
```

## Related Projects

This pattern matches:
- **VANI**: Uses `ENABLE_NGROK=false` in production, `true` for development
- **theaicompany-web**: Same pattern - ngrok commented out/disabled in production

## Migration Checklist

When moving from development to production:

- [ ] Set `ENABLE_NGROK=false` in `.env.local`
- [ ] Update `WEBHOOK_BASE_URL` to load balancer URL
- [ ] Run `./manage-infra.sh disable-ngrok`
- [ ] Verify ngrok is not running: `./manage-infra.sh ngrok-status`
- [ ] Test webhooks with production URL
