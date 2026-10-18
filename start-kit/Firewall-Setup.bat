@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Right-click this file and choose "Run as administrator".
  pause
  exit /b 1
)
netsh advfirewall firewall add rule name="Showroom Backend 8000" dir=in action=allow protocol=TCP localport=8000 profile=private
netsh advfirewall firewall add rule name="Showroom Web 8080" dir=in action=allow protocol=TCP localport=8080 profile=private
echo.
echo Done. Ports 8000 and 8080 are now open on your private Wi-Fi network.
pause
