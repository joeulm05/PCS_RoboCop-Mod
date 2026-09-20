@echo off
rem RoboCop Native Build v1.0.1 | Author: Joe "Gambit" Bradford
setlocal DisableDelayedExpansion
pushd "%~dp0"
if not exist "..\..\Payload\RoboCopGameplay" mkdir "..\..\Payload\RoboCopGameplay"
zig cc -target x86_64-windows-gnu -shared -O2 -Wall -Wextra robocop.c -o "..\..\Payload\RoboCopGameplay\robocop_native.dll" -lpsapi -luser32
set "RCP_BUILD_EXIT=%ERRORLEVEL%"
popd
exit /b %RCP_BUILD_EXIT%
