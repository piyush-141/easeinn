// src/lib/whatsappClient.ts
import {
  WhatsAppSystemStatus,
  WhatsAppTemplate,
  WhatsAppLogEntry,
  WhatsAppPlaceholder,
} from '../types';
function requestHeaders(json = false): Record<string, string> {
  return {
    ...(json ? { 'Content-Type': 'application/json' } : {}),
  };
}

function resolveBackendUrl(): string {
  const whatsappUrl = import.meta.env.VITE_WHATSAPP_API_URL || import.meta.env.VITE_OCR_API_URL;
  if (whatsappUrl && String(whatsappUrl).trim()) {
    return String(whatsappUrl).replace(/\/$/, '');
  }
  if (typeof window !== 'undefined') {
    const host = window.location.hostname;
    if (host === 'localhost' || host === '127.0.0.1') {
      return 'http://localhost:3001';
    }
  }
  const sharedBackendUrl = import.meta.env.VITE_OCR_SERVER_URL;
  if (sharedBackendUrl && String(sharedBackendUrl).trim()) {
    return String(sharedBackendUrl).replace(/\/$/, '');
  }
  return 'https://easeinn.onrender.com';
}

const BASE_URL = resolveBackendUrl();

export async function getWhatsAppStatus(): Promise<WhatsAppSystemStatus> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/status`, { headers: requestHeaders(), signal: AbortSignal.timeout(12000) });
  if (!res.ok) {
    throw new Error(`Failed to fetch WhatsApp status (${res.status})`);
  }
  return res.json();
}

export async function connectWhatsApp(): Promise<{ success: boolean; message: string }> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/connect`, {
    method: 'POST',
    headers: requestHeaders(true),
  });
  if (!res.ok) {
    throw new Error(`Failed to request WhatsApp connect (${res.status})`);
  }
  return res.json();
}

export async function disconnectWhatsApp(): Promise<{ success: boolean; message: string }> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/disconnect`, {
    method: 'POST',
    headers: requestHeaders(true),
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
  const res = await fetch(`${BASE_URL}/api/whatsapp/templates`, { headers: requestHeaders() });
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
    headers: requestHeaders(true),
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
    headers: requestHeaders(true),
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
    headers: requestHeaders(true),
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
    method: 'POST', headers: requestHeaders(true),
    body: JSON.stringify(payload), signal: AbortSignal.timeout(110000),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok && !data.error) data.error = `WhatsApp request failed (${res.status})`;
  if (data.success && data.accepted !== true) {
    return { ...data, success: false, error: 'WhatsApp did not confirm acceptance of the message.' };
  }
  return data;
}

export async function getWhatsAppLogs(limit: number = 50): Promise<WhatsAppLogEntry[]> {
  const res = await fetch(`${BASE_URL}/api/whatsapp/logs?limit=${limit}`, { headers: requestHeaders() });
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
      headers: requestHeaders(true),
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
  pdfBase64?: string;
  pdfFileName?: string;
  totalAmount?: number;
  amountPaid?: number;
  balanceDue?: number;
  paymentMethod?: string;
}): Promise<any> {
  try {
    const res = await fetch(`${BASE_URL}/api/whatsapp/hook/checkout`, {
      method: 'POST',
      headers: requestHeaders(true),
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
      headers: requestHeaders(true),
      body: JSON.stringify(data),
    });
    return await res.json();
  } catch (err: any) {
    console.warn('[WhatsApp] Reservation auto-trigger failed gracefully:', err.message);
    return { success: false, error: err.message };
  }
}
