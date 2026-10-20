@echo off
title Disable factory account
net session >nul 2>&1 || ( powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b )
if /i not "%USERNAME%"=="CEAS" (
  echo You are signed in as %USERNAME%. Sign in as CEAS first, then run this again.
  pause
  exit /b 1
)
net user user /active:no
echo.
echo Factory account "user" (AXONE NEMO PLUS) is disabled. CEAS is the only account.
pause
