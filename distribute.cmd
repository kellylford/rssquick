@echo off
setlocal EnableDelayedExpansion

echo RSS Quick - Distribution Build
echo ================================
echo Creating standalone executable for distribution...
echo This will take a few moments...
echo.

REM Get the current directory
set PROJECT_DIR=%~dp0

REM Change to project directory
cd /d "%PROJECT_DIR%"

REM Set output directory
set DIST_DIR=dist
set PUBLISH_DIR=bin\Release\net8.0-windows\win-x64\publish

echo [1/4] Cleaning previous distribution...
if exist "%DIST_DIR%" (
    rmdir /s /q "%DIST_DIR%"
)

if exist "%PUBLISH_DIR%" (
    rmdir /s /q "%PUBLISH_DIR%"
)

echo [2/4] Building standalone executable...
dotnet publish RSSReaderWPF.csproj ^
    --configuration Release ^
    --runtime win-x64 ^
    --self-contained true ^
    --output "%PUBLISH_DIR%"

if %ERRORLEVEL% neq 0 (
    echo.
    echo *** DISTRIBUTION BUILD FAILED ***
    echo Check the error messages above
    pause
    exit /b 1
)

echo [3/4] Creating distribution package...
mkdir "%DIST_DIR%"

REM Copy all the published files (not single-file, so we need everything)
xcopy "%PUBLISH_DIR%\*" "%DIST_DIR%\" /E /I /Y

REM Copy essential files for users (these will overwrite if they exist)
copy "RSS.opml" "%DIST_DIR%\"
copy "README.md" "%DIST_DIR%\"

REM Create a simple run script for users
echo @echo off > "%DIST_DIR%\Run-RSSQuick.cmd"
echo echo Starting RSS Quick... >> "%DIST_DIR%\Run-RSSQuick.cmd"
echo start "" "RSSQuick.exe" >> "%DIST_DIR%\Run-RSSQuick.cmd"

REM Create user instructions
echo RSS Quick - Standalone Distribution > "%DIST_DIR%\DISTRIBUTION-README.txt"
echo ================================== >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo This is a standalone version of RSS Quick that does NOT require >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo .NET to be installed on the user's machine. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo HOW TO RUN: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo 1. Double-click "RSSQuick.exe" OR >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo 2. Double-click "Run-RSSQuick.cmd" >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo IMPORTANT: Keep all files together! The application needs >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo all the accompanying DLL files to run properly. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo INCLUDED FILES: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - RSSQuick.exe           (Main application executable) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Various .dll files     (Required runtime libraries) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Run-RSSQuick.cmd       (Convenient launcher script) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - RSS.opml               (Sample RSS feeds to import) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - README.md              (Full documentation) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - DISTRIBUTION-README.txt (This file) >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo SYSTEM REQUIREMENTS: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Windows 10 or Windows 11 >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - No .NET installation required >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo - Internet connection for RSS feeds >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo. >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo For support and source code: >> "%DIST_DIR%\DISTRIBUTION-README.txt"
echo https://github.com/kellylford/rssquick >> "%DIST_DIR%\DISTRIBUTION-README.txt"

echo [4/4] Distribution package complete!
echo.
echo *** SUCCESS! ***
echo.
echo Distribution created in: %PROJECT_DIR%%DIST_DIR%\
echo.
echo Files included:
dir /b "%DIST_DIR%"
echo.
echo File sizes:
for %%f in ("%DIST_DIR%\*") do (
    for %%s in ("%%f") do (
        set size=%%~zs
        set /a size_mb=!size!/1024/1024
        echo   %%~nxf: !size_mb! MB
    )
)
echo.
echo DISTRIBUTION READY FOR END USERS:
echo - Copy the entire "%DIST_DIR%" folder to distribute
echo - Users can run RSSQuick.exe directly (no .NET required)
echo - Or they can use Run-RSSQuick.cmd for convenience
echo.

REM Ask if user wants to test the distribution
set /p TESTDIST="Test the distribution executable now? (y/n): "
if /i "!TESTDIST!"=="y" (
    echo.
    echo Testing distribution executable...
    start "" "%DIST_DIR%\RSSQuick.exe"
)

REM Ask if user wants to open the distribution folder
set /p OPENFOLDER="Open distribution folder in Explorer? (y/n): "
if /i "!OPENFOLDER!"=="y" (
    start "" explorer "%PROJECT_DIR%%DIST_DIR%"
)

echo.
echo Distribution build complete!
pause
