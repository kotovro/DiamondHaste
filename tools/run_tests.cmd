@echo off
rem Validation: import + tests. Optional argument: filter by test file path or test name.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_tests.ps1" %*
exit /b %ERRORLEVEL%
