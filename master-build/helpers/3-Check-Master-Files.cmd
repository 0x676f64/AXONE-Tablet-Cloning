@echo off
REM Double-click after copying files into C:\Setup. Writes master-files-report.txt onto this USB.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp03-Check-Master-Files.ps1"
