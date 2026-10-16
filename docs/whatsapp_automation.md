# Automated WhatsApp Messaging in EaseInn

EaseInn incorporates an unofficial, zero-cost, one-way automated WhatsApp notification system powered by [`whatsapp-web.js`](https://github.com/wwebjs/whatsapp-web.js). It allows hotels to authenticate their existing WhatsApp Business or standard WhatsApp number via a QR code and automatically dispatch transactional notifications to guests upon check-in, checkout, or reservation.

---

## 1. Architecture Overview

```
                      +-----------------------------------+
                      |   EaseInn Frontdesk Web / Mobile  |
                      |  (Check-In / Checkout / Booking)   |
                      +-----------------+-----------------+
                                        |
                 REST Hooks / API Calls | (Non-blocking)
                                        v
                      +-----------------------------------+
                      |         Node.js Backend           |
                      |     (ocr-server / port 3001)      |
                      |                                   |
                      | - WhatsAppService (LocalAuth)     |
                      | - Template Interpolation Engine   |
                      | - 10-Min Idempotency Cache        |
                      | - Delivery Audit Logger           |
                      +-----------------+-----------------+
                                        |
                      Puppeteer Headless Browser Session
                                        |
                                        v
                            +-----------------------+
                            |     WhatsApp Web      |
                            | (Official Web Client) |
                            +-----------+-----------+
                                        |
                                        v
                            +-----------------------+
                            | Guest's Mobile Device |
                            +-----------------------+
```

### Key Technical Elements:
1. **Engine**: `whatsapp-web.js` with Puppeteer running in headless mode.
2. **Session Persistence**: `LocalAuth` storing WhatsApp authentication tokens in `.wwebjs_auth/`.
3. **Template Engine**: Regex-based interpolation for dynamic placeholders.
4. **Idempotency & Duplicate Suppression**: 10-minute duplicate suppression window to prevent re-sending identical notifications when frontdesk double-clicks or re-saves a stay.
5. **Fail-Safe & Non-Blocking**: Sending errors or connection disconnects are logged and returned as non-blocking promises, ensuring hotel operations (check-in/check-out) are never interrupted or slowed down.

---

## 2. Dynamic Placeholders

The template engine supports 5 standard placeholders:
- `{guestName}`: Full name of the primary guest (e.g., `Ananya Deshmukh`).
- `{hotelName}`: Name of the property (e.g., `EaseInn Boutique & Suites`).
- `{roomNumber}`: Assigned room number (e.g., `104`).
- `{checkInDate}`: Date of arrival (e.g., `16 Oct 2026`).
- `{checkOutDate}`: Date of departure (e.g., `17 Oct 2026`).

---

## 3. Predefined Templates

EaseInn comes pre-configured with 4 editable templates:

### 1. Check-in Welcome (`checkin_welcome`)
*Triggered automatically upon guest check-in.*
```
Dear {guestName},
Welcome to {hotelName}! 🏨✨
We are delighted to host you. Your Room {roomNumber} is ready.
Check-in Date: {checkInDate}
Expected Check-out: {checkOutDate}

If you need any assistance, room service, or local recommendations, please feel free to reach out to the front desk.
Wishing you a comfortable and memorable stay!
```

### 2. Checkout Thank-You (`checkout_thankyou`)
*Triggered automatically upon settling the bill and checking out.*
```
Dear {guestName},
Thank you for staying with us at {hotelName}! 🙏
We hope you had a pleasant and restful experience in Room {roomNumber}.
Your checkout on {checkOutDate} is complete.

We would love to welcome you back on your next visit. Have safe travels ahead! 🌟
```

### 3. Booking Confirmation (`booking_confirmation`)
*Triggered when a reservation or advance booking is created.*
```
Dear {guestName},
Your booking at {hotelName} has been confirmed! 🎉
Room: {roomNumber}
Check-in: {checkInDate}
Check-out: {checkOutDate}

We look forward to welcoming you soon. Please let us know if you require early check-in or airport transfer assistance.
```

### 4. Custom Guest Notification (`custom_notification`)
*Used for ad-hoc notices (e.g., breakfast timings, Wi-Fi details, special events).*
```
Dear {guestName},
Important update regarding your stay at {hotelName} (Room {roomNumber}):

We hope you are enjoying your stay! If you need any assistance, our front desk team is always here to help.
```

---

## 4. Settings UI & Management

Accessible via the sidebar **WhatsApp Automation** tab (`/whatsapp`):
- **QR Code Authentication**: Scan with your WhatsApp / WhatsApp Business app (Settings -> Linked Devices -> Link a Device).
- **Session Status**: Live indicator (`READY`, `QR_READY`, `AUTHENTICATING`, `DISCONNECTED`).
- **Template Editor**: Switch between the 4 templates, toggle them on/off, insert dynamic placeholders with one click, and preview live messages in a WhatsApp chat bubble simulation.
- **Test Message Dispatcher**: Send a live test message to any phone number to verify deliverability and formatting.
- **Audit & Delivery Logs**: Inspect timestamps, recipient numbers, template IDs, and delivery statuses.

---

## 5. Security & Privacy

1. **Session Credentials**: Stored securely in `.wwebjs_auth/` on the server host machine.
2. **No Frontend Exposure**: Session tokens, keys, and cookies are strictly contained on the backend and are never transmitted over API endpoints.
3. **Repository Exclusion**: `.wwebjs_auth/` and `.wwebjs_cache/` are added to `.gitignore`, preventing accidental commits of live credentials.
4. **Data Isolation**: Template contents and delivery logs are stored in `ocr-server/data/`, which is ignored by version control.

---

## 6. Risks of Unofficial WhatsApp Web Automation

> [!CAUTION]
> `whatsapp-web.js` interacts with the unofficial WhatsApp Web interface via Puppeteer. While completely free with zero subscription or per-message fees, hotels must be aware of the operational risks and follow recommended safeguards.

### Risk 1: Number Banning or Temporary Account Restrictions
- **Risk**: Meta enforces strict automated spam-detection algorithms. Using unofficial web automation to blast unsolicited promotional bulk messages or mass marketing campaigns can trigger a temporary or permanent account ban.
- **Safeguard**: EaseInn **strictly limits WhatsApp messaging to transactional 1-to-1 operational notices** (check-in, checkout, reservation confirmation) initiated directly by guest actions. Do not use this account for bulk broadcast marketing.

### Risk 2: WhatsApp Web Session Invalidation
- **Risk**: Meta periodically logs out inactive linked devices or updates the WhatsApp Web DOM.
- **Safeguard**: EaseInn includes an automatic reconnection loop (`puppeteer` restart) and provides a 1-click **Disconnect / Re-link** button in the dashboard to scan a fresh QR code if the session is revoked.

### Risk 3: Rate Limiting & Rapid Multi-Sending
- **Risk**: Sending multiple messages within milliseconds can be flagged as bot behavior.
- **Safeguard**: EaseInn incorporates a **10-minute duplicate suppression window** per guest/phone/template and dispatches messages sequentially.

### Risk 4: Headless Browser Dependency
- **Risk**: Running Chromium via Puppeteer requires modest CPU and RAM (~150-300MB RAM).
- **Safeguard**: Chromium launch flags are optimized (`--no-sandbox`, `--disable-setuid-sandbox`, `--disable-dev-shm-usage`, `--disable-gpu`) for lightweight resource consumption on modest cloud VMs or local frontdesk machines.

---

## 7. API Endpoints Reference

All endpoints are hosted on the Node.js backend (`/api/whatsapp`):

| Endpoint | Method | Description |
| :--- | :--- | :--- |
| `/api/whatsapp/status` | GET | Returns current connection status, phone, battery, and QR data URL. |
| `/api/whatsapp/connect` | POST | Initializes client and generates QR code if disconnected. |
| `/api/whatsapp/disconnect` | POST | Logs out and destroys the active Puppeteer session. |
| `/api/whatsapp/templates` | GET | Fetches all 4 templates and dynamic placeholder specifications. |
| `/api/whatsapp/templates/:templateId` | PUT | Updates template subject, body, or active status. |
| `/api/whatsapp/templates/reset` | POST | Resets all templates to default factory settings. |
| `/api/whatsapp/preview` | POST | Returns interpolated message text for given template and variables. |
| `/api/whatsapp/send` | POST | Sends manual or custom message to a specified phone number. |
| `/api/whatsapp/logs` | GET | Returns recent message delivery audit logs. |
| `/api/whatsapp/hook/checkin` | POST | Automated hook for check-in welcome notification. |
| `/api/whatsapp/hook/checkout` | POST | Automated hook for checkout thank-you notification. |
| `/api/whatsapp/hook/reservation` | POST | Automated hook for booking confirmation notification. |
