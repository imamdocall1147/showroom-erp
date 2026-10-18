@echo off
title Showroom Backend (port 8000)
cd /d "%~dp0backend"
if exist "venv\Scripts\activate.bat" call "venv\Scripts\activate.bat"
if exist ".venv\Scripts\activate.bat" call ".venv\Scripts\activate.bat"
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
pause
