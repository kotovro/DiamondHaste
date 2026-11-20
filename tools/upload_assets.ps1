# Uploads local models and art sources to the bucket and updates assets.lock.json.
# Run after adding or changing a model, then commit assets.lock.json.
# Usage: tools\upload_assets.cmd [-Prune]
#   -Prune  also drop lock entries whose files no longer exist locally.
param([switch]$Prune)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "assets_common.ps1")

$files = Read-AssetLock
$found = @{}

$existing = @{}
$listing = & $AwsExe --endpoint-url $AssetEndpoint s3 ls "s3://$AssetBucket/blobs/" 2>$null
foreach ($line in $listing) {
    $name = ($line -split '\s+')[-1]
    if ($name) { $existing[$name] = $true }
}

$uploaded = 0
foreach ($folder in $AssetFolders) {
    $dir = Join-Path $RepoRoot $folder
    if (-not (Test-Path $dir)) { continue }
    $items = Get-ChildItem -LiteralPath $dir -Recurse -File |
        Where-Object { $AssetExtensions -contains $_.Extension.ToLowerInvariant() }
    foreach ($item in $items) {
        $rel = Get-RelativeAssetPath $item.FullName
        $sha = Get-Sha256 $item.FullName
        if ($sha -notmatch '^[0-9a-f]{64}$') { Write-Host "HASH FAILED: $rel" -ForegroundColor Red; exit 1 }
        $found[$rel] = $true
        if (-not $existing.ContainsKey($sha)) {
            Write-Host "upload  $rel  ($sha)"
            $code = Invoke-S3 @("s3", "cp", "--only-show-errors", $item.FullName, "s3://$AssetBucket/blobs/$sha")
            if ($code -ne 0) { Write-Host "UPLOAD FAILED: $rel" -ForegroundColor Red; exit 1 }
            $existing[$sha] = $true
            $uploaded++
        } else {
            Write-Host "ok      $rel"
        }
        $files[$rel] = [ordered]@{ sha256 = $sha; size = [long]$item.Length }
    }
}

if ($Prune) {
    foreach ($key in @($files.Keys)) {
        if (-not $found.ContainsKey($key)) { Write-Host "drop    $key"; $files.Remove($key) }
    }
}

Write-AssetLock $files
Write-Host "Uploaded $uploaded file(s). Lock: $AssetLockName ($($files.Count) entries). Commit it." -ForegroundColor Green
exit 0
