import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Users,
  Search,
  ShieldCheck,
  Phone,
  Mail,
  MapPin,
  Calendar,
  BedDouble,
  UserCheck,
  Eye,
  Filter,
} from 'lucide-react';
import { useHotel } from '../context/HotelContext';
import { Guest } from '../types';
import { GuestProfileModal } from '../components/GuestProfileModal';

export const Guests: React.FC = () => {
  const { guests, stays, rooms } = useHotel();
  const navigate = useNavigate();

  const [searchQuery, setSearchQuery] = useState('');
  const [filterMode, setFilterMode] = useState<'all' | 'in_house' | 'past'>('all');
  const [selectedGuest, setSelectedGuest] = useState<Guest | null>(null);

  // Active stay guest IDs
  const activeGuestIds = new Set(
    stays.filter((s) => s.status === 'active').map((s) => s.guest_id)
  );

  const filteredGuests = guests.filter((g) => {
    const matchesQuery =
      g.full_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (g.phone && g.phone.includes(searchQuery)) ||
      (g.id_number_masked && g.id_number_masked.includes(searchQuery)) ||
      (g.address && g.address.toLowerCase().includes(searchQuery.toLowerCase()));

    const isInHouse = activeGuestIds.has(g.id);

    if (filterMode === 'in_house') return matchesQuery && isInHouse;
    if (filterMode === 'past') return matchesQuery && !isInHouse;
    return matchesQuery;
  });

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="font-outfit text-2xl font-bold text-slate-900 flex items-center gap-2">
            <Users className="w-6 h-6 text-brand-600" />
            Guest Directory & Verified ID Archive
          </h1>
          <p className="text-xs text-slate-500">
            Searchable profile archive of all guests registered via OCR check-in.
          </p>
        </div>

        <button
          onClick={() => navigate('/checkin')}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-gradient-to-r from-brand-600 to-indigo-600 hover:from-brand-700 hover:to-indigo-700 text-white text-xs font-bold shadow-md shadow-brand-500/20 transition transform active:scale-95"
        >
          <UserCheck className="w-4 h-4" />
          <span>New Guest Check-In</span>
        </button>
      </div>

      {/* Search & Filter Toolbar */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-sm flex flex-col sm:flex-row items-center justify-between gap-4">
        <div className="relative w-full sm:w-96">
          <Search className="w-4 h-4 text-slate-400 absolute left-3.5 top-3" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search by name, phone, ID number, or city..."
            className="w-full pl-10 pr-4 py-2 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-xs font-medium"
          />
        </div>

        <div className="flex items-center gap-2 w-full sm:w-auto overflow-x-auto">
          {[
            { id: 'all', label: 'All Guests' },
            { id: 'in_house', label: 'Currently In-House' },
            { id: 'past', label: 'Past Guests' },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setFilterMode(tab.id as any)}
              className={`px-3 py-1.5 rounded-xl text-xs font-bold transition flex-shrink-0 ${
                filterMode === tab.id
                  ? 'bg-brand-600 text-white shadow-sm'
                  : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Guest Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        {filteredGuests.length === 0 ? (
          <div className="col-span-full py-12 text-center text-slate-400 bg-white rounded-3xl border border-slate-200">
            <Users className="w-10 h-10 mx-auto mb-2 text-slate-300" />
            <p className="font-bold text-sm text-slate-600">No guests match your search</p>
            <p className="text-xs text-slate-400 mt-1">Try searching by partial name or phone number</p>
          </div>
        ) : (
          filteredGuests.map((guest) => {
            const isInHouse = activeGuestIds.has(guest.id);
            const activeStay = stays.find((s) => s.guest_id === guest.id && s.status === 'active');
            const room = rooms.find((r) => r.id === activeStay?.room_id);

            return (
              <div
                key={guest.id}
                className="bg-white rounded-3xl border border-slate-200/90 p-5 shadow-sm hover:shadow-md transition flex flex-col justify-between"
              >
                <div>
                  {/* Top: Avatar & In-House Badge */}
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex items-center gap-3">
                      <div className="w-12 h-12 rounded-2xl bg-gradient-to-tr from-brand-600 to-indigo-500 text-white font-bold text-lg flex items-center justify-center shadow-md shadow-brand-500/20">
                        {guest.full_name.charAt(0)}
                      </div>
                      <div>
                        <h3 className="font-bold text-sm text-slate-900 truncate max-w-[160px]">
                          {guest.full_name}
                        </h3>
                        <span className="text-[11px] text-slate-400 flex items-center gap-1">
                          <Phone className="w-3 h-3" />
                          {guest.phone || 'No phone'}
                        </span>
                      </div>
                    </div>

                    {isInHouse ? (
                      <span className="text-[10px] font-bold text-emerald-700 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded-full">
                        Room {room?.room_number}
                      </span>
                    ) : (
                      <span className="text-[10px] font-bold text-slate-400 bg-slate-100 px-2 py-0.5 rounded-full">
                        Past Guest
                      </span>
                    )}
                  </div>

                  {/* ID Verification Badge */}
                  <div className="p-3 rounded-2xl bg-indigo-50/60 border border-indigo-100/80 mb-3 text-xs flex items-center justify-between">
                    <div>
                      <span className="text-[10px] uppercase font-bold text-indigo-700">
                        {guest.id_type || 'Aadhaar'} Verified
                      </span>
                      <p className="font-mono font-bold text-slate-800 text-xs">
                        {guest.id_number_masked || 'XXXX-XXXX-8921'}
                      </p>
                    </div>
                    <ShieldCheck className="w-4 h-4 text-brand-600" />
                  </div>

                  {/* Address Snippet */}
                  {guest.address && (
                    <p className="text-[11px] text-slate-500 flex items-start gap-1.5 mb-2 line-clamp-2">
                      <MapPin className="w-3.5 h-3.5 text-slate-400 flex-shrink-0 mt-0.5" />
                      <span>{guest.address}</span>
                    </p>
                  )}
                </div>

                {/* Footer Action */}
                <div className="pt-3 border-t border-slate-100 flex items-center justify-between">
                  <span className="text-[11px] text-slate-400 font-medium">
                    {guest.stays_count || 1} stay{(guest.stays_count || 1) > 1 ? 's' : ''} total
                  </span>
                  <button
                    onClick={() => setSelectedGuest(guest)}
                    className="px-3 py-1.5 rounded-xl bg-slate-900 hover:bg-brand-600 text-white text-xs font-bold transition flex items-center gap-1.5"
                  >
                    <Eye className="w-3.5 h-3.5" />
                    <span>View Profile</span>
                  </button>
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* Guest Profile Drawer / Modal */}
      <GuestProfileModal guest={selectedGuest} onClose={() => setSelectedGuest(null)} />
    </div>
  );
};
