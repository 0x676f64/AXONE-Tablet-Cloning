@echo off
title Prep Master
net session >nul 2>&1 || ( powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b )
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Setup\kit\Prep-Master.ps1"
echo.
echo If it said MASTER READY the tablet shuts down by itself.
echo If there are red lines, fix them and double-click this again.
pause
