<#
.SYNOPSIS
  Push current project to GitHub

.DESCRIPTION
  This script checks git status, optionally commits changes, and pushes to GitHub.
  Supports both SSH and HTTPS authentication methods with automatic fallback.
  Run this from the project root directory.

  AUTHENTICATION:
  - By default, the script auto-detects the authentication method based on your
    current git remote URL (preserves existing configuration)
  - If SSH push fails, automatically falls back to HTTPS
  - Use -UseHttps or -UseSsh to explicitly force a method

.PARAMETER AutoCommit
  Automatically commit all changes without prompting

.PARAMETER CommitMessage
  Custom commit message (if not provided, will prompt or use default)

.PARAMETER ForceCommit
  Force commit even if no changes detected (creates empty commit)

.PARAMETER UseHttps
  Force use HTTPS for GitHub operations (instead of SSH).
  Useful when SSH authentication is not configured or fails.

.PARAMETER UseSsh
  Force use SSH for GitHub operations (default if auto-detection fails).
  Requires SSH key to be set up and added to GitHub.

.EXAMPLE
  .\push-to-github.ps1
  Push with auto-detected authentication method (preserves current remote)

.EXAMPLE
  .\push-to-github.ps1 -AutoCommit
  Auto-commit and push with default message

.EXAMPLE
  .\push-to-github.ps1 -CommitMessage "Update deployment scripts"
  Commit with custom message and push

.EXAMPLE
  .\push-to-github.ps1 -AutoCommit -CommitMessage "Full repository commit" -ForceCommit
  Force commit everything and push

.EXAMPLE
  .\push-to-github.ps1 -UseHttps
  Force use HTTPS authentication (bypasses SSH)

.EXAMPLE
  .\push-to-github.ps1 -UseSsh
  Force use SSH authentication (requires SSH key setup)

.NOTES
  - The script automatically falls back from SSH to HTTPS if SSH fails
  - HTTPS requires credential helper or personal access token
  - SSH requires SSH key to be added to GitHub: https://github.com/settings/keys
#>

param(
    [switch]$AutoCommit = $false,
    [string]$CommitMessage = "",
    [switch]$ForceCommit = $false,
    [switch]$UseHttps = $false,
    [switch]$UseSsh = $false
)

$ErrorActionPreference = "Stop"

# GitHub repository URLs
$GitHubRepoSsh = "git@github.com:theaicompany007/rag-infrastructure.git"
$GitHubRepoHttps = "https://github.com/theaicompany007/rag-infrastructure.git"

# Determine which method to use
$useHttpsMethod = $false
if ($UseHttps) {
    $useHttpsMethod = $true
} elseif ($UseSsh) {
    $useHttpsMethod = $false
} else {
    # Auto-detect: check current remote and preserve if working
    $currentRemote = git config --get remote.origin.url 2>$null
    if ($currentRemote -match "^https://") {
        $useHttpsMethod = $true
        Write-Host "[INFO] Auto-detected: Using HTTPS (current remote is HTTPS)" -ForegroundColor Cyan
    } elseif ($currentRemote -match "^git@") {
        $useHttpsMethod = $false
        Write-Host "[INFO] Auto-detected: Using SSH (current remote is SSH)" -ForegroundColor Cyan
    } else {
        # Default to SSH if we can't determine
        $useHttpsMethod = $false
        Write-Host "[INFO] Auto-detected: Defaulting to SSH" -ForegroundColor Cyan
    }
}

# Function to configure git remote (supports both SSH and HTTPS)
function Configure-GitRemote {
    param([bool]$UseHttps)
    
    $currentRemote = git config --get remote.origin.url 2>$null
    
    if ($UseHttps) {
        Write-Host "[INFO] Configuring git remote to use HTTPS..." -ForegroundColor Cyan
        if ($currentRemote -match "^git@") {
            Write-Host "[INFO] Current remote uses SSH, switching to HTTPS..." -ForegroundColor Yellow
            git remote set-url origin $GitHubRepoHttps
            Write-Host "[OK] Git remote configured to use HTTPS" -ForegroundColor Green
        } elseif ($currentRemote -match "^https://") {
            Write-Host "[INFO] Git remote already uses HTTPS" -ForegroundColor Green
        } else {
            Write-Host "[INFO] Setting remote to HTTPS URL..." -ForegroundColor Cyan
            git remote set-url origin $GitHubRepoHttps
            Write-Host "[OK] Git remote configured to use HTTPS" -ForegroundColor Green
        }
    } else {
        Write-Host "[INFO] Configuring git remote to use SSH..." -ForegroundColor Cyan
        if ($currentRemote -match "^https://") {
            Write-Host "[INFO] Current remote uses HTTPS, switching to SSH..." -ForegroundColor Yellow
            git remote set-url origin $GitHubRepoSsh
            Write-Host "[OK] Git remote configured to use SSH" -ForegroundColor Green
        } elseif ($currentRemote -match "^git@") {
            Write-Host "[INFO] Git remote already uses SSH" -ForegroundColor Green
        } else {
            Write-Host "[INFO] Setting remote to SSH URL..." -ForegroundColor Cyan
            git remote set-url origin $GitHubRepoSsh
            Write-Host "[OK] Git remote configured to use SSH" -ForegroundColor Green
        }
    }
}

# Function to test SSH connection to GitHub
function Test-GitHubSshConnection {
    Write-Host "[INFO] Testing SSH connection to GitHub..." -ForegroundColor Cyan
    
    # Clear any previous errors
    $Error.Clear()
    
    # Temporarily change error action to silently continue so we can capture the output
    $oldErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    
    try {
        # Run SSH test and capture all output (stdout and stderr)
        $testResult = & ssh -T git@github.com 2>&1
        $exitCode = $LASTEXITCODE
        
        # Also check PowerShell's $Error variable for the message
        $errorMessages = $Error | ForEach-Object { $_.Exception.Message -join " " }
        
        # Convert output to string for pattern matching
        # Handle both array and string outputs
        $outputString = ""
        if ($testResult) {
            if ($testResult -is [System.Array]) {
                $outputString = ($testResult | Out-String).Trim()
            } else {
                $outputString = $testResult.ToString().Trim()
            }
        }
        
        # Check error messages as well (PowerShell may have captured it)
        $allOutput = "$outputString $errorMessages"
        
        # GitHub returns exit code 1 even on successful authentication
        # The message "You've successfully authenticated" indicates success
        if ($allOutput -match "successfully authenticated" -or $outputString -match "successfully authenticated") {
            Write-Host "[OK] SSH connection to GitHub verified" -ForegroundColor Green
            return $true
        } elseif ($exitCode -eq 0 -or $exitCode -eq 1) {
            # Exit code 0 or 1 usually means connection succeeded
            # Even if we don't see the exact message, these exit codes indicate success
            Write-Host "[OK] SSH connection to GitHub works" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[WARN] SSH connection to GitHub may not be configured (exit code: $exitCode)" -ForegroundColor Yellow
            if ($outputString) {
                Write-Host "[WARN] Output: $outputString" -ForegroundColor Yellow
            }
            Write-Host "[INFO] To set up SSH for GitHub:" -ForegroundColor Cyan
            Write-Host "[INFO]   1. Generate SSH key: ssh-keygen -t ed25519 -C 'your_email@example.com'" -ForegroundColor Gray
            Write-Host "[INFO]   2. Add to ssh-agent: ssh-add ~/.ssh/id_ed25519" -ForegroundColor Gray
            Write-Host "[INFO]   3. Add public key to GitHub: https://github.com/settings/keys" -ForegroundColor Gray
            Write-Host "[INFO]   4. Test: ssh -T git@github.com" -ForegroundColor Gray
            return $false
        }
    } catch {
        # PowerShell may treat stderr output as an exception, but check the message
        $errorMessage = $_.Exception.Message
        
        # Check error record if available
        $errorRecord = $_
        $fullErrorText = ""
        if ($errorRecord.ErrorRecord) {
            $fullErrorText = $errorRecord.ErrorRecord.ToString()
        } elseif ($errorRecord.Exception) {
            $fullErrorText = $errorRecord.Exception.ToString()
        }
        
        # Combine all error text for pattern matching
        $allErrorText = "$errorMessage $fullErrorText"
        
        if ($allErrorText -match "successfully authenticated") {
            Write-Host "[OK] SSH connection to GitHub verified" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[WARN] SSH connection test encountered an error" -ForegroundColor Yellow
            Write-Host "[WARN] Error: $errorMessage" -ForegroundColor Yellow
            Write-Host "[INFO] To set up SSH for GitHub:" -ForegroundColor Cyan
            Write-Host "[INFO]   1. Generate SSH key: ssh-keygen -t ed25519 -C 'your_email@example.com'" -ForegroundColor Gray
            Write-Host "[INFO]   2. Add to ssh-agent: ssh-add ~/.ssh/id_ed25519" -ForegroundColor Gray
            Write-Host "[INFO]   3. Add public key to GitHub: https://github.com/settings/keys" -ForegroundColor Gray
            Write-Host "[INFO]   4. Test: ssh -T git@github.com" -ForegroundColor Gray
            return $false
        }
    } finally {
        # Restore original error action preference
        $ErrorActionPreference = $oldErrorAction
    }
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   Push to GitHub" -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# Check if we're in a git repository
if (-not (Test-Path ".git")) {
    Write-Host "[ERROR] Not in a git repository" -ForegroundColor Red
    Write-Host "[TIP] Run this script from the project root directory" -ForegroundColor Yellow
    exit 1
}

# Get project name from current directory
$ProjectName = Split-Path -Leaf (Get-Location)
Write-Host "[INFO] Project: $ProjectName" -ForegroundColor Cyan
Write-Host ""

# Check git remote
Write-Host "[CHECK] Checking git remote..." -ForegroundColor Yellow
$remoteUrl = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] No 'origin' remote configured" -ForegroundColor Red
    Write-Host "[TIP] Configure git remote first:" -ForegroundColor Yellow
    Write-Host '   git remote add origin "your-github-repo-url"' -ForegroundColor Gray
    exit 1
}

Write-Host "[OK] Remote: $remoteUrl" -ForegroundColor Green
Write-Host ""

# Configure git remote based on selected method
Configure-GitRemote -UseHttps $useHttpsMethod

# Test SSH connection only if using SSH
if (-not $useHttpsMethod) {
    $sshWorks = Test-GitHubSshConnection
    if (-not $sshWorks) {
        Write-Host "[WARN] SSH connection to GitHub may not be working, but continuing..." -ForegroundColor Yellow
        Write-Host "[INFO] If push fails, the script will automatically try HTTPS as fallback" -ForegroundColor Cyan
    }
} else {
    Write-Host "[INFO] Using HTTPS method - skipping SSH connection test" -ForegroundColor Cyan
}

Write-Host ""

# Check git status
Write-Host "[CHECK] Checking git status..." -ForegroundColor Yellow
$status = git status --porcelain
$branch = git rev-parse --abbrev-ref HEAD

Write-Host "[INFO] Branch: $branch" -ForegroundColor Cyan

# Check for any changes (staged, unstaged, or untracked)
$hasChanges = $false
if ($status) {
    $statusLines = $status -split "`n" | Where-Object { $_.Trim() -ne "" }
    if ($statusLines) {
        $hasChanges = $true
        $changedFiles = $statusLines.Count
        Write-Host "[INFO] Changes detected: $changedFiles file(s)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Changed files:" -ForegroundColor Gray
        git status --short | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
        Write-Host ""
    }
}

if ($hasChanges) {
    
    # Handle committing
    $shouldCommit = $false
    if ($AutoCommit) {
        $shouldCommit = $true
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
            $CommitMessage = "Update RAG infrastructure"
        }
    } else {
        $response = Read-Host "Commit and push these changes? (y/n)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            $shouldCommit = $true
            if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
                $CommitMessage = Read-Host "Enter commit message (or press Enter for default)"
                if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
                    $CommitMessage = "Update RAG infrastructure"
                }
            }
        }
    }
    
    if ($shouldCommit) {
        Write-Host ""
        Write-Host "[COMMIT] Committing all changes..." -ForegroundColor Yellow
        
        # Stage all changes (including new files, modified files, and deleted files)
        Write-Host "  Staging all changes..." -ForegroundColor Cyan
        git add -A
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to stage changes" -ForegroundColor Red
            exit 1
        }
        
        # Commit with message
        Write-Host "  Committing with message: $CommitMessage" -ForegroundColor Cyan
        git commit -m "$CommitMessage"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to commit changes" -ForegroundColor Red
            Write-Host "[TIP] This might happen if there are no changes to commit" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "[OK] All changes committed successfully" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Skipping commit" -ForegroundColor Yellow
    }
} else {
    Write-Host "[OK] Working directory clean - no changes to commit" -ForegroundColor Green
    Write-Host ""
    
    if ($ForceCommit) {
        Write-Host "[WARN] Force commit requested - will create empty commit" -ForegroundColor Yellow
        Write-Host ""
        
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
            if ($AutoCommit) {
                $CommitMessage = "Empty commit - force update"
            } else {
                $CommitMessage = Read-Host "Enter commit message for empty commit"
                if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
                    $CommitMessage = "Empty commit - force update"
                }
            }
        }
        
        Write-Host "[COMMIT] Creating empty commit..." -ForegroundColor Yellow
        git commit --allow-empty -m "$CommitMessage"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to create empty commit" -ForegroundColor Red
            exit 1
        }
        Write-Host "[OK] Empty commit created" -ForegroundColor Green
    } else {
        Write-Host "[TIP] If you want to commit everything, make sure you have changes in the repository" -ForegroundColor Cyan
        Write-Host "[TIP] Or use -ForceCommit to create an empty commit" -ForegroundColor Cyan
    }
}

# Check if we need to push
Write-Host ""
Write-Host "[CHECK] Checking if push is needed..." -ForegroundColor Yellow
$localCommit = git rev-parse HEAD

# Try to get remote commit, but handle SSH errors gracefully
$ErrorActionPreference = "SilentlyContinue"
$remoteCommit = git ls-remote origin $branch 2>&1 | Select-Object -First 1
$lsRemoteExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"

if ($lsRemoteExitCode -eq 0 -and $remoteCommit -and $remoteCommit -notmatch "Permission denied" -and $remoteCommit -notmatch "fatal:") {
    $remoteHash = ($remoteCommit -split '\s+')[0]
    if ($localCommit -eq $remoteHash) {
        Write-Host "[OK] Local and remote are in sync" -ForegroundColor Green
        Write-Host ""
        Write-Host "[INFO] No push needed. Repository is up to date." -ForegroundColor Cyan
        exit 0
    } else {
        Write-Host "[INFO] Local commits ahead of remote" -ForegroundColor Yellow
    }
} else {
    if ($remoteCommit -match "Permission denied" -or $remoteCommit -match "fatal:") {
        Write-Host "[WARN] Could not check remote status (SSH authentication issue)" -ForegroundColor Yellow
        Write-Host "[INFO] Will attempt to push anyway..." -ForegroundColor Cyan
    } else {
        Write-Host "[INFO] No remote branch found, will push new branch" -ForegroundColor Yellow
    }
}

# Push to GitHub with fallback logic
Write-Host ""
$pushMethod = if ($useHttpsMethod) { "HTTPS" } else { "SSH" }
Write-Host "[PUSH] Pushing to GitHub via $pushMethod..." -ForegroundColor Yellow

$pushSucceeded = $false
$pushError = $null

try {
    # Suppress error output and capture both stdout and stderr
    $ErrorActionPreference = "SilentlyContinue"
    $pushOutput = & git push origin $branch 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    
    # Display output
    if ($pushOutput) {
        Write-Host $pushOutput.Trim()
    }
    
    # Check for actual errors vs informational messages
    $hasRealError = $false
    if ($pushOutput) {
        $pushOutputLines = $pushOutput -split "`n" | Where-Object { $_.Trim() }
        foreach ($line in $pushOutputLines) {
            $trimmedLine = $line.Trim()
            # Check for real errors (not "Everything up-to-date")
            if ($trimmedLine -match "Permission denied" -or 
                $trimmedLine -match "fatal:.*Permission denied" -or 
                $trimmedLine -match "ERROR: Repository not found" -or 
                ($trimmedLine -match "fatal:" -and $trimmedLine -notmatch "Everything up-to-date")) {
                $hasRealError = $true
                break
            }
        }
    }
    
    # Check exit code - 0 means success (even if "Everything up-to-date")
    if ($exitCode -eq 0 -or $pushOutput -match "Everything up-to-date" -or $pushOutput -match "Already up to date") {
        $pushSucceeded = $true
        if ($pushOutput -match "Everything up-to-date" -or $pushOutput -match "Already up to date") {
            Write-Host "[OK] Repository is already up-to-date on GitHub" -ForegroundColor Green
        } else {
            Write-Host "[OK] Pushed to GitHub successfully via $pushMethod" -ForegroundColor Green
        }
    } elseif ($hasRealError) {
        throw "Git push failed: $pushOutput"
    } else {
        # If exit code is non-zero but no real error detected, still check for success messages
        if ($pushOutput -match "Everything up-to-date" -or $pushOutput -match "Already up to date") {
            $pushSucceeded = $true
            Write-Host "[OK] Repository is already up-to-date on GitHub" -ForegroundColor Green
        } else {
            throw "Git push failed with exit code $exitCode"
        }
    }
} catch {
    $pushError = $_.Exception.Message
    Write-Host "[WARN] Push via $pushMethod failed: $pushError" -ForegroundColor Yellow
    
    # If SSH failed, try HTTPS as fallback
    if (-not $useHttpsMethod) {
        Write-Host "[INFO] Attempting fallback to HTTPS..." -ForegroundColor Cyan
        Configure-GitRemote -UseHttps $true
        
        try {
            Write-Host "[PUSH] Retrying push via HTTPS..." -ForegroundColor Yellow
            
            # Suppress error output and capture both stdout and stderr
            $ErrorActionPreference = "SilentlyContinue"
            $retryOutput = & git push origin $branch 2>&1 | Out-String
            $retryExitCode = $LASTEXITCODE
            $ErrorActionPreference = "Stop"
            
            # Display output
            if ($retryOutput) {
                Write-Host $retryOutput.Trim()
            }
            
            # Check exit code - 0 means success (even if "Everything up-to-date")
            if ($retryExitCode -eq 0 -or $retryOutput -match "Everything up-to-date" -or $retryOutput -match "Already up to date") {
                $pushSucceeded = $true
                if ($retryOutput -match "Everything up-to-date" -or $retryOutput -match "Already up to date") {
                    Write-Host "[OK] Repository is already up-to-date on GitHub (HTTPS)" -ForegroundColor Green
                } else {
                    Write-Host "[OK] Pushed to GitHub successfully via HTTPS (fallback)" -ForegroundColor Green
                }
            } else {
                throw "Git push via HTTPS also failed with exit code $retryExitCode"
            }
        } catch {
            Write-Host "[ERROR] Both SSH and HTTPS push failed" -ForegroundColor Red
            Write-Host "[ERROR] SSH error: $pushError" -ForegroundColor Red
            Write-Host "[ERROR] HTTPS error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "[INFO] Troubleshooting:" -ForegroundColor Cyan
            Write-Host "[INFO]   1. For SSH: Set up SSH key at https://github.com/settings/keys" -ForegroundColor Gray
            Write-Host "[INFO]   2. For HTTPS: Use credential helper or personal access token" -ForegroundColor Gray
            Write-Host "[INFO]   3. Or use -UseHttps parameter to force HTTPS" -ForegroundColor Gray
            exit 1
        }
    } else {
        # HTTPS failed, no fallback
        Write-Host "[ERROR] Failed to push to GitHub via HTTPS: $pushError" -ForegroundColor Red
        Write-Host "[INFO] Troubleshooting:" -ForegroundColor Cyan
        Write-Host "[INFO]   1. Check your GitHub credentials" -ForegroundColor Gray
        Write-Host "[INFO]   2. Use credential helper: git config --global credential.helper wincred" -ForegroundColor Gray
        Write-Host "[INFO]   3. Or try SSH: .\push-to-github.ps1 -UseSsh" -ForegroundColor Gray
        exit 1
    }
}

if (-not $pushSucceeded) {
    Write-Host "[ERROR] Push failed" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Successfully pushed to GitHub!" -ForegroundColor Green
Write-Host ""
Write-Host "[INFO] Repository: $remoteUrl" -ForegroundColor Cyan
Write-Host "[INFO] Branch: $branch" -ForegroundColor Cyan
Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "[OK] Push Complete!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""
