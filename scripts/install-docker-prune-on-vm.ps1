# Install docker-prune-safe script and daily cron on chroma-vm via gcloud SSH/SCP.
# Uses same VM connection as deploy-rag-infrastructure-complete.ps1.
# Run from repo root: .\scripts\install-docker-prune-on-vm.ps1

$ErrorActionPreference = "Stop"
$VmHost = "chroma-vm"
$VmUser = "postgres"
$GcpZone = "asia-south1-a"
$GcpProject = "onlynereputation-agentic"
$RemoteProjectPath = "/home/postgres/rag-infrastructure"
$ScriptDir = Join-Path $PSScriptRoot "."
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

Write-Host "Installing docker-prune-safe on VM ($VmUser@$VmHost)..." -ForegroundColor Cyan

# 0) Ensure scripts dir exists on VM
& gcloud compute ssh "${VmUser}@${VmHost}" --zone=$GcpZone --project=$GcpProject --command="mkdir -p ${RemoteProjectPath}/scripts"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 1) Copy prune script to VM (to repo so it can also be updated by git pull later)
$pruneScript = Join-Path $RepoRoot "scripts\docker-prune-safe.sh"
if (-not (Test-Path $pruneScript)) {
    Write-Host "ERROR: Not found: $pruneScript" -ForegroundColor Red
    exit 1
}
Write-Host "Copying docker-prune-safe.sh to VM..." -ForegroundColor Yellow
& gcloud compute scp $pruneScript "${VmUser}@${VmHost}:${RemoteProjectPath}/scripts/docker-prune-safe.sh" --zone=$GcpZone --project=$GcpProject
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 2) On VM: install script to /usr/local/bin
Write-Host "Installing script to /usr/local/bin on VM..." -ForegroundColor Yellow
$cmd1 = "sudo cp ${RemoteProjectPath}/scripts/docker-prune-safe.sh /usr/local/bin/docker-prune-safe.sh && sudo chmod +x /usr/local/bin/docker-prune-safe.sh"
& gcloud compute ssh "${VmUser}@${VmHost}" --zone=$GcpZone --project=$GcpProject --command=$cmd1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 3) Create cron.daily file on VM
Write-Host "Creating /etc/cron.daily/docker-prune-safe on VM..." -ForegroundColor Yellow
$cronLine = "/usr/local/bin/docker-prune-safe.sh >> /var/log/docker-prune-safe.log 2>&1"
$cmd2 = "echo '#!/bin/sh' | sudo tee /etc/cron.daily/docker-prune-safe && echo '$cronLine' | sudo tee -a /etc/cron.daily/docker-prune-safe && sudo chmod +x /etc/cron.daily/docker-prune-safe"
& gcloud compute ssh "${VmUser}@${VmHost}" --zone=$GcpZone --project=$GcpProject --command=$cmd2
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Install complete. Cron runs daily; log: /var/log/docker-prune-safe.log" -ForegroundColor Green
