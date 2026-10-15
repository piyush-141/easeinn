# EaseInn Project & Server Startup Guide

This document outlines all servers and apps in the EaseInn repository and provides copy-paste commands to start them via Command Prompt (`cmd`) or PowerShell.

---

## Architecture Overview

| Component | Directory | Port / Runtime | Description |
| :--- | :--- | :--- | :--- |
| **OCR / Verification API** | `ocr-server/` | `http://localhost:3001` | Express & Tesseract/Ollama pipeline for Aadhaar & ID processing |
| **Web Dashboard (Frontend)** | `frontend/` | `http://localhost:5173` | React 19 + Vite PMS web application |
| **Mobile App (Flutter)** | `mobile/` | Chrome / Android / iOS | Flutter cross-platform staff application |
| **Ollama (Optional AI)** | System service | `http://localhost:11434` | Vision model (`llava:latest`) for high-accuracy OCR fallback |

---

## Option 1: One-Click Startup Script (Recommended)

A [`start-all.bat`](file:///c:/Users/Piyush/OneDrive/Desktop/codes/extras/Easeinn/start-all.bat) script has been provided in the project root to start the **OCR Server** and **Frontend Web Dashboard** in separate windows.

**In PowerShell / Terminal:**
```powershell
.\start-all.bat
```

**In CMD:**
```cmd
start-all.bat
```

---

## Option 2: Running via PowerShell Command Line

If you prefer launching directly via **PowerShell**:

```powershell
Start-Process cmd -ArgumentList '/k "cd /d ocr-server && npm run dev"'
Start-Process cmd -ArgumentList '/k "cd /d frontend && npm run dev"'
```

---

## Option 3: Running via Classic Command Prompt (`cmd.exe`)

```cmd
start cmd /k "cd /d ocr-server && npm run dev"
start cmd /k "cd /d frontend && npm run dev"
```

---

## Running the Mobile App (Whenever & Wherever You Want)

Once your servers are up, launch the mobile/staff app on whichever target device you prefer (Chrome, Android emulator, or connected phone):

```cmd
cd mobile
```
- **List available devices:** `flutter devices`
- **Run on default / connected device:** `flutter run`
- **Run specifically on Chrome:** `flutter run -d chrome`
- **Run on Android:** `flutter run -d <device_id>`

---

## Option 2: Starting Services Individually

Open separate Command Prompt (`cmd`) windows for each service:

### 1. OCR Backend Server (Port 3001)
Required for document OCR processing and verification.

```cmd
cd /d "C:\Users\Piyush\OneDrive\Desktop\codes\extras\Easeinn\ocr-server"
npm run dev
```
*(Or `npm start` for production mode without nodemon)*

> **Note:** If you want LLM vision extraction enabled, ensure Ollama is running in the background:
> ```cmd
> ollama serve
> ```

---

### 2. Frontend Web App (Port 5173)
The desktop/web management dashboard.

```cmd
cd /d "C:\Users\Piyush\OneDrive\Desktop\codes\extras\Easeinn\frontend"
npm run dev
```
Once launched, open [http://localhost:5173](http://localhost:5173) in your browser.

---

### 3. Mobile / Staff App (Flutter)
The mobile check-in app.

```cmd
cd /d "C:\Users\Piyush\OneDrive\Desktop\codes\extras\Easeinn\mobile"
flutter run -d chrome
```

*For Android emulator or physical device:*
```cmd
flutter run
```

---

## Quick Reference Summary Table

| Server / App | Path | Command |
| :--- | :--- | :--- |
| **OCR Backend** | `cd ocr-server` | `npm run dev` |
| **Frontend Dashboard** | `cd frontend` | `npm run dev` |
| **Flutter Staff App** | `cd mobile` | `flutter run -d chrome` |
| **Ollama Service (Optional)**| Anywhere | `ollama serve` |
