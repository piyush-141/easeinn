import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  BedDouble,
  CheckCircle2,
  Sparkles,
  AlertTriangle,
  UserCheck,
  Filter,
  Plus,
  RefreshCw,
} from 'lucide-react';
import { useHotel } from '../context/HotelContext';
import { RoomStatus } from '../types';

export const Rooms: React.FC = () => {
  const { rooms, updateRoomStatus, currentProperty } = useHotel();
  const navigate = useNavigate();
  const [statusFilter, setStatusFilter] = useState<'all' | RoomStatus>('all');
  const [selectedFloor, setSelectedFloor] = useState<'all' | number>('all');

  // Filtered rooms
  const filteredRooms = rooms.filter((r) => {
    const matchesStatus = statusFilter === 'all' || r.status === statusFilter;
    const matchesFloor = selectedFloor === 'all' || r.floor === selectedFloor;
    return matchesStatus && matchesFloor;
  });

  // Group by floor
  const floors = [1, 2];

  const getStatusBadge = (status: RoomStatus) => {
    switch (status) {
      case 'vacant':
        return (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
            <span className="w-2 h-2 rounded-full bg-emerald-500" />
            Vacant
          </span>
        );
      case 'occupied':
        return (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-indigo-50 text-indigo-700 border border-indigo-200">
            <span className="w-2 h-2 rounded-full bg-indigo-500" />
            Occupied
          </span>
        );
      case 'needs_cleaning':
        return (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-amber-50 text-amber-700 border border-amber-200">
            <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
            Needs Cleaning
          </span>
        );
      case 'reserved':
        return (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-sky-50 text-sky-700 border border-sky-200">
            <span className="w-2 h-2 rounded-full bg-sky-500" />
            Reserved
          </span>
        );
      default:
        return (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-rose-50 text-rose-700 border border-rose-200">
            <span className="w-2 h-2 rounded-full bg-rose-500" />
            Maintenance
          </span>
        );
    }
  };

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="font-outfit text-2xl font-bold text-slate-900">
            Room Status & Housekeeping
          </h1>
          <p className="text-xs text-slate-500">
            Live occupancy and room cleanliness management for {currentProperty.name}
          </p>
        </div>

        <button
          onClick={() => navigate('/checkin')}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-gradient-to-r from-brand-600 to-indigo-600 hover:from-brand-700 hover:to-indigo-700 text-white text-xs font-bold shadow-md shadow-brand-500/20 transition transform active:scale-95"
        >
          <UserCheck className="w-4 h-4" />
          <span>New Check-In</span>
        </button>
      </div>

      {/* Filter Toolbar (Inspired by UI inspo) */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-sm flex flex-wrap items-center justify-between gap-4">
        {/* Status Filters */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs font-semibold text-slate-400 mr-1 flex items-center gap-1">
            <Filter className="w-3.5 h-3.5" />
            Filter:
          </span>
          {[
            { id: 'all', label: 'All Rooms' },
            { id: 'vacant', label: 'Vacant', dot: 'bg-emerald-500' },
            { id: 'occupied', label: 'Occupied', dot: 'bg-indigo-500' },
            { id: 'needs_cleaning', label: 'Needs Cleaning', dot: 'bg-amber-500' },
            { id: 'reserved', label: 'Reserved', dot: 'bg-sky-500' },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setStatusFilter(tab.id as any)}
              className={`px-3 py-1.5 rounded-xl text-xs font-semibold flex items-center gap-2 transition ${
                statusFilter === tab.id
                  ? 'bg-slate-900 text-white shadow-sm'
                  : 'bg-slate-100/80 text-slate-600 hover:bg-slate-200/80'
              }`}
            >
              {tab.dot && <span className={`w-2 h-2 rounded-full ${tab.dot}`} />}
              <span>{tab.label}</span>
            </button>
          ))}
        </div>

        {/* Floor selector */}
        <div className="flex items-center gap-2">
          <span className="text-xs font-semibold text-slate-500">Floor:</span>
          {(['all', 1, 2] as const).map((floor) => (
            <button
              key={floor}
              onClick={() => setSelectedFloor(floor)}
              className={`px-3 py-1 rounded-lg text-xs font-semibold transition ${
                selectedFloor === floor
                  ? 'bg-brand-600 text-white'
                  : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
              }`}
            >
              {floor === 'all' ? 'All Floors' : `Floor ${floor}`}
            </button>
          ))}
        </div>
      </div>

      {/* Floors Room Cards */}
      {floors.map((floorNum) => {
        const floorRooms = filteredRooms.filter((r) => r.floor === floorNum);
        if (floorRooms.length === 0 && selectedFloor !== 'all' && selectedFloor !== floorNum) {
          return null;
        }

        return (
          <div key={floorNum} className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="font-outfit text-base font-bold text-slate-800 flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-brand-500" />
                Floor {floorNum}
                <span className="text-xs text-slate-400 font-normal">
                  ({floorRooms.length} rooms)
                </span>
              </h3>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
              {floorRooms.map((room) => {
                const isCleaning = room.status === 'needs_cleaning';
                const isVacant = room.status === 'vacant';
                const isOccupied = room.status === 'occupied';

                return (
                  <div
                    key={room.id}
                    className={`p-4 rounded-2xl bg-white border transition-all relative flex flex-col justify-between ${
                      isCleaning
                        ? 'border-amber-300 shadow-sm shadow-amber-100 ring-2 ring-amber-400/20'
                        : isOccupied
                        ? 'border-indigo-200 shadow-sm'
                        : 'border-slate-200/80 shadow-sm hover:border-brand-300'
                    }`}
                  >
                    <div>
                      {/* Top Row: Room number & status badge */}
                      <div className="flex items-start justify-between gap-1 mb-2">
                        <span className="font-outfit text-2xl font-black text-slate-900 tracking-tight">
                          {room.room_number}
                        </span>
                        {getStatusBadge(room.status)}
                      </div>

                      {/* Category & Rate */}
                      <p className="text-xs font-semibold text-slate-700 truncate">
                        {room.category_name}
                      </p>
                      <p className="text-[11px] text-slate-400 font-medium">
                        ₹{room.base_rate}/night
                      </p>

                      {/* Guest details if occupied */}
                      {room.current_stay && (
                        <div className="mt-3 pt-2.5 border-t border-slate-100">
                          <p className="text-[10px] text-slate-400 uppercase font-bold tracking-wider">
                            Current Guest
                          </p>
                          <p className="text-xs font-bold text-slate-800 truncate">
                            {room.current_stay.guest_name}
                          </p>
                          <p className="text-[10px] text-slate-500">
                            Out: {room.current_stay.expected_checkout}
                          </p>
                        </div>
                      )}
                    </div>

                    {/* Action buttons */}
                    <div className="mt-4 pt-3 border-t border-slate-100">
                      {isCleaning ? (
                        <button
                          onClick={() => updateRoomStatus(room.id, 'vacant')}
                          className="w-full py-1.5 px-2 rounded-xl bg-amber-500 hover:bg-amber-600 text-white text-[11px] font-bold shadow-sm flex items-center justify-center gap-1.5 transition"
                        >
                          <CheckCircle2 className="w-3.5 h-3.5" />
                          <span>Mark Clean</span>
                        </button>
                      ) : isVacant ? (
                        <button
                          onClick={() => navigate(`/checkin?room=${room.id}`)}
                          className="w-full py-1.5 px-2 rounded-xl bg-slate-900 hover:bg-brand-600 text-white text-[11px] font-bold transition flex items-center justify-center gap-1"
                        >
                          <UserCheck className="w-3.5 h-3.5" />
                          <span>Check In</span>
                        </button>
                      ) : (
                        <button
                          onClick={() => navigate('/checkout')}
                          className="w-full py-1.5 px-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-700 text-[11px] font-bold transition"
                        >
                          Details / Bill
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
};
