@echo off
REM Development builds and tests. For release artefacts use package.cmd.
setlocal
cd /d "%~dp0"

if "%1"==""        goto :debug
if "%1"=="debug"   goto :debug
if "%1"=="release" goto :release
if "%1"=="test"    goto :test
if "%1"=="clean"   goto :clean
if "%1"=="help"    goto :help
if "%1"=="-h"      goto :help
if "%1"=="/?"      goto :help

echo Unknown option "%1".
goto :help

:debug
echo Building and running (Debug)...
dotnet run --configuration Debug
goto :done

:release
echo Building and running (Release)...
dotnet run --configuration Release
goto :done

:test
echo Running tests...
dotnet test --project tests\RSSQuick.Tests\RSSQuick.Tests.csproj
goto :done

:clean
echo Cleaning build output...
if exist "bin"       rmdir /s /q "bin"
if exist "obj"       rmdir /s /q "obj"
if exist "artifacts" rmdir /s /q "artifacts"
if exist "tests\RSSQuick.Tests\bin" rmdir /s /q "tests\RSSQuick.Tests\bin"
if exist "tests\RSSQuick.Tests\obj" rmdir /s /q "tests\RSSQuick.Tests\obj"
echo Done.
goto :done

:help
echo.
echo Usage: build.cmd [option]
echo.
echo   (none) or debug   Build and run in Debug
echo   release           Build and run in Release
echo   test              Run the test suite
echo   clean             Delete build output and artefacts
echo   help              Show this
echo.
echo To build the installer and portable ZIP, run package.cmd instead.
echo.

:done
if errorlevel 1 (
    echo.
    echo *** FAILED *** - see the messages above.
)
pause
