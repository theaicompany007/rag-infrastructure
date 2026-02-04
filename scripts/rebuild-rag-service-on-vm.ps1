<#
.SYNOPSIS
  Rebuild and restart the RAG service on the Google Cloud VM (chroma-vm / chroma-vn).

.DESCRIPTION
  SSHs to the VM and runs:
    cd ~/rag-infrastructure
    docker compose -p infra build rag-service && docker compose -p infra up -d rag-service
  Or uses manage-infra.sh: ./manage-infra.sh rebuild-rag

  Uses the same VM connection settings as deploy-rag-infrastructure-complete.ps1 (gcloud).

.PARAMETER VmHost
  VM name (default: chroma-vm). Use chroma-vn if your VM is named that.

.PARAMETER UseManageInfra
  If set, runs ./manage-infra.sh rebuild-rag on the VM instead of raw docker compose.

.EXAMPLE
  .\scripts\rebuild-rag-service-on-vm.ps1
  Rebuild RAG service on chroma-vm via gcloud SSH.

.EXAMPLE
  .\scripts\rebuild-rag-service-on-vm.ps1 -VmHost chroma-vn
  Rebuild on VM named chroma-vn.
#>

param(
    [string]$VmHost = "chroma-vm",
    [string]$VmUser = "postgres",
    [string]$GcpZone = "asia-south1-a",
    [string]$GcpProject = "onlynereputation-agentic",
    [switch]$UseManageInfra = $true
)

$ErrorActionPreference = "Stop"
$RemoteProjectPath = "/home/postgres/rag-infrastructure"

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "   Rebuild RAG service on VM: $VmHost" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Check gcloud
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Host "  [ERROR] gcloud CLI not found. Install Google Cloud SDK or ensure it is in PATH." -ForegroundColor Red
    exit 1
}

if ($UseManageInfra) {
    $cmd = "cd $RemoteProjectPath && ./manage-infra.sh rebuild-rag 2>&1"
    Write-Host "  [INFO] Running: ./manage-infra.sh rebuild-rag on $VmHost" -ForegroundColor Cyan
} else {
    $cmd = "cd $RemoteProjectPath && docker compose -p infra build rag-service && docker compose -p infra up -d rag-service 2>&1"
    Write-Host "  [INFO] Running: docker compose build rag-service && up -d rag-service on $VmHost" -ForegroundColor Cyan
}

Write-Host ""
$result = & gcloud compute ssh "${VmUser}@${VmHost}" --zone=$GcpZone --project=$GcpProject --command=$cmd 2>&1
$exitCode = $LASTEXITCODE
$result | ForEach-Object { Write-Host $_ }
Write-Host ""

if ($exitCode -ne 0) {
    Write-Host "  [ERROR] Rebuild failed with exit code $exitCode" -ForegroundColor Red
    exit $exitCode
}

Write-Host "  [OK] RAG service rebuilt and restarted on $VmHost" -ForegroundColor Green
Write-Host ""
