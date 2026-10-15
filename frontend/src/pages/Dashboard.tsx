import React from 'react';
import { useNavigate } from 'react-router-dom';
import {
  BedDouble,
  UserCheck,
  LogOut,
  Users,
  CheckCircle2,
  Clock,
  Sparkles,
  ArrowUpRight,
  TrendingUp,
  AlertTriangle,
  Receipt,
  ScanLine,
} from 'lucide-react';
import { useHotel } from '../context/HotelContext';

export const Dashboard: React.FC = () => {
  const { currentProperty, getDashboardStats, rooms, stays } = useHotel();
  const navigate = useNavigate();
  const stats = getDashboardStats();

  const activeStays = stays.filter((s) => s.status === 'active');

  return (
    <div className="space-y-6">
      {/* Welcome Banner */}
      <div className="relative overflow-hidden rounded-3xl bg-gradient-to-r from-brand-900 via-indigo-900 to-slate-900 p-8 text-white shadow-xl">
        <div className="relative z-10 max-w-2xl">
          <div className="inline-flex items-center gap-2 rounded-full bg-brand-500/20 border border-brand-400/30 px-3 py-1 text-xs font-semibold text-brand-300 mb-3">
            <Sparkles className="w-3.5 h-3.5" />
            <span>AI & OCR Powered PMS</span>
          </div>
          <h1 className="font-outfit text-3xl font-bold tracking-tight text-white mb-2">
            Welcome to {currentProperty.name}
          </h1>
          <p className="text-sm text-slate-300 leading-relaxed">
            Fast guest check-in with Indian ID auto-OCR (Aadhaar front+back, PAN, Passport).
            Real-time room occupancy and automated billing.
          </p>

          <div className="flex flex-wrap gap-3 mt-6">
            <button
              onClick={() => navigate('/checkin')}
              className="flex items-center gap-2 px-5 py-2.5 rounded-xl bg-gradient-to-r from-brand-500 to-indigo-500 hover:from-brand-600 hover:to-indigo-600 text-white text-xs font-bold shadow-lg shadow-brand-500/30 transition transform active:scale-95"
            >
              <ScanLine className="w-4 h-4" />
              <span>Start Quick Check-In</span>
            </button>
            <button
              onClick={() => navigate('/rooms')}
              className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-white/10 hover:bg-white/20 text-white text-xs font-semibold backdrop-blur transition"
            >
              <BedDouble className="w-4 h-4" />
              <span>View Floor Grid</span>
            </button>
          </div>
        </div>

        {/* Decorative background glow */}
        <div className="absolute right-0 top-0 w-96 h-96 bg-brand-600/20 rounded-full blur-3xl pointer-events-none -mr-20 -mt-20" />
      </div>

      {/* KPI Cards Row */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        {/* Total Rooms */}
        <div className="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm flex items-center justify-between hover:shadow-md transition">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Total Rooms</p>
            <h3 className="font-outfit text-2xl font-bold text-slate-900 mt-1">{stats.total_rooms}</h3>
            <span className="text-[11px] text-slate-400 font-medium">Across 2 active floors</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-slate-100 flex items-center justify-center text-slate-700">
            <BedDouble className="w-6 h-6" />
          </div>
        </div>

        {/* Occupied */}
        <div className="bg-white p-5 rounded-2xl border border-indigo-100 shadow-sm flex items-center justify-between hover:shadow-md transition">
          <div>
            <p className="text-xs font-semibold text-indigo-600 uppercase tracking-wider">Occupied</p>
            <div className="flex items-baseline gap-2 mt-1">
              <h3 className="font-outfit text-2xl font-bold text-indigo-900">{stats.occupied_rooms}</h3>
              <span className="text-xs font-bold text-indigo-700 bg-indigo-50 px-2 py-0.5 rounded-full">
                {stats.occupancy_rate}% Occupancy
              </span>
            </div>
            <span className="text-[11px] text-slate-400 font-medium">{stats.active_guests} In-house guests</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-indigo-50 flex items-center justify-center text-indigo-600">
            <TrendingUp className="w-6 h-6" />
          </div>
        </div>

        {/* Vacant Rooms */}
        <div className="bg-white p-5 rounded-2xl border border-emerald-100 shadow-sm flex items-center justify-between hover:shadow-md transition">
          <div>
            <p className="text-xs font-semibold text-emerald-600 uppercase tracking-wider">Available Vacant</p>
            <h3 className="font-outfit text-2xl font-bold text-emerald-900 mt-1">{stats.vacant_rooms}</h3>
            <span className="text-[11px] text-emerald-600 font-medium">Ready for immediate check-in</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-emerald-50 flex items-center justify-center text-emerald-600">
            <CheckCircle2 className="w-6 h-6" />
          </div>
        </div>

        {/* Housekeeping / Cleaning */}
        <div className="bg-white p-5 rounded-2xl border border-amber-100 shadow-sm flex items-center justify-between hover:shadow-md transition">
          <div>
            <p className="text-xs font-semibold text-amber-600 uppercase tracking-wider">Needs Cleaning</p>
            <h3 className="font-outfit text-2xl font-bold text-amber-900 mt-1">{stats.cleaning_rooms}</h3>
            <span className="text-[11px] text-amber-700 font-medium">Housekeeping alert</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-amber-50 flex items-center justify-center text-amber-600">
            <AlertTriangle className="w-6 h-6" />
          </div>
        </div>
      </div>

      {/* Quick Action Grid (Inspired by UI Inspo) */}
      <div>
        <h3 className="font-outfit text-base font-bold text-slate-800 mb-3">Front Desk Shortcuts</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {/* Quick Checkin CTA card */}
          <div
            onClick={() => navigate('/checkin')}
            className="cursor-pointer group p-5 rounded-2xl bg-gradient-to-br from-brand-600 to-indigo-700 text-white shadow-md shadow-brand-500/20 hover:shadow-xl hover:shadow-brand-500/30 transition-all transform hover:-translate-y-0.5"
          >
            <div className="flex items-center justify-between mb-4">
              <div className="w-10 h-10 rounded-xl bg-white/20 backdrop-blur flex items-center justify-center">
                <ScanLine className="w-5 h-5 text-white" />
              </div>
              <ArrowUpRight className="w-4 h-4 text-white/70 group-hover:text-white group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition" />
            </div>
            <h4 className="font-bold text-base text-white">Scan ID & Check-In</h4>
            <p className="text-xs text-brand-100 mt-1">
              Upload Aadhaar front + back for instant guest autofill
            </p>
          </div>

          {/* Rooms Grid shortcut */}
          <div
            onClick={() => navigate('/rooms')}
            className="cursor-pointer group p-5 rounded-2xl bg-white border border-slate-200/90 hover:border-brand-300 shadow-sm hover:shadow-md transition-all transform hover:-translate-y-0.5"
          >
            <div className="flex items-center justify-between mb-4">
              <div className="w-10 h-10 rounded-xl bg-indigo-50 flex items-center justify-center text-indigo-600">
                <BedDouble className="w-5 h-5" />
              </div>
              <ArrowUpRight className="w-4 h-4 text-slate-400 group-hover:text-brand-600 transition" />
            </div>
            <h4 className="font-bold text-base text-slate-800 group-hover:text-brand-600 transition">
              Room Housekeeping
            </h4>
            <p className="text-xs text-slate-500 mt-1">
              Floor-by-floor live room status & cleaning management
            </p>
          </div>

          {/* Check-Out shortcut */}
          <div
            onClick={() => navigate('/checkout')}
            className="cursor-pointer group p-5 rounded-2xl bg-white border border-slate-200/90 hover:border-brand-300 shadow-sm hover:shadow-md transition-all transform hover:-translate-y-0.5"
          >
            <div className="flex items-center justify-between mb-4">
              <div className="w-10 h-10 rounded-xl bg-emerald-50 flex items-center justify-center text-emerald-600">
                <Receipt className="w-5 h-5" />
              </div>
              <ArrowUpRight className="w-4 h-4 text-slate-400 group-hover:text-brand-600 transition" />
            </div>
            <h4 className="font-bold text-base text-slate-800 group-hover:text-brand-600 transition">
              Check-Out & Settle
            </h4>
            <p className="text-xs text-slate-500 mt-1">
              Bill breakdown, payment collection and room release
            </p>
          </div>

          {/* Guests Directory shortcut */}
          <div
            onClick={() => navigate('/guests')}
            className="cursor-pointer group p-5 rounded-2xl bg-white border border-slate-200/90 hover:border-brand-300 shadow-sm hover:shadow-md transition-all transform hover:-translate-y-0.5"
          >
            <div className="flex items-center justify-between mb-4">
              <div className="w-10 h-10 rounded-xl bg-purple-50 flex items-center justify-center text-purple-600">
                <Users className="w-5 h-5" />
              </div>
              <ArrowUpRight className="w-4 h-4 text-slate-400 group-hover:text-brand-600 transition" />
            </div>
            <h4 className="font-bold text-base text-slate-800 group-hover:text-brand-600 transition">
              Guests Directory
            </h4>
            <p className="text-xs text-slate-500 mt-1">
              Verified ID archive, contact cards and stay logs
            </p>
          </div>
        </div>
      </div>

      {/* Live Floor Overview & Active Stays Section */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Active In-House Stays */}
        <div className="lg:col-span-2 bg-white rounded-3xl border border-slate-200/80 p-6 shadow-sm">
          <div className="flex items-center justify-between mb-5">
            <div>
              <h3 className="font-outfit text-lg font-bold text-slate-900">Active In-House Stays</h3>
              <p className="text-xs text-slate-500">Currently checked-in guests</p>
            </div>
            <button
              onClick={() => navigate('/guests')}
              className="text-xs font-semibold text-brand-600 hover:text-brand-700 transition"
            >
              View All Guests →
            </button>
          </div>

          <div className="space-y-3">
            {activeStays.length === 0 ? (
              <p className="text-xs text-slate-400 py-6 text-center">No active stays recorded</p>
            ) : (
              activeStays.map((stay) => {
                const room = rooms.find((r) => r.id === stay.room_id);
                return (
                  <div
                    key={stay.id}
                    className="p-4 rounded-2xl bg-slate-50 border border-slate-100 flex items-center justify-between hover:bg-slate-100/70 transition"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-12 h-12 rounded-xl bg-brand-100 text-brand-700 font-bold flex flex-col items-center justify-center leading-tight">
                        <span className="text-[10px] uppercase font-semibold text-brand-500">Room</span>
                        <span className="text-base font-extrabold">{room?.room_number || '102'}</span>
                      </div>
                      <div>
                        <h4 className="font-bold text-sm text-slate-900">
                          {stay.guest?.full_name || 'Guest'}
                        </h4>
                        <p className="text-xs text-slate-500">
                          {room?.category_name} • Rate: ₹{stay.nightly_rate}/night
                        </p>
                      </div>
                    </div>

                    <div className="flex items-center gap-4">
                      <div className="text-right hidden sm:block">
                        <span className="text-[10px] text-slate-400 uppercase font-semibold">Expected Out</span>
                        <p className="text-xs font-semibold text-slate-700">
                          {stay.expected_checkout || 'Tomorrow'}
                        </p>
                      </div>
                      <button
                        onClick={() => navigate('/checkout')}
                        className="px-3 py-1.5 rounded-lg bg-white border border-slate-200 text-xs font-bold text-slate-700 hover:bg-brand-50 hover:text-brand-600 hover:border-brand-200 shadow-sm transition"
                      >
                        Check-Out
                      </button>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* Today's Reception Summary */}
        <div className="bg-white rounded-3xl border border-slate-200/80 p-6 shadow-sm flex flex-col justify-between">
          <div>
            <h3 className="font-outfit text-lg font-bold text-slate-900 mb-1">Today's Shift Log</h3>
            <p className="text-xs text-slate-500 mb-5">Front desk daily operations summary</p>

            <div className="space-y-4">
              <div className="p-3.5 rounded-2xl bg-brand-50/60 border border-brand-100 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-xl bg-brand-500 text-white flex items-center justify-center">
                    <UserCheck className="w-4 h-4" />
                  </div>
                  <div>
                    <p className="text-xs font-bold text-brand-900">Arrivals Today</p>
                    <p className="text-[11px] text-brand-700">2 Check-ins registered</p>
                  </div>
                </div>
                <span className="font-mono text-lg font-bold text-brand-900">2</span>
              </div>

              <div className="p-3.5 rounded-2xl bg-indigo-50/60 border border-indigo-100 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-xl bg-indigo-500 text-white flex items-center justify-center">
                    <LogOut className="w-4 h-4" />
                  </div>
                  <div>
                    <p className="text-xs font-bold text-indigo-900">Departures Due</p>
                    <p className="text-[11px] text-indigo-700">1 Guest checking out</p>
                  </div>
                </div>
                <span className="font-mono text-lg font-bold text-indigo-900">1</span>
              </div>

              <div className="p-3.5 rounded-2xl bg-emerald-50/60 border border-emerald-100 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-xl bg-emerald-500 text-white flex items-center justify-center">
                    <Receipt className="w-4 h-4" />
                  </div>
                  <div>
                    <p className="text-xs font-bold text-emerald-900">Collection Today</p>
                    <p className="text-[11px] text-emerald-700">Cash, UPI & Card payments</p>
                  </div>
                </div>
                <span className="font-mono text-lg font-bold text-emerald-900">
                  ₹{stats.revenue_today.toLocaleString('en-IN')}
                </span>
              </div>
            </div>
          </div>

          <div className="mt-6 pt-4 border-t border-slate-100 text-center">
            <p className="text-[11px] text-slate-400">
              EaseInn PMS • Version 1.0.0
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};
