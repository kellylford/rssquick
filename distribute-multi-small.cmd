@echo off
setlocal EnableDelayedExpansion

echo RSS Quick - Multi-Platform Small Distribution Build
echo ==================================================
echo Creating framework-dependent packages for multiple platforms...
echo This creates separate packages for different processor types.
echo.

REM Get the current directory
set PROJECT_DIR=%~dp0

REM Change to project directory
cd /d "%PROJECT_DIR%"

REM Set base output directory
set BASE_DIST_DIR=dist-multi-small

echo [1/5] Cleaning previous distributions...
if exist "%BASE_DIST_DIR%" (
    rmdir /s /q "%BASE_DIST_DIR%"
)

echo [2/5] Creating platform-specific distributions...
echo.

REM Define platforms to build for
set PLATFORMS=win-x64 win-arm64

for %%P in (%PLATFORMS%) do (
    echo Building for %%P...
    
    set PLATFORM_DIR=%BASE_DIST_DIR%\%%P
    set PUBLISH_DIR=bin\Release\net8.0-windows\%%P\publish-small
    
    REM Clean previous build for this platform
    if exist "!PUBLISH_DIR!" (
        rmdir /s /q "!PUBLISH_DIR!"
    )
    
    REM Build for this platform
    dotnet publish RSSReaderWPF.csproj ^
        --configuration Release ^
        --runtime %%P ^
        --self-contained false ^
        --output "!PUBLISH_DIR!"
    
    if !ERRORLEVEL! neq 0 (
        echo *** BUILD FAILED for %%P ***
        echo Check the error messages above
        pause
        exit /b 1
    )
    
    REM Create distribution folder for this platform
    mkdir "!PLATFORM_DIR!"
    
    REM Copy all the published files
    xcopy "!PUBLISH_DIR!\*" "!PLATFORM_DIR!\" /E /I /Y
    
    REM Copy essential files for users
    copy "RSS.opml" "!PLATFORM_DIR!\"
    copy "README.md" "!PLATFORM_DIR!\"
    
    REM Create platform-specific run script
    echo @echo off > "!PLATFORM_DIR!\Run-RSSQuick.cmd"
    echo echo Starting RSS Quick for %%P... >> "!PLATFORM_DIR!\Run-RSSQuick.cmd"
    echo echo Note: This requires .NET 8.0 Runtime for %%P >> "!PLATFORM_DIR!\Run-RSSQuick.cmd"
    echo start "" "RSSQuick.exe" >> "!PLATFORM_DIR!\Run-RSSQuick.cmd"
    
    REM Create platform-specific instructions
    echo RSS Quick - Small Distribution (%%P) > "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo ===================================== >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo. >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo This version is built for %%P processors. >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo. >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo SYSTEM REQUIREMENTS: >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    if "%%P"=="win-x64" (
        echo - Windows 10/11 on Intel/AMD processors ^(x64^) >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    ) else (
        echo - Windows 10/11 on ARM64 processors ^(Surface, newer laptops^) >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    )
    echo - .NET 8.0 Runtime for %%P >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo - Download from: https://dotnet.microsoft.com/download/dotnet/8.0 >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo - Choose "Runtime" not "SDK" >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo - Select the %%P version >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo. >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo HOW TO RUN: >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo 1. Install .NET 8.0 Runtime for %%P if not already installed >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo 2. Double-click "RSSQuick.exe" >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo 3. Or use "Run-RSSQuick.cmd" >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo. >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    echo For support: https://github.com/kellylford/rssquick >> "!PLATFORM_DIR!\DISTRIBUTION-README.txt"
    
    echo ✓ Completed %%P distribution
    echo.
)

echo [3/5] Creating universal download helper...

REM Create a universal installer script
echo @echo off > "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo RSS Quick - .NET Runtime Installer Helper >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo ========================================== >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo. >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo This script will help you install the correct .NET 8.0 Runtime. >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo. >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo Detecting your processor type... >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo if "%%PROCESSOR_ARCHITECTURE%%"=="ARM64" goto :ARM64 >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo if "%%PROCESSOR_ARCHITEW6432%%"=="ARM64" goto :ARM64 >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo You have an x64 ^(Intel/AMD^) processor >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo Opening .NET 8.0 Runtime download page for x64... >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo start "" "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/runtime-8.0.19-windows-x64-installer" >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo goto :END >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo :ARM64 >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo You have an ARM64 processor >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo echo Opening .NET 8.0 Runtime download page for ARM64... >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo start "" "https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/runtime-8.0.19-windows-arm64-installer" >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo :END >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"
echo pause >> "%BASE_DIST_DIR%\Install-DotNet-Runtime.cmd"

echo [4/5] Creating distribution summary...

REM Create main README for the multi-platform distribution
echo RSS Quick - Multi-Platform Small Distribution > "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo ============================================== >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo. >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo This package contains RSS Quick for multiple processor types. >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo Choose the folder that matches your computer: >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo. >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo FOLDERS: >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo. >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo win-x64/     - For Intel/AMD processors ^(most common^) >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo              - Most desktop PCs, older laptops >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo. >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo win-arm64/   - For ARM64 processors >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo              - Surface devices, newer laptops >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo. >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo HOW TO CHOOSE: >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo 1. Try win-x64/ first ^(works for most people^) >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo 2. If it asks for .NET download, try win-arm64/ >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo 3. Or run Install-DotNet-Runtime.cmd to get the right .NET version >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo. >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo INSTALLATION: >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo 1. Choose your platform folder >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo 2. Read the DISTRIBUTION-README.txt in that folder >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo 3. Install .NET Runtime if prompted >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"
echo 4. Run RSSQuick.exe >> "%BASE_DIST_DIR%\README-CHOOSE-YOUR-PLATFORM.txt"

echo [5/5] Multi-platform distribution complete!
echo.
echo *** SUCCESS! ***
echo.
echo Multi-platform distribution created in: %PROJECT_DIR%%BASE_DIST_DIR%\
echo.
echo Package structure:
dir /b "%BASE_DIST_DIR%"
echo.

REM Show size information
echo Platform sizes:
for %%P in (%PLATFORMS%) do (
    for /f "tokens=3" %%s in ('dir "%BASE_DIST_DIR%\%%P" /s /-c ^| find "File(s)"') do (
        set /a size_mb=%%s/1024/1024
        echo   %%P: !size_mb! MB
    )
)

echo.
echo DISTRIBUTION READY:
echo - win-x64/     - For Intel/AMD computers
echo - win-arm64/   - For ARM64 computers  
echo - Install-DotNet-Runtime.cmd - Helper to install correct .NET
echo - README-CHOOSE-YOUR-PLATFORM.txt - User instructions
echo.

REM Ask if user wants to open the distribution folder
set /p OPENFOLDER="Open multi-platform distribution folder? (y/n): "
if /i "!OPENFOLDER!"=="y" (
    start "" explorer "%PROJECT_DIR%%BASE_DIST_DIR%"
)

echo.
echo Multi-platform distribution build complete!
pause
