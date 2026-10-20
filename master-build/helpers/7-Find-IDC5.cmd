@echo off
REM Double-click. Lists every trace of IDC5/TEXA on the tablet. Report saved on this USB.
net session >nul 2>&1 || ( powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b )
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp07-Find-IDC5.ps1"
