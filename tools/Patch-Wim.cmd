@echo off
setlocal
title Patch WIM
REM ============================================================
REM  Patch-Wim.cmd  -  run on your PC. Updates FirstBoot.ps1 INSIDE a
REM  CEAS-Tablet.wim without recapturing the master.
REM  Put the new FirstBoot.ps1 in the SAME folder as this file, then
REM  drag CEAS-Tablet.wim onto this file. 5-15 minutes.
REM  Replaces C:\Setup\FirstBoot.ps1 and C:\Setup\kit\FirstBoot.ps1 in the image.
REM ============================================================
set "HANDOFF=%PUBLIC%\patch-wim-path.txt"
net session >nul 2>&1
if errorlevel 1 (
  if not "%~1"=="" > "%HANDOFF%" echo %~f1
  if not exist "%HANDOFF%" ( echo Drag CEAS-Tablet.wim onto this file. & pause & exit /b 1 )
  powershell -NoProfile -Command "Start-Process -FilePath $env:ComSpec -ArgumentList '/c','\"%~f0\"' -Verb RunAs"
  exit /b
)
if not "%~1"=="" ( set "WIM=%~f1" ) else ( set /p WIM=<"%HANDOFF%" )
set "NEW=%~dp0FirstBoot.ps1"
if not exist "%WIM%" ( echo WIM not found: %WIM% & pause & exit /b 1 )
if not exist "%NEW%" ( echo FirstBoot.ps1 must be in the same folder as Patch-Wim.cmd & pause & exit /b 1 )

set "MNT=%SystemDrive%\WimPatch_%RANDOM%"
echo.
echo Image : %WIM%
echo New   : %NEW%
echo.
Dism /Cleanup-Wim >nul 2>&1
mkdir "%MNT%" >nul 2>&1
echo [1/3] Opening the image for editing...
Dism /Mount-Image /ImageFile:"%WIM%" /Index:1 /MountDir:"%MNT%" /CheckIntegrity
if errorlevel 1 ( echo FAILED to open the image. Nothing was changed. & rmdir "%MNT%" >nul 2>&1 & pause & exit /b 1 )

if not exist "%MNT%\Setup\FirstBoot.ps1" (
  echo This does not look like a CEAS master image: no \Setup\FirstBoot.ps1 inside. Nothing changed.
  Dism /Unmount-Image /MountDir:"%MNT%" /Discard >nul
  rmdir "%MNT%" >nul 2>&1
  pause & exit /b 1
)
echo [2/3] Replacing FirstBoot.ps1...
copy /Y "%NEW%" "%MNT%\Setup\FirstBoot.ps1" >nul
if exist "%MNT%\Setup\kit" copy /Y "%NEW%" "%MNT%\Setup\kit\FirstBoot.ps1" >nul
fc /b "%NEW%" "%MNT%\Setup\FirstBoot.ps1" >nul
if errorlevel 1 (
  echo Copy did not take. Discarding, nothing changed.
  Dism /Unmount-Image /MountDir:"%MNT%" /Discard >nul
  rmdir "%MNT%" >nul 2>&1
  pause & exit /b 1
)
echo [3/3] Saving the image...
Dism /Unmount-Image /MountDir:"%MNT%" /Commit /CheckIntegrity
set "RC=%errorlevel%"
if not "%RC%"=="0" Dism /Unmount-Image /MountDir:"%MNT%" /Discard >nul 2>&1
rmdir "%MNT%" >nul 2>&1
echo.
echo ==================================================
if "%RC%"=="0" (
  echo    PATCHED. Now drag the same WIM onto Verify-Wim.cmd.
) else (
  echo    FAILED to save ^(code %RC%^). The image was left as it was.
)
echo ==================================================
pause
