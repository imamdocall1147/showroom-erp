@echo off
setlocal
set "ROOT=%~dp0"
set "BACKEND=%ROOT%backend"
set "FRONTEND=%ROOT%frontend"

if not exist "%BACKEND%" (
  echo [ERROR] backend folder not found: %BACKEND%
  echo Edit this file and fix the BACKEND path at the top.
  pause
  exit /b 1
)
if not exist "%FRONTEND%" (
  echo [ERROR] frontend folder not found: %FRONTEND%
  pause
  exit /b 1
)

set "LANIP="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%get-ip.ps1"`) do set "LANIP=%%i"
if "%LANIP%"=="" set "LANIP=127.0.0.1"

echo ============================================================
echo  Showroom ERP - starting everything
echo  PC app          : opens automatically
echo  Phone browser   : http://%LANIP%:8080
echo  (phone must be on the same Wi-Fi as this PC)
echo ============================================================

echo [1/3] Starting backend server ...
start "Showroom Backend (port 8000)" cmd /k ""%ROOT%_backend.bat""

timeout /t 6 /nobreak >nul

echo [2/3] Starting mobile web version ...
start "Showroom Mobile Web (port 8080)" cmd /k ""%ROOT%_web.bat""

echo [3/3] Starting PC app ...
cd /d "%FRONTEND%"
flutter run -d windows

echo.
echo PC app closed. Backend and mobile windows are still running.
echo Close those two windows to stop everything.
pause
