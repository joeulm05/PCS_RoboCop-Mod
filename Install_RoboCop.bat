@echo off
rem RoboCop Installer v1.0.0-RC4 | Author: Joe "Gambit" Bradford
setlocal DisableDelayedExpansion
title RoboCop - Police Chief Simulator Installer
if not exist "%~dp0Installer\Install.ps1" (
  echo Extract the entire ZIP before running Install_RoboCop.bat.
  pause
  exit /b 1
)
set "RCP_SELECTED_PATH=%~1"
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Installer\Install.ps1"
set "RCP_EXIT=%ERRORLEVEL%"
echo.
if not "%RCP_EXIT%"=="0" (
  pause
) else (
  timeout /t 8 /nobreak >nul
)
exit /b %RCP_EXIT%
