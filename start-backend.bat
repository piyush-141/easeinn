@echo off
REM EaseInn - Start OCR & WhatsApp Backend Server
echo Starting LOCAL EaseInn Backend on Port 3001...
cd /d "%~dp0ocr-server"
set "PORT=3001"
set "WHATSAPP_DATA_DIR=%CD%\data"
set "WHATSAPP_AUTH_DIR=%CD%\.baileys_auth"
set "WHATSAPP_ALLOW_LOCAL_ACCESS=true"
echo Local API: http://localhost:3001
echo WhatsApp session and logs are stored locally under ocr-server, not on Render.
echo Local WhatsApp access is enabled for emulator testing; production still requires the app's signed-in Supabase session.
echo Close this window to stop the backend. WhatsApp events will appear below.
npm run dev
pause
