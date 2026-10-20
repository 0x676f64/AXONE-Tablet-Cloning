@echo off
setlocal
title CEAS - Build WinPE ISO (for Rufus)

REM ============================================================
REM  build-winpe-iso.cmd
REM  Makes a small bootable WinPE .ISO with the auto-imaging
REM  scripts baked in. You then burn that ISO to a USB with
REM  Rufus (2 clicks). RIGHT-CLICK > Run as administrator.
REM
REM  Before running:
REM   - Windows ADK + Windows PE add-on installed.
REM   - deploy.cmd and startnet.cmd in THIS folder.
REM  This does NOT touch any USB - it only creates an .iso file.
REM ============================================================

net session >nul 2>&1
if %errorlevel% NEQ 0 ( echo Please RIGHT-CLICK this file and Run as administrator. & pause & exit /b 1 )

set "HERE=%~dp0"
if not exist "%HERE%deploy.cmd"   ( echo Missing deploy.cmd in this folder.   & pause & exit /b 1 )
if not exist "%HERE%startnet.cmd" ( echo Missing startnet.cmd in this folder. & pause & exit /b 1 )

set "DANDI=%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
if not exist "%DANDI%" set "DANDI=%ProgramFiles%\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
if not exist "%DANDI%" ( echo Windows ADK not found. Install the ADK + WinPE add-on. & pause & exit /b 1 )
call "%DANDI%"

set "WORK=%TEMP%\CEAS_WinPE"
if exist "%WORK%" rmdir /s /q "%WORK%"

echo [1/4] Creating WinPE...
call copype amd64 "%WORK%"
if not exist "%WORK%\media\sources\boot.wim" ( echo copype failed - is the WinPE add-on installed? & pause & exit /b 1 )

echo [2/4] Adding the auto-run scripts...
set "MNT=%WORK%\mount"
dism /Mount-Image /ImageFile:"%WORK%\media\sources\boot.wim" /Index:1 /MountDir:"%MNT%"
copy /Y "%HERE%deploy.cmd"   "%MNT%\Windows\System32\deploy.cmd"   >nul
copy /Y "%HERE%startnet.cmd" "%MNT%\Windows\System32\startnet.cmd" >nul
dism /Unmount-Image /MountDir:"%MNT%" /Commit

echo [3/4] Building the ISO...
set "OUT=%HERE%CEAS-WinPE.iso"
call MakeWinPEMedia /ISO "%WORK%" "%OUT%"

echo [4/4] Cleaning up...
rmdir /s /q "%WORK%"

echo.
echo ============================================================
if exist "%OUT%" (
  echo   DONE. Your ISO is here:
  echo   %OUT%
  echo   Burn it to a USB with Rufus, then use that USB + the
  echo   storage USB that holds CEAS-Tablet.wim.
) else (
  echo   Something went wrong - the ISO was not created.
  echo   Tell Claude which step number this stopped on.
)
echo ============================================================
pause
