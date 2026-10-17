import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Bell,
  Building2,
  Calendar,
  ChevronDown,
  UserCheck,
  Clock,
  Sparkles,
  MessageSquare,
  LogOut,
} from 'lucide-react';
import { useHotel } from '../context/HotelContext';
import { supabase } from '../lib/supabase';

interface HeaderProps {
  onOpenAddHotel: () => void;
}

export const Header: React.FC<HeaderProps> = ({ onOpenAddHotel }) => {
  const { currentProperty, properties, switchProperty, currentUser } = useHotel();
  const navigate = useNavigate();
  const [currentTime, setCurrentTime] = useState(new Date());
  const [propertyDropdownOpen, setPropertyDropdownOpen] = useState(false);

  useEffect(() => {
    const timer = setInterval(() => setCurrentTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  const formattedDate = currentTime.toLocaleDateString('en-IN', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });

  const formattedTime = currentTime.toLocaleTimeString('en-IN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });

  return (
    <header className="h-16 bg-white border-b border-slate-200 px-6 flex items-center justify-between z-10">
      {/* Left: Property Selector & Date */}
      <div className="flex items-center gap-6">
        {/* Hotel Switcher Dropdown */}
        <div className="relative">
          <button
            onClick={() => setPropertyDropdownOpen(!propertyDropdownOpen)}
            className="flex items-center gap-2.5 px-3 py-1.5 rounded-xl border border-slate-200 hover:border-slate-300 bg-slate-50/80 hover:bg-slate-100/80 transition text-sm font-semibold text-slate-800"
          >
            <Building2 className="w-4 h-4 text-brand-600" />
            <span className="truncate max-w-[180px]">{currentProperty.name}</span>
            <ChevronDown className="w-3.5 h-3.5 text-slate-400" />
          </button>

          {propertyDropdownOpen && (
            <div className="absolute left-0 mt-2 w-72 bg-white rounded-2xl shadow-xl border border-slate-200 p-2 z-50">
              <div className="px-3 py-2 text-xs font-semibold text-slate-400 uppercase tracking-wider">
                Select Property
              </div>
              <div className="space-y-1">
                {properties.map((prop) => (
                  <button
                    key={prop.id}
                    onClick={() => {
                      switchProperty(prop.id);
                      setPropertyDropdownOpen(false);
                    }}
                    className={`w-full text-left px-3 py-2 rounded-xl text-sm font-medium flex items-center justify-between transition ${
                      prop.id === currentProperty.id
                        ? 'bg-brand-50 text-brand-700 font-semibold'
                        : 'text-slate-700 hover:bg-slate-50'
                    }`}
                  >
                    <span className="truncate">{prop.name}</span>
                    {prop.id === currentProperty.id && (
                      <span className="w-2 h-2 rounded-full bg-brand-600" />
                    )}
                  </button>
                ))}
              </div>
              <div className="pt-2 mt-2 border-t border-slate-100">
                <button
                  onClick={() => {
                    setPropertyDropdownOpen(false);
                    onOpenAddHotel();
                  }}
                  className="w-full text-center py-2 px-3 text-xs font-semibold text-brand-600 hover:bg-brand-50 rounded-xl transition"
                >
                  + Add New Property / Branch
                </button>
              </div>
            </div>
          )}
        </div>

        {/* Live Date & Time Indicator */}
        <div className="hidden md:flex items-center gap-4 text-xs font-medium text-slate-500 border-l border-slate-200 pl-6">
          <div className="flex items-center gap-1.5">
            <Calendar className="w-3.5 h-3.5 text-slate-400" />
            <span>{formattedDate}</span>
          </div>
          <div className="flex items-center gap-1.5 text-slate-600 font-mono">
            <Clock className="w-3.5 h-3.5 text-brand-500" />
            <span>{formattedTime}</span>
          </div>
        </div>
      </div>

      {/* Right: Quick Checkin CTA & Profile */}
      <div className="flex items-center gap-3">
        <button
          onClick={() => { void supabase.auth.signOut(); }}
          className="flex items-center gap-1.5 rounded-xl border border-slate-200 px-3 py-2 text-xs font-semibold text-slate-600 transition hover:bg-slate-50 hover:text-red-600"
          title="Sign out"
        >
          <LogOut className="h-3.5 w-3.5" />
          <span className="hidden sm:inline">Sign out</span>
        </button>
        <button
          onClick={() => navigate('/whatsapp')}
          className="flex items-center gap-1.5 bg-emerald-50 hover:bg-emerald-100 text-emerald-800 border border-emerald-200 text-xs font-semibold px-3 py-2 rounded-xl transition shadow-xs active:scale-95"
          title="WhatsApp Automated Messaging Settings"
        >
          <MessageSquare className="w-3.5 h-3.5 text-emerald-600" />
          <span className="hidden sm:inline">WhatsApp</span>
        </button>

        <button
          onClick={() => navigate('/checkin')}
          className="flex items-center gap-2 bg-gradient-to-r from-brand-600 to-indigo-600 hover:from-brand-700 hover:to-indigo-700 text-white text-xs font-semibold px-4 py-2 rounded-xl shadow-md shadow-brand-500/20 transition-all hover:shadow-brand-500/30 transform active:scale-95"
        >
          <UserCheck className="w-4 h-4" />
          <span>Quick Check-In (OCR)</span>
        </button>

        {/* Staff Profile Pill */}
        <div className="flex items-center gap-2.5 pl-3 border-l border-slate-200">
          <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-brand-500 to-purple-400 text-white flex items-center justify-center font-bold text-xs shadow">
            {currentUser.full_name.charAt(0)}
          </div>
          <div className="hidden sm:block text-left">
            <p className="text-xs font-bold text-slate-800 leading-tight">
              {currentUser.full_name}
            </p>
            <p className="text-[10px] font-medium text-brand-600 capitalize">
              Front Desk Lead
            </p>
          </div>
        </div>
      </div>
    </header>
  );
};
