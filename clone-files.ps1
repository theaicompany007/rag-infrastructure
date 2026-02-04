# Script to clone rag-infrastructure files from chroma-vm using gcloud compute scp
# Run this script from the rag-infrastructure directory
# You may need to run PowerShell as Administrator if you encounter permission errors

$ErrorActionPreference = "Continue"
$zone = "asia-south1-a"
$project = "onlynereputation-agentic"
$remoteUser = "postgres@chroma-vm"
$remotePath = "/home/postgres/rag-infrastructure"

Write-Host "Cloning rag-infrastructure files from $remoteUser..." -ForegroundColor Cyan
Write-Host ""

# Change to rag-infrastructure directory
Set-Location "C:\Raaj\kcube_consulting_labs\onlyne-reputation\rag-infrastructure"

# Root directory files
Write-Host "Copying root directory files..." -ForegroundColor Yellow
$rootFiles = @(
    ".env",
    ".env.local",
    "Dockerfile.rag",
    "docker-compose.yml",
    "manage-infra.sh"
)

foreach ($file in $rootFiles) {
    Write-Host "  Copying $file..." -ForegroundColor Gray
    gcloud compute scp "$remoteUser`:$remotePath/$file" . --zone=$zone --project=$project
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    [OK] $file copied" -ForegroundColor Green
    } else {
        Write-Host "    [FAILED] Failed to copy $file" -ForegroundColor Red
    }
}

# Create workers directory
Write-Host ""
Write-Host "Creating workers directory..." -ForegroundColor Yellow
if (-not (Test-Path "workers")) {
    New-Item -ItemType Directory -Path "workers" | Out-Null
    Write-Host "  [OK] workers directory created" -ForegroundColor Green
} else {
    Write-Host "  [INFO] workers directory already exists" -ForegroundColor Cyan
}

# Change to workers directory
Set-Location "workers"

# Workers directory files
Write-Host ""
Write-Host "Copying workers directory files..." -ForegroundColor Yellow
$workerFiles = @(
    "README.md",
    "__init__.py",
    "config.py",
    "cron_scheduler.py",
    "cron_scheduler.py.backup.20251217_172954",
    "cron_scheduler.py.backup.20251217_173657",
    "cron_scheduler.py.backup.20251217_180033",
    "cron_scheduler.py.backup.20251217_180131",
    "cron_scheduler.py.backup.20251217_180456",
    "cron_scheduler_FIXED.py",
    "diagnose_collection.py",
    "ingest.py",
    "langflow_index_partial.html",
    "langflow_partial.js",
    "load_data.py",
    "main.py",
    "rag_engine.py",
    "rag_engine.py.backup.",
    "requirements.txt",
    "run_cron_local.py"
)

foreach ($file in $workerFiles) {
    Write-Host "  Copying workers/$file..." -ForegroundColor Gray
    gcloud compute scp "$remoteUser`:$remotePath/workers/$file" . --zone=$zone --project=$project
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    [OK] $file copied" -ForegroundColor Green
    } else {
        Write-Host "    [FAILED] Failed to copy $file" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "File cloning completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Review the cloned files" -ForegroundColor White
Write-Host "2. Merge Celery configuration from docker-compose.yml.template into docker-compose.yml" -ForegroundColor White
Write-Host "3. Merge Celery commands from manage-infra.sh.template into manage-infra.sh" -ForegroundColor White
Write-Host "4. Review and update .env.local with Celery configuration" -ForegroundColor White
