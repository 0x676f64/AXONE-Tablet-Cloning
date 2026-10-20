@echo off
setlocal
title Verify WIM
REM ============================================================
REM  Verify-Wim.cmd  -  run on your PC.
REM  Drag a CEAS-Tablet.wim onto this file (or double-click it and
REM  it uses the last file you dragged).
REM  1. Size and SHA256 fingerprint (to compare copies)
REM  2. Reads the ENTIRE image and checks it against the integrity
REM     table written at capture. Any damaged byte = FAIL.
REM  Nothing is changed. 10-20 minutes for a 50 GB image.
REM ============================================================
set "HANDOFF=%PUBLIC%\verify-wim-path.txt"

REM Not elevated yet: save the dropped path to a file, relaunch as admin.
net session >nul 2>&1
if errorlevel 1 (
  if not "%~1"=="" > "%HANDOFF%" echo %~f1
  if not exist "%HANDOFF%" (
    echo Drag CEAS-Tablet.wim onto this file.
    pause
    exit /b 1
  )
  powershell -NoProfile -Command "Start-Process -FilePath $env:ComSpec -ArgumentList '/c','\"%~f0\"' -Verb RunAs"
  if errorlevel 1 ( echo Could not get administrator rights. & pause )
  exit /b
)

REM Elevated: read the path back.
if not "%~1"=="" ( set "WIM=%~f1" ) else ( set /p WIM=<"%HANDOFF%" )
if not defined WIM ( echo No WIM path found. Drag the file onto this script again. & pause & exit /b 1 )
if not exist "%WIM%" ( echo File not found: %WIM% & pause & exit /b 1 )

set "MNT=%SystemDrive%\WimCheck_%RANDOM%"
echo.
echo File: %WIM%
for %%F in ("%WIM%") do echo Size: %%~zF bytes
echo.
echo [1/2] Fingerprint (SHA256). Copies must match exactly.
certutil -hashfile "%WIM%" SHA256 | findstr /v /i "certutil hash"
echo.
echo [2/2] Reading the whole image and checking integrity...
mkdir "%MNT%" >nul 2>&1
Dism /Mount-Image /ImageFile:"%WIM%" /Index:1 /MountDir:"%MNT%" /ReadOnly /CheckIntegrity
set "RC=%errorlevel%"
Dism /Unmount-Image /MountDir:"%MNT%" /Discard >nul 2>&1
rmdir "%MNT%" >nul 2>&1
echo.
echo ==================================================
if "%RC%"=="0" (
  echo    PASS - this copy of the image is intact.
) else (
  echo    FAIL - this copy is damaged ^(code %RC%^). Do not use it.
)
echo ==================================================
pause
