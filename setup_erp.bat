@echo off
setlocal
rem ---- Showroom ERP: one-time setup. Run this once (double click). ----
rem This file can be in the showroom-erp folder or in a sub-folder of it.
set "HERE=%~dp0"
set "ROOT=%~dp0"
if not exist "%ROOT%frontend" if exist "%ROOT%..\frontend" set "ROOT=%~dp0..\"
pushd "%ROOT%"
set "ROOT=%CD%\"
popd

echo Project folder: %ROOT%
echo.
echo [1/3] Building the app. The first time takes several minutes, please wait...
pushd "%ROOT%frontend"
call flutter build windows --release
if errorlevel 1 goto buildfail
popd

echo [2/3] Creating the desktop icon "Showroom ERP"...
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop')+'\Showroom ERP.lnk'); $s.TargetPath='%HERE%start_erp.bat'; $s.WorkingDirectory='%ROOT%'; $s.WindowStyle=7; $s.Save()"

echo [3/3] Optional: start the backend automatically when Windows starts (needed for phone use).
choice /c YN /m "Start the backend automatically when Windows starts"
if errorlevel 2 goto done
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\ERP Backend.lnk'); $s.TargetPath='%HERE%start_backend_only.bat'; $s.WorkingDirectory='%ROOT%'; $s.WindowStyle=7; $s.Save()"

:done
echo.
echo All done. Now double click "Showroom ERP" on the desktop to start everything.
pause
exit /b 0

:buildfail
popd
echo.
echo The build failed. Check the messages above (low disk space is a common reason).
pause
exit /b 1
