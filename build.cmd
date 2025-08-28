@echo off
setlocal EnableDelayedExpansion

echo RSS Quick - Advanced Build and Run
echo ===================================

REM Get the current directory
set PROJECT_DIR=%~dp0

REM Change to project directory
cd /d "%PROJECT_DIR%"

REM Check for command line arguments
if "%1"=="publish" goto :publish
if "%1"=="exe" goto :publish
if "%1"=="release" goto :release
if "%1"=="debug" goto :debug
if "%1"=="clean" goto :clean
if "%1"=="help" goto :help
if "%1"=="-h" goto :help
if "%1"=="/?" goto :help

REM Default: Debug build and run
:debug
echo Building RSS Quick (Debug)...
dotnet build --configuration Debug
if %ERRORLEVEL% neq 0 goto :buildfailed
echo.
echo Starting RSS Quick (Debug)...
dotnet run --configuration Debug
goto :end

:release
echo Building RSS Quick (Release)...
dotnet build --configuration Release
if %ERRORLEVEL% neq 0 goto :buildfailed
echo.
echo Starting RSS Quick (Release)...
dotnet run --configuration Release
goto :end

:publish
echo Creating standalone executable...
echo This will take a moment...
echo.

REM Clean previous publish
if exist "bin\Release\net8.0-windows\win-x64\publish" (
    echo Cleaning previous publish...
    rmdir /s /q "bin\Release\net8.0-windows\win-x64\publish"
)

REM Publish self-contained executable
dotnet publish --configuration Release --runtime win-x64 --self-contained true --output "bin\Release\net8.0-windows\win-x64\publish"

if %ERRORLEVEL% neq 0 (
    echo.
    echo *** PUBLISH FAILED ***
    echo Check the error messages above
    pause
    exit /b 1
)

echo.
echo *** SUCCESS! ***
echo Standalone executable created:
echo %PROJECT_DIR%bin\Release\net8.0-windows\win-x64\publish\RSSQuick.exe
echo.
echo You can copy this exe file anywhere and run it without installing .NET!
echo.

REM Ask if user wants to run the published version
set /p RUNPUB="Run the published executable now? (y/n): "
if /i "!RUNPUB!"=="y" (
    echo.
    echo Starting published executable...
    start "" "bin\Release\net8.0-windows\win-x64\publish\RSSQuick.exe"
)
goto :end

:clean
echo Cleaning build artifacts...
if exist "bin" rmdir /s /q "bin"
if exist "obj" rmdir /s /q "obj"
echo Clean complete.
goto :end

:buildfailed
echo.
echo *** BUILD FAILED ***
echo Check the error messages above
pause
exit /b 1

:help
echo.
echo Usage: run.cmd [option]
echo.
echo Options:
echo   (no option)  - Build and run in Debug mode
echo   debug       - Build and run in Debug mode
echo   release     - Build and run in Release mode  
echo   publish     - Create standalone executable (no .NET required)
echo   exe         - Same as publish
echo   clean       - Clean build artifacts
echo   help        - Show this help
echo.
echo Examples:
echo   run.cmd              (debug build and run)
echo   run.cmd release      (release build and run)
echo   run.cmd publish      (create standalone exe)
echo   run.cmd clean        (clean build files)
echo.
goto :end

:end
if not "%1"=="publish" pause
