// src/lib/whatsappClient.ts
import {
  WhatsAppSystemStatus,
  WhatsAppTemplate,
  WhatsAppLogEntry,
  WhatsAppPlaceholder,
} from '../types';

const BASE_URL =
  import.meta.env.VITE_OCR_API_URL ||
  import.meta.env.VITE_OCR_SERVER_URL ||
  'http://localhost:3001';

export async function getWhatsAppStatus(): Promise<WhatsAppSystemStatus> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/status`);
  if (!res.ok) {
    throw new Error(`Failed to fetch WhatsApp status (${res.status})`);
  }
  return res.json();
}

export async function connectWhatsApp(): Promise<{ success: boolean; message: string }> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/connect`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) {
    throw new Error(`Failed to request WhatsApp connect (${res.status})`);
  }
  return res.json();
}

export async function disconnectWhatsApp(): Promise<{ success: boolean; message: string }> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/disconnect`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) {
    throw new Error(`Failed to disconnect WhatsApp (${res.status})`);
  }
  return res.json();
}

export async function getWhatsAppTemplates(): Promise<{
  templates: Record<string, WhatsAppTemplate>;
  placeholders: WhatsAppPlaceholder[];
}> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/templates`);
  if (!res.ok) {
    throw new Error(`Failed to fetch WhatsApp templates (${res.status})`);
  }
  return res.json();
}

export async function updateWhatsAppTemplate(
  templateId: string,
  updates: Partial<WhatsAppTemplate>
): Promise<{ success: boolean; template: WhatsAppTemplate }> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/templates/${templateId}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(updates),
  });
  if (!res.ok) {
    throw new Error(`Failed to update template (${res.status})`);
  }
  return res.json();
}

export async function resetWhatsAppTemplates(): Promise<{
  success: boolean;
  templates: Record<string, WhatsAppTemplate>;
}> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/templates/reset`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) {
    throw new Error(`Failed to reset templates (${res.status})`);
  }
  return res.json();
}

export async function previewWhatsAppTemplate(
  templateId?: string,
  context?: Record<string, any>,
  templateString?: string
): Promise<string> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/preview`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ templateId, context, templateString }),
  });
  if (!res.ok) {
    throw new Error(`Failed to preview template (${res.status})`);
  }
  const data = await res.json();
  return data.preview || '';
}

export async function sendWhatsAppMessage(payload: {
  templateId?: string;
  recipientPhone: string;
  customMessage?: string;
  context?: Record<string, any>;
  stayId?: string;
  bypassDuplicateCheck?: boolean;
}): Promise<any> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/send`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return res.json();
}

export async function getWhatsAppLogs(limit: number = 50): Promise<WhatsAppLogEntry[]> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/logs?limit=${limit}`);
  if (!res.ok) {
    return [];
  }
  const data = await res.json();
  return data.logs || [];
}

/**
 * Trigger automated check-in WhatsApp message
 */
export async function triggerCheckInWhatsApp(data: {
  guestName: string;
  phone: string;
  hotelName: string;
  roomNumber: string;
  checkInDate: string;
  checkOutDate: string;
  stayId?: string;
}): Promise<any> {
  try {
    const res = await fetch(`${BASE_URL}/api/whatsapp/hook/checkin`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    return await res.json();
  } catch (err: any) {
    console.warn('[WhatsApp] Check-in auto-trigger failed gracefully:', err.message);
    return { success: false, error: err.message };
  }
}

/**
 * Trigger automated check-out WhatsApp message
 */
export async function triggerCheckOutWhatsApp(data: {
  guestName: string;
  phone: string;
  hotelName: string;
  roomNumber: string;
  checkInDate: string;
  checkOutDate: string;
  stayId?: string;
}): Promise<any> {
  try {
    const res = await fetch(`${BASE_URL}/api/whatsapp/hook/checkout`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    return await res.json();
  } catch (err: any) {
    console.warn('[WhatsApp] Check-out auto-trigger failed gracefully:', err.message);
    return { success: false, error: err.message };
  }
}

/**
 * Trigger automated reservation WhatsApp message
 */
export async function triggerReservationWhatsApp(data: {
  guestName: string;
  phone: string;
  hotelName: string;
  roomNumber: string;
  checkInDate: string;
  checkOutDate: string;
  stayId?: string;
}): Promise<any> {
  try {
    const res = await fetch(`${BASE_URL}/api/whatsapp/hook/reservation`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    return await res.json();
  } catch (err: any) {
    console.warn('[WhatsApp] Reservation auto-trigger failed gracefully:', err.message);
    return { success: false, error: err.message };
  }
}
