@echo off
rem Launches two game windows on one PC: host on the left, client on the right.
rem Adjust the Godot path for your machine.
set GODOT=C:\Repositories\Godot_v4.4.1-stable_mono_win64\Godot_v4.4.1-stable_mono_win64.exe

cd /d "%~dp0.."
start "Diamond Heist - Host" "%GODOT%" --path . --resolution 960x540 --position 0,60 -- --host
timeout /t 2 /nobreak >nul
start "Diamond Heist - Client" "%GODOT%" --path . --resolution 960x540 --position 960,60 -- --join 127.0.0.1
