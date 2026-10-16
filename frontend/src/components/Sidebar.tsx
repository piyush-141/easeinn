import React from 'react';
import { NavLink } from 'react-router-dom';
import {
  LayoutDashboard,
  BedDouble,
  UserCheck,
  LogOut,
  Users,
  BarChart3,
  Building2,
  Sparkles,
  ShieldCheck,
  MessageSquare,
} from 'lucide-react';
import { useHotel } from '../context/HotelContext';

interface SidebarProps {
  onOpenAddHotel: () => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ onOpenAddHotel }) => {
  const { currentProperty } = useHotel();

  const navItems = [
    { to: '/', label: 'Dashboard', icon: LayoutDashboard },
    { to: '/rooms', label: 'Rooms & Housekeeping', icon: BedDouble },
    { to: '/checkin', label: 'Quick Check-In (OCR)', icon: UserCheck, highlight: true },
    { to: '/checkout', label: 'Check-Out & Billing', icon: LogOut },
    { to: '/guests', label: 'Guests Directory', icon: Users },
    { to: '/insights', label: 'Analytics & Insights', icon: BarChart3 },
    { to: '/whatsapp', label: 'WhatsApp Automation', icon: MessageSquare, badge: 'AUTO' },
    { to: '/hotels', label: 'Hotels & Branches', icon: Building2 },
  ];

  return (
    <aside className="w-64 bg-slate-900 text-white flex flex-col flex-shrink-0 border-r border-slate-800 select-none">
      {/* Brand Header */}
      <div className="p-5 border-b border-slate-800/80 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-brand-600 to-indigo-500 flex items-center justify-center shadow-lg shadow-brand-500/30">
            <Sparkles className="w-5 h-5 text-white" />
          </div>
          <div>
            <span className="font-outfit text-xl font-bold tracking-tight text-white flex items-center gap-1.5">
              EaseInn
              <span className="text-[10px] uppercase font-semibold bg-brand-500/20 text-brand-300 border border-brand-500/30 px-1.5 py-0.5 rounded">
                PMS
              </span>
            </span>
            <p className="text-xs text-slate-400 truncate max-w-[140px] font-medium">
              {currentProperty.name}
            </p>
          </div>
        </div>
      </div>

      {/* Active Property Badge */}
      <div className="px-4 py-3 mx-3 my-3 rounded-xl bg-slate-800/60 border border-slate-700/50 flex items-center justify-between">
        <div className="flex items-center gap-2 overflow-hidden">
          <div className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
          <div className="truncate text-xs">
            <p className="text-slate-300 font-medium truncate">{currentProperty.city}</p>
            <p className="text-[10px] text-slate-400">12 Rooms Active</p>
          </div>
        </div>
        <button
          onClick={onOpenAddHotel}
          className="text-[11px] font-semibold text-brand-300 hover:text-brand-200 bg-brand-500/20 hover:bg-brand-500/30 px-2 py-1 rounded-lg transition"
          title="Add another branch"
        >
          + Add
        </button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-2 space-y-1 overflow-y-auto">
        <p className="px-3 text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-2">
          Operations
        </p>
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) =>
              `flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all group ${
                isActive
                  ? 'bg-brand-600 text-white shadow-md shadow-brand-600/30'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/70'
              } ${item.highlight && !isActive ? 'text-brand-300 font-semibold' : ''}`
            }
          >
            {({ isActive }) => (
              <>
                <item.icon
                  className={`w-4 h-4 transition-transform group-hover:scale-110 ${
                    isActive ? 'text-white' : item.highlight ? 'text-brand-400' : 'text-slate-400'
                  }`}
                />
                <span className="flex-1 truncate">{item.label}</span>
                {item.highlight && (
                  <span className="text-[9px] font-bold uppercase bg-brand-400/20 text-brand-300 px-1.5 py-0.5 rounded-full border border-brand-400/30">
                    OCR
                  </span>
                )}
                {item.badge && (
                  <span className="text-[9px] font-bold uppercase bg-emerald-500/20 text-emerald-300 px-1.5 py-0.5 rounded-full border border-emerald-500/30">
                    {item.badge}
                  </span>
                )}
              </>
            )}
          </NavLink>
        ))}
      </nav>

      {/* ID Verification & Offline Status */}
      <div className="p-4 mx-3 mb-3 rounded-xl bg-gradient-to-br from-indigo-950/60 to-slate-900 border border-indigo-800/40">
        <div className="flex items-center gap-2 mb-1.5">
          <ShieldCheck className="w-4 h-4 text-brand-400" />
          <span className="text-xs font-semibold text-indigo-200">IITR OCR Engine</span>
        </div>
        <p className="text-[11px] text-slate-400 leading-relaxed">
          Tesseract multi-variant engine ready for Indian Aadhaar, PAN & Passports.
        </p>
      </div>
    </aside>
  );
};
