@echo off
title Battle-Star.SOL Web Development Launcher
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\rebuild-web.ps1"
if errorlevel 1 (
  echo.
  echo The Godot Web package could not be rebuilt.
  echo Close any old Godot windows and try again.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\launch-web.ps1" %*
if errorlevel 1 (
  echo.
  echo The Web development launcher stopped with an error.
  pause
)
