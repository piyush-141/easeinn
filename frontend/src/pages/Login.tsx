import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Sparkles, Lock, Mail, ShieldCheck, ArrowRight } from 'lucide-react';
import { supabase } from '../lib/supabase';

export const Login: React.FC = () => {
  const navigate = useNavigate();
  const [email, setEmail] = useState('frontdesk@easeinn.com');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSigningIn, setIsSigningIn] = useState(false);

  const signIn = async (loginEmail: string, loginPassword: string) => {
    setError(null);
    setIsSigningIn(true);
    const { error: authError } = await supabase.auth.signInWithPassword({ email: loginEmail, password: loginPassword });
    setIsSigningIn(false);
    if (authError) {
      setError(authError.message);
      return;
    }
    navigate('/');
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    await signIn(email.trim(), password);
  };

  const handleDemoLogin = async () => {
    setEmail('frontdesk@easeinn.com');
    setPassword('easeinn2026');
    await signIn('frontdesk@easeinn.com', 'easeinn2026');
  };

  return (
    <div className="min-h-screen bg-slate-950 flex items-center justify-center p-4 relative overflow-hidden">
      {/* Background Decorative Ambient Gradients */}
      <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-brand-600/20 rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-indigo-600/15 rounded-full blur-3xl pointer-events-none" />

      <div className="max-w-md w-full bg-slate-900 border border-slate-800 rounded-3xl p-8 shadow-2xl relative z-10 text-white space-y-6">
        {/* Brand */}
        <div className="text-center space-y-2">
          <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-brand-600 to-indigo-500 flex items-center justify-center mx-auto shadow-lg shadow-brand-500/30">
            <Sparkles className="w-7 h-7 text-white" />
          </div>
          <h1 className="font-outfit text-3xl font-extrabold tracking-tight text-white">
            EaseInn PMS
          </h1>
          <p className="text-xs text-slate-400">
            Automated Indian ID OCR Check-In & Hotel Property Management
          </p>
        </div>

        {/* Form */}
        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider mb-1.5">
              Staff Email Address
            </label>
            <div className="relative">
              <Mail className="w-4 h-4 text-slate-500 absolute left-3.5 top-3.5" />
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-slate-800/80 border border-slate-700/80 text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
              />
            </div>
          </div>

          {error && <p role="alert" className="rounded-xl border border-red-800 bg-red-950/50 px-3 py-2 text-xs text-red-200">{error}</p>}

          <div>
            <label className="block text-xs font-semibold text-slate-300 uppercase tracking-wider mb-1.5">
              Password
            </label>
            <div className="relative">
              <Lock className="w-4 h-4 text-slate-500 absolute left-3.5 top-3.5" />
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-slate-800/80 border border-slate-700/80 text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
              />
            </div>
          </div>

          <div className="flex items-center justify-between text-xs text-slate-400">
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" defaultChecked className="rounded bg-slate-800 border-slate-700 text-brand-600 focus:ring-0" />
              <span>Remember shift session</span>
            </label>
            <a href="#reset" className="hover:text-brand-300 transition">Forgot?</a>
          </div>

          <button
            type="submit"
            disabled={isSigningIn}
            className="w-full py-3 rounded-xl bg-gradient-to-r from-brand-600 to-indigo-600 hover:from-brand-500 hover:to-indigo-500 text-white text-sm font-bold shadow-lg shadow-brand-500/25 transition transform active:scale-95 flex items-center justify-center gap-2"
          >
            <span>{isSigningIn ? 'Signing in…' : 'Sign In to Front Desk'}</span>
            <ArrowRight className="w-4 h-4" />
          </button>
        </form>

        {/* 1-Click Demo Login */}
        <div className="pt-3 border-t border-slate-800/80">
          <button
            type="button"
            onClick={handleDemoLogin}
            disabled={isSigningIn}
            className="w-full py-2.5 rounded-xl bg-white/5 hover:bg-white/10 border border-slate-700 text-xs font-bold text-slate-300 hover:text-white transition flex items-center justify-center gap-2"
          >
            <ShieldCheck className="w-4 h-4 text-brand-400" />
            <span>1-Click Demo Login (Receptionist)</span>
          </button>
        </div>
      </div>
    </div>
  );
};
