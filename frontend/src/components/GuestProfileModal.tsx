import React from 'react';
import { X, ShieldCheck, MapPin, Phone, Mail, Calendar, User, FileText, Clock, BedDouble } from 'lucide-react';
import { Guest } from '../types';

interface GuestProfileModalProps {
  guest: Guest | null;
  onClose: () => void;
}

export const GuestProfileModal: React.FC<GuestProfileModalProps> = ({ guest, onClose }) => {
  if (!guest) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-200">
      <div className="bg-white rounded-3xl shadow-2xl border border-slate-100 max-w-lg w-full overflow-hidden">
        {/* Header Banner */}
        <div className="relative px-6 pt-8 pb-6 bg-gradient-to-tr from-brand-900 via-indigo-900 to-slate-900 text-white">
          <button
            onClick={onClose}
            className="absolute top-4 right-4 w-8 h-8 rounded-full bg-white/10 hover:bg-white/20 text-white flex items-center justify-center transition"
          >
            <X className="w-4 h-4" />
          </button>

          <div className="flex items-center gap-4">
            <div className="w-16 h-16 rounded-2xl bg-gradient-to-tr from-brand-500 to-purple-400 text-white font-bold text-2xl flex items-center justify-center shadow-lg shadow-black/20 border-2 border-white/20">
              {guest.full_name.charAt(0)}
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="font-outfit font-bold text-xl text-white">{guest.full_name}</h3>
                <span className="flex items-center gap-1 bg-emerald-500/20 text-emerald-300 border border-emerald-400/30 text-[10px] font-bold uppercase px-2 py-0.5 rounded-full">
                  <ShieldCheck className="w-3 h-3 text-emerald-400" />
                  Verified
                </span>
              </div>
              <p className="text-xs text-slate-300 flex items-center gap-2 mt-1">
                <span>{guest.phone || 'No phone recorded'}</span>
                <span>•</span>
                <span className="capitalize">{guest.gender || 'Not specified'}</span>
              </p>
            </div>
          </div>
        </div>

        {/* Content Body */}
        <div className="p-6 space-y-5 max-h-[70vh] overflow-y-auto">
          {/* Government ID Verification Section */}
          <div className="p-4 rounded-2xl bg-gradient-to-br from-indigo-50/80 to-purple-50/50 border border-indigo-100 flex items-start justify-between">
            <div>
              <span className="text-[10px] font-bold uppercase tracking-wider text-indigo-700 bg-indigo-100/80 px-2 py-0.5 rounded-md">
                Government ID Record
              </span>
              <div className="mt-2">
                <p className="text-xs font-semibold text-slate-500 uppercase">
                  {guest.id_type || 'Aadhaar Card'}
                </p>
                <p className="text-base font-bold font-mono text-slate-800 tracking-wider">
                  {guest.id_number_masked || 'XXXX-XXXX-8921'}
                </p>
              </div>
              {guest.father_name && (
                <p className="text-xs text-slate-600 mt-1">
                  <span className="text-slate-400">Care of: </span>
                  {guest.father_name}
                </p>
              )}
            </div>
            <div className="w-9 h-9 rounded-xl bg-white shadow-sm flex items-center justify-center text-brand-600 border border-indigo-100">
              <ShieldCheck className="w-5 h-5 text-brand-600" />
            </div>
          </div>

          {/* Guest Personal Info */}
          <div className="grid grid-cols-2 gap-3 text-xs">
            <div className="p-3 rounded-xl bg-slate-50 border border-slate-100">
              <span className="text-slate-400 flex items-center gap-1.5 mb-1">
                <Calendar className="w-3.5 h-3.5 text-slate-400" />
                Date of Birth
              </span>
              <span className="font-semibold text-slate-800">
                {guest.date_of_birth || 'Not recorded'}
              </span>
            </div>

            <div className="p-3 rounded-xl bg-slate-50 border border-slate-100">
              <span className="text-slate-400 flex items-center gap-1.5 mb-1">
                <BedDouble className="w-3.5 h-3.5 text-slate-400" />
                Stay History
              </span>
              <span className="font-semibold text-slate-800">
                {guest.stays_count || 1} Total Stay{(guest.stays_count || 1) > 1 ? 's' : ''}
              </span>
            </div>
          </div>

          {/* Contact Details */}
          <div className="space-y-2 text-xs">
            {guest.email && (
              <div className="flex items-center gap-2.5 p-3 rounded-xl bg-slate-50 border border-slate-100 text-slate-700">
                <Mail className="w-4 h-4 text-brand-600 flex-shrink-0" />
                <span className="font-medium">{guest.email}</span>
              </div>
            )}

            <div className="flex items-start gap-2.5 p-3 rounded-xl bg-slate-50 border border-slate-100 text-slate-700">
              <MapPin className="w-4 h-4 text-brand-600 flex-shrink-0 mt-0.5" />
              <div>
                <p className="font-medium leading-relaxed">
                  {guest.address || 'Address verified from Aadhaar OCR'}
                </p>
                {guest.pincode && (
                  <p className="text-[11px] font-mono text-slate-500 font-semibold mt-0.5">
                    PIN: {guest.pincode}
                  </p>
                )}
              </div>
            </div>
          </div>

          {/* Staff Notes */}
          {guest.notes && (
            <div className="p-3 rounded-xl bg-amber-50/70 border border-amber-200/60 text-xs">
              <span className="font-bold text-amber-900 block mb-1">Special Preferences / Notes:</span>
              <p className="text-amber-800 leading-relaxed">{guest.notes}</p>
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="p-4 bg-slate-50 border-t border-slate-100 flex justify-end">
          <button
            onClick={onClose}
            className="px-5 py-2 rounded-xl bg-slate-900 hover:bg-slate-800 text-white text-xs font-semibold shadow transition"
          >
            Close Profile
          </button>
        </div>
      </div>
    </div>
  );
};
