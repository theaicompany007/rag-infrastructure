# Deployment Steps: Update RAG Infrastructure and VANI on chroma-vm

## Quick Summary

You have two options:
1. **Automated (Recommended)**: Use the deployment scripts
2. **Manual**: Push to GitHub, then SSH to VM and pull

---

## Option 1: Automated Deployment (Recommended)

### For RAG Infrastructure

```powershell
# Navigate to rag-infrastructure directory
cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\rag-infrastructure

# Run complete deployment script
.\deploy-rag-infrastructure-complete.ps1
```

**What it does:**
1. ✅ Pushes changes to GitHub (auto-commits if needed)
2. ✅ Pulls latest code on VM (or clones if missing)
3. ✅ Copies `.env.local` and `.env` files
4. ✅ Sets permissions on shell scripts
5. ✅ Runs `manage-infra.sh restart` (or `start` if not running)
6. ✅ Checks service status

**Options:**
```powershell
# Skip push (if already pushed)
.\deploy-rag-infrastructure-complete.ps1 -SkipPush

# Only push, don't deploy
.\deploy-rag-infrastructure-complete.ps1 -SkipDeploy

# Auto-commit with message
.\deploy-rag-infrastructure-complete.ps1 -AutoCommit -CommitMessage "Add ngrok management"

# Fresh clone (removes and clones fresh)
.\deploy-rag-infrastructure-complete.ps1 -FreshClone
```

### For VANI

```powershell
# Navigate to vani directory
cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\vani

# Run complete deployment script
.\deploy-vani-complete.ps1
```

**What it does:**
1. ✅ Pushes changes to GitHub
2. ✅ Syncs code to VM
3. ✅ Copies environment files
4. ✅ Sets permissions
5. ✅ Runs `manage-vani.sh full-deploy` (or specified action)

---

## Option 2: Manual Deployment

### Step 1: Push to GitHub

**For RAG Infrastructure:**
```powershell
cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\rag-infrastructure
.\push-to-github.ps1 -AutoCommit -CommitMessage "Add ngrok management"
```

**For VANI:**
```powershell
cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\vani
# Use git commands or push script if available
git add -A
git commit -m "Update vani"
git push origin main
```

### Step 2: SSH to VM and Pull Updates

```bash
# SSH to VM
gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic

# Update RAG Infrastructure
cd /home/postgres/rag-infrastructure
git pull origin main

# Update VANI
cd /home/postgres/vani
git pull origin main
```

### Step 3: Restart Services

**RAG Infrastructure:**
```bash
cd /home/postgres/rag-infrastructure
./manage-infra.sh restart
```

**VANI:**
```bash
cd /home/postgres/vani
./manage-vani.sh restart
```

---

## What Changed (Ngrok Integration)

### RAG Infrastructure Changes:
- ✅ `manage-infra.sh` - Added ngrok management commands
- ✅ `infra-ngrok.service` - New systemd service file
- ✅ `README.md` - Updated with ngrok documentation
- ✅ `NGROK_MANAGEMENT.md` - New guide
- ✅ `NGROK_INTEGRATION_SUMMARY.md` - Summary document

### New Commands Available:
```bash
# On VM after deployment
cd /home/postgres/rag-infrastructure

# Check all services (including ngrok)
./manage-infra.sh status

# Enable ngrok
./manage-infra.sh enable-ngrok

# Check ngrok status
./manage-infra.sh ngrok-status

# Disable ngrok
./manage-infra.sh disable-ngrok
```

---

## Recommended Workflow

### 1. Deploy RAG Infrastructure First

```powershell
cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\rag-infrastructure
.\deploy-rag-infrastructure-complete.ps1 -AutoCommit -CommitMessage "Add ngrok management to infrastructure"
```

### 2. Verify RAG Infrastructure

```bash
# SSH to VM
gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic

# Check status
cd /home/postgres/rag-infrastructure
./manage-infra.sh status

# Test ngrok commands
./manage-infra.sh ngrok-status
```

### 3. Deploy VANI (if needed)

```powershell
cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\vani
.\deploy-vani-complete.ps1
```

---

## Troubleshooting

### If GitHub Push Fails

The scripts automatically fall back from SSH to HTTPS. If both fail:

1. **For SSH**: Add your SSH key to GitHub
   - https://github.com/settings/keys

2. **For HTTPS**: Configure credential helper
   ```powershell
   git config --global credential.helper wincred
   ```

### If VM Git Pull Fails

The VM needs its SSH key added to GitHub:

```bash
# On VM, get the public key
cat ~/.ssh/id_ed25519.pub

# Add it to GitHub at:
# https://github.com/theaicompany007/rag-infrastructure/settings/keys
```

### If Services Don't Start

```bash
# Check logs
cd /home/postgres/rag-infrastructure
docker compose -p infra logs

# Check status
./manage-infra.sh status

# Restart manually
./manage-infra.sh restart
```

---

## Verification Checklist

After deployment, verify:

- [ ] RAG Infrastructure services running (`./manage-infra.sh status`)
- [ ] Ngrok commands work (`./manage-infra.sh ngrok-status`)
- [ ] Docker containers running (`docker ps`)
- [ ] Network exists (`docker network ls | grep shared-infra-network`)
- [ ] VANI can connect to infrastructure (if deploying VANI)

---

## Quick Reference

**Deploy RAG Infrastructure:**
```powershell
cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\rag-infrastructure
.\deploy-rag-infrastructure-complete.ps1
```

**Deploy VANI:**
```powershell
cd C:\Raaj\kcube_consulting_labs\onlyne-reputation\vani
.\deploy-vani-complete.ps1
```

**Check Status on VM:**
```bash
cd /home/postgres/rag-infrastructure
./manage-infra.sh status
./manage-infra.sh ngrok-status
```
