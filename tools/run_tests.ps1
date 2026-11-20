# Validation: project import + all GdUnit4 tests + script error scan in the log.
# Usage: tools\run_tests.cmd [res://path/to/test_file.gd or folder]   (default: res://tests)
# Godot path can be overridden with the GODOT_BIN environment variable (GODOT also works).
param([string]$Target = "res://tests")

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$godot = $env:GODOT_BIN
if (-not $godot) { $godot = $env:GODOT }
if (-not $godot) {
    $godot = "C:\Repositories\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64_console.exe"
}
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found: $godot (set the GODOT_BIN environment variable)" -ForegroundColor Red
    exit 2
}

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    Write-Host "== Import" -ForegroundColor Cyan
    $importLog = & $godot --headless --path . --import 2>&1 | ForEach-Object { "$_" }
    $importErrors = $importLog | Where-Object { $_ -match "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script" }
    if ($importErrors) {
        $importErrors | Write-Host -ForegroundColor Red
        Write-Host "VALIDATION FAILED: script errors during import" -ForegroundColor Red
        exit 1
    }

    Write-Host "== Tests ($Target)" -ForegroundColor Cyan
    # -c: do not stop at the first failure, report all of them.
    $runArgs = @("--headless", "--path", ".", "-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
                 "--ignoreHeadlessMode", "-c", "-a", $Target)
    $log = & $godot @runArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $log | Write-Host

    # A runtime script error may abort a test function without failing it, so the log is scanned too.
    $runtimeErrors = $log | Where-Object { $_ -match "SCRIPT ERROR|^\s*ERROR:" }
    if ($runtimeErrors) {
        Write-Host ""
        Write-Host "Errors in log:" -ForegroundColor Red
        $runtimeErrors | Write-Host -ForegroundColor Red
    }
    # GdUnit4 exit codes: 0 ok, 100 failures, 101 orphan nodes (leaks), 103/104 setup problems.
    if ($code -ne 0 -or $runtimeErrors) {
        Write-Host "VALIDATION FAILED (exit code $code)" -ForegroundColor Red
        exit 1
    }
    Write-Host "VALIDATION OK" -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}
