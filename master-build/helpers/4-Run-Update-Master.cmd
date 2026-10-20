@echo off
title Update Master
net session >nul 2>&1 || ( powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b )
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Setup\kit\Update-Master.ps1"
echo.
echo If it said RESTART NOW: restart the tablet, sign in as CEAS, double-click this again.
echo If it said CLEAN: next is 5-Disable-Factory-User.cmd, then 6-Run-Prep-Master.cmd
pause
