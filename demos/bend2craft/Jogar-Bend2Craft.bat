@echo off
setlocal EnableExtensions
title Bend2Craft

rem Build the current bundle before serving it. The build toolchain runs in WSL.
cd /d "%~dp0"
if not defined PORT set "PORT=8080"
set "OPEN_BROWSER=1"
set "LAN_FLAG="
:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--no-open" (
  set "OPEN_BROWSER=0"
) else if /I "%~1"=="--lan" (
  set "LAN_FLAG=--lan"
) else (
  goto usage
)
shift
goto parse_args
:args_done

where node >nul 2>nul
if errorlevel 1 goto no_node
where wsl.exe >nul 2>nul
if errorlevel 1 goto no_wsl

set "WSL_ROOT="
for /f "delims=" %%I in ('wsl.exe wslpath -a -u "%CD%" 2^>nul') do if not defined WSL_ROOT set "WSL_ROOT=%%I"
if not defined WSL_ROOT goto bad_wsl_path

wsl.exe bash -lc "command -v npm >/dev/null 2>&1"
if errorlevel 1 goto no_npm

echo Building the current Bend2Craft bundle in WSL...
wsl.exe bash -lc "cd '%WSL_ROOT%' && npm run build"
if errorlevel 1 goto build_failed

if not exist "dist\index.html" goto missing_bundle
if not exist "dist\chunk-worker.js" goto missing_bundle
if not exist "dist\mesh-worker.js" goto missing_bundle
if not exist "dist\lod-worker.js" goto missing_bundle

echo Starting Bend2Craft at http://localhost:%PORT%/?play=1^&seed=1337 ...
echo Keep this window open while you play. Press Ctrl+C to stop.
if "%OPEN_BROWSER%"=="1" (
  node scripts\play-server.mjs --open %LAN_FLAG%
) else (
  node scripts\play-server.mjs %LAN_FLAG%
)
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" goto server_failed
goto finished

:usage
echo Usage: %~nx0 [--no-open] [--lan]
echo   Default: build the current bundle and open the browser after listening.
echo   --no-open: build and serve without opening a browser window.
echo   --lan: let players on your network join the multiplayer world.
pause
exit /b 2

:no_node
echo Node.js was not found. Install Node.js to run the local server.
pause
exit /b 1

:no_wsl
echo WSL was not found. Install/enable WSL because the Bend build runs there.
pause
exit /b 1

:bad_wsl_path
echo Could not translate the repository path for WSL.
pause
exit /b 1

:no_npm
echo npm was not found in WSL. Install Node.js in WSL before launching.
pause
exit /b 1

:build_failed
echo Build failed. The old bundle was not served.
pause
exit /b 1

:missing_bundle
echo The build completed without the required bundle files. Nothing was served.
pause
exit /b 1

:server_failed
echo The Bend2Craft server stopped with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%

:finished
echo Bend2Craft server stopped.
pause
exit /b 0
