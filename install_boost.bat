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

if exist "%BOOST_ARCHIVE%" (
  echo Checking existing Boost archive...
  call :verify_boost_archive >nul 2>&1
  if not errorlevel 1 (
    echo Existing Boost archive is complete; skipping download.
    goto boost_archive_ready
  )
  for %%I in ("%BOOST_ARCHIVE%") do echo Resuming Boost %boost_version% download from %%~zI bytes...
) else (
  echo Downloading Boost %boost_version% source...
)

where curl.exe >nul 2>&1
if errorlevel 1 (
  echo Error: curl.exe is required for resumable downloads.
  echo The existing partial archive has been preserved:
  echo   "%BOOST_ARCHIVE%"
  exit /b 1
)

curl.exe --location --fail --retry 5 --retry-delay 2 --continue-at - --output "%BOOST_ARCHIVE%" "%BOOST_DOWNLOAD_URL%"
if errorlevel 1 (
  echo Error: failed to download or resume Boost from:
  echo   %BOOST_DOWNLOAD_URL%
  echo The partial archive has been preserved; run this script again to resume.
  exit /b 1
)

echo Verifying Boost archive...
call :verify_boost_archive
if errorlevel 1 (
  echo Error: Boost archive verification failed.
  echo If the download is already complete, delete this corrupt file and retry:
  echo   "%BOOST_ARCHIVE%"
  exit /b 1
)

:boost_archive_ready
echo Extracting Boost source...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; Add-Type -AssemblyName System.IO.Compression.FileSystem; $destinationRoot = [System.IO.Path]::GetFullPath($env:BOOST_PARENT) + [System.IO.Path]::DirectorySeparatorChar; $archive = [System.IO.Compression.ZipFile]::OpenRead($env:BOOST_ARCHIVE); try { foreach ($entry in $archive.Entries) { $entryPath = $entry.FullName.Replace('/', [System.IO.Path]::DirectorySeparatorChar); $targetPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($destinationRoot, $entryPath)); if (-not $targetPath.StartsWith($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw ('Unsafe ZIP entry: ' + $entry.FullName) }; if ([System.String]::IsNullOrEmpty($entry.Name)) { [System.IO.Directory]::CreateDirectory($targetPath) | Out-Null } else { $targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath); [System.IO.Directory]::CreateDirectory($targetDirectory) | Out-Null; [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true) } } } finally { $archive.Dispose() }"
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

:verify_boost_archive
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; $sha256 = [System.Security.Cryptography.SHA256]::Create(); try { $stream = [System.IO.File]::OpenRead($env:BOOST_ARCHIVE); try { $actual = ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() } finally { $stream.Dispose() } } finally { $sha256.Dispose() }; if ($actual -ne $env:BOOST_EXPECTED_SHA256) { throw ('SHA256 mismatch. Expected: ' + $env:BOOST_EXPECTED_SHA256 + '; actual: ' + $actual) }"
exit /b %ERRORLEVEL%
