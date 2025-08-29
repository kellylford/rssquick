@echo off
REM zip-for-release.cmd - Zips build output folders for GitHub Releases using PowerShell Compress-Archive

setlocal

REM Zip dist-simple (standard x64 build)
if exist dist-simple\ (
    echo Zipping dist-simple/ ...
    powershell -Command "Compress-Archive -Path 'dist-simple/*' -DestinationPath 'RSSQuick-win-x64.zip' -Force"
)

REM Zip dist-multi-small (multi-arch small build)
if exist dist-multi-small\ (
    echo Zipping dist-multi-small/ ...
    powershell -Command "Compress-Archive -Path 'dist-multi-small/*' -DestinationPath 'RSSQuick-multi-small.zip' -Force"
)

REM Zip dist (self-contained build)
if exist dist\ (
    echo Zipping dist/ ...
    powershell -Command "Compress-Archive -Path 'dist/*' -DestinationPath 'RSSQuick-self-contained.zip' -Force"
)

echo.
echo Done! Upload the .zip files as release assets on GitHub.
endlocal
