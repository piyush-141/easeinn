import React, { useState } from 'react';
import { X, Building2, MapPin, Phone, Mail, Layers, Check } from 'lucide-react';
import { useHotel } from '../context/HotelContext';

interface AddHotelModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const AddHotelModal: React.FC<AddHotelModalProps> = ({ isOpen, onClose }) => {
  const { addNewProperty } = useHotel();
  const [name, setName] = useState('');
  const [address, setAddress] = useState('');
  const [city, setCity] = useState('Bengaluru');
  const [state, setState] = useState('Karnataka');
  const [phone, setPhone] = useState('+91 ');
  const [email, setEmail] = useState('');
  const [floors, setFloors] = useState(2);
  const [totalRooms, setTotalRooms] = useState(10);
  const [submitted, setSubmitted] = useState(false);

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;

    addNewProperty({
      name,
      address,
      city,
      state,
      phone,
      email,
      total_rooms: Number(totalRooms),
    });

    setSubmitted(true);
    setTimeout(() => {
      setSubmitted(false);
      onClose();
      // reset form
      setName('');
      setAddress('');
    }, 900);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-200">
      <div className="bg-white rounded-3xl shadow-2xl border border-slate-100 max-w-lg w-full overflow-hidden">
        {/* Modal Header */}
        <div className="px-6 py-5 bg-gradient-to-r from-brand-900 to-slate-900 text-white flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-brand-500/20 border border-brand-400/30 flex items-center justify-center">
              <Building2 className="w-5 h-5 text-brand-300" />
            </div>
            <div>
              <h3 className="font-outfit font-bold text-lg text-white">Add New Hotel / Branch</h3>
              <p className="text-xs text-slate-300">Register a new property under your PMS account</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="w-8 h-8 rounded-lg bg-white/10 hover:bg-white/20 text-slate-300 hover:text-white flex items-center justify-center transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Modal Body */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
              Property / Hotel Name *
            </label>
            <input
              type="text"
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. EaseInn Lakeview Heritage"
              className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
                City
              </label>
              <div className="relative">
                <MapPin className="w-4 h-4 text-slate-400 absolute left-3 top-3" />
                <input
                  type="text"
                  value={city}
                  onChange={(e) => setCity(e.target.value)}
                  className="w-full pl-9 pr-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
                />
              </div>
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
                State
              </label>
              <input
                type="text"
                value={state}
                onChange={(e) => setState(e.target.value)}
                className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
              Street Address
            </label>
            <input
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="e.g. 14 Airport Road, Near Metro"
              className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
                Reception Phone
              </label>
              <div className="relative">
                <Phone className="w-4 h-4 text-slate-400 absolute left-3 top-3" />
                <input
                  type="text"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  className="w-full pl-9 pr-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
                />
              </div>
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
                Email
              </label>
              <div className="relative">
                <Mail className="w-4 h-4 text-slate-400 absolute left-3 top-3" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="frontdesk@hotel.com"
                  className="w-full pl-9 pr-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
                />
              </div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4 pt-1">
            <div className="bg-slate-50 p-3 rounded-2xl border border-slate-200">
              <label className="block text-xs font-semibold text-slate-600 mb-1">Total Floors</label>
              <div className="flex items-center gap-2">
                <Layers className="w-4 h-4 text-brand-600" />
                <input
                  type="number"
                  min="1"
                  max="50"
                  value={floors}
                  onChange={(e) => setFloors(Number(e.target.value))}
                  className="w-full bg-white px-3 py-1.5 rounded-lg border border-slate-200 text-sm font-bold"
                />
              </div>
            </div>

            <div className="bg-slate-50 p-3 rounded-2xl border border-slate-200">
              <label className="block text-xs font-semibold text-slate-600 mb-1">Total Rooms</label>
              <div className="flex items-center gap-2">
                <Building2 className="w-4 h-4 text-brand-600" />
                <input
                  type="number"
                  min="1"
                  max="500"
                  value={totalRooms}
                  onChange={(e) => setTotalRooms(Number(e.target.value))}
                  className="w-full bg-white px-3 py-1.5 rounded-lg border border-slate-200 text-sm font-bold"
                />
              </div>
            </div>
          </div>

          {/* Footer Actions */}
          <div className="pt-4 flex items-center justify-end gap-3 border-t border-slate-100">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-slate-600 hover:bg-slate-100 text-sm font-semibold transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitted}
              className="px-5 py-2.5 rounded-xl bg-gradient-to-r from-brand-600 to-indigo-600 hover:from-brand-700 hover:to-indigo-700 text-white text-sm font-semibold shadow-md shadow-brand-500/20 transition flex items-center gap-2"
            >
              {submitted ? (
                <>
                  <Check className="w-4 h-4" />
                  <span>Created!</span>
                </>
              ) : (
                <span>Register & Activate</span>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
