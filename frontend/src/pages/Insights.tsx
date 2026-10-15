import React from 'react';
import {
  BarChart3,
  TrendingUp,
  Download,
  Calendar,
  DollarSign,
  Users,
  BedDouble,
  PieChart,
} from 'lucide-react';
import { useHotel } from '../context/HotelContext';

export const Insights: React.FC = () => {
  const { currentProperty, getDashboardStats, rooms, stays } = useHotel();
  const stats = getDashboardStats();

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="font-outfit text-2xl font-bold text-slate-900 flex items-center gap-2">
            <BarChart3 className="w-6 h-6 text-brand-600" />
            Performance Insights & Analytics
          </h1>
          <p className="text-xs text-slate-500">
            Occupancy trends, revenue channels, and guest demographics for {currentProperty.name}
          </p>
        </div>

        <button
          onClick={() => window.print()}
          className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-white border border-slate-200 hover:bg-slate-50 text-slate-700 text-xs font-bold shadow-sm transition"
        >
          <Download className="w-4 h-4 text-brand-600" />
          <span>Export Analytics Report</span>
        </button>
      </div>

      {/* Overview Stat Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        <div className="bg-white p-5 rounded-3xl border border-slate-200/80 shadow-sm">
          <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
            Current Occupancy
          </span>
          <h3 className="font-outfit text-3xl font-extrabold text-slate-900 mt-1">
            {stats.occupancy_rate}%
          </h3>
          <p className="text-[11px] text-emerald-600 font-bold flex items-center gap-1 mt-1">
            <TrendingUp className="w-3.5 h-3.5" />
            +8.4% from last week
          </p>
        </div>

        <div className="bg-white p-5 rounded-3xl border border-slate-200/80 shadow-sm">
          <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
            Avg Length of Stay (ALOS)
          </span>
          <h3 className="font-outfit text-3xl font-extrabold text-slate-900 mt-1">
            2.4 <span className="text-base font-normal text-slate-500">Nights</span>
          </h3>
          <p className="text-[11px] text-slate-400 font-medium mt-1">
            Steady corporate and leisure bookings
          </p>
        </div>

        <div className="bg-white p-5 rounded-3xl border border-slate-200/80 shadow-sm">
          <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
            Total Revenue Today
          </span>
          <h3 className="font-outfit text-3xl font-extrabold text-brand-600 mt-1">
            ₹{stats.revenue_today.toLocaleString('en-IN')}
          </h3>
          <p className="text-[11px] text-emerald-600 font-bold flex items-center gap-1 mt-1">
            <TrendingUp className="w-3.5 h-3.5" />
            Active advance folios collected
          </p>
        </div>

        <div className="bg-white p-5 rounded-3xl border border-slate-200/80 shadow-sm">
          <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider">
            OCR Auto-Verification Rate
          </span>
          <h3 className="font-outfit text-3xl font-extrabold text-indigo-600 mt-1">
            98.2%
          </h3>
          <p className="text-[11px] text-indigo-700 font-bold mt-1">
            IITR Multi-Pass Tesseract Engine
          </p>
        </div>
      </div>

      {/* Visual Analytics Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Weekly Occupancy Trend */}
        <div className="bg-white rounded-3xl border border-slate-200/80 p-6 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-outfit text-base font-bold text-slate-900">
              Weekly Occupancy Trend
            </h3>
            <span className="text-xs text-slate-400 font-medium">Past 7 Days</span>
          </div>

          <div className="h-48 flex items-end justify-between gap-3 pt-6 px-2">
            {[
              { day: 'Mon', pct: 65 },
              { day: 'Tue', pct: 72 },
              { day: 'Wed', pct: 85 },
              { day: 'Thu', pct: 78 },
              { day: 'Fri', pct: 92 },
              { day: 'Sat', pct: 100 },
              { day: 'Sun', pct: 80 },
            ].map((bar) => (
              <div key={bar.day} className="flex-1 flex flex-col items-center gap-2">
                <span className="text-[10px] font-mono font-bold text-slate-500">{bar.pct}%</span>
                <div className="w-full bg-slate-100 rounded-xl h-36 flex items-end overflow-hidden p-1">
                  <div
                    style={{ height: `${bar.pct}%` }}
                    className={`w-full rounded-lg transition-all duration-500 ${
                      bar.pct >= 90
                        ? 'bg-gradient-to-t from-brand-600 to-indigo-500'
                        : 'bg-gradient-to-t from-indigo-400 to-brand-300'
                    }`}
                  />
                </div>
                <span className="text-xs font-bold text-slate-600">{bar.day}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Payment Channels Breakdown */}
        <div className="bg-white rounded-3xl border border-slate-200/80 p-6 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-outfit text-base font-bold text-slate-900">
              Payment Channels Share
            </h3>
            <span className="text-xs text-slate-400 font-medium">Month to Date</span>
          </div>

          <div className="space-y-4 pt-2">
            <div>
              <div className="flex justify-between text-xs font-bold mb-1">
                <span className="text-slate-700">UPI / QR Codes</span>
                <span className="text-brand-600">62% (₹1,45,200)</span>
              </div>
              <div className="w-full h-3 bg-slate-100 rounded-full overflow-hidden">
                <div className="h-full bg-brand-600 rounded-full w-[62%]" />
              </div>
            </div>

            <div>
              <div className="flex justify-between text-xs font-bold mb-1">
                <span className="text-slate-700">Credit / Debit Cards</span>
                <span className="text-indigo-600">26% (₹60,900)</span>
              </div>
              <div className="w-full h-3 bg-slate-100 rounded-full overflow-hidden">
                <div className="h-full bg-indigo-500 rounded-full w-[26%]" />
              </div>
            </div>

            <div>
              <div className="flex justify-between text-xs font-bold mb-1">
                <span className="text-slate-700">Cash Payments</span>
                <span className="text-emerald-600">12% (₹28,100)</span>
              </div>
              <div className="w-full h-3 bg-slate-100 rounded-full overflow-hidden">
                <div className="h-full bg-emerald-500 rounded-full w-[12%]" />
              </div>
            </div>
          </div>

          <div className="pt-4 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
            <span>Average folio settlement time:</span>
            <span className="font-bold text-slate-800">1.8 minutes</span>
          </div>
        </div>
      </div>
    </div>
  );
};
