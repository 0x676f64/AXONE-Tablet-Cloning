@echo off
title Create CEAS user
net session >nul 2>&1 || ( powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b )
net user CEAS >nul 2>&1 && ( echo CEAS user already exists. ) || ( net user CEAS "" /add )
net localgroup Administrators CEAS /add >nul 2>&1
echo.
net user CEAS | findstr /i "User.name Local.Group Account.active"
echo.
echo Done. Now: Start ^> account picture ^> Sign out, then sign in as CEAS.
pause
