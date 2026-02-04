<#
.SYNOPSIS
  Push RAG Infrastructure to GitHub

.DESCRIPTION
  This script pushes the rag-infrastructure project to GitHub.
  Supports both SSH and HTTPS authentication with automatic fallback.

.PARAMETER CommitMessage
  Custom commit message for git push

.PARAMETER AutoCommit
  Automatically commit changes without prompting

.PARAMETER GitHubMethod
  GitHub authentication method: 'ssh', 'https', or 'auto' (default: 'auto')

.PARAMETER Help
  Show this help message

.EXAMPLE
  .\push-to-github.ps1
  Push with auto-detected GitHub authentication

.EXAMPLE
  .\push-to-github.ps1 -AutoCommit -CommitMessage "Update infrastructure"
  Auto-commit with custom message and push

.EXAMPLE
  .\push-to-github.ps1 -GitHubMethod https
  Force use HTTPS for GitHub push

.NOTES
  - The script automatically falls back from SSH to HTTPS if SSH push fails
  - HTTPS requires credential helper: git config --global credential.helper wincred
  - SSH requires SSH key at: https://github.com/settings/keys
#>

param(
    [string]$CommitMessage = "",
    [switch]$AutoCommit = $false,
    [switch]$Help = $false,
    [ValidateSet('ssh', 'https', 'auto')]
    [string]$GitHubMethod = 'auto'
)

$ErrorActionPreference = "Stop"

# Run from the script's directory (repo root) so git commands always see .git
$RepoRoot = (Resolve-Path $PSScriptRoot).Path
Set-Location $RepoRoot

# ============================================================================
# HELP FUNCTION
# ============================================================================

function Show-Help {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "   RAG Infrastructure - Push to GitHub" -ForegroundColor Yellow
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "SYNOPSIS:" -ForegroundColor Yellow
    Write-Host "  Pushes rag-infrastructure project to GitHub"
    Write-Host ""
    Write-Host "PARAMETERS:" -ForegroundColor Yellow
    Write-Host "  -CommitMessage      Custom commit message for git push"
    Write-Host "  -AutoCommit         Automatically commit changes without prompting"
    Write-Host "  -GitHubMethod       GitHub auth method: 'ssh', 'https', or 'auto' (default: 'auto')"
    Write-Host "  -Help              Show this help message"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\push-to-github.ps1"
    Write-Host "  .\push-to-github.ps1 -AutoCommit -CommitMessage 'Update infrastructure'"
    Write-Host "  .\push-to-github.ps1 -GitHubMethod https"
    Write-Host ""
    Write-Host "GITHUB REPO:" -ForegroundColor Yellow
    Write-Host "  https://github.com/theaicompany007/rag-infrastructure"
    Write-Host ""
    exit 0
}

if ($Help) {
    Show-Help
}

# ============================================================================
# CONFIGURATION
# ============================================================================

$GitHubRepoSsh = "git@github.com:theaicompany007/rag-infrastructure.git"
$GitHubRepoHttps = "https://github.com/theaicompany007/rag-infrastructure.git"

# Determine which GitHub method to use
$useHttpsMethod = $false
if ($GitHubMethod -eq 'https') {
    $useHttpsMethod = $true
} elseif ($GitHubMethod -eq 'ssh') {
    $useHttpsMethod = $false
} else {
    # Auto-detect: check current remote and preserve if working
    $currentRemote = git config --get remote.origin.url 2>$null
    if ($currentRemote -match "^https://") {
        $useHttpsMethod = $true
        Write-Host "  [INFO] Auto-detected: Using HTTPS (current remote is HTTPS)" -ForegroundColor Cyan
    } elseif ($currentRemote -match "^git@") {
        $useHttpsMethod = $false
        Write-Host "  [INFO] Auto-detected: Using SSH (current remote is SSH)" -ForegroundColor Cyan
    } else {
        # Default to SSH if we can't determine
        $useHttpsMethod = $false
        Write-Host "  [INFO] Auto-detected: Defaulting to SSH" -ForegroundColor Cyan
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "  [ERROR] $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Configure-GitRemote {
    param([bool]$UseHttps)
    
    if ($UseHttps) {
        Write-Info "Configuring git remote to use HTTPS..."
        $currentRemote = git config --get remote.origin.url 2>$null
        
        if ($currentRemote -match "^git@") {
            Write-Info "Current remote uses SSH, switching to HTTPS..."
            git remote set-url origin $GitHubRepoHttps
            Write-Success "Git remote configured to use HTTPS"
        } elseif ($currentRemote -match "^https://") {
            Write-Info "Git remote already uses HTTPS"
        } else {
            Write-Info "Setting remote to HTTPS URL..."
            git remote set-url origin $GitHubRepoHttps
            Write-Success "Git remote configured to use HTTPS"
        }
    } else {
        Write-Info "Configuring git remote to use SSH..."
        $currentRemote = git config --get remote.origin.url 2>$null
        
        if ($currentRemote -match "^https://") {
            Write-Info "Current remote uses HTTPS, switching to SSH..."
            git remote set-url origin $GitHubRepoSsh
            Write-Success "Git remote configured to use SSH"
        } elseif ($currentRemote -match "^git@") {
            Write-Info "Git remote already uses SSH"
        } else {
            Write-Info "Setting remote to SSH URL..."
            git remote set-url origin $GitHubRepoSsh
            Write-Success "Git remote configured to use SSH"
        }
    }
}

function Test-GitHubSshConnection {
    Write-Info "Testing SSH connection to GitHub..."
    
    $Error.Clear()
    $oldErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    
    try {
        $testResult = & ssh -T git@github.com 2>&1
        $exitCode = $LASTEXITCODE
        $errorMessages = $Error | ForEach-Object { $_.Exception.Message -join " " }
        
        $outputString = ""
        if ($testResult) {
            if ($testResult -is [System.Array]) {
                $outputString = ($testResult | Out-String).Trim()
            } else {
                $outputString = $testResult.ToString().Trim()
            }
        }
        
        $allOutput = "$outputString $errorMessages"
        
        if ($allOutput -match "successfully authenticated" -or $outputString -match "successfully authenticated") {
            Write-Success "SSH connection to GitHub verified"
            return $true
        } elseif ($exitCode -eq 0 -or $exitCode -eq 1) {
            Write-Success "SSH connection to GitHub works"
            return $true
        } else {
            Write-Warning "SSH connection to GitHub may not be configured (exit code: $exitCode)"
            return $false
        }
    } catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -match "successfully authenticated") {
            Write-Success "SSH connection to GitHub verified"
            return $true
        } else {
            Write-Warning "SSH connection test encountered an error"
            return $false
        }
    } finally {
        $ErrorActionPreference = $oldErrorAction
    }
}

# ============================================================================
# MAIN: PUSH TO GITHUB
# ============================================================================

Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "   Pushing RAG Infrastructure to GitHub" -ForegroundColor Yellow
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Ensure we're in a git repo (must have .git directory, and git must see it)
if (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
    Write-Error "Not a git repository: no .git in $RepoRoot"
    Write-Info "Run this script from the rag-infrastructure folder that contains .git"
    Write-Info "Example: cd C:\raaj\kcube_consulting_labs\onlyne-reputation\rag-infrastructure"
    exit 1
}
$errPrev = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
$gitOut = git rev-parse --is-inside-work-tree 2>&1
$gitExit = $LASTEXITCODE
$ErrorActionPreference = $errPrev
if ($gitExit -ne 0) {
    Write-Error "Git does not see a repository here. Repo path used: $RepoRoot"
    Write-Info "Run from the repo root: cd path\to\rag-infrastructure"
    Write-Info "Do NOT delete .git - that removes your repo and history."
    exit 1
}

# Configure git remote based on selected method
Configure-GitRemote -UseHttps $useHttpsMethod

# Test SSH connection only if using SSH
if (-not $useHttpsMethod) {
    $sshWorks = Test-GitHubSshConnection
    if (-not $sshWorks) {
        Write-Warning "SSH connection to GitHub may not be working, but continuing..."
        Write-Info "If push fails, the script will automatically try HTTPS as fallback"
    }
}

# Check git status and ensure we push main only
$status = git status --porcelain
$branch = git rev-parse --abbrev-ref HEAD
if ($branch -ne "main") {
    Write-Error "You are on branch '$branch'. This script is set up to push 'main' only."
    Write-Info "Switch to main:  git checkout main"
    Write-Info "Or rename current branch to main:  git branch -m $branch main   then   git push origin -u main"
    exit 1
}

$hasChanges = $status -and ($status.Trim() -ne "")

if ($hasChanges) {
    Write-Info "Changes detected, committing..."
    
    if ($AutoCommit) {
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
            $CommitMessage = "Update RAG infrastructure - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        }
    } else {
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
            $CommitMessage = Read-Host "Enter commit message (or press Enter for default)"
            if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
                $CommitMessage = "Update RAG infrastructure - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            }
        }
    }
    
    git add -A
    git commit -m "$CommitMessage"
    Write-Success "Changes committed"
} else {
    Write-Info "No local changes to commit"
}

# Push to GitHub with fallback logic
$pushMethod = if ($useHttpsMethod) { "HTTPS" } else { "SSH" }
Write-Info "Pushing to GitHub via $pushMethod..."

# Pull first so we don't get "rejected (fetch first)"
$pullErr = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
$null = & git pull origin $branch --no-edit 2>&1
$ErrorActionPreference = $pullErr

$pushSucceeded = $false
$pushError = $null

try {
    $oldErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    
    $pushOutput = & git push origin $branch 2>&1 | Out-String
    $pushExitCode = $LASTEXITCODE
    
    $ErrorActionPreference = $oldErrorAction
    
    $filteredOutput = $pushOutput -replace "git: 'credential-manager-core' is not a git command[^\n]*\n?", "" -replace "See 'git --help'[^\n]*\n?", ""
    
    $filteredOutput -split "`n" | ForEach-Object {
        $line = $_.Trim()
        if ($line -and $line -notmatch "^$" -and $line -notmatch "credential-manager-core") {
            Write-Host $line
        }
    }
    
    if ($pushOutput -match "Permission denied" -or $pushOutput -match "fatal:.*Permission denied" -or $pushOutput -match "ERROR: Repository not found" -or $pushOutput -match "fatal:.*authentication failed") {
        throw "Git push authentication failed"
    }
    
    if ($pushExitCode -eq 0) {
        $pushSucceeded = $true
        Write-Success "Pushed to GitHub successfully via $pushMethod"
    } elseif ($pushOutput -match "Everything up-to-date") {
        $pushSucceeded = $true
        Write-Success "Repository is up-to-date (nothing to push)"
    } elseif ($pushOutput -match "main -> main" -or $pushOutput -match "->") {
        $pushSucceeded = $true
        Write-Success "Pushed to GitHub successfully via $pushMethod"
    } else {
        # On push exit 1, try pull then retry (unless it was an auth failure)
        $isAuthFailure = $pushOutput -match "Permission denied|Repository not found|authentication failed"
        if ($pushExitCode -eq 1 -and -not $isAuthFailure) {
            Write-Info "Push was rejected; pulling remote changes then retrying push..."
            $ErrorActionPreference = "SilentlyContinue"
            $null = & git pull origin $branch --rebase 2>&1
            $pushOutput = & git push origin $branch 2>&1 | Out-String
            $pushExitCode = $LASTEXITCODE
            $ErrorActionPreference = $oldErrorAction
            if ($pushExitCode -eq 0 -or $pushOutput -match "Everything up-to-date|->") {
                $pushSucceeded = $true
                Write-Success "Pushed to GitHub successfully via $pushMethod (after pull)"
            } else {
                if ($pushOutput -and $pushOutput.Trim()) {
                    Write-Host "  Git output:" -ForegroundColor Yellow
                    $pushOutput -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
                }
                if ($pushOutput -match "rejected|non-fast-forward|unrelated histories") {
                    Write-Info "To overwrite remote with your local branch: git push origin $branch --force"
                }
                throw "Git push failed with exit code $pushExitCode"
            }
        } else {
            if ($pushOutput -and $pushOutput.Trim()) {
                Write-Host "  Git output:" -ForegroundColor Yellow
                $pushOutput -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
            }
            throw "Git push failed with exit code $pushExitCode"
        }
    }
} catch {
    $pushError = $_.Exception.Message
    Write-Warning "Push via $pushMethod failed: $pushError"
    if ($pushOutput -and $pushOutput.Trim() -and $pushError -notmatch "Git push (via HTTPS )?also failed") {
        Write-Host "  Git output:" -ForegroundColor Yellow
        $pushOutput -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
    }
    
    # If SSH failed, try HTTPS as fallback
    if (-not $useHttpsMethod) {
        Write-Info "Attempting fallback to HTTPS..."
        Configure-GitRemote -UseHttps $true
        
        try {
            $oldErrorAction = $ErrorActionPreference
            $ErrorActionPreference = "SilentlyContinue"
            
            Write-Info "Retrying push via HTTPS..."
            $pushOutputHttps = & git push origin $branch 2>&1 | Out-String
            $pushExitCodeHttps = $LASTEXITCODE
            
            $ErrorActionPreference = $oldErrorAction
            
            $filteredOutputHttps = $pushOutputHttps -replace "git: 'credential-manager-core' is not a git command[^\n]*\n?", "" -replace "See 'git --help'[^\n]*\n?", ""
            
            $filteredOutputHttps -split "`n" | ForEach-Object {
                $line = $_.Trim()
                if ($line -and $line -notmatch "^$" -and $line -notmatch "credential-manager-core") {
                    Write-Host $line
                }
            }
            
            if ($pushOutputHttps -match "Permission denied" -or $pushOutputHttps -match "fatal:.*Permission denied" -or $pushOutputHttps -match "ERROR: Repository not found" -or $pushOutputHttps -match "fatal:.*authentication failed") {
                throw "Git push authentication failed"
            }
            
            if ($pushExitCodeHttps -eq 0) {
                $pushSucceeded = $true
                Write-Success "Pushed to GitHub successfully via HTTPS (fallback)"
            } elseif ($pushOutputHttps -match "Everything up-to-date") {
                $pushSucceeded = $true
                Write-Success "Repository is up-to-date (nothing to push)"
            } elseif ($pushOutputHttps -match "main -> main" -or $pushOutputHttps -match "->") {
                $pushSucceeded = $true
                Write-Success "Pushed to GitHub successfully via HTTPS (fallback)"
            } else {
                throw "Git push via HTTPS also failed with exit code $pushExitCodeHttps"
            }
        } catch {
            Write-Error "Both SSH and HTTPS push failed"
            Write-Error "SSH error: $pushError"
            Write-Error "HTTPS error: $($_.Exception.Message)"
            if ($pushOutputHttps -and $pushOutputHttps.Trim()) {
                Write-Info "Git push (HTTPS) raw output:"
                $pushOutputHttps -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
            }
            Write-Info "Troubleshooting:"
            Write-Info "  1. For SSH: Set up SSH key at https://github.com/settings/keys"
            Write-Info "  2. For HTTPS: Use credential helper or personal access token"
            Write-Info "  3. Or use -GitHubMethod https parameter to force HTTPS"
            throw
        }
    } else {
        Write-Error "Failed to push to GitHub via HTTPS: $pushError"
        if ($pushOutput -and $pushOutput.Trim()) {
            Write-Host "  Git output:" -ForegroundColor Yellow
            $pushOutput -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
        }
        Write-Info "Troubleshooting:"
        Write-Info "  1. Check your GitHub credentials (use a Personal Access Token as password)"
        Write-Info "  2. Use credential helper: git config --global credential.helper wincred"
        Write-Info "  3. Or try SSH: -GitHubMethod ssh"
        throw
    }
}

if (-not $pushSucceeded) {
    Write-Error "Push failed"
    throw "Failed to push to GitHub"
}

Write-Host ""
Write-Success "Push to GitHub completed successfully!"
Write-Host ""
