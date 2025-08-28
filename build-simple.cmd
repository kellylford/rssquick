@echo off
echo RSS Quick - Simple Build
echo ========================
echo Building the standard way (what most .NET developers do)...
echo.

echo [1/2] Building for x64 (Intel/AMD)...
dotnet publish --configuration Release --runtime win-x64 --self-contained false --output "dist-simple"

if %ERRORLEVEL% neq 0 (
    echo.
    echo *** BUILD FAILED ***
    echo Check the error messages above
    pause
    exit /b 1
)

echo [2/2] Adding documentation...

REM Copy essential files
copy "RSS.opml" "dist-simple\"
copy "README.md" "dist-simple\"

REM Create simple user instructions
echo RSS Quick - Simple Distribution > "dist-simple\INSTALLATION.txt"
echo ================================ >> "dist-simple\INSTALLATION.txt"
echo. >> "dist-simple\INSTALLATION.txt"
echo REQUIREMENTS: >> "dist-simple\INSTALLATION.txt"
echo - Windows 10 or Windows 11 >> "dist-simple\INSTALLATION.txt"
echo - .NET 8.0 Runtime (download link below) >> "dist-simple\INSTALLATION.txt"
echo. >> "dist-simple\INSTALLATION.txt"
echo INSTALLATION: >> "dist-simple\INSTALLATION.txt"
echo 1. Install .NET 8.0 Runtime if you don't have it: >> "dist-simple\INSTALLATION.txt"
echo    https://dotnet.microsoft.com/download/dotnet/8.0 >> "dist-simple\INSTALLATION.txt"
echo    Choose "Runtime" not "SDK" >> "dist-simple\INSTALLATION.txt"
echo. >> "dist-simple\INSTALLATION.txt"
echo 2. Double-click RSSQuick.exe to run >> "dist-simple\INSTALLATION.txt"
echo. >> "dist-simple\INSTALLATION.txt"
echo 3. To get started: >> "dist-simple\INSTALLATION.txt"
echo    - Click "Import OPML File" >> "dist-simple\INSTALLATION.txt"
echo    - Select the included RSS.opml file >> "dist-simple\INSTALLATION.txt"
echo    - Use Tab and arrow keys to navigate >> "dist-simple\INSTALLATION.txt"
echo. >> "dist-simple\INSTALLATION.txt"
echo SUPPORT: >> "dist-simple\INSTALLATION.txt"
echo - Source code: https://github.com/kellylford/rssquick >> "dist-simple\INSTALLATION.txt"
echo - Issues: https://github.com/kellylford/rssquick/issues >> "dist-simple\INSTALLATION.txt"

echo.
echo *** SUCCESS! ***
echo.
echo Simple distribution created in: dist-simple\
echo.

REM Show what was created
echo Files created:
dir /b "dist-simple"
echo.

REM Show size
for /f "tokens=3" %%s in ('dir "dist-simple" /s /-c ^| find "File(s)"') do set size=%%s
set /a size_kb=%size%/1024
echo Total size: %size_kb% KB
echo.

echo STANDARD .NET DISTRIBUTION:
echo - Works on Intel/AMD processors (most computers)
echo - Users need .NET 8.0 Runtime (one-time install)
echo - Small download (~400 KB)
echo - This is what 90%% of .NET developers distribute
echo.

echo NEXT STEPS:
echo 1. Test: Run dist-simple\RSSQuick.exe
echo 2. Distribute: Zip the dist-simple folder  
echo 3. Tell users: "Requires .NET 8.0 Runtime"
echo.

set /p OPEN="Open the distribution folder? (y/n): "
if /i "%OPEN%"=="y" start "" explorer "dist-simple"

echo.
echo Simple build complete!
pause
