// EaseInn PMS Data Types

export type UserRole = 'admin' | 'receptionist';

export type RoomStatus = 'vacant' | 'occupied' | 'reserved' | 'needs_cleaning' | 'maintenance';

export type IdType = 'aadhaar' | 'pan' | 'passport' | 'voter_id' | 'driving_license' | 'other';

export type PaymentMethod = 'cash' | 'upi' | 'card' | 'bank_transfer' | 'other';

export type PaymentType = 'advance' | 'partial' | 'full' | 'refund';

export interface Property {
  id: string;
  name: string;
  address?: string;
  city?: string;
  state?: string;
  pincode?: string;
  phone?: string;
  email?: string;
  gst_number?: string;
  currency: string;
  timezone: string;
  default_checkin_time: string;
  default_checkout_time: string;
  total_rooms?: number;
  created_at?: string;
}

export interface UserProfile {
  id: string;
  property_id?: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  email?: string;
}

export interface RoomCategory {
  id: string;
  property_id: string;
  name: string;
  base_rate: number;
  max_occupancy: number;
  description?: string;
}

export interface Room {
  id: string;
  property_id: string;
  category_id?: string;
  category_name?: string;
  room_number: string;
  floor: number;
  status: RoomStatus;
  rate_override?: number;
  base_rate?: number;
  is_active: boolean;
  current_stay?: {
    stay_id: string;
    guest_name: string;
    guest_phone?: string;
    check_in_at: string;
    expected_checkout?: string;
    nightly_rate: number;
  };
}

export interface Guest {
  id: string;
  property_id: string;
  full_name: string;
  phone?: string;
  email?: string;
  id_type?: IdType;
  id_number_masked?: string;
  id_number_hash?: string;
  date_of_birth?: string;
  gender?: 'male' | 'female' | 'other' | string;
  address?: string;
  pincode?: string;
  father_name?: string;
  notes?: string;
  id_document_path?: string;
  created_at?: string;
  stays_count?: number;
}

export interface Stay {
  id: string;
  property_id: string;
  reservation_id?: string;
  guest_id: string;
  room_id: string;
  guest?: Guest;
  room?: Room;
  check_in_at: string;
  check_out_at?: string;
  expected_checkout?: string;
  num_guests: number;
  nightly_rate: number;
  status: 'active' | 'checked_out';
  checked_in_by?: string;
  checked_out_by?: string;
  bill?: Bill;
}

export interface BillLineItem {
  id: string;
  bill_id: string;
  description: string;
  quantity: number;
  unit_price: number;
  amount: number;
  item_type: 'room_charge' | 'extra_charge' | 'tax' | 'discount';
}

export interface Payment {
  id: string;
  property_id: string;
  bill_id: string;
  amount: number;
  method: PaymentMethod;
  payment_type: PaymentType;
  reference?: string;
  recorded_by?: string;
  recorded_at: string;
  is_void: boolean;
}

export interface Bill {
  id: string;
  property_id: string;
  stay_id: string;
  bill_number: string;
  subtotal: number;
  tax_amount: number;
  discount_amount: number;
  total: number;
  amount_paid: number;
  outstanding: number;
  status: 'draft' | 'finalized' | 'void';
  line_items?: BillLineItem[];
  payments?: Payment[];
  created_at?: string;
}

export interface DashboardStats {
  total_rooms: number;
  vacant_rooms: number;
  occupied_rooms: number;
  reserved_rooms: number;
  cleaning_rooms: number;
  occupancy_rate: number;
  today_arrivals: number;
  today_departures: number;
  active_guests: number;
  revenue_today: number;
}

export interface OCRScanResult {
  success: boolean;
  document_type?: IdType | string;
  has_both_sides?: boolean;
  guest_data: {
    full_name: string;
    id_type: IdType;
    id_number: string;
    date_of_birth: string;
    gender: string;
    address: string;
    pincode: string;
    father_name?: string;
  };
  details?: {
    front?: {
      filename: string;
      confidence: string;
      extracted: Record<string, any>;
    } | null;
    back?: {
      filename: string;
      confidence: string;
      extracted: Record<string, any>;
    } | null;
  };
}

// WhatsApp Automation Types
export type WhatsAppStatus =
  | 'DISCONNECTED'
  | 'INITIALIZING'
  | 'QR_READY'
  | 'AUTHENTICATED'
  | 'CONNECTED'
  | 'AUTH_FAILURE'
  | 'ERROR';

export interface WhatsAppPlaceholder {
  key: string;
  label: string;
  sample: string;
}

export interface WhatsAppSystemStatus {
  status: WhatsAppStatus;
  isConnected: boolean;
  isReady: boolean;
  qrCodeDataUrl: string | null;
  hasActiveQr: boolean;
  connectedNumber: string | null;
  connectedPushname: string | null;
  lastStatusChange: string;
  initializationError: string | null;
  activeTemplatesCount: number;
  totalTemplatesCount: number;
  supportedPlaceholders: WhatsAppPlaceholder[];
}

export interface WhatsAppTemplate {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
  category: 'automated' | 'manual';
  trigger: 'on_checkin' | 'on_checkout' | 'on_reservation' | 'manual';
  template: string;
}

export interface WhatsAppLogEntry {
  id: string;
  timestamp: string;
  templateId: string;
  recipientPhone: string;
  status: 'SENT' | 'FAILED' | 'SKIPPED_DISABLED' | 'SKIPPED_DUPLICATE' | 'FAILED_CLIENT_NOT_CONNECTED';
  error?: string;
  messageId?: string;
  preview?: string;
  context?: Record<string, any>;
}
