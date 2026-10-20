@echo off
title Check Tablet
REM Double-click after entering the IDC6 key and setting the TeamViewer password.
REM Shows GREEN "READY TO SHIP" or tells you what is missing.
net session >nul 2>&1 || ( powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b )
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Setup\FirstBoot.ps1" -VerifyOnly
