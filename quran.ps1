# ============================================================================
# Holy Quran 24/7 Live Stream Launcher
# Pure ASCII - Sheikh Abdul Rahman Al-Sudais
# ============================================================================

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "Holy Quran - 24/7 Live Stream Launcher"
$repo = "lefraich/mt5-farm"

Clear-Host
Write-Host ""
Write-Host "=======================================================" -ForegroundColor Green
Write-Host "   HOLY QURAN 24/7 LIVE STREAM BROADCASTER            " -ForegroundColor Green
Write-Host "   Reciter: Sheikh Abdul Rahman Al-Sudais (Complete)   " -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host ""

try {
    $null = Get-Command gh -ErrorAction Stop
} catch {
    Write-Host "[ERROR] GitHub CLI (gh) is not installed!" -ForegroundColor Red
    Write-Host "Download from https://cli.github.com" -ForegroundColor Yellow
    exit 1
}

# -----------------------------------------------------------------------------
# Step 1: Get Stream Key
# -----------------------------------------------------------------------------
Write-Host "-------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Step 1: Live Stream Key" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------" -ForegroundColor Cyan

$streamKey = Read-Host " Enter Stream Key for Holy Quran Live"
if ([string]::IsNullOrWhiteSpace($streamKey)) {
    Write-Host "[ERROR] Stream Key is required!" -ForegroundColor Red
    exit 1
}

gh secret set QURAN_STREAM_KEY --body $streamKey --repo $repo
Write-Host "[OK] Secret QURAN_STREAM_KEY updated successfully!" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# Step 2: Trigger Workflow
# -----------------------------------------------------------------------------
Write-Host "-------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Step 2: Launch Stream to YouTube" -ForegroundColor Cyan
Write-Host "-------------------------------------------------------" -ForegroundColor Cyan

Write-Host "[INFO] Triggering GitHub Actions workflow (stream_quran.yml)..." -ForegroundColor Yellow
$runResult = gh workflow run "stream_quran.yml" --repo $repo -f stream_key="$streamKey" -f quality="1080p" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Workflow triggered successfully!" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Failed to trigger workflow: $runResult" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Connecting to cloud runner..." -ForegroundColor Yellow
Start-Sleep -Seconds 4

$runs = gh run list --repo $repo --workflow "stream_quran.yml" --limit 1 --json databaseId,url 2>$null | ConvertFrom-Json
if ($runs.Count -gt 0) {
    $runId = $runs[0].databaseId
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "  HOLY QURAN 24/7 LIVE STREAM IS NOW RUNNING!          " -ForegroundColor Green
    Write-Host "  Track Run: https://github.com/$repo/actions/runs/$runId" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
}

Write-Host "Check YouTube Studio Live Control Room in about 1-2 minutes!" -ForegroundColor Cyan
Write-Host ""
