# EaseInn WhatsApp Automation

EaseInn connects to a single WhatsApp linked device from the Node.js backend using Baileys. This is an unofficial WhatsApp Web integration; WhatsApp may unlink the device, change its protocol, or restrict the account. For production messaging with a delivery guarantee, use the official WhatsApp Business Platform API.

## Components

- Backend: `ocr-server`, mounted at `/api/whatsapp`.
- Engine: `@whiskeysockets/baileys` (no Chromium runtime).
- Session storage: `WHATSAPP_AUTH_DIR`, which must live on persistent storage. Render uses `/data/baileys_auth` on its persistent disk.
- Templates, bounded logs, and send-idempotency records: `WHATSAPP_DATA_DIR`, set to `/data` on Render.
- Frontend and mobile use the same backend. Local web development defaults to `localhost:3001`; set `VITE_WHATSAPP_API_URL` to override the frontend service URL.
- WhatsApp routes do not require EaseInn sign-in; the web and mobile clients can use the WhatsApp controls without an app account session.
- The Render Blueprint intentionally leaves these Supabase values unsynced. Add the same Supabase project URL and publishable/anon key used by the clients to the Render service environment before deploying; without them, WhatsApp endpoints fail closed with `AUTH_NOT_CONFIGURED`.
- The backend rate-limits WhatsApp API traffic and message sends to reduce abuse.

## Session lifecycle

The backend restores its session during startup. If the linked device is still valid, status becomes `CONNECTED` without a new QR scan. Otherwise the dashboard shows the current QR. Temporary disconnects reconnect automatically; an explicit logout or an invalidated session requires linking again. The **Disconnect** action deliberately logs out and removes saved credentials. Do not use it to restart the service.

Only one active backend instance should use a WhatsApp session directory at a time. Do not run multiple Render instances against one Baileys auth directory; credentials and encryption keys are mutable. On Render, keep a single instance and a persistent disk mounted at `/data`.

## Sending and delivery status

Sends are serialized. Phone numbers are normalized and checked with WhatsApp before sending. Duplicate suppression uses a five-minute window, keyed by stay and template when available, or by recipient and message content otherwise. Accepted send identifiers and logs persist under `WHATSAPP_DATA_DIR` across restarts.

The API returns **accepted** only after Baileys returns a message identifier. That confirms WhatsApp accepted the outbound message for submission; it is not a delivery guarantee. Receipt events update log entries to **DELIVERED** or **READ** when WhatsApp supplies those receipts. A timeout after a send begins is recorded as **UNKNOWN** because the send may still have reached WhatsApp; check the chat/log before retrying. Duplicate protection is retained to reduce accidental repeats.

## Render deployment

`render.yaml` defines a Docker web service using `ocr-server/Dockerfile`, a health check at `/`, and a persistent disk mounted at `/data`. The frontend's production default points to `https://easeinn.onrender.com`; its `/api/whatsapp/status` endpoint must report the new backend version after deployment. Preserve existing required OCR provider environment variables in Render.

After deploying, check `/` and `/api/whatsapp/status`, then link the account once and verify it remains connected after a service restart. Send a test to a controlled number and verify the log transitions from **Accepted** to **Delivered** or **Read** if receipts are available.

## API endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /api/whatsapp/status` | Connection state, QR, linked account, and session presence. |
| `POST /api/whatsapp/connect` | Start connection or return the current connection attempt. |
| `POST /api/whatsapp/disconnect` | Explicitly unlink and remove saved credentials. |
| `GET /api/whatsapp/templates` | Read notification templates. |
| `PUT /api/whatsapp/templates/:templateId` | Update a template. |
| `POST /api/whatsapp/templates/reset` | Restore factory templates. |
| `POST /api/whatsapp/preview` | Render placeholders into a template preview. |
| `POST /api/whatsapp/send` | Send a manual or custom message. |
| `GET /api/whatsapp/logs` | Read recent send and receipt records. |
| `POST /api/whatsapp/hook/checkin` | Send check-in notice. |
| `POST /api/whatsapp/hook/checkout` | Send checkout notice. |
| `POST /api/whatsapp/hook/reservation` | Send reservation notice. |

## Operational security

Treat the auth directory as a credential store. Never commit, log, expose, or copy its contents. Restrict access to the Render service and disk. Only send messages to guests who expect the transactional notice, and avoid bulk or promotional messaging.
