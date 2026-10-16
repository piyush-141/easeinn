// src/config/whatsapp.config.js
const path = require("path");

const DATA_DIR = path.join(__dirname, "../../data");
const TEMPLATES_FILE = path.join(DATA_DIR, "whatsapp_templates.json");
const LOGS_FILE = path.join(DATA_DIR, "whatsapp_logs.json");
const AUTH_DIR = path.join(__dirname, "../../.wwebjs_auth");

const DEFAULT_TEMPLATES = {
  checkin_welcome: {
    id: "checkin_welcome",
    name: "Check-in Welcome",
    description: "Sent automatically when a guest check-in is completed",
    enabled: true,
    category: "automated",
    trigger: "on_checkin",
    template:
      "Namaste {guestName}! 🙏 Welcome to {hotelName}.\n\n" +
      "We are delighted to have you stay with us! Your check-in to Room {roomNumber} is complete.\n" +
      "📅 Check-In: {checkInDate}\n" +
      "📅 Expected Check-Out: {checkOutDate}\n\n" +
      "If you need any housekeeping or front desk assistance, simply let our team know. We wish you a peaceful and comfortable stay!",
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
      "Your check-out from Room {roomNumber} has been successfully completed.\n" +
      "We hope you had a memorable stay with us. Safe travels on your onward journey, and we look forward to welcoming you back soon!",
  },
  booking_confirmation: {
    id: "booking_confirmation",
    name: "Booking Confirmation",
    description: "Sent when an advance room reservation or booking is created",
    enabled: true,
    category: "automated",
    trigger: "on_reservation",
    template:
      "Dear {guestName}, your reservation at {hotelName} is confirmed! 🏨\n\n" +
      "📋 Reservation Details:\n" +
      "• Room Assigned: {roomNumber}\n" +
      "• Arrival Date: {checkInDate}\n" +
      "• Departure Date: {checkOutDate}\n\n" +
      "Please carry a valid government ID for express check-in upon arrival. We look forward to hosting you!",
  },
  custom_notification: {
    id: "custom_notification",
    name: "Custom Guest Notification",
    description: "Sent manually by front desk staff for room service, alerts, or queries",
    enabled: true,
    category: "manual",
    trigger: "manual",
    template:
      "Hello {guestName}, greetings from {hotelName}! 🛎️\n\n" +
      "Regarding Room {roomNumber} (Stay: {checkInDate} to {checkOutDate}):\n" +
      "We have an update regarding your stay. Please contact front desk if you require any assistance.\n\n" +
      "Warm regards,\n{hotelName} Front Desk",
  },
};

const SUPPORTED_PLACEHOLDERS = [
  { key: "{guestName}", label: "Guest Name", sample: "Vikram Aditya Singh" },
  { key: "{hotelName}", label: "Hotel Name", sample: "EaseInn Boutique & Suites" },
  { key: "{roomNumber}", label: "Room Number", sample: "102" },
  { key: "{checkInDate}", label: "Check-in Date", sample: "16 Oct 2026, 12:00 PM" },
  { key: "{checkOutDate}", label: "Check-out Date", sample: "18 Oct 2026, 11:00 AM" },
];

module.exports = {
  DATA_DIR,
  TEMPLATES_FILE,
  LOGS_FILE,
  AUTH_DIR,
  DEFAULT_TEMPLATES,
  SUPPORTED_PLACEHOLDERS,
};
