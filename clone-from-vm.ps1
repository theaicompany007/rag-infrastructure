# Script to clone rag-infrastructure from chroma-vm
# Run this script from the rag-infrastructure directory

$ErrorActionPreference = "Stop"

Write-Host "Cloning rag-infrastructure from postgres@chroma-vm..." -ForegroundColor Cyan

# Try using SCP
Write-Host "Attempting SCP copy..." -ForegroundColor Yellow
try {
    scp -r postgres@chroma-vm:~/rag-infrastructure/* .
    Write-Host "✅ Successfully cloned using SCP" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "SCP failed, trying alternative method..." -ForegroundColor Yellow
}

# Alternative: Use SSH with tar
Write-Host "Attempting SSH + tar method..." -ForegroundColor Yellow
try {
    ssh postgres@chroma-vm "cd ~/rag-infrastructure && tar czf - ." | tar xzf -
    Write-Host "✅ Successfully cloned using SSH + tar" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "SSH + tar failed" -ForegroundColor Red
}

# If both fail, provide manual instructions
Write-Host "`n❌ Automated clone failed. Please use one of these methods:" -ForegroundColor Red
Write-Host "`nMethod 1: Using Git (if repository is on GitLab/GitHub):" -ForegroundColor Yellow
Write-Host "  git clone <repository-url> ."
Write-Host "`nMethod 2: Manual SCP from command line:" -ForegroundColor Yellow
Write-Host "  scp -r postgres@chroma-vm:~/rag-infrastructure/* ."
Write-Host "`nMethod 3: Using WinSCP or similar GUI tool" -ForegroundColor Yellow
Write-Host "  Connect to chroma-vm and copy ~/rag-infrastructure folder contents"

exit 1
