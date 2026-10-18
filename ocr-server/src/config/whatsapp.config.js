// src/config/whatsapp.config.js
const path = require("path");
const fs = require("fs");

const DATA_DIR = process.env.WHATSAPP_DATA_DIR || path.join(__dirname, "../../data");
const TEMPLATES_FILE = path.join(DATA_DIR, "whatsapp_templates.json");
const LOGS_FILE = path.join(DATA_DIR, "whatsapp_logs.json");
const AUTH_DIR =
  process.env.WHATSAPP_AUTH_DIR || path.join(__dirname, "../../.baileys_auth");

const DEFAULT_TEMPLATES = {
  checkin_welcome: {
    id: "checkin_welcome",
    name: "Check-in Welcome",
    description: "Sent automatically when a guest check-in is completed",
    enabled: true,
    category: "automated",
    trigger: "on_checkin",
    template:
      "Namaste {guestName}! 🙏 Welcome to {hotelName}!\n\n" +
      "Your check-in to Room {roomNumber} is complete. We’re delighted to host you and hope you have a relaxing, comfortable stay.\n\n" +
      "📅 Check-in: {checkInDate}\n" +
      "📅 Check-out: {checkOutDate}\n\n" +
      "Need anything? Just message us or contact the front desk. We’re happy to help!\n\n" +
      "Warm regards,\n{hotelName} Team\n\n" +
      "---\n\n" +
      "नमस्ते {guestName} जी! 🙏 {hotelName} में आपका हार्दिक स्वागत है!\n\n" +
      "कमरा {roomNumber} में आपका चेक-इन पूरा हो गया है। हमें आपकी मेज़बानी करके खुशी हो रही है। हम आपके सुखद और आरामदायक प्रवास की कामना करते हैं।\n\n" +
      "📅 चेक-इन: {checkInDate}\n" +
      "📅 चेक-आउट: {checkOutDate}\n\n" +
      "किसी भी सहायता के लिए हमें संदेश भेजें या फ्रंट डेस्क से संपर्क करें। हमें आपकी मदद करके खुशी होगी!\n\n" +
      "सादर,\n{hotelName} टीम",
  },
  checkout_thankyou: {
    id: "checkout_thankyou",
    name: "Checkout Thank-you",
    description: "Sent automatically when a guest check-out is processed",
    enabled: true,
    category: "automated",
    trigger: "on_checkout",
    template:
      "Dear {guestName}, thank you for choosing {hotelName}! ✨\n\n" +
      "Your check-out from Room {roomNumber} is complete. We hope you enjoyed your stay and made some lovely memories with us.\n\n" +
      "Wishing you a safe journey! We look forward to welcoming you again.\n\n" +
      "Warm regards,\n{hotelName} Team\n\n" +
      "---\n\n" +
      "प्रिय {guestName} जी, {hotelName} को चुनने के लिए आपका धन्यवाद! ✨\n\n" +
      "कमरा {roomNumber} से आपका चेक-आउट पूरा हो गया है। हमें उम्मीद है कि आपका प्रवास सुखद रहा और आप यहाँ से अच्छी यादें लेकर जा रहे हैं।\n\n" +
      "आपकी यात्रा मंगलमय हो! हमें फिर से आपकी मेज़बानी करने की आशा रहेगी।\n\n" +
      "सादर,\n{hotelName} टीम",
  },
  booking_confirmation: {
    id: "booking_confirmation",
    name: "Booking Confirmation",
    description: "Sent when an advance room reservation or booking is created",
    enabled: true,
    category: "automated",
    trigger: "on_reservation",
    template:
      "Namaste {guestName}! Your booking at {hotelName} is confirmed! 🏨\n\n" +
      "Here are your reservation details:\n\n" +
      "📅 Arrival: {checkInDate}\n" +
      "📅 Departure: {checkOutDate}\n" +
      "🛏️ Room: {roomNumber}\n\n" +
      "Please carry a valid government-issued photo ID for check-in. Have questions or special requests? Feel free to contact us.\n\n" +
      "We look forward to welcoming you!\n\n" +
      "{hotelName} Team\n\n" +
      "---\n\n" +
      "नमस्ते {guestName} जी! {hotelName} में आपकी बुकिंग की पुष्टि हो गई है! 🏨\n\n" +
      "आपकी बुकिंग का विवरण:\n\n" +
      "📅 आगमन: {checkInDate}\n" +
      "📅 प्रस्थान: {checkOutDate}\n" +
      "🛏️ कमरा: {roomNumber}\n\n" +
      "चेक-इन के समय कृपया अपना वैध सरकारी फोटो पहचान पत्र साथ लाएँ। कोई सवाल या विशेष अनुरोध हो, तो हमसे संपर्क करें।\n\n" +
      "आपका स्वागत करने के लिए हम उत्सुक हैं!\n\n" +
      "{hotelName} टीम",
  },
  custom_notification: {
    id: "custom_notification",
    name: "Custom Guest Notification",
    description: "Sent manually by front desk staff for room service, alerts, or queries",
    enabled: true,
    category: "manual",
    trigger: "manual",
    template:
      "Hello {guestName}! Greetings from {hotelName}. 🛎️\n\n" +
      "A quick update regarding your stay in Room {roomNumber}:\n\n" +
      "{message}\n\n" +
      "Need any assistance? Just reply to this message or contact our front desk. We’re always happy to help!\n\n" +
      "Regards,\n{hotelName} Team\n\n" +
      "---\n\n" +
      "नमस्ते {guestName} जी! {hotelName} की ओर से सादर अभिवादन। 🛎️\n\n" +
      "आपके कमरे {roomNumber} में ठहरने के संबंध में एक जानकारी:\n\n" +
      "{messageHindi}\n\n" +
      "किसी भी सहायता के लिए इस संदेश का जवाब दें या हमारे फ्रंट डेस्क से संपर्क करें। हमें आपकी मदद करके खुशी होगी!\n\n" +
      "सादर,\n{hotelName} टीम",
  },
};

const SUPPORTED_PLACEHOLDERS = [
  { key: "{guestName}", label: "Guest Name", sample: "Vikram Aditya Singh" },
  { key: "{hotelName}", label: "Hotel Name", sample: "EaseInn Boutique & Suites" },
  { key: "{roomNumber}", label: "Room Number", sample: "102" },
  { key: "{checkInDate}", label: "Check-in Date", sample: "16 Oct 2026, 12:00 PM" },
  { key: "{checkOutDate}", label: "Check-out Date", sample: "18 Oct 2026, 11:00 AM" },
  { key: "{message}", label: "Custom Message (English)", sample: "Your laundry is ready for collection." },
  { key: "{messageHindi}", label: "Custom Message (Hindi)", sample: "आपकी लॉन्ड्री संग्रह के लिए तैयार है।" },
];

function sanitizeHotelId(hotelId) {
  if (!hotelId || typeof hotelId !== "string") return "default";
  const cleaned = hotelId.trim().replace(/[^a-zA-Z0-9_-]/g, "_");
  return cleaned || "default";
}

function getHotelAuthDir(hotelId) {
  const sanitized = sanitizeHotelId(hotelId);
  // If base AUTH_DIR already contains creds directly and requested is default, keep for backward compat
  if (sanitized === "default" && fs.existsSync(path.join(AUTH_DIR, "creds.json"))) {
    return AUTH_DIR;
  }
  const dir = path.join(AUTH_DIR, sanitized);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  }
  return dir;
}

function getHotelTemplatesFile(hotelId) {
  const sanitized = sanitizeHotelId(hotelId);
  if (sanitized === "default") return TEMPLATES_FILE;
  const hotelDir = path.join(DATA_DIR, "hotels", sanitized);
  if (!fs.existsSync(hotelDir)) fs.mkdirSync(hotelDir, { recursive: true });
  return path.join(hotelDir, "whatsapp_templates.json");
}

function getHotelLogsFile(hotelId) {
  const sanitized = sanitizeHotelId(hotelId);
  if (sanitized === "default") return LOGS_FILE;
  const hotelDir = path.join(DATA_DIR, "hotels", sanitized);
  if (!fs.existsSync(hotelDir)) fs.mkdirSync(hotelDir, { recursive: true });
  return path.join(hotelDir, "whatsapp_logs.json");
}

module.exports = {
  DATA_DIR,
  TEMPLATES_FILE,
  LOGS_FILE,
  AUTH_DIR,
  DEFAULT_TEMPLATES,
  SUPPORTED_PLACEHOLDERS,
  sanitizeHotelId,
  getHotelAuthDir,
  getHotelTemplatesFile,
  getHotelLogsFile,
};

