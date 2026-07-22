@echo off
setlocal

if not defined RIME_ROOT set "RIME_ROOT=%CD%"
if not defined boost_version set "boost_version=1.84.0"

if /i not "%boost_version%"=="1.84.0" (
  echo Error: this helper currently supports Boost 1.84.0 only.
  exit /b 1
)

set "boost_x_y_z=%boost_version:.=_%"
if not defined BOOST_ROOT set "BOOST_ROOT=%RIME_ROOT%\deps\boost_%boost_x_y_z%"

if exist "%BOOST_ROOT%\boost" if exist "%BOOST_ROOT%\bootstrap.bat" goto boost_found

for %%I in ("%BOOST_ROOT%\..") do set "BOOST_PARENT=%%~fI"
if not exist "%BOOST_PARENT%" mkdir "%BOOST_PARENT%"
if errorlevel 1 (
  echo Error: failed to create the Boost parent directory.
  exit /b 1
)

set "BOOST_ARCHIVE=%BOOST_PARENT%\boost_%boost_x_y_z%.zip"
set "BOOST_DOWNLOAD_URL=https://archives.boost.io/release/%boost_version%/source/boost_%boost_x_y_z%.zip"
set "BOOST_EXPECTED_SHA256=cc77eb8ed25da4d596b25e77e4dbb6c5afaac9cddd00dc9ca947b6b268cc76a4"

echo Downloading Boost %boost_version% source...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $env:BOOST_DOWNLOAD_URL -OutFile $env:BOOST_ARCHIVE"
if errorlevel 1 (
  echo Error: failed to download Boost from:
  echo   %BOOST_DOWNLOAD_URL%
  exit /b 1
)

echo Verifying Boost archive...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$actual = (Get-FileHash -LiteralPath $env:BOOST_ARCHIVE -Algorithm SHA256).Hash.ToLowerInvariant(); if ($actual -ne $env:BOOST_EXPECTED_SHA256) { Write-Error ('SHA256 mismatch. Expected: ' + $env:BOOST_EXPECTED_SHA256 + '; actual: ' + $actual); exit 1 }"
if errorlevel 1 (
  echo Error: Boost archive verification failed.
  exit /b 1
)

echo Extracting Boost source...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $env:BOOST_ARCHIVE -DestinationPath $env:BOOST_PARENT -Force"
if errorlevel 1 (
  echo Error: failed to extract Boost.
  exit /b 1
)

if not exist "%BOOST_ROOT%\boost" (
  echo Error: Boost headers were not found after extraction.
  exit /b 1
)
if not exist "%BOOST_ROOT%\bootstrap.bat" (
  echo Error: Boost bootstrap.bat was not found after extraction.
  exit /b 1
)

:boost_found
echo Boost source is ready:
echo   "%BOOST_ROOT%"

pushd "%RIME_ROOT%"
if errorlevel 1 (
  echo Error: failed to enter the project root.
  exit /b 1
)

call .\build.bat boost
set "BUILD_RESULT=%ERRORLEVEL%"
popd
exit /b %BUILD_RESULT%
