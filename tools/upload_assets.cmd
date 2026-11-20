@echo off
rem Models and art sources live in Yandex Object Storage; see assets_common.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload_assets.ps1" %*
exit /b %ERRORLEVEL%
