@echo off
echo RSS Quick - Build and Run
echo ========================

REM Get the current directory
set PROJECT_DIR=%~dp0

REM Change to project directory
cd /d "%PROJECT_DIR%"

echo Building RSS Quick...
dotnet build --configuration Release

if %ERRORLEVEL% neq 0 (
    echo.
    echo *** BUILD FAILED ***
    echo Check the error messages above
    pause
    exit /b 1
)

echo.
echo Build successful! Starting RSS Quick...
echo.

dotnet run --configuration Release

if %ERRORLEVEL% neq 0 (
    echo.
    echo *** RUN FAILED ***
    echo Check the error messages above
    pause
    exit /b 1
)

echo.
echo RSS Quick has exited.
pause
