# Local WhatsApp development

Use the local backend while developing so sends, receipts, connection events, and errors are visible in its terminal. Flutter debug builds and the local web frontend use the local server automatically. Release builds continue to use Render.

## Run locally

1. Start `start-backend.bat` from the repository root. It runs the API on port `3001`, allows local emulator testing with the app's offline/demo account, and prints WhatsApp events in that window. This development-only access bypass is disabled in production, where the existing Supabase session is required.
2. In another terminal, run `cd frontend` and `npm run dev -- --host 0.0.0.0`. Open the local Vite URL it prints; the web app targets `localhost:3001`.
3. With the Android emulator running, use another terminal to run `cd mobile` and `flutter run`. Android emulator requests use `10.0.2.2:3001` to reach the host computer.
4. Connect the local WhatsApp session by scanning its QR code. Then send a test and watch the backend terminal for `Accepted by WhatsApp`, `Recipient receipt DELIVERED/READ`, or a 60-second no-receipt warning.

The local Baileys session and logs are stored under `ocr-server/.baileys_auth` and `ocr-server/data`; they are separate from Render's persistent disk. The local server does not change the deployed service. A physical Android phone can use `flutter run --dart-define=EASEINN_BACKEND_URL=http://<computer-LAN-IP>:3001` while both devices share a network.

An accepted send means WhatsApp acknowledged submission. Delivery is confirmed only when WhatsApp sends a recipient receipt. No receipt is reported as unconfirmed; the backend does not resend automatically, to avoid duplicate messages.
