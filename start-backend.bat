@echo off
REM EaseInn - Start OCR & WhatsApp Backend Server
echo Starting EaseInn Backend Server on Port 3001...
cd /d "%~dp0ocr-server"
npm run dev
pause
