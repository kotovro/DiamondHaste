@echo off
rem Launches two game windows on one PC: host on the left, client on the right.
rem Usage: tools\run_local_coop.cmd [ping_ms]
rem   ping_ms  optional round-trip latency, e.g. 150: the client then connects through
rem            tools\lag_proxy.py (port 24681), which delays packets by ping_ms/2 each way.
rem Godot path: GODOT_BIN environment variable, otherwise the default below.
set GODOT=%GODOT_BIN%
if "%GODOT%"=="" set GODOT=C:\Repositories\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64.exe
set PING=%~1
set CLIENT_PORT=24680
set /a DELAY=0

cd /d "%~dp0.."
if not "%PING%"=="" set /a DELAY=%PING% / 2
if not "%PING%"=="" set CLIENT_PORT=24681
if not "%PING%"=="" start "Diamond Heist - lag proxy" python -I tools\lag_proxy.py --listen-port 24681 --target 127.0.0.1:24680 --delay %DELAY%

start "Diamond Heist - Host" "%GODOT%" --path . --resolution 960x540 --position 0,60 -- --host
timeout /t 2 /nobreak >nul
start "Diamond Heist - Client" "%GODOT%" --path . --resolution 960x540 --position 960,60 -- --join 127.0.0.1 --port %CLIENT_PORT%
