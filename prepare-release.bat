@echo off
REM prepare-release.bat <version>
REM Automates versioning, changelog, and build for RSS Quick

if "%1"=="" (
    echo Usage: prepare-release.bat ^<version^>
    exit /b 1
)

set VERSION=%1

echo Updating version file...
echo %VERSION% > VERSION

echo Please update CHANGELOG.md and RELEASE-NOTES-v%VERSION%.md for this release.
echo.
echo Next steps:
echo 1. Build the app and create zips as usual.
echo 2. Commit all changes: git add . && git commit -m "Release v%VERSION%"
echo 3. Tag the release: git tag -a v%VERSION% -m "Release v%VERSION%"
echo 4. Push: git push origin main && git push origin v%VERSION%
echo 5. Create GitHub release and upload zips.
echo.
echo Release preparation complete!
