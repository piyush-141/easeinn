// src/routes/whatsapp.routes.js
const express = require("express");
const router = express.Router();
const whatsappController = require("../controllers/whatsapp.controller");

// Status & Connection Management
router.get("/status", whatsappController.getStatus);
router.post("/connect", whatsappController.connect);
router.post("/disconnect", whatsappController.disconnect);

// Template Management
router.get("/templates", whatsappController.getTemplates);
router.put("/templates/:templateId", whatsappController.updateTemplate);
router.post("/templates/reset", whatsappController.resetTemplates);
router.post("/preview", whatsappController.previewTemplate);

// Manual & Dynamic Dispatch
router.post("/send", whatsappController.sendMessage);
router.get("/logs", whatsappController.getLogs);

// Automated Booking Workflow Hooks
router.post("/hook/checkin", whatsappController.onCheckIn);
router.post("/hook/checkout", whatsappController.onCheckOut);
router.post("/hook/reservation", whatsappController.onReservation);

module.exports = router;
