@echo off
setlocal
rem ---- Showroom ERP: one-click start (backend + app) ----
rem This file can be in the showroom-erp folder or in a sub-folder of it.
set "HERE=%~dp0"
set "ROOT=%~dp0"
if not exist "%ROOT%frontend" if exist "%ROOT%..\frontend" set "ROOT=%~dp0..\"
pushd "%ROOT%"
set "ROOT=%CD%\"
popd
set "APPDIR=%ROOT%frontend\build\windows\x64\runner\Release"
set "APP="
for %%f in ("%APPDIR%\*.exe") do set "APP=%%f"
if not defined APP (
  echo The app is not built yet.
  echo Run setup_erp.bat first, or in the frontend folder run: flutter build windows --release
  pause
  exit /b 1
)

rem ---- start the backend only if it is not already running ----
netstat -ano | findstr ":8000" | findstr "LISTENING" >nul
if %errorlevel%==0 goto waitbackend
pushd "%ROOT%backend"
start "ERP Backend" /min cmd /c "call venv\Scripts\activate.bat && uvicorn main:app --host 0.0.0.0 --port 8000"
popd

:waitbackend
set /a tries=0
:loop
powershell -NoProfile -Command "try { Invoke-WebRequest http://127.0.0.1:8000/ -UseBasicParsing -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"
if %errorlevel%==0 goto launch
set /a tries+=1
if %tries% GEQ 40 goto launch
timeout /t 1 /nobreak >nul
goto loop

:launch
start "" "%APP%"
exit /b 0
