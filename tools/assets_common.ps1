# Shared settings for upload_assets.ps1 / fetch_assets.ps1.
# Models and art sources are not stored in git: they live in Yandex Object Storage (S3 API).
# Git stores only assets.lock.json: path -> sha256 of every such file.
# Objects in the bucket are named by content hash (blobs/<sha256>), so an old commit's
# lock file still points at the files it was made with.

$AssetBucket = "thiefs-diamonds"
$AssetEndpoint = "https://storage.yandexcloud.net"
$AssetRegion = "ru-central1"
$AssetFolders = @("assets", "art")
$AssetExtensions = @(".glb", ".gltf", ".bin", ".fbx", ".obj", ".blend")
$AssetLockName = "assets.lock.json"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LockPath = Join-Path $RepoRoot $AssetLockName

# Credentials: AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY from the environment (CI),
# otherwise the local AWS CLI profile "yc-storage" (see `aws configure --profile yc-storage`).
if (-not $env:AWS_ACCESS_KEY_ID -and -not $env:AWS_PROFILE) { $env:AWS_PROFILE = "yc-storage" }
if (-not $env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION = $AssetRegion }

$AwsExe = (Get-Command aws -ErrorAction SilentlyContinue).Source
if (-not $AwsExe -and (Test-Path "C:\Program Files\Amazon\AWSCLIV2\aws.exe")) {
    $AwsExe = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
}
if (-not $AwsExe) {
    Write-Host "AWS CLI not found. Install it: winget install Amazon.AWSCLI" -ForegroundColor Red
    exit 2
}

function Invoke-S3 {
    param([string[]]$Arguments)
    & $AwsExe --endpoint-url $AssetEndpoint @Arguments | Out-Host
    return $LASTEXITCODE
}

function Get-RelativeAssetPath([string]$FullPath) {
    $rel = $FullPath.Substring($RepoRoot.Length).TrimStart('\', '/')
    return $rel -replace '\\', '/'
}

# .NET directly: Get-FileHash is missing in Windows PowerShell started from PowerShell 7.
function Get-Sha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try {
        $bytes = $sha.ComputeHash($stream)
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
    return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Read-AssetLock {
    $files = [ordered]@{}
    if (Test-Path $LockPath) {
        $json = Get-Content -Raw -Encoding UTF8 $LockPath | ConvertFrom-Json
        foreach ($p in $json.files.PSObject.Properties) {
            $files[$p.Name] = [ordered]@{ sha256 = $p.Value.sha256; size = [long]$p.Value.size }
        }
    }
    return $files
}

function Write-AssetLock($Files) {
    # Written by hand: ConvertTo-Json formats differently in PowerShell 5.1 and 7,
    # and the lock file must not change on its own between machines.
    $entries = @()
    foreach ($key in ($Files.Keys | Sort-Object)) {
        $e = $Files[$key]
        if ($e.sha256 -notmatch '^[0-9a-f]{64}$') { throw "bad sha256 for $key" }
        $entries += "    `"$key`": { `"sha256`": `"$($e.sha256)`", `"size`": $($e.size) }"
    }
    $lines = @(
        "{",
        "  `"version`": 1,",
        "  `"bucket`": `"$AssetBucket`",",
        "  `"endpoint`": `"$AssetEndpoint`",",
        "  `"files`": {",
        ($entries -join ",`n"),
        "  }",
        "}"
    )
    [IO.File]::WriteAllText($LockPath, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
}
