# Downloads the models and art sources listed in assets.lock.json.
# Files already present with the right hash are skipped.
# Usage: tools\fetch_assets.cmd [-Only assets]   (path prefix filter, e.g. CI needs only "assets")
param([string]$Only = "")

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "assets_common.ps1")

if (-not (Test-Path $LockPath)) {
    Write-Host "$AssetLockName not found" -ForegroundColor Red
    exit 1
}
$files = Read-AssetLock

$fetched = 0
$failed = 0
foreach ($rel in $files.Keys) {
    if ($Only -and -not $rel.StartsWith($Only)) { continue }
    $entry = $files[$rel]
    $target = Join-Path $RepoRoot $rel
    if ((Test-Path -LiteralPath $target) -and (Get-Sha256 $target) -eq $entry.sha256) {
        Write-Host "ok      $rel"
        continue
    }
    $dir = Split-Path -Parent $target
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = "$target.download"
    Write-Host "fetch   $rel"
    $code = Invoke-S3 @("s3", "cp", "--only-show-errors", "s3://$AssetBucket/blobs/$($entry.sha256)", $tmp)
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $tmp)) {
        Write-Host "FETCH FAILED: $rel" -ForegroundColor Red
        $failed++
        continue
    }
    if ((Get-Sha256 $tmp) -ne $entry.sha256) {
        Remove-Item -LiteralPath $tmp -Force
        Write-Host "HASH MISMATCH: $rel" -ForegroundColor Red
        $failed++
        continue
    }
    Move-Item -LiteralPath $tmp -Destination $target -Force
    $fetched++
}

if ($failed -gt 0) {
    Write-Host "Fetched $fetched, failed $failed" -ForegroundColor Red
    exit 1
}
Write-Host "Fetched $fetched file(s), assets up to date" -ForegroundColor Green
exit 0
