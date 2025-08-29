@echo off
setlocal EnableDelayedExpansion

echo RSS Quick - Multi-Platform Small Distribution
echo ==============================================
echo Creating small packages for x64 and ARM64...
echo.

set BASE_DIR=dist-multi-small

echo [1/3] Cleaning previous builds...
if exist "%BASE_DIR%" rmdir /s /q "%BASE_DIR%"

echo [2/3] Building for both platforms...

echo Building for x64 (Intel/AMD)...
dotnet publish RSSReaderWPF.csproj --configuration Release --runtime win-x64 --self-contained false --output "%BASE_DIR%\win-x64"
if %ERRORLEVEL% neq 0 goto :error

echo Building for ARM64 (Surface/newer laptops)...
dotnet publish RSSReaderWPF.csproj --configuration Release --runtime win-arm64 --self-contained false --output "%BASE_DIR%\win-arm64"
if %ERRORLEVEL% neq 0 goto :error


echo [3/3] Adding documentation, samples, and zipping outputs...

REM Copy files to both platforms
copy "RSS.opml" "%BASE_DIR%\win-x64\"
copy "README.md" "%BASE_DIR%\win-x64\"
copy "RSS.opml" "%BASE_DIR%\win-arm64\"
copy "README.md" "%BASE_DIR%\win-arm64\"

REM Create simple instructions
echo RSS Quick - Multi-Platform Distribution > "%BASE_DIR%\README.txt"
echo ======================================= >> "%BASE_DIR%\README.txt"
echo. >> "%BASE_DIR%\README.txt"
echo Choose the right folder for your computer: >> "%BASE_DIR%\README.txt"
echo. >> "%BASE_DIR%\README.txt"
echo win-x64\     - For most computers (Intel/AMD) >> "%BASE_DIR%\README.txt"
echo win-arm64\   - For ARM computers (Surface Pro X, etc) >> "%BASE_DIR%\README.txt"
echo. >> "%BASE_DIR%\README.txt"
echo Try win-x64 first. If it asks to download .NET, try win-arm64. >> "%BASE_DIR%\README.txt"
echo. >> "%BASE_DIR%\README.txt"
echo Both require .NET 8.0 Runtime to be installed. >> "%BASE_DIR%\README.txt"
echo Download from: https://dotnet.microsoft.com/download/dotnet/8.0 >> "%BASE_DIR%\README.txt"

REM Zip each platform's output into its own folder
echo Zipping win-x64 output...
if exist "%BASE_DIR%\win-x64" powershell -Command "Compress-Archive -Path '%BASE_DIR%/win-x64/*' -DestinationPath '%BASE_DIR%/win-x64/RSSQuick-win-x64.zip' -Force"

echo Zipping win-arm64 output...
if exist "%BASE_DIR%\win-arm64" powershell -Command "Compress-Archive -Path '%BASE_DIR%/win-arm64/*' -DestinationPath '%BASE_DIR%/win-arm64/RSSQuick-win-arm64.zip' -Force"

echo.
echo *** SUCCESS! ***
echo.
echo Created: %BASE_DIR%\
echo   win-x64\     - For Intel/AMD computers
echo     RSSQuick-win-x64.zip (ready for release)
echo   win-arm64\   - For ARM computers
echo     RSSQuick-win-arm64.zip (ready for release)
echo   README.txt   - Instructions
echo.

REM Show sizes
for /f "tokens=3" %%s in ('dir "%BASE_DIR%\win-x64" /s /-c ^| find "File(s)"') do set size_x64=%%s
for /f "tokens=3" %%s in ('dir "%BASE_DIR%\win-arm64" /s /-c ^| find "File(s)"') do set size_arm64=%%s
set /a size_x64_kb=!size_x64!/1024
set /a size_arm64_kb=!size_arm64!/1024

echo Sizes:
echo   win-x64: !size_x64_kb! KB
echo   win-arm64: !size_arm64_kb! KB
echo.

set /p OPEN="Open the distribution folder? (y/n): "
if /i "%OPEN%"=="y" start "" explorer "%BASE_DIR%"

echo Multi-platform build complete!
pause
goto :end

:error
echo.
echo *** BUILD FAILED ***
echo Check the errors above
pause
exit /b 1

:end
