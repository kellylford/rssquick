@echo off
setlocal EnableDelayedExpansion

echo RSS Quick - Small Distribution Build
echo ====================================
echo Creating framework-dependent package (requires .NET 8.0 Runtime)...
echo This will be much smaller but users need .NET installed.
echo.

REM Get the current directory
set PROJECT_DIR=%~dp0

REM Change to project directory
cd /d "%PROJECT_DIR%"

REM Set output directory
set DIST_DIR=dist-small
set PUBLISH_DIR=bin\Release\net8.0-windows\win-x64\publish-small

echo [1/4] Cleaning previous distribution...
if exist "%DIST_DIR%" (
    rmdir /s /q "%DIST_DIR%"
)

if exist "%PUBLISH_DIR%" (
    rmdir /s /q "%PUBLISH_DIR%"
)

echo [2/4] Building framework-dependent package...

REM Detect system architecture
set ARCH=win-x64
if "%PROCESSOR_ARCHITECTURE%"=="ARM64" set ARCH=win-arm64
if "%PROCESSOR_ARCHITEW6432%"=="ARM64" set ARCH=win-arm64

echo Building for architecture: %ARCH%

dotnet publish RSSReaderWPF.csproj ^
    --configuration Release ^
    --runtime %ARCH% ^
    --self-contained false ^
    --output "%PUBLISH_DIR%"

if %ERRORLEVEL% neq 0 (
    echo.
    echo *** BUILD FAILED ***
    echo Check the error messages above
    pause
    exit /b 1
)

echo [3/4] Creating distribution package...
mkdir "%DIST_DIR%"

REM Copy all the published files
xcopy "%PUBLISH_DIR%\*" "%DIST_DIR%\" /E /I /Y

REM Copy essential files for users
copy "RSS.opml" "%DIST_DIR%\"
copy "README.md" "%DIST_DIR%\"

REM Create a simple run script for users
echo @echo off > "%DIST_DIR%\Run-RSSQuick.cmd"
echo echo Starting RSS Quick... >> "%DIST_DIR%\Run-RSSQuick.cmd"
echo echo Note: This requires .NET 8.0 Runtime to be installed >> "%DIST_DIR%\Run-RSSQuick.cmd"
echo start "" "RSSQuick.exe" >> "%DIST_DIR%\Run-RSSQuick.cmd"

REM Create user instructions
echo RSS Quick - Framework-Dependent Distribution > "%DIST_DIR%\DISTRIBUTION-README.txt"
echo ============================================ >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo This version of RSS Quick is SMALLER but requires .NET to be installed. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo SYSTEM REQUIREMENTS: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Windows 10 or Windows 11 >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - .NET 8.0 Runtime (download from: https://dotnet.microsoft.com/download/dotnet/8.0) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Choose "Runtime" not "SDK" for end users >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Internet connection for RSS feeds >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo HOW TO RUN: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo 1. Install .NET 8.0 Runtime if not already installed >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo 2. Double-click "RSSQuick.exe" OR >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo 3. Double-click "Run-RSSQuick.cmd" >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo ADVANTAGES: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Much smaller download (~5-10 MB vs ~160 MB) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Faster updates (only app files, not entire .NET runtime) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Uses system .NET installation >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo DISADVANTAGES: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Users must install .NET 8.0 Runtime separately >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Won't work on systems without .NET >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo For support and source code: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo https://github.com/kellylford/rssquick >> "%DIST_DIR%\DISTRIBUTION-README.txt"

echo [4/4] Distribution package complete!
echo.
echo *** SUCCESS! ***
echo.
echo Small distribution created in: %PROJECT_DIR%%DIST_DIR%\
echo.
echo Files included:
dir /b "%DIST_DIR%"
echo.
echo File sizes:
for %%f in ("%DIST_DIR%\*") do (
    for %%s in ("%%f") do (
        set size=%%~zs
        set /a size_mb=!size!/1024/1024
        if !size_mb! equ 0 (
            set /a size_kb=!size!/1024
            echo   %%~nxf: !size_kb! KB
        ) else (
            echo   %%~nxf: !size_mb! MB
        )
    )
)
echo.
echo SMALL DISTRIBUTION READY:
echo - Much smaller than self-contained version
echo - Users need to install .NET 8.0 Runtime first
echo - Get .NET Runtime: https://dotnet.microsoft.com/download/dotnet/8.0
echo.

REM Ask if user wants to test the distribution
set /p TESTDIST="Test the small distribution executable now? (y/n): "
if /i "!TESTDIST!"=="y" (
    echo.
    echo Testing framework-dependent executable...
    start "" "%DIST_DIR%\RSSQuick.exe"
)

REM Ask if user wants to open the distribution folder
set /p OPENFOLDER="Open distribution folder in Explorer? (y/n): "
if /i "!OPENFOLDER!"=="y" (
    start "" explorer "%PROJECT_DIR%%DIST_DIR%"
)

echo.
echo Small distribution build complete!
pause
