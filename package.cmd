@echo off
REM Build the release artefacts: a portable ZIP and an installer, for x64 and ARM64, plus the
REM update feed installed copies read. Output lands in artifacts\. Pass x64 or arm64 to build
REM just one.
REM
REM   package.cmd store             the Microsoft Store bundle, both architectures
REM   package.cmd store -Install    ...and register it on this machine to try it
setlocal
cd /d "%~dp0"

set ARCH=%1
if "%ARCH%"=="" set ARCH=both

if /i "%ARCH%"=="store" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "build\package-store.ps1" %2 %3 %4
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "build\publish.ps1" -Architecture %ARCH%
)

if errorlevel 1 (
    echo.
    echo *** PACKAGING FAILED *** - see the messages above.
    pause
    exit /b 1
)

echo.
set /p OPEN="Open the artifacts folder? (y/n): "
if /i "%OPEN%"=="y" start "" explorer "artifacts"
pause
