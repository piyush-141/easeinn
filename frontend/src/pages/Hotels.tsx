import React from 'react';
import { Building2, MapPin, BedDouble, CheckCircle2, Plus, Sparkles, Phone, Mail } from 'lucide-react';
import { useHotel } from '../context/HotelContext';

interface HotelsProps {
  onOpenAddHotel: () => void;
}

export const Hotels: React.FC<HotelsProps> = ({ onOpenAddHotel }) => {
  const { properties, currentProperty, switchProperty } = useHotel();

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="font-outfit text-2xl font-bold text-slate-900 flex items-center gap-2">
            <Building2 className="w-6 h-6 text-brand-600" />
            Hotel Properties & Branches
          </h1>
          <p className="text-xs text-slate-500">
            Multi-property PMS management. Switch between branches or register a new hotel.
          </p>
        </div>

        <button
          onClick={onOpenAddHotel}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-gradient-to-r from-brand-600 to-indigo-600 hover:from-brand-700 hover:to-indigo-700 text-white text-xs font-bold shadow-md shadow-brand-500/20 transition transform active:scale-95"
        >
          <Plus className="w-4 h-4" />
          <span>Add New Property</span>
        </button>
      </div>

      {/* Property Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {properties.map((prop) => {
          const isActive = prop.id === currentProperty.id;

          return (
            <div
              key={prop.id}
              className={`rounded-3xl border bg-white overflow-hidden shadow-sm transition-all flex flex-col justify-between ${
                isActive
                  ? 'border-brand-500 ring-2 ring-brand-500/20 shadow-md'
                  : 'border-slate-200/90 hover:border-slate-300'
              }`}
            >
              {/* Hotel Visual Banner */}
              <div className="h-36 bg-gradient-to-r from-slate-900 via-indigo-950 to-brand-950 p-5 flex flex-col justify-between relative overflow-hidden">
                <div className="flex items-center justify-between z-10">
                  <span className="w-9 h-9 rounded-xl bg-white/10 backdrop-blur border border-white/20 flex items-center justify-center text-brand-300">
                    <Building2 className="w-5 h-5" />
                  </span>
                  {isActive && (
                    <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold bg-emerald-500/20 text-emerald-300 border border-emerald-400/40 backdrop-blur">
                      <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                      Active Shift
                    </span>
                  )}
                </div>

                <div className="z-10">
                  <h3 className="font-outfit text-lg font-bold text-white tracking-tight leading-tight">
                    {prop.name}
                  </h3>
                  <p className="text-xs text-slate-300 flex items-center gap-1 mt-0.5">
                    <MapPin className="w-3.5 h-3.5 text-brand-400" />
                    {prop.city}, {prop.state}
                  </p>
                </div>

                {/* Ambient glow */}
                <div className="absolute right-0 bottom-0 w-32 h-32 bg-brand-500/20 rounded-full blur-2xl pointer-events-none" />
              </div>

              {/* Property Details */}
              <div className="p-5 space-y-4">
                <div className="grid grid-cols-2 gap-3 text-xs">
                  <div className="p-3 rounded-2xl bg-slate-50 border border-slate-100">
                    <span className="text-slate-400 block mb-0.5">Room Capacity</span>
                    <span className="font-bold text-slate-800 flex items-center gap-1.5">
                      <BedDouble className="w-3.5 h-3.5 text-brand-600" />
                      {prop.total_rooms || 12} Rooms
                    </span>
                  </div>

                  <div className="p-3 rounded-2xl bg-slate-50 border border-slate-100">
                    <span className="text-slate-400 block mb-0.5">Timezone / Base</span>
                    <span className="font-bold text-slate-800 font-mono">
                      {prop.currency || 'INR'} • IST
                    </span>
                  </div>
                </div>

                {prop.address && (
                  <p className="text-xs text-slate-500 leading-relaxed">
                    {prop.address}
                  </p>
                )}

                {/* Footer Switch Action */}
                <div className="pt-3 border-t border-slate-100">
                  {isActive ? (
                    <div className="w-full py-2.5 rounded-xl bg-slate-100 text-slate-600 text-xs font-bold text-center flex items-center justify-center gap-2">
                      <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                      <span>Currently Managing This Hotel</span>
                    </div>
                  ) : (
                    <button
                      onClick={() => switchProperty(prop.id)}
                      className="w-full py-2.5 rounded-xl bg-slate-900 hover:bg-brand-600 text-white text-xs font-bold transition shadow-sm"
                    >
                      Switch to This Hotel
                    </button>
                  )}
                </div>
              </div>
            </div>
          );
        })}

        {/* Add New Property Card */}
        <div
          onClick={onOpenAddHotel}
          className="rounded-3xl border-2 border-dashed border-slate-300 hover:border-brand-500 bg-white p-8 flex flex-col items-center justify-center text-center cursor-pointer group transition min-h-[300px]"
        >
          <div className="w-14 h-14 rounded-2xl bg-brand-50 group-hover:bg-brand-100 text-brand-600 flex items-center justify-center mb-3 transition">
            <Plus className="w-7 h-7" />
          </div>
          <h3 className="font-outfit font-bold text-base text-slate-800 group-hover:text-brand-600 transition">
            Add Another Hotel Branch
          </h3>
          <p className="text-xs text-slate-400 max-w-xs mt-1">
            Configure rooms, floors, and rates for an additional property location.
          </p>
        </div>
      </div>
    </div>
  );
};
