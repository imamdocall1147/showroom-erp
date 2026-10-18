@echo off
rem ---- Builds the phone app and publishes it so phones can update themselves ----
rem Put this file and publish_update.ps1 in the showroom-erp folder.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish_update.ps1"
if errorlevel 1 (
  echo.
  echo Something went wrong. Check the messages above.
)
pause
