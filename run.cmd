@echo off
REM Build and run RSS Quick. The everyday development loop.
setlocal
cd /d "%~dp0"

echo RSS Quick - build and run
echo =========================
echo.

dotnet run --project src\RSSQuick --configuration Release
if errorlevel 1 (
    echo.
    echo *** FAILED *** - see the messages above.
    pause
    exit /b 1
)

echo.
echo RSS Quick has exited.
pause
