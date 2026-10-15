import React, { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  LogOut,
  Receipt,
  BedDouble,
  Calendar,
  CheckCircle2,
  CreditCard,
  Printer,
  Sparkles,
  ArrowRight,
  User,
  ShieldCheck,
} from 'lucide-react';
import { useHotel } from '../context/HotelContext';
import { PaymentMethod, Bill } from '../types';

export const CheckOut: React.FC = () => {
  const { rooms, stays, bills, checkOut, currentProperty } = useHotel();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const activeStays = stays.filter((s) => s.status === 'active');
  const paramStayId = searchParams.get('stay') || '';

  const [selectedStayId, setSelectedStayId] = useState<string>(
    paramStayId || (activeStays.length > 0 ? activeStays[0].id : '')
  );

  const selectedStay = stays.find((s) => s.id === selectedStayId);
  const selectedRoom = rooms.find((r) => r.id === selectedStay?.room_id);
  const selectedBill = bills.find((b) => b.stay_id === selectedStayId);

  // Billing calculation
  const checkInDate = selectedStay ? new Date(selectedStay.check_in_at) : new Date();
  const checkoutDate = new Date();
  const nightsStayed = Math.max(
    1,
    Math.ceil((checkoutDate.getTime() - checkInDate.getTime()) / (1000 * 60 * 60 * 24))
  );

  const roomTotal = nightsStayed * (selectedStay?.nightly_rate || 2200);
  const advancePaid = selectedBill?.amount_paid || 0;
  const balanceDue = Math.max(0, roomTotal - advancePaid);

  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('upi');
  const [checkoutDone, setCheckoutDone] = useState<boolean>(false);
  const [finalInvoice, setFinalInvoice] = useState<Bill | null>(null);

  const handleCheckoutSubmit = () => {
    if (!selectedStayId) return;
    const res = checkOut(selectedStayId, balanceDue, paymentMethod);
    setFinalInvoice(res.bill);
    setCheckoutDone(true);
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="font-outfit text-2xl font-bold text-slate-900 flex items-center gap-2">
            <LogOut className="w-6 h-6 text-brand-600" />
            Check-Out & Final Billing
          </h1>
          <p className="text-xs text-slate-500">
            Settle folio balance, finalize invoice, and release room to housekeeping.
          </p>
        </div>
      </div>

      {activeStays.length === 0 ? (
        <div className="bg-white rounded-3xl border border-slate-200 p-12 text-center space-y-3">
          <div className="w-12 h-12 rounded-2xl bg-slate-100 flex items-center justify-center mx-auto text-slate-400">
            <BedDouble className="w-6 h-6" />
          </div>
          <h3 className="font-outfit font-bold text-base text-slate-700">No Active Stays</h3>
          <p className="text-xs text-slate-400 max-w-sm mx-auto">
            All rooms are currently vacant or awaiting guests. Check-in a new guest from the dashboard.
          </p>
          <button
            onClick={() => navigate('/checkin')}
            className="px-4 py-2 rounded-xl bg-brand-600 hover:bg-brand-700 text-white text-xs font-bold transition"
          >
            Start Check-In
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Active Stays Selector List */}
          <div className="bg-white rounded-3xl border border-slate-200/90 p-5 shadow-sm space-y-3">
            <h3 className="font-outfit text-sm font-bold text-slate-800 uppercase tracking-wider">
              Select Occupied Room
            </h3>

            <div className="space-y-2 max-h-[500px] overflow-y-auto pr-1">
              {activeStays.map((stay) => {
                const room = rooms.find((r) => r.id === stay.room_id);
                const isSelected = selectedStayId === stay.id;
                return (
                  <div
                    key={stay.id}
                    onClick={() => setSelectedStayId(stay.id)}
                    className={`p-3.5 rounded-2xl border cursor-pointer transition flex items-center justify-between ${
                      isSelected
                        ? 'border-brand-600 bg-brand-50/70 ring-2 ring-brand-500/20 shadow-sm'
                        : 'border-slate-200 hover:border-slate-300 bg-white'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-xl bg-brand-100 text-brand-800 font-bold flex items-center justify-center text-sm">
                        {room?.room_number}
                      </div>
                      <div>
                        <h4 className="font-bold text-xs text-slate-900 truncate max-w-[130px]">
                          {stay.guest?.full_name || 'Guest'}
                        </h4>
                        <p className="text-[10px] text-slate-400">
                          {nightsStayed} night{nightsStayed > 1 ? 's' : ''} • Fl {room?.floor}
                        </p>
                      </div>
                    </div>
                    {isSelected && <CheckCircle2 className="w-4 h-4 text-brand-600" />}
                  </div>
                );
              })}
            </div>
          </div>

          {/* Checkout & Bill Breakdown Card */}
          <div className="lg:col-span-2 bg-white rounded-3xl border border-slate-200/90 p-6 shadow-sm space-y-6">
            <div className="flex items-center justify-between border-b border-slate-100 pb-4">
              <div>
                <span className="text-[10px] font-bold text-brand-600 bg-brand-50 border border-brand-200 px-2 py-0.5 rounded-md uppercase">
                  Room {selectedRoom?.room_number} • Folio
                </span>
                <h3 className="font-outfit text-xl font-bold text-slate-900 mt-1">
                  {selectedStay?.guest?.full_name}
                </h3>
              </div>
              <div className="text-right">
                <span className="text-[10px] text-slate-400 uppercase font-semibold block">Folio Number</span>
                <span className="font-mono text-xs font-bold text-slate-700">
                  {selectedBill?.bill_number || 'INV-2026-0001'}
                </span>
              </div>
            </div>

            {/* Stay Meta info */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 p-4 rounded-2xl bg-slate-50 border border-slate-100 text-xs">
              <div>
                <span className="text-slate-400 block mb-0.5">Check-In:</span>
                <span className="font-bold text-slate-800">
                  {new Date(selectedStay?.check_in_at || Date.now()).toLocaleDateString('en-IN')}
                </span>
              </div>
              <div>
                <span className="text-slate-400 block mb-0.5">Check-Out:</span>
                <span className="font-bold text-slate-800">
                  {new Date().toLocaleDateString('en-IN')} (Today)
                </span>
              </div>
              <div>
                <span className="text-slate-400 block mb-0.5">Room Category:</span>
                <span className="font-bold text-slate-800">{selectedRoom?.category_name}</span>
              </div>
            </div>

            {/* Invoice Line Items */}
            <div className="space-y-3">
              <h4 className="font-outfit text-xs font-bold text-slate-700 uppercase tracking-wider">
                Bill Breakdown
              </h4>

              <div className="rounded-2xl border border-slate-200 divide-y divide-slate-100 text-xs">
                <div className="p-3.5 flex justify-between items-center">
                  <div>
                    <p className="font-bold text-slate-800">Room Stay Charges</p>
                    <p className="text-[11px] text-slate-400">
                      {nightsStayed} night(s) × ₹{selectedStay?.nightly_rate}/night
                    </p>
                  </div>
                  <span className="font-mono font-bold text-slate-900">₹{roomTotal}</span>
                </div>

                <div className="p-3.5 flex justify-between items-center text-slate-600">
                  <span>Taxes (CGST + SGST)</span>
                  <span className="font-mono">Included</span>
                </div>

                <div className="p-3.5 flex justify-between items-center bg-emerald-50/50 text-emerald-800">
                  <div className="flex items-center gap-1.5 font-semibold">
                    <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
                    <span>Advance Payment Deducted</span>
                  </div>
                  <span className="font-mono font-bold text-emerald-700">- ₹{advancePaid}</span>
                </div>

                <div className="p-4 flex justify-between items-baseline bg-slate-900 text-white rounded-b-2xl">
                  <div>
                    <span className="font-bold text-sm block">Net Balance Due</span>
                    <span className="text-[10px] text-slate-400">Payable at reception</span>
                  </div>
                  <span className="font-mono text-2xl font-black text-brand-300">
                    ₹{balanceDue}
                  </span>
                </div>
              </div>
            </div>

            {/* Payment Mode for Balance */}
            {balanceDue > 0 && (
              <div className="space-y-2">
                <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider">
                  Payment Method for Remaining Balance
                </label>
                <div className="grid grid-cols-3 gap-2">
                  {[
                    { id: 'upi', label: 'UPI / QR' },
                    { id: 'cash', label: 'Cash' },
                    { id: 'card', label: 'Credit Card' },
                  ].map((m) => (
                    <button
                      key={m.id}
                      type="button"
                      onClick={() => setPaymentMethod(m.id as PaymentMethod)}
                      className={`py-2 px-3 rounded-xl text-xs font-bold transition ${
                        paymentMethod === m.id
                          ? 'bg-brand-600 text-white shadow-sm'
                          : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                      }`}
                    >
                      {m.label}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* Submit Checkout Button */}
            <div className="pt-2">
              <button
                onClick={handleCheckoutSubmit}
                className="w-full py-3.5 rounded-2xl bg-gradient-to-r from-slate-900 to-brand-900 hover:from-black hover:to-brand-950 text-white text-sm font-bold shadow-lg shadow-black/10 transition transform active:scale-95 flex items-center justify-center gap-2"
              >
                <Receipt className="w-4 h-4" />
                <span>Complete Checkout & Print Final Invoice</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* FINAL INVOICE MODAL */}
      {checkoutDone && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in zoom-in-95 duration-200">
          <div className="bg-white rounded-3xl shadow-2xl border border-slate-100 max-w-lg w-full p-6 space-y-4">
            <div className="text-center space-y-1">
              <div className="w-12 h-12 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center mx-auto mb-2">
                <CheckCircle2 className="w-8 h-8" />
              </div>
              <h3 className="font-outfit text-xl font-bold text-slate-900">
                Checkout Completed & Paid
              </h3>
              <p className="text-xs text-slate-500">
                Room {selectedRoom?.room_number} is now marked as <strong>Needs Cleaning</strong>
              </p>
            </div>

            {/* Printable Invoice Card */}
            <div className="p-5 rounded-2xl bg-slate-50 border border-slate-200 text-xs space-y-3 font-sans">
              <div className="flex justify-between items-start border-b border-slate-200 pb-2">
                <div>
                  <h4 className="font-bold text-slate-900">{currentProperty.name}</h4>
                  <p className="text-[10px] text-slate-400">{currentProperty.address}</p>
                </div>
                <div className="text-right">
                  <span className="font-mono font-bold text-brand-600">
                    {finalInvoice?.bill_number}
                  </span>
                  <p className="text-[10px] text-slate-400">
                    {new Date().toLocaleDateString('en-IN')}
                  </p>
                </div>
              </div>

              <div className="flex justify-between">
                <span className="text-slate-500">Guest:</span>
                <span className="font-bold text-slate-800">{selectedStay?.guest?.full_name}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Room:</span>
                <span className="font-bold text-slate-800">
                  {selectedRoom?.room_number} ({selectedRoom?.category_name})
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Duration:</span>
                <span className="font-bold text-slate-800">{nightsStayed} Night(s)</span>
              </div>
              <div className="flex justify-between pt-2 border-t border-slate-200 font-bold text-sm">
                <span>Total Amount Paid:</span>
                <span className="text-emerald-600 font-mono">₹{roomTotal}</span>
              </div>
            </div>

            <div className="flex gap-3 pt-2">
              <button
                onClick={() => window.print()}
                className="flex-1 py-2.5 rounded-xl border border-slate-200 hover:bg-slate-50 text-slate-700 text-xs font-bold transition flex items-center justify-center gap-1.5"
              >
                <Printer className="w-4 h-4" />
                <span>Print Bill</span>
              </button>
              <button
                onClick={() => {
                  setCheckoutDone(false);
                  navigate('/rooms');
                }}
                className="flex-1 py-2.5 rounded-xl bg-slate-900 hover:bg-slate-800 text-white text-xs font-bold transition"
              >
                Done / View Rooms
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
