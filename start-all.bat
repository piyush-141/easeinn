@echo off
REM EaseInn - Start All Backend & Web Servers
echo Starting EaseInn Servers (OCR Server & Frontend Dashboard)...

start "EaseInn - OCR Server (3001)" cmd /k "cd /d "%~dp0ocr-server" && npm run dev"
start "EaseInn - Frontend (5173)" cmd /k "cd /d "%~dp0frontend" && npm run dev"

echo Servers launched in separate windows!
echo To run the mobile app on your desired device, run:
echo   cd mobile ^&^& flutter run
