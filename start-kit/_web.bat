@echo off
title Showroom Mobile Web (port 8080)
cd /d "%~dp0frontend"
echo.
echo Open this on your phone:  http://%LANIP%:8080
echo After changing code: press  R  in this window, then reload the phone page.
echo.
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 --dart-define=API_URL=http://%LANIP%:8000
pause
