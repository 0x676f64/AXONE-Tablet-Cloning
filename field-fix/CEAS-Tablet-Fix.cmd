@echo off
setlocal
title CEAS Tablet Fix

REM ============================================================
REM  CEAS-Tablet-Fix.cmd  -  double-click this on the tablet.
REM  Needs Fix-TabletIdentity.ps1 in the same folder.
REM  1. asks Windows for admin rights (click YES)
REM  2. shows what the tablet currently reports
REM  3. asks for the serial number on the sticker on the back
REM  4. renames the tablet to CEAS-<that serial> and restarts it
REM ============================================================

REM --- get admin rights ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
  echo Asking Windows for permission... click YES on the box that pops up.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "SRC=%~dp0Fix-TabletIdentity.ps1"
if not exist "%SRC%" (
  echo.
  echo  PROBLEM: Fix-TabletIdentity.ps1 is not in the same folder as this file.
  echo  Copy the WHOLE folder onto the tablet, then run this again.
  echo.
  pause
  exit /b 1
)

if not exist C:\Setup mkdir C:\Setup
copy /Y "%SRC%" C:\Setup\Fix-TabletIdentity.ps1 >nul
set "PS=C:\Setup\Fix-TabletIdentity.ps1"

cls
echo ==================================================
echo    CEAS TABLET FIX
echo ==================================================
echo.
echo  STEP 1 of 3 - Checking this tablet (nothing is changed yet)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS%"
echo.
echo --------------------------------------------------
echo  Copy the "Tracking line" above into the tablet sheet.
echo --------------------------------------------------
echo.
echo  STEP 2 of 3 - Ask the customer:
echo  "Please read me the SERIAL NUMBER on the sticker on the BACK of the tablet."
echo.
set "TAG="
set /p "TAG=  Type that serial number here and press Enter (or press Enter alone to stop): "
if "%TAG%"=="" (
  echo.
  echo  Stopped. Nothing was changed on this tablet.
  pause
  exit /b 0
)
echo.
echo  STEP 3 of 3 - The tablet will be renamed to match the sticker and then RESTART.
echo  Tell the customer: "The tablet is going to restart, that is normal."
echo  After it restarts, connect again in TeamViewer with the SAME ID and password.
echo.
echo  Press any key to do it, or close this window to stop.
pause >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS%" -Rename -AssetTag "%TAG%" -Restart
echo.
pause
