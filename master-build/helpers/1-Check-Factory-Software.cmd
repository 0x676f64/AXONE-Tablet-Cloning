@echo off
REM Double-click. Writes factory-check-report.txt onto this USB and opens it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp01-Check-Factory-Software.ps1"
