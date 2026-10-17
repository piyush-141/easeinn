import React, { useEffect, useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router-dom';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './lib/supabase';
import { HotelProvider } from './context/HotelContext';
import { Sidebar } from './components/Sidebar';
import { Header } from './components/Header';
import { AddHotelModal } from './components/AddHotelModal';

import { Dashboard } from './pages/Dashboard';
import { Rooms } from './pages/Rooms';
import { CheckIn } from './pages/CheckIn';
import { CheckOut } from './pages/CheckOut';
import { Guests } from './pages/Guests';
import { Insights } from './pages/Insights';
import { Hotels } from './pages/Hotels';
import { Login } from './pages/Login';
import { WhatsAppSettings } from './pages/WhatsAppSettings';

const Layout: React.FC<{ children: React.ReactNode; onOpenAddHotel: () => void }> = ({
  children,
  onOpenAddHotel,
}) => {
  const location = useLocation();
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(false);

  useEffect(() => {
    let active = true;
    supabase.auth.getSession().then(({ data }) => {
      if (active) {
        setSession(data.session);
        setAuthReady(true);
      }
    });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setAuthReady(true);
    });
    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, []);
  const isLoginPage = location.pathname === '/login';

  if (!authReady) return <div className="min-h-screen bg-slate-50" />;
  if (!isLoginPage && !session) return <Navigate to="/login" replace />;
  if (isLoginPage && session) return <Navigate to="/" replace />;

  if (isLoginPage) {
    return <>{children}</>;
  }

  return (
    <div className="flex h-screen bg-slate-50 overflow-hidden font-sans">
      {/* Left Sidebar */}
      <Sidebar onOpenAddHotel={onOpenAddHotel} />

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Top Header */}
        <Header onOpenAddHotel={onOpenAddHotel} />

        {/* Scrollable Page Body */}
        <main className="flex-1 overflow-y-auto p-6 md:p-8">
          {children}
        </main>
      </div>
    </div>
  );
};

export function App() {
  const [isAddHotelOpen, setIsAddHotelOpen] = useState(false);

  return (
    <HotelProvider>
      <BrowserRouter>
        <Layout onOpenAddHotel={() => setIsAddHotelOpen(true)}>
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/rooms" element={<Rooms />} />
            <Route path="/checkin" element={<CheckIn />} />
            <Route path="/checkout" element={<CheckOut />} />
            <Route path="/guests" element={<Guests />} />
            <Route path="/insights" element={<Insights />} />
            <Route path="/hotels" element={<Hotels onOpenAddHotel={() => setIsAddHotelOpen(true)} />} />
            <Route path="/whatsapp" element={<WhatsAppSettings />} />
            <Route path="/login" element={<Login />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Layout>
        <AddHotelModal isOpen={isAddHotelOpen} onClose={() => setIsAddHotelOpen(false)} />
      </BrowserRouter>
    </HotelProvider>
  );
}

export default App;
