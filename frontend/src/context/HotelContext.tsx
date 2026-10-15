import React, { createContext, useContext, useState, useEffect } from 'react';
import {
  Property,
  UserProfile,
  RoomCategory,
  Room,
  Guest,
  Stay,
  Bill,
  Payment,
  DashboardStats,
  RoomStatus,
  IdType,
  PaymentMethod,
} from '../types';

// Initial Demo Hotel
const DEMO_PROPERTY: Property = {
  id: 'a0000000-0000-0000-0000-000000000001',
  name: 'EaseInn Boutique & Suites',
  address: '88 MG Road, Indiranagar',
  city: 'Bengaluru',
  state: 'Karnataka',
  pincode: '560038',
  phone: '+91 98765 43210',
  email: 'frontdesk@easeinn.com',
  gst_number: '29ABCDE1234F1Z5',
  currency: 'INR',
  timezone: 'Asia/Kolkata',
  default_checkin_time: '12:00',
  default_checkout_time: '11:00',
  total_rooms: 12,
};

const DEMO_CATEGORIES: RoomCategory[] = [
  {
    id: 'b0000000-0000-0000-0000-000000000001',
    property_id: DEMO_PROPERTY.id,
    name: 'Standard Room',
    base_rate: 2200,
    max_occupancy: 2,
    description: 'Cozy room with queen bed, ensuite bath, and high-speed Wi-Fi',
  },
  {
    id: 'b0000000-0000-0000-0000-000000000002',
    property_id: DEMO_PROPERTY.id,
    name: 'Deluxe Room',
    base_rate: 3500,
    max_occupancy: 3,
    description: 'Spacious room with king bed, executive workspace, and private balcony',
  },
  {
    id: 'b0000000-0000-0000-0000-000000000003',
    property_id: DEMO_PROPERTY.id,
    name: 'Executive Suite',
    base_rate: 5500,
    max_occupancy: 4,
    description: 'Premium luxury suite with separate living area, bathtub, and complimentary minibar',
  },
];

const INITIAL_ROOMS: Room[] = [
  // Floor 1
  {
    id: 'r101',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[0].id,
    category_name: 'Standard Room',
    room_number: '101',
    floor: 1,
    status: 'vacant',
    base_rate: 2200,
    is_active: true,
  },
  {
    id: 'r102',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[0].id,
    category_name: 'Standard Room',
    room_number: '102',
    floor: 1,
    status: 'occupied',
    base_rate: 2200,
    is_active: true,
    current_stay: {
      stay_id: 'stay-001',
      guest_name: 'Vikram Aditya Singh',
      guest_phone: '+91 98450 11223',
      check_in_at: new Date(Date.now() - 24 * 3600 * 1000).toISOString(),
      expected_checkout: new Date(Date.now() + 2 * 24 * 3600 * 1000).toISOString().split('T')[0],
      nightly_rate: 2200,
    },
  },
  {
    id: 'r103',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[1].id,
    category_name: 'Deluxe Room',
    room_number: '103',
    floor: 1,
    status: 'vacant',
    base_rate: 3500,
    is_active: true,
  },
  {
    id: 'r104',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[1].id,
    category_name: 'Deluxe Room',
    room_number: '104',
    floor: 1,
    status: 'occupied',
    base_rate: 3500,
    is_active: true,
    current_stay: {
      stay_id: 'stay-002',
      guest_name: 'Ananya Deshmukh',
      guest_phone: '+91 97112 33445',
      check_in_at: new Date().toISOString(),
      expected_checkout: new Date(Date.now() + 24 * 3600 * 1000).toISOString().split('T')[0],
      nightly_rate: 3500,
    },
  },
  {
    id: 'r105',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[2].id,
    category_name: 'Executive Suite',
    room_number: '105',
    floor: 1,
    status: 'needs_cleaning',
    base_rate: 5500,
    is_active: true,
  },
  {
    id: 'r106',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[2].id,
    category_name: 'Executive Suite',
    room_number: '106',
    floor: 1,
    status: 'vacant',
    base_rate: 5500,
    is_active: true,
  },
  // Floor 2
  {
    id: 'r201',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[0].id,
    category_name: 'Standard Room',
    room_number: '201',
    floor: 2,
    status: 'vacant',
    base_rate: 2200,
    is_active: true,
  },
  {
    id: 'r202',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[0].id,
    category_name: 'Standard Room',
    room_number: '202',
    floor: 2,
    status: 'vacant',
    base_rate: 2200,
    is_active: true,
  },
  {
    id: 'r203',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[1].id,
    category_name: 'Deluxe Room',
    room_number: '203',
    floor: 2,
    status: 'vacant',
    base_rate: 3500,
    is_active: true,
  },
  {
    id: 'r204',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[1].id,
    category_name: 'Deluxe Room',
    room_number: '204',
    floor: 2,
    status: 'reserved',
    base_rate: 3500,
    is_active: true,
  },
  {
    id: 'r205',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[2].id,
    category_name: 'Executive Suite',
    room_number: '205',
    floor: 2,
    status: 'vacant',
    base_rate: 5500,
    is_active: true,
  },
  {
    id: 'r206',
    property_id: DEMO_PROPERTY.id,
    category_id: DEMO_CATEGORIES[2].id,
    category_name: 'Executive Suite',
    room_number: '206',
    floor: 2,
    status: 'vacant',
    base_rate: 5500,
    is_active: true,
  },
];

const INITIAL_GUESTS: Guest[] = [
  {
    id: 'c0000000-0000-0000-0000-000000000001',
    property_id: DEMO_PROPERTY.id,
    full_name: 'Vikram Aditya Singh',
    phone: '+91 98450 11223',
    email: 'vikram.singh@example.com',
    id_type: 'aadhaar',
    id_number_masked: 'XXXX-XXXX-8921',
    date_of_birth: '1989-08-14',
    gender: 'male',
    address: 'Flat 402, Sunshine Apartments, Sector 14, Gurugram',
    pincode: '122001',
    father_name: 'Mahesh Singh',
    notes: 'Prefers higher floor away from elevator. Frequent corporate traveler.',
    stays_count: 3,
  },
  {
    id: 'c0000000-0000-0000-0000-000000000002',
    property_id: DEMO_PROPERTY.id,
    full_name: 'Ananya Deshmukh',
    phone: '+91 97112 33445',
    email: 'ananya.d@example.com',
    id_type: 'passport',
    id_number_masked: 'ZXXXX491',
    date_of_birth: '1994-03-22',
    gender: 'female',
    address: '12 Prabhat Road, Shivaji Nagar, Pune',
    pincode: '411005',
    father_name: 'Suhas Deshmukh',
    notes: 'Late check-out requested on weekends.',
    stays_count: 1,
  },
];

const INITIAL_STAYS: Stay[] = [
  {
    id: 'stay-001',
    property_id: DEMO_PROPERTY.id,
    guest_id: INITIAL_GUESTS[0].id,
    room_id: 'r102',
    guest: INITIAL_GUESTS[0],
    check_in_at: new Date(Date.now() - 24 * 3600 * 1000).toISOString(),
    expected_checkout: new Date(Date.now() + 2 * 24 * 3600 * 1000).toISOString().split('T')[0],
    num_guests: 1,
    nightly_rate: 2200,
    status: 'active',
  },
  {
    id: 'stay-002',
    property_id: DEMO_PROPERTY.id,
    guest_id: INITIAL_GUESTS[1].id,
    room_id: 'r104',
    guest: INITIAL_GUESTS[1],
    check_in_at: new Date().toISOString(),
    expected_checkout: new Date(Date.now() + 24 * 3600 * 1000).toISOString().split('T')[0],
    num_guests: 2,
    nightly_rate: 3500,
    status: 'active',
  },
];

const INITIAL_BILLS: Bill[] = [
  {
    id: 'b-001',
    property_id: DEMO_PROPERTY.id,
    stay_id: 'stay-001',
    bill_number: 'INV-2026-0001',
    subtotal: 6600,
    tax_amount: 0,
    discount_amount: 0,
    total: 6600,
    amount_paid: 2200,
    outstanding: 4400,
    status: 'draft',
    line_items: [
      {
        id: 'li-01',
        bill_id: 'b-001',
        description: 'Room Stay (3 nights)',
        quantity: 3,
        unit_price: 2200,
        amount: 6600,
        item_type: 'room_charge',
      },
    ],
  },
  {
    id: 'b-002',
    property_id: DEMO_PROPERTY.id,
    stay_id: 'stay-002',
    bill_number: 'INV-2026-0002',
    subtotal: 3500,
    tax_amount: 0,
    discount_amount: 0,
    total: 3500,
    amount_paid: 3500,
    outstanding: 0,
    status: 'draft',
    line_items: [
      {
        id: 'li-02',
        bill_id: 'b-002',
        description: 'Room Stay (1 night)',
        quantity: 1,
        unit_price: 3500,
        amount: 3500,
        item_type: 'room_charge',
      },
    ],
  },
];

interface CheckInPayload {
  roomId: string;
  expectedCheckout: string;
  numGuests: number;
  nightlyRate: number;
  guestData: {
    fullName: string;
    phone: string;
    email?: string;
    idType: IdType;
    idNumber: string;
    dob?: string;
    gender?: string;
    address?: string;
    pincode?: string;
    fatherName?: string;
  };
  advanceAmount: number;
  paymentMethod: PaymentMethod;
  paymentReference?: string;
}

interface HotelContextType {
  properties: Property[];
  currentProperty: Property;
  currentUser: UserProfile;
  rooms: Room[];
  roomCategories: RoomCategory[];
  guests: Guest[];
  stays: Stay[];
  bills: Bill[];
  switchProperty: (propertyId: string) => void;
  addNewProperty: (prop: Partial<Property>) => void;
  updateRoomStatus: (roomId: string, status: RoomStatus) => void;
  checkIn: (payload: CheckInPayload) => { stayId: string; billNumber: string };
  checkOut: (stayId: string, paymentAmount?: number, paymentMethod?: PaymentMethod) => { success: boolean; bill: Bill };
  getDashboardStats: () => DashboardStats;
}

const HotelContext = createContext<HotelContextType | undefined>(undefined);

export const HotelProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [properties, setProperties] = useState<Property[]>([DEMO_PROPERTY]);
  const [currentProperty, setCurrentProperty] = useState<Property>(DEMO_PROPERTY);
  const [currentUser] = useState<UserProfile>({
    id: 'user-001',
    full_name: 'Devika Rao',
    role: 'receptionist',
    is_active: true,
    email: 'frontdesk@easeinn.com',
  });

  const [roomCategories] = useState<RoomCategory[]>(DEMO_CATEGORIES);
  const [rooms, setRooms] = useState<Room[]>(INITIAL_ROOMS);
  const [guests, setGuests] = useState<Guest[]>(INITIAL_GUESTS);
  const [stays, setStays] = useState<Stay[]>(INITIAL_STAYS);
  const [bills, setBills] = useState<Bill[]>(INITIAL_BILLS);

  const switchProperty = (propertyId: string) => {
    const found = properties.find((p) => p.id === propertyId);
    if (found) setCurrentProperty(found);
  };

  const addNewProperty = (prop: Partial<Property>) => {
    const newProp: Property = {
      id: `prop-${Date.now()}`,
      name: prop.name || 'New Hotel',
      address: prop.address || '',
      city: prop.city || 'Bengaluru',
      state: prop.state || 'Karnataka',
      currency: 'INR',
      timezone: 'Asia/Kolkata',
      default_checkin_time: '12:00',
      default_checkout_time: '11:00',
      total_rooms: prop.total_rooms || 10,
    };
    setProperties((prev) => [...prev, newProp]);
    setCurrentProperty(newProp);
  };

  const updateRoomStatus = (roomId: string, status: RoomStatus) => {
    setRooms((prev) =>
      prev.map((r) => {
        if (r.id === roomId) {
          return {
            ...r,
            status,
            current_stay: status === 'vacant' || status === 'needs_cleaning' ? undefined : r.current_stay,
          };
        }
        return r;
      })
    );
  };

  const checkIn = (payload: CheckInPayload) => {
    const guestId = `guest-${Date.now()}`;
    const stayId = `stay-${Date.now()}`;
    const billId = `bill-${Date.now()}`;
    const billNumber = `INV-2026-${String(bills.length + 1).padStart(4, '0')}`;

    // Mask ID number for privacy (preserve last 4 characters)
    const rawId = payload.guestData.idNumber || 'XXXX';
    const maskedId = rawId.length > 4 ? `XXXX-XXXX-${rawId.slice(-4)}` : rawId;

    // 1. Create or update guest
    const newGuest: Guest = {
      id: guestId,
      property_id: currentProperty.id,
      full_name: payload.guestData.fullName,
      phone: payload.guestData.phone,
      email: payload.guestData.email,
      id_type: payload.guestData.idType,
      id_number_masked: maskedId,
      date_of_birth: payload.guestData.dob,
      gender: payload.guestData.gender,
      address: payload.guestData.address,
      pincode: payload.guestData.pincode,
      father_name: payload.guestData.fatherName,
      stays_count: 1,
    };

    // Calculate nights
    const checkInDate = new Date();
    const checkOutDate = new Date(payload.expectedCheckout);
    const diffTime = Math.max(1, Math.ceil((checkOutDate.getTime() - checkInDate.getTime()) / (1000 * 60 * 60 * 24)));
    const totalAmount = diffTime * payload.nightlyRate;
    const advancePaid = payload.advanceAmount || 0;
    const outstanding = Math.max(0, totalAmount - advancePaid);

    // 2. Create Stay
    const targetRoom = rooms.find((r) => r.id === payload.roomId);
    const newStay: Stay = {
      id: stayId,
      property_id: currentProperty.id,
      guest_id: guestId,
      room_id: payload.roomId,
      guest: newGuest,
      room: targetRoom,
      check_in_at: new Date().toISOString(),
      expected_checkout: payload.expectedCheckout,
      num_guests: payload.numGuests,
      nightly_rate: payload.nightlyRate,
      status: 'active',
    };

    // 3. Create Bill
    const newBill: Bill = {
      id: billId,
      property_id: currentProperty.id,
      stay_id: stayId,
      bill_number: billNumber,
      subtotal: totalAmount,
      tax_amount: 0,
      discount_amount: 0,
      total: totalAmount,
      amount_paid: advancePaid,
      outstanding,
      status: 'draft',
      line_items: [
        {
          id: `li-${Date.now()}`,
          bill_id: billId,
          description: `Room Stay (${diffTime} night${diffTime > 1 ? 's' : ''})`,
          quantity: diffTime,
          unit_price: payload.nightlyRate,
          amount: totalAmount,
          item_type: 'room_charge',
        },
      ],
    };

    // State updates
    setGuests((prev) => [newGuest, ...prev]);
    setStays((prev) => [newStay, ...prev]);
    setBills((prev) => [newBill, ...prev]);

    // Update Room
    setRooms((prev) =>
      prev.map((r) => {
        if (r.id === payload.roomId) {
          return {
            ...r,
            status: 'occupied',
            current_stay: {
              stay_id: stayId,
              guest_name: newGuest.full_name,
              guest_phone: newGuest.phone,
              check_in_at: newStay.check_in_at,
              expected_checkout: payload.expectedCheckout,
              nightly_rate: payload.nightlyRate,
            },
          };
        }
        return r;
      })
    );

    return { stayId, billNumber };
  };

  const checkOut = (stayId: string, paymentAmount: number = 0, _paymentMethod: PaymentMethod = 'cash') => {
    const stay = stays.find((s) => s.id === stayId);
    if (!stay) throw new Error('Stay not found');

    const bill = bills.find((b) => b.stay_id === stayId);
    let updatedBill: Bill = bill || {
      id: `b-${Date.now()}`,
      property_id: currentProperty.id,
      stay_id: stayId,
      bill_number: `INV-2026-${Date.now()}`,
      subtotal: stay.nightly_rate,
      tax_amount: 0,
      discount_amount: 0,
      total: stay.nightly_rate,
      amount_paid: stay.nightly_rate,
      outstanding: 0,
      status: 'finalized',
    };

    if (bill) {
      const newPaid = bill.amount_paid + paymentAmount;
      const newOutstanding = Math.max(0, bill.total - newPaid);
      updatedBill = {
        ...bill,
        amount_paid: newPaid,
        outstanding: newOutstanding,
        status: 'finalized',
      };
      setBills((prev) => prev.map((b) => (b.id === bill.id ? updatedBill : b)));
    }

    // Mark stay checked out
    setStays((prev) =>
      prev.map((s) => (s.id === stayId ? { ...s, status: 'checked_out', check_out_at: new Date().toISOString() } : s))
    );

    // Mark room needs_cleaning
    setRooms((prev) =>
      prev.map((r) => {
        if (r.id === stay.room_id) {
          return {
            ...r,
            status: 'needs_cleaning',
            current_stay: undefined,
          };
        }
        return r;
      })
    );

    return { success: true, bill: updatedBill };
  };

  const getDashboardStats = (): DashboardStats => {
    const total = rooms.length;
    const vacant = rooms.filter((r) => r.status === 'vacant').length;
    const occupied = rooms.filter((r) => r.status === 'occupied').length;
    const reserved = rooms.filter((r) => r.status === 'reserved').length;
    const cleaning = rooms.filter((r) => r.status === 'needs_cleaning' || r.status === 'maintenance').length;
    const occupancyRate = total > 0 ? Math.round((occupied / total) * 100) : 0;

    const activeStays = stays.filter((s) => s.status === 'active');
    const totalGuests = activeStays.reduce((sum, s) => sum + (s.num_guests || 1), 0);

    const revenueToday = bills.reduce((sum, b) => sum + (b.amount_paid || 0), 0);

    return {
      total_rooms: total,
      vacant_rooms: vacant,
      occupied_rooms: occupied,
      reserved_rooms: reserved,
      cleaning_rooms: cleaning,
      occupancy_rate: occupancyRate,
      today_arrivals: 2,
      today_departures: 1,
      active_guests: totalGuests,
      revenue_today: revenueToday,
    };
  };

  return (
    <HotelContext.Provider
      value={{
        properties,
        currentProperty,
        currentUser,
        rooms,
        roomCategories,
        guests,
        stays,
        bills,
        switchProperty,
        addNewProperty,
        updateRoomStatus,
        checkIn,
        checkOut,
        getDashboardStats,
      }}
    >
      {children}
    </HotelContext.Provider>
  );
};

export const useHotel = () => {
  const context = useContext(HotelContext);
  if (!context) throw new Error('useHotel must be used within a HotelProvider');
  return context;
};
