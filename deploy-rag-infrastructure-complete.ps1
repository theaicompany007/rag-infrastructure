<#
.SYNOPSIS
  Complete RAG Infrastructure Deployment Script - Automates full workflow from Windows to VM

.DESCRIPTION
  This script automates the complete deployment workflow:
  1. Pushes code to GitHub (with SSH/HTTPS support and automatic fallback)
  2. SSH to VM and pulls/clones from GitHub
  3. Copies .env.local and .env files
  4. Sets permissions on shell scripts
  5. Runs infrastructure deployment (manage-infra.sh start)
  6. Checks status

  GITHUB AUTHENTICATION:
  - By default, uses 'auto' mode which detects your current git remote URL
  - If SSH push fails, automatically falls back to HTTPS
  - Use -GitHubMethod to explicitly choose 'ssh', 'https', or 'auto'

.PARAMETER SkipPush
  Skip pushing to GitHub (useful if already pushed)

.PARAMETER SkipDeploy
  Only push to GitHub, don't deploy to VM

.PARAMETER CommitMessage
  Custom commit message for git push

.PARAMETER AutoCommit
  Automatically commit changes without prompting

.PARAMETER FreshClone
  Remove existing project on VM and clone fresh from GitHub

.PARAMETER GitHubMethod
  GitHub authentication method for local push operations.
  - 'auto' (default): Auto-detect based on current remote URL (preserves existing config)
  - 'ssh': Force use SSH (requires SSH key setup)
  - 'https': Force use HTTPS (requires credential helper or token)
  Note: VM operations always use SSH (VM has its own SSH key)

.PARAMETER Help
  Show this help message

.EXAMPLE
  .\deploy-rag-infrastructure-complete.ps1
  Full deployment with auto-detected GitHub authentication

.EXAMPLE
  .\deploy-rag-infrastructure-complete.ps1 -AutoCommit -CommitMessage "Update infrastructure"
  Auto-commit with custom message and deploy

.EXAMPLE
  .\deploy-rag-infrastructure-complete.ps1 -SkipPush -FreshClone
  Skip push (already pushed), fresh clone on VM

.EXAMPLE
  .\deploy-rag-infrastructure-complete.ps1 -GitHubMethod https
  Force use HTTPS for GitHub push (bypasses SSH)

.EXAMPLE
  .\deploy-rag-infrastructure-complete.ps1 -SkipDeploy
  Only push to GitHub, don't deploy to VM

.EXAMPLE
  .\deploy-rag-infrastructure-complete.ps1 -Help
  Show detailed help message

.NOTES
  - The script automatically falls back from SSH to HTTPS if SSH push fails
  - HTTPS requires credential helper: git config --global credential.helper wincred
  - SSH requires SSH key at: https://github.com/settings/keys
  - VM uses SSH for git operations (separate from local authentication)
#>

param(
    [switch]$SkipPush = $false,
    [switch]$SkipDeploy = $false,
    [string]$CommitMessage = "",
    [switch]$AutoCommit = $false,
    [switch]$FreshClone = $false,
    [switch]$Help = $false,
    [ValidateSet('ssh', 'https', 'auto')]
    [string]$GitHubMethod = 'auto'
)

$ErrorActionPreference = "Stop"

# ============================================================================
# HELP FUNCTION
# ============================================================================

function Show-Help {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "   RAG Infrastructure Complete Deployment Script - Help" -ForegroundColor Yellow
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "SYNOPSIS:" -ForegroundColor Yellow
    Write-Host "  Automates complete RAG infrastructure deployment workflow from Windows to VM"
    Write-Host ""
    Write-Host "WORKFLOW:" -ForegroundColor Yellow
    Write-Host "  1. Push code to GitHub (unless -SkipPush)"
    Write-Host "  2. Update code on VM:"
    Write-Host "     - By default: git pull (updates existing project)"
    Write-Host "     - With -FreshClone: Delete and clone fresh from GitHub"
    Write-Host "  3. Copy .env.local and .env files"
    Write-Host "  4. Set permissions on shell scripts"
    Write-Host "  5. Run infrastructure deployment (manage-infra.sh start)"
    Write-Host "  6. Check service status"
    Write-Host ""
    Write-Host "PARAMETERS:" -ForegroundColor Yellow
    Write-Host "  -SkipPush          Skip pushing to GitHub (useful if already pushed)"
    Write-Host "  -SkipDeploy        Only push to GitHub, don't deploy to VM"
    Write-Host "  -CommitMessage      Custom commit message for git push"
    Write-Host "  -AutoCommit         Automatically commit changes without prompting"
    Write-Host "  -FreshClone         Remove existing project on VM and clone fresh"
    Write-Host "                     (Default: git pull to update existing project)"
    Write-Host "  -GitHubMethod       GitHub auth method: 'ssh', 'https', or 'auto' (default: 'auto')"
    Write-Host "  -Help              Show this help message"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  # Full deployment (push + pull updates + deploy)"
    Write-Host "  .\deploy-rag-infrastructure-complete.ps1"
    Write-Host ""
    Write-Host "  # Auto-commit with custom message"
    Write-Host '  .\deploy-rag-infrastructure-complete.ps1 -AutoCommit -CommitMessage "Update infrastructure"'
    Write-Host ""
    Write-Host "  # Skip push (already pushed), fresh clone on VM"
    Write-Host "  .\deploy-rag-infrastructure-complete.ps1 -SkipPush -FreshClone"
    Write-Host ""
    Write-Host "  # Only push to GitHub, don't deploy"
    Write-Host "  .\deploy-rag-infrastructure-complete.ps1 -SkipDeploy"
    Write-Host ""
    Write-Host "  # Force use HTTPS for GitHub push"
    Write-Host "  .\deploy-rag-infrastructure-complete.ps1 -GitHubMethod https"
    Write-Host ""
    Write-Host "  # Force use SSH for GitHub push"
    Write-Host "  .\deploy-rag-infrastructure-complete.ps1 -GitHubMethod ssh"
    Write-Host ""
    Write-Host "  # Show help"
    Write-Host "  .\deploy-rag-infrastructure-complete.ps1 -Help"
    Write-Host ""
    Write-Host "CODE UPDATE BEHAVIOR:" -ForegroundColor Yellow
    Write-Host "  Default (no -FreshClone):"
    Write-Host "    - If project exists on VM: git pull origin main (updates)"
    Write-Host "    - If project missing: git clone (creates new)"
    Write-Host ""
    Write-Host "  With -FreshClone:"
    Write-Host "    - Always: sudo rm -rf /home/postgres/rag-infrastructure (deletes)"
    Write-Host "    - Then: git clone (fresh clone)"
    Write-Host ""
    Write-Host "CONFIGURATION:" -ForegroundColor Yellow
    Write-Host "  VM Host: chroma-vm"
    Write-Host "  VM User: postgres"
    Write-Host "  Remote Path: /home/postgres/rag-infrastructure"
    Write-Host "  GitHub Repo: git@github.com:theaicompany007/rag-infrastructure.git (SSH)"
    Write-Host "             https://github.com/theaicompany007/rag-infrastructure.git (HTTPS)"
    Write-Host ""
    Write-Host "GITHUB AUTHENTICATION:" -ForegroundColor Yellow
    Write-Host "  The script supports both SSH and HTTPS with automatic fallback."
    Write-Host "  Use -GitHubMethod to choose:"
    Write-Host "  - 'auto' (default): Auto-detects based on current remote URL"
    Write-Host "                     (preserves existing configuration)"
    Write-Host "  - 'ssh': Forces SSH (requires SSH key setup)"
    Write-Host "  - 'https': Forces HTTPS (uses credential helper or token)"
    Write-Host ""
    Write-Host "  AUTOMATIC FALLBACK:"
    Write-Host "  If SSH push fails, the script automatically retries with HTTPS."
    Write-Host "  This ensures deployment works even if SSH is not configured."
    Write-Host ""
    Write-Host "  For SSH setup:"
    Write-Host "  1. SSH key is generated: ssh-keygen -t ed25519 -C 'your_email@example.com'"
    Write-Host "  2. SSH key is added to ssh-agent: ssh-add ~/.ssh/id_ed25519"
    Write-Host "  3. Public key is added to GitHub: https://github.com/settings/keys"
    Write-Host "  4. Test connection: ssh -T git@github.com"
    Write-Host ""
    Write-Host "  For HTTPS setup:"
    Write-Host "  1. Configure credential helper: git config --global credential.helper wincred"
    Write-Host "  2. Or use personal access token when prompted"
    Write-Host ""
    Write-Host "  NOTE: VM git operations always use SSH (VM has its own SSH key)"
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

# Show help if requested
if ($Help) {
    Show-Help
}

# Run from the script's directory (repo root) so git and file paths are correct
Set-Location $PSScriptRoot

# ============================================================================
# CONFIGURATION
# ============================================================================

# VM Connection Settings
$VmHost = "chroma-vm"
$VmUser = "postgres"
$SshKeyPath = ""  # Path to SSH private key for VM (leave empty to use default SSH config)
$DeployMethod = "gcloud"  # "ssh" or "gcloud"
$GcpZone = "asia-south1-a"
$GcpProject = "onlynereputation-agentic"

# VM key for GitHub (chroma-vm key added to theaicompany007 account)
$VmGitKeyName = "id_ed25519_chroma_vm"

# Project Paths
$LocalProjectPath = $PSScriptRoot
$RemoteProjectPath = "/home/postgres/rag-infrastructure"
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

function Write-Step {
    param([string]$Message, [string]$Color = "Yellow")
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "   $Message" -ForegroundColor $Color
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
}

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

function Invoke-SshCommand {
    param([string]$Command, [switch]$NoOutput = $false, [switch]$NoThrow = $false)
    
    $sshTarget = "${VmUser}@${VmHost}"
    
    if ($DeployMethod -eq "gcloud") {
        $errPrev = $ErrorActionPreference
        if ($NoThrow) { $ErrorActionPreference = 'SilentlyContinue' }
        if ($NoOutput) {
            $result = & gcloud compute ssh "${VmUser}@${VmHost}" --zone=$GcpZone --project=$GcpProject --command=$Command 2>&1 | Out-Null
        } else {
            $result = & gcloud compute ssh "${VmUser}@${VmHost}" --zone=$GcpZone --project=$GcpProject --command=$Command 2>&1
        }
        if ($NoThrow) { $ErrorActionPreference = $errPrev }
        $exitCode = $LASTEXITCODE
        if (-not $NoThrow -and $exitCode -ne 0 -and $null -ne $exitCode) {
            throw "SSH command failed with exit code $exitCode"
        }
        if ($NoThrow) {
            $outStr = if ($result -is [System.Array]) { $result | Out-String } else { [string]$result }
            return @{ Output = $outStr; ExitCode = $exitCode }
        }
        return $result
    } else {
        $isolatedCommand = "env -i HOME=/home/postgres USER=postgres PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin GIT_SSH='' GIT_SSH_COMMAND='' SSH_AUTH_SOCK='' /bin/sh -c `"$Command`""
        $errPrev = $ErrorActionPreference
        if ($NoThrow) { $ErrorActionPreference = 'SilentlyContinue' }
        if ($SshKeyPath -and (Test-Path $SshKeyPath)) {
            if ($NoOutput) {
                $result = & ssh -i $SshKeyPath $sshTarget $isolatedCommand 2>&1 | Out-Null
            } else {
                $result = & ssh -i $SshKeyPath $sshTarget $isolatedCommand 2>&1
            }
        } else {
            if ($SshKeyPath -and -not (Test-Path $SshKeyPath)) {
                Write-Warning "SSH key path specified but file not found: $SshKeyPath. Using default SSH config."
            }
            if ($NoOutput) {
                $result = & ssh $sshTarget $isolatedCommand 2>&1 | Out-Null
            } else {
                $result = & ssh $sshTarget $isolatedCommand 2>&1
            }
        }
        if ($NoThrow) { $ErrorActionPreference = $errPrev }
        $exitCode = $LASTEXITCODE
        if (-not $NoThrow -and $exitCode -ne 0 -and $null -ne $exitCode) {
            throw "SSH command failed with exit code $exitCode"
        }
        if ($NoThrow) {
            $outStr = if ($result -is [System.Array]) { $result | Out-String } else { [string]$result }
            return @{ Output = $outStr; ExitCode = $exitCode }
        }
        return $result
    }
}

function Invoke-ScpCommand {
    param([string]$Source, [string]$Destination)
    
    $sshTarget = "${VmUser}@${VmHost}"
    
    Write-Info "Copying: $(Split-Path $Source -Leaf) -> $Destination"
    
    if ($DeployMethod -eq "gcloud") {
        & gcloud compute scp $Source "${VmUser}@${VmHost}:${Destination}" --zone=$GcpZone --project=$GcpProject 2>&1 | Out-Null
    } else {
        if ($SshKeyPath -and (Test-Path $SshKeyPath)) {
            & scp -i $SshKeyPath $Source "${sshTarget}:${Destination}" 2>&1 | Out-Null
        } else {
            if ($SshKeyPath -and -not (Test-Path $SshKeyPath)) {
                Write-Warning "SSH key path specified but file not found: $SshKeyPath. Using default SSH config."
            }
            & scp $Source "${sshTarget}:${Destination}" 2>&1 | Out-Null
        }
    }
    
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        throw "SCP command failed with exit code $LASTEXITCODE"
    }
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

function Test-InfrastructureRunning {
    <#
    .SYNOPSIS
    Check if infrastructure services are already running on the VM.
    
    .DESCRIPTION
    Checks if any of the infrastructure containers (rag-service, chroma, redis, celery-worker)
    are currently running. This is used to determine whether to use 'restart' or 'start' command.
    
    .RETURNS
    Boolean: $true if any services are running, $false otherwise
    #>
    
    Write-Info "Checking if infrastructure services are running..."
    
    try {
        # Check if any infra containers are running
        # This checks after files are copied, so it works for both regular and fresh clone scenarios
        $checkCmd = "docker ps --format '{{.Names}}' | grep -E '^(rag-service|chroma|redis|celery-worker)$' | wc -l"
        $runningCount = Invoke-SshCommand $checkCmd
        
        # Extract number from output (handles both gcloud and ssh output formats)
        $count = ($runningCount -split "`n" | Select-Object -First 1).Trim()
        
        if ($count -match "[1-9]") {
            Write-Info "Found $count infrastructure service(s) running"
            return $true
        } else {
            Write-Info "No infrastructure services are currently running"
            return $false
        }
    } catch {
        # If check fails, assume not running (safer default - will try to start)
        Write-Warning "Could not check service status: $_ - assuming services are not running"
        return $false
    }
}

# ============================================================================
# STEP 1: PUSH TO GITHUB
# ============================================================================

if (-not $SkipPush) {
    Write-Step "Step 1: Pushing to GitHub" "Yellow"
    
    if (-not (Test-Path ".git")) {
        Write-Error "Not in a git repository"
        Write-Info "Initialize git repository first: git init"
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
    } else {
        Write-Info "Using HTTPS method - skipping SSH connection test"
    }
    
    # Check git status and ensure we push main only (so we don't recreate master on GitHub)
    $status = git status --porcelain
    $branch = git rev-parse --abbrev-ref HEAD
    if ($branch -ne "main") {
        Write-Error "You are on branch '$branch'. This script pushes to 'main' only (to avoid recreating master on GitHub)."
        Write-Info "Switch to main:  git checkout main"
        Write-Info "Or rename master to main:  git branch -m master main   then   git push origin -u main"
        throw "Switch to branch 'main' and run the script again"
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
    $pullOut = & git pull origin $branch --no-edit 2>&1 | Out-String
    $ErrorActionPreference = $pullErr
    if ($LASTEXITCODE -eq 0 -and $pullOut -match "Already up to date|Successfully rebased|Merge made|Updated") {
        Write-Info "Local branch is up to date with origin/$branch"
    } elseif ($LASTEXITCODE -ne 0 -and $pullOut -match "refusing to merge unrelated histories|CONFLICT") {
        Write-Warning "Pull had conflicts or unrelated histories. Push may be rejected; consider resolving locally or using: git push origin $branch --force"
    }
    
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
                $retryOut = & git push origin $branch 2>&1 | Out-String
                $retryExit = $LASTEXITCODE
                $ErrorActionPreference = $oldErrorAction
                if ($retryExit -eq 0 -or $retryOut -match "Everything up-to-date|->") {
                    $pushSucceeded = $true
                    Write-Success "Pushed to GitHub successfully via $pushMethod (after pull)"
                } else {
                    if ($retryOut -and $retryOut.Trim()) {
                        Write-Host "  Git output (push retry):" -ForegroundColor Yellow
                        $retryOut -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
                    }
                    Write-Info "To overwrite remote with your local branch: git push origin $branch --force"
                    throw "Git push failed with exit code $retryExit"
                }
            } else {
                if ($pushOutput -and $pushOutput.Trim()) {
                    Write-Host "  Git output:" -ForegroundColor Yellow
                    $pushOutput -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
                }
                if ($pushExitCode -eq 1) {
                    Write-Info "To overwrite remote with your local branch: git push origin $branch --force"
                }
                throw "Git push failed with exit code $pushExitCode"
            }
        }
    } catch {
        $pushError = $_.Exception.Message
        Write-Warning "Push via $pushMethod failed: $pushError"
        if ($pushOutput -and $pushOutput.Trim() -and $pushError -notmatch "also failed") {
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
                Write-Info "  3. Or use -SkipPush and push manually / use -GitHubMethod https"
                throw
            }
        } else {
            Write-Error "Failed to push to GitHub via HTTPS: $pushError"
            if ($pushOutput -and $pushOutput.Trim()) {
                Write-Host "  Git output:" -ForegroundColor Yellow
                $pushOutput -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
            }
            Write-Info "Troubleshooting:"
            Write-Info "  1. HTTPS: Use a Personal Access Token (not password) at https://github.com/settings/tokens"
            Write-Info "  2. Or try SSH from this machine: .\deploy-rag-infrastructure-complete.ps1 -GitHubMethod ssh"
            Write-Info "     (Requires your Windows SSH key added to theaicompany007: https://github.com/settings/keys)"
            throw
        }
    }
    
    if (-not $pushSucceeded) {
        Write-Error "Push failed"
        throw "Failed to push to GitHub"
    }
} else {
    Write-Step "Step 1: Skipping GitHub Push" "Yellow"
    Write-Info "Skipped (-SkipPush flag set)"
}

if ($SkipDeploy) {
    Write-Step "Deployment Skipped" "Yellow"
    Write-Info "Only pushed to GitHub (-SkipDeploy flag set)"
    exit 0
}

# ============================================================================
# STEP 2: PULL/CLONE ON VM
# ============================================================================

Write-Step "Step 2: Updating Code on VM" "Yellow"

try {
    Write-Info "Assuming SSH is configured on VM (skipping check to avoid config issues)..."
    Write-Success "Proceeding with git operations using explicit SSH commands"
    
    # Fix any git and SSH config issues
    Write-Info "Fixing any config issues on VM..."
    try {
        $fixGitConfigCmd = '/bin/sed -i "/sshCommand/d" /home/postgres/rag-infrastructure/.git/config 2>/dev/null; /bin/sed -i "/sshCommand/d" /home/postgres/.gitconfig 2>/dev/null; /bin/sed -i "/C:.*id_ed25519/d" /home/postgres/rag-infrastructure/.git/config 2>/dev/null; /bin/sed -i "/C:.*id_ed25519/d" /home/postgres/.gitconfig 2>/dev/null'
        $fixSshConfigCmd = '/bin/sed -i "/C:.*id_ed25519/d" /home/postgres/.ssh/config 2>/dev/null; /bin/sed -i "/rag-infrastructure/d" /home/postgres/.ssh/config 2>/dev/null'
        $fixAllCmd = "$fixGitConfigCmd; $fixSshConfigCmd; echo 'config_fixed'"
        Invoke-SshCommand $fixAllCmd -NoOutput
    } catch {
        Write-Info "Config cleanup had issues, but continuing: $_"
    }
    
    # Check if project exists
    $checkCmd = '/usr/bin/stat /home/postgres/rag-infrastructure >/dev/null 2>&1 && echo exists || echo missing'
    try {
        $projectExists = Invoke-SshCommand $checkCmd
    } catch {
        Write-Warning "Could not check if project exists, assuming missing: $_"
        $projectExists = "missing"
    }
    
    if ($FreshClone) {
        # Fresh clone: Delete and clone fresh
        if ($projectExists -match "exists") {
            Write-Info "Removing existing project for fresh clone..."
            Invoke-SshCommand "sudo rm -rf $RemoteProjectPath" -NoOutput
            Write-Success "Removed existing project"
        }
        Write-Info "Cloning fresh from GitHub..."
        
        # Show VM's public key
        Write-Info "Checking VM's SSH key for GitHub..."
        try {
$vmKeyCheck = Invoke-SshCommand "cat /home/postgres/.ssh/$VmGitKeyName.pub 2>/dev/null || echo 'KEY_NOT_FOUND'"
                if ($vmKeyCheck -and $vmKeyCheck -notmatch "KEY_NOT_FOUND") {
                    Write-Host ""
                    Write-Host "VM's SSH Public Key (add this to GitHub if clone fails):" -ForegroundColor Yellow
                Write-Host $vmKeyCheck.Trim() -ForegroundColor White
                Write-Host ""
                Write-Host "Add it at: https://github.com/theaicompany007/rag-infrastructure/settings/keys" -ForegroundColor Cyan
                Write-Host ""
            }
        } catch {
            Write-Warning "Could not retrieve VM's SSH key: $_"
        }
        
        # Create wrapper script for clone
        $cloneWrapperScript = @"
#!/bin/sh
export GIT_SSH_COMMAND="ssh -i /home/postgres/.ssh/$VmGitKeyName -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -F /dev/null"
cd /home/postgres
/usr/bin/git clone git@github.com:theaicompany007/rag-infrastructure.git rag-infrastructure
"@
        
        $tempWrapper = [System.IO.Path]::GetTempFileName()
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $unixWrapper = $cloneWrapperScript -replace "`r`n", "`n" -replace "`r", "`n"
        [System.IO.File]::WriteAllText($tempWrapper, $unixWrapper, $utf8NoBom)
        
        $remoteWrapper = "/tmp/clone-rag-infra.sh"
        Invoke-ScpCommand $tempWrapper $remoteWrapper
        $execWrapperCmd = "chmod +x $remoteWrapper && /bin/sh $remoteWrapper 2>&1; exit_code=`$?; rm -f $remoteWrapper; if [ `$exit_code -ne 0 ]; then echo 'GIT_CLONE_FAILED'; fi; exit `$exit_code"
        try {
            $cloneOutput = Invoke-SshCommand $execWrapperCmd
            if ($cloneOutput -match "GIT_CLONE_FAILED" -or $cloneOutput -match "Permission denied" -or $cloneOutput -match "ERROR: Repository not found") {
                Write-Error "Git clone failed. Error output: $cloneOutput"
                Write-Info "This usually means the VM's SSH key is not added to GitHub."
                Write-Info "To fix this:"
                Write-Info "1. Get the VM's public key by running on VM: cat ~/.ssh/$VmGitKeyName.pub"
                Write-Info "2. Add it to GitHub as a Deploy Key: https://github.com/theaicompany007/rag-infrastructure/settings/keys"
                Write-Info "3. Make sure to check 'Allow write access' if you want the VM to push"
                throw "Git clone failed - SSH key not configured"
            }
        } catch {
            if ($_.Exception.Message -notmatch "Git clone failed") {
                Write-Error "Git clone failed: $_"
                Write-Info "This usually means the VM's SSH key is not added to GitHub."
                Write-Info "Add the VM's SSH key to GitHub: https://github.com/theaicompany007/rag-infrastructure/settings/keys"
            }
            throw
        }
        
        Remove-Item $tempWrapper -ErrorAction SilentlyContinue
        Write-Success "Cloned fresh from GitHub"
    } else {
        # Default: Pull updates if exists, clone if missing
        if ($projectExists -match "missing") {
            Write-Info "Project not found, cloning from GitHub..."
            
            $cloneWrapperScript = @"
#!/bin/sh
export GIT_SSH_COMMAND="ssh -i /home/postgres/.ssh/$VmGitKeyName -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -F /dev/null"
cd /home/postgres
/usr/bin/git clone git@github.com:theaicompany007/rag-infrastructure.git rag-infrastructure
"@
            
            $tempWrapper = [System.IO.Path]::GetTempFileName()
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            $unixWrapper = $cloneWrapperScript -replace "`r`n", "`n" -replace "`r", "`n"
            [System.IO.File]::WriteAllText($tempWrapper, $unixWrapper, $utf8NoBom)
            
            $remoteWrapper = "/tmp/clone-rag-infra.sh"
            Invoke-ScpCommand $tempWrapper $remoteWrapper
            $execWrapperCmd = "chmod +x $remoteWrapper && env -i HOME=/home/postgres USER=postgres PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/sh $remoteWrapper && rm -f $remoteWrapper"
            Invoke-SshCommand $execWrapperCmd
            
            Remove-Item $tempWrapper -ErrorAction SilentlyContinue
            Write-Success "Cloned from GitHub"
        } else {
            Write-Info "Project exists, pulling latest changes (git pull)..."
            
            # Show VM's SSH key
            Write-Info "Checking VM's SSH key for GitHub..."
            try {
                $vmKeyCheck = Invoke-SshCommand "cat /home/postgres/.ssh/$VmGitKeyName.pub 2>/dev/null || echo 'KEY_NOT_FOUND'"
                if ($vmKeyCheck -and $vmKeyCheck -notmatch "KEY_NOT_FOUND") {
                    Write-Host ""
                    Write-Host "VM's SSH Public Key (add this to GitHub if pull fails):" -ForegroundColor Yellow
                    Write-Host $vmKeyCheck.Trim() -ForegroundColor White
                    Write-Host ""
                    Write-Host "Add it at: https://github.com/theaicompany007/rag-infrastructure/settings/keys" -ForegroundColor Cyan
                    Write-Host ""
                }
            } catch {
                Write-Warning "Could not retrieve VM's SSH key: $_"
            }
            
            # Use wrapper script for pull
            $pullWrapperScript = @"
#!/bin/sh
export GIT_SSH_COMMAND="ssh -i /home/postgres/.ssh/$VmGitKeyName -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -F /dev/null"
cd /home/postgres/rag-infrastructure
/usr/bin/git remote set-url origin git@github.com:theaicompany007/rag-infrastructure.git
/usr/bin/git pull origin main
"@
            
            $tempWrapper = [System.IO.Path]::GetTempFileName()
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            $unixWrapper = $pullWrapperScript -replace "`r`n", "`n" -replace "`r", "`n"
            [System.IO.File]::WriteAllText($tempWrapper, $unixWrapper, $utf8NoBom)
            
            $remoteWrapper = "/tmp/pull-rag-infra.sh"
            Invoke-ScpCommand $tempWrapper $remoteWrapper
            $execWrapperCmd = "chmod +x $remoteWrapper && /bin/sh $remoteWrapper 2>&1; exit_code=`$?; rm -f $remoteWrapper; if [ `$exit_code -ne 0 ]; then echo 'GIT_PULL_FAILED'; fi; exit `$exit_code"
            
            $pullResult = Invoke-SshCommand $execWrapperCmd -NoThrow
            $pullOutput = $pullResult.Output
            $pullExitCode = $pullResult.ExitCode
            
            if ($pullExitCode -ne 0 -or $pullOutput -match "GIT_PULL_FAILED" -or $pullOutput -match "Permission denied" -or $pullOutput -match "ERROR: Repository not found" -or $pullOutput -match "fatal:") {
                Write-Error "Git pull failed on VM (exit code: $pullExitCode)"
                if ($pullOutput -and $pullOutput.Trim()) {
                    Write-Host "  Git output:" -ForegroundColor Yellow
                    $pullOutput -split "`n" | ForEach-Object { $l = $_.Trim(); if ($l) { Write-Host "    $l" -ForegroundColor Gray } }
                }
                Write-Host ""
                if ($pullOutput -match "ERROR: Repository not found") {
                    Write-Host "  [TROUBLESHOOTING] 'Repository not found' usually means:" -ForegroundColor Yellow
                    Write-Host "    - Deploy key was added in the WRONG place. It must be under THIS repo:" -ForegroundColor Gray
                    Write-Host "      https://github.com/theaicompany007/rag-infrastructure/settings/keys" -ForegroundColor Cyan
                    Write-Host "      (Repo Settings -> Deploy keys, NOT your profile SSH keys)" -ForegroundColor Gray
                    Write-Host "    - Or the repo name/org is wrong. Confirm the repo exists:" -ForegroundColor Gray
                    Write-Host "      https://github.com/theaicompany007/rag-infrastructure" -ForegroundColor Cyan
                }
                Write-Info "Add the VM's SSH key (shown above) to THIS repo's Deploy keys:"
                Write-Host "  1. Open: https://github.com/theaicompany007/rag-infrastructure/settings/keys" -ForegroundColor Cyan
                Write-Host "  2. Under 'Deploy keys', click 'Add deploy key'" -ForegroundColor Cyan
                Write-Host "  3. Title: e.g. chroma-vm" -ForegroundColor Cyan
                Write-Host "  4. Key: paste the VM's public key (ssh-ed25519 ... line above)" -ForegroundColor Cyan
                Write-Host "  5. Click 'Add key', then run this script again" -ForegroundColor Cyan
                throw "Git pull failed - add VM SSH key to GitHub and re-run"
            }
            Write-Host $pullOutput
            
            Remove-Item $tempWrapper -ErrorAction SilentlyContinue
            Write-Success "Pulled latest changes"
        }
    }
} catch {
    Write-Error "Failed to update code on VM: $_"
    Write-Warning "If SSH key is not set up on VM, you may need to:"
    Write-Warning "1. Add the VM's public key to GitHub"
    Write-Warning "2. Or add it as a Deploy Key at: https://github.com/theaicompany007/rag-infrastructure/settings/keys"
    exit 1
}

# ============================================================================
# STEP 3: COPY ENVIRONMENT FILES
# ============================================================================

Write-Step "Step 3: Copying Environment Files" "Yellow"

try {
    # Copy .env.local
    $envLocalPath = Join-Path $LocalProjectPath ".env.local"
    if (Test-Path $envLocalPath) {
        Write-Info "Copying .env.local to VM..."
        Invoke-ScpCommand $envLocalPath "$RemoteProjectPath/.env.local"
        Write-Success "Copied .env.local"
    } else {
        Write-Warning ".env.local not found locally, skipping copy"
    }
    
    # Copy .env (if exists)
    $envPath = Join-Path $LocalProjectPath ".env"
    if (Test-Path $envPath) {
        Write-Info "Copying .env to VM..."
        Invoke-ScpCommand $envPath "$RemoteProjectPath/.env"
        Write-Success "Copied .env"
    } else {
        Write-Info ".env not found locally, skipping copy (optional file)"
    }
} catch {
    Write-Error "Failed to copy environment files: $_"
    exit 1
}

# ============================================================================
# STEP 4: SET PERMISSIONS
# ============================================================================

Write-Step "Step 4: Setting Script Permissions" "Yellow"

try {
    Write-Info "Making all .sh files executable..."
    $chmodScript = @'
#!/bin/sh
cd /home/postgres/rag-infrastructure
find . -name "*.sh" -type f | while IFS= read -r file; do
    chmod +x "$file"
done
'@
    
    $tempChmodScript = [System.IO.Path]::GetTempFileName()
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $unixChmodScript = $chmodScript -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText($tempChmodScript, $unixChmodScript, $utf8NoBom)
    
    $remoteChmodScript = "/tmp/chmod-scripts.sh"
    Invoke-ScpCommand $tempChmodScript $remoteChmodScript
    Invoke-SshCommand "chmod +x $remoteChmodScript && $remoteChmodScript && rm -f $remoteChmodScript"
    
    Remove-Item $tempChmodScript -ErrorAction SilentlyContinue
    Write-Success "Set permissions on shell scripts"
} catch {
    Write-Error "Failed to set permissions: $_"
    exit 1
}

# ============================================================================
# STEP 5: START INFRASTRUCTURE
# ============================================================================

Write-Step "Step 5: Starting Infrastructure Services" "Yellow"

try {
    # Check if services are running (works for both regular deploy and fresh clone)
    # This check happens AFTER:
    # - Code is pulled/cloned (Step 2)
    # - .env.local is copied (Step 3)
    # - Permissions are set (Step 4)
    # This ensures that even with fresh clone, we detect running services correctly
    # and restart them to use the new code/config.
    $isRunning = Test-InfrastructureRunning
    
    if ($isRunning) {
        Write-Info "Services are already running, restarting to apply changes..."
        Write-Info "This will pick up new code, .env.local changes, and configuration updates"
        Write-Info "Running manage-infra.sh restart..."
        $deployCmd = "cd $RemoteProjectPath; ./manage-infra.sh restart 2>&1"
    } else {
        Write-Info "Services are not running, starting infrastructure..."
        Write-Info "Running manage-infra.sh start..."
        $deployCmd = "cd $RemoteProjectPath; ./manage-infra.sh start 2>&1"
    }
    
    $output = Invoke-SshCommand $deployCmd
    
    # Display output
    Write-Host $output
    
    # Check if deployment succeeded
    if ($output -match "✅.*started" -or $output -match "✅.*restarted" -or $output -match "Infrastructure services started" -or $output -match "Infrastructure services restarted" -or $output -match "Container.*Running" -or $output -match "Container.*Started" -or $output -match "restarted") {
        if ($isRunning) {
            Write-Success "Infrastructure services restarted successfully (changes applied)"
        } else {
            Write-Success "Infrastructure services started successfully"
        }
    } elseif ($output -match "ERROR" -or $output -match "Failed" -or $output -match "fatal") {
        Write-Error "Deployment appears to have failed. Check output above for details."
        Write-Warning "Check logs on VM: gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic --command='cd /home/postgres/rag-infrastructure && docker compose -p infra logs'"
        exit 1
    } else {
        if ($isRunning) {
            Write-Success "Infrastructure services restarted (check output above to verify)"
        } else {
            Write-Success "Infrastructure services started (check output above to verify)"
        }
    }
} catch {
    Write-Error "Deployment command failed: $_"
    Write-Warning "This might be a false error. Check the output above."
    Write-Warning "To verify deployment status, run on VM:"
    Write-Warning "  gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic --command='cd /home/postgres/rag-infrastructure && ./manage-infra.sh status'"
    # Don't exit - let it continue to status check
}

# ============================================================================
# STEP 6: CHECK STATUS
# ============================================================================

Write-Step "Step 6: Checking Service Status" "Yellow"

try {
    Write-Info "Checking Docker container status..."
    $statusCmd = "cd $RemoteProjectPath; docker compose -p infra ps"
    try {
        $containerStatus = Invoke-SshCommand $statusCmd
        Write-Host $containerStatus
    } catch {
        Write-Warning "Could not check container status: $_"
    }
    
    Write-Info "Checking network status..."
    try {
        $networkCmd = "docker network ls | grep shared-infra-network || echo 'network_not_found'"
        $networkStatus = Invoke-SshCommand $networkCmd
        if ($networkStatus -match "shared-infra-network") {
            Write-Host "shared-infra-network: exists" -ForegroundColor Green
        } else {
            Write-Host "shared-infra-network: not found" -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Could not check network status: $_"
    }
    
    Write-Info "Testing RAG service health endpoint..."
    try {
        $healthCmd = "curl -s http://localhost:8001/health"
        $healthCheck = Invoke-SshCommand $healthCmd
        if ($healthCheck -match "ok" -or $healthCheck -match "healthy" -or $healthCheck -match "status") {
            Write-Host "RAG Service health check: $healthCheck" -ForegroundColor Green
        } else {
            Write-Host "RAG Service health check response: $healthCheck"
        }
    } catch {
        Write-Warning "Could not check RAG service health endpoint: $_"
    }
    
    Write-Info "Checking Celery worker status..."
    try {
        $celeryStatusCmd = "cd $RemoteProjectPath; ./manage-infra.sh celery-status 2>&1"
        $celeryStatus = Invoke-SshCommand $celeryStatusCmd
        Write-Host $celeryStatus
    } catch {
        Write-Warning "Could not check Celery status: $_"
    }
    
    Write-Success "Status check completed"
} catch {
    Write-Warning "Status check had issues: $_"
}

# ============================================================================
# COMPLETION
# ============================================================================

Write-Step "Deployment Complete!" "Green"

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  View logs:" -ForegroundColor Cyan
Write-Host "    gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic --command='cd /home/postgres/rag-infrastructure && docker compose -p infra logs -f'" -ForegroundColor Gray
Write-Host ""
Write-Host "  Check status:" -ForegroundColor Cyan
Write-Host "    gcloud compute ssh postgres@chroma-vm --zone=asia-south1-a --project=onlynereputation-agentic --command='cd /home/postgres/rag-infrastructure && ./manage-infra.sh status'" -ForegroundColor Gray
Write-Host ""
Write-Host "  Access services:" -ForegroundColor Cyan
Write-Host "    - RAG Service: http://localhost:8001 (or configured URL)" -ForegroundColor Gray
Write-Host "    - ChromaDB: http://localhost:8000" -ForegroundColor Gray
Write-Host "    - Redis: localhost:6379" -ForegroundColor Gray
Write-Host "    - Celery Worker: Processing VANI tasks" -ForegroundColor Gray
Write-Host ""
Write-Host "  Manage Celery:" -ForegroundColor Cyan
Write-Host "    ./manage-infra.sh enable-celery   # Enable Celery worker" -ForegroundColor Gray
Write-Host "    ./manage-infra.sh disable-celery # Disable Celery worker" -ForegroundColor Gray
Write-Host "    ./manage-infra.sh celery-status  # Check Celery status" -ForegroundColor Gray
Write-Host ""
