# RAG Infrastructure Deployment Scripts

This directory contains PowerShell scripts for deploying rag-infrastructure to GitHub and the VM.

## Scripts

### 1. `push-to-github.ps1`

Simple script to push rag-infrastructure code to GitHub.

**Usage:**
```powershell
.\push-to-github.ps1
.\push-to-github.ps1 -AutoCommit -CommitMessage "Update infrastructure"
.\push-to-github.ps1 -GitHubMethod https
```

**Parameters:**
- `-CommitMessage`: Custom commit message
- `-AutoCommit`: Automatically commit changes without prompting
- `-GitHubMethod`: 'ssh', 'https', or 'auto' (default: 'auto')
- `-Help`: Show help message

**Features:**
- Auto-detects SSH/HTTPS based on current git remote
- Automatic fallback from SSH to HTTPS if SSH fails
- Supports both authentication methods

### 2. `deploy-rag-infrastructure-complete.ps1`

Complete deployment script that automates the full workflow:
1. Push to GitHub
2. Pull/clone on VM
3. Copy environment files (.env.local, .env)
4. Set script permissions
5. Start infrastructure (manage-infra.sh start)
6. Check service status

**Usage:**
```powershell
# Full deployment
.\deploy-rag-infrastructure-complete.ps1

# Auto-commit and deploy
.\deploy-rag-infrastructure-complete.ps1 -AutoCommit -CommitMessage "Update infrastructure"

# Skip push (already pushed), fresh clone on VM
.\deploy-rag-infrastructure-complete.ps1 -SkipPush -FreshClone

# Only push to GitHub, don't deploy
.\deploy-rag-infrastructure-complete.ps1 -SkipDeploy
```

**Parameters:**
- `-SkipPush`: Skip pushing to GitHub
- `-SkipDeploy`: Only push to GitHub, don't deploy
- `-CommitMessage`: Custom commit message
- `-AutoCommit`: Automatically commit changes
- `-FreshClone`: Remove existing project and clone fresh
- `-GitHubMethod`: 'ssh', 'https', or 'auto' (default: 'auto')
- `-Help`: Show help message

## GitHub Repository

- **Repository**: https://github.com/theaicompany007/rag-infrastructure
- **SSH URL**: git@github.com:theaicompany007/rag-infrastructure.git
- **HTTPS URL**: https://github.com/theaicompany007/rag-infrastructure.git

## VM Configuration

- **VM Host**: chroma-vm
- **VM User**: postgres
- **Remote Path**: /home/postgres/rag-infrastructure
- **Zone**: asia-south1-a
- **Project**: onlynereputation-agentic

## Deployment Workflow

### Typical Workflow

1. **Make changes locally**
2. **Push to GitHub:**
   ```powershell
   .\push-to-github.ps1 -AutoCommit -CommitMessage "Your changes"
   ```
3. **Deploy to VM:**
   ```powershell
   .\deploy-rag-infrastructure-complete.ps1 -SkipPush
   ```

### Full Deployment (Push + Deploy)

```powershell
.\deploy-rag-infrastructure-complete.ps1 -AutoCommit
```

This will:
- Commit and push changes to GitHub
- Pull/clone on VM
- Copy .env.local and .env files
- Set permissions
- Start infrastructure services
- Check status

## Files Copied to VM

The deployment script copies:
- `.env.local` - Environment variables (required)
- `.env` - Additional environment variables (optional)

## Infrastructure Services

After deployment, the following services are started:
- **RAG Service**: Port 8001
- **ChromaDB**: Port 8000
- **Redis**: Port 6379
- **Celery Worker**: Processing VANI tasks (if enabled)

## Managing Services on VM

After deployment, you can manage services using `manage-infra.sh`:

```bash
# SSH to VM
gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic

# Then run:
cd /home/postgres/rag-infrastructure
./manage-infra.sh start          # Start all services
./manage-infra.sh stop           # Stop all services
./manage-infra.sh restart        # Restart all services
./manage-infra.sh status         # Check status
./manage-infra.sh enable-celery  # Enable Celery worker
./manage-infra.sh disable-celery # Disable Celery worker
./manage-infra.sh celery-status  # Check Celery status
```

## Troubleshooting

### GitHub Push Fails

1. **SSH Method:**
   - Set up SSH key: `ssh-keygen -t ed25519 -C 'your_email@example.com'`
   - Add to ssh-agent: `ssh-add ~/.ssh/id_ed25519`
   - Add public key to GitHub: https://github.com/settings/keys

2. **HTTPS Method:**
   - Configure credential helper: `git config --global credential.helper wincred`
   - Or use personal access token when prompted

3. **Force Method:**
   ```powershell
   .\push-to-github.ps1 -GitHubMethod https
   ```

### VM Git Operations Fail

The VM needs its SSH key added to GitHub:
1. Get VM's public key:
   ```bash
   gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic --command='cat ~/.ssh/id_ed25519.pub'
   ```
2. Add to GitHub: https://github.com/theaicompany007/rag-infrastructure/settings/keys
3. Check "Allow write access" if you want the VM to push

### Services Not Starting

1. Check logs:
   ```bash
   gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic --command='cd /home/postgres/rag-infrastructure && docker compose -p infra logs'
   ```

2. Check status:
   ```bash
   gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic --command='cd /home/postgres/rag-infrastructure && ./manage-infra.sh status'
   ```

3. Verify .env.local is copied correctly

## Notes

- The scripts use `gcloud compute ssh` and `gcloud compute scp` for VM operations
- VM git operations always use SSH (VM has its own SSH key)
- Local git operations can use either SSH or HTTPS (auto-detected or specified)
- Environment files (.env.local, .env) are copied from local to VM
- Scripts automatically handle line endings (Unix format for shell scripts)
