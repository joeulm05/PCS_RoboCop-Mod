@echo off
rem RoboCop Native Helper Build | Author: Joe "Gambit" Bradford
setlocal DisableDelayedExpansion
pushd "%~dp0"
where zig >nul 2>nul
if errorlevel 1 (
  echo Install Zig 0.16.0 and add zig.exe to PATH first.
  popd
  exit /b 1
)
zig cc -target x86_64-windows-gnu -shared -O2 robocop.c -o "..\..\Payload\RoboCopGameplay\robocop_native.dll"
set "RCP_BUILD_EXIT=%ERRORLEVEL%"
popd
exit /b %RCP_BUILD_EXIT%
