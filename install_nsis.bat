@echo off
setlocal

set "MAKENSIS=%ProgramFiles(x86)%\NSIS\Bin\makensis.exe"

if exist "%MAKENSIS%" (
  echo NSIS is already installed:
  echo   "%MAKENSIS%"
  exit /b 0
)

where winget.exe >nul 2>&1
if errorlevel 1 (
  echo Error: winget.exe was not found.
  echo Install NSIS manually from https://nsis.sourceforge.io/Download
  exit /b 1
)

echo Installing NSIS with winget...
winget install --id NSIS.NSIS --exact --source winget --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
  echo Error: winget failed to install NSIS.
  exit /b 1
)

if not exist "%MAKENSIS%" (
  echo Error: NSIS installation finished, but makensis.exe was not found at:
  echo   "%MAKENSIS%"
  exit /b 1
)

echo NSIS installed successfully:
echo   "%MAKENSIS%"
exit /b 0

