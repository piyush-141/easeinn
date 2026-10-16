import React, { useState, useEffect, useRef } from 'react';
import {
  MessageSquare,
  QrCode,
  CheckCircle2,
  AlertTriangle,
  RefreshCw,
  LogOut,
  Send,
  Sparkles,
  ShieldAlert,
  Sliders,
  History,
  Copy,
  Check,
  Eye,
  Info,
  Smartphone,
  ExternalLink,
} from 'lucide-react';
import {
  getWhatsAppStatus,
  connectWhatsApp,
  disconnectWhatsApp,
  getWhatsAppTemplates,
  updateWhatsAppTemplate,
  resetWhatsAppTemplates,
  previewWhatsAppTemplate,
  sendWhatsAppMessage,
  getWhatsAppLogs,
} from '../lib/whatsappClient';
import {
  WhatsAppSystemStatus,
  WhatsAppTemplate,
  WhatsAppLogEntry,
  WhatsAppPlaceholder,
} from '../types';
import { useHotel } from '../context/HotelContext';

export const WhatsAppSettings: React.FC = () => {
  const { currentProperty } = useHotel();

  // Status & Connection State
  const [statusData, setStatusData] = useState<WhatsAppSystemStatus | null>(null);
  const [isLoadingStatus, setIsLoadingStatus] = useState<boolean>(true);
  const [isConnecting, setIsConnecting] = useState<boolean>(false);
  const [isDisconnecting, setIsDisconnecting] = useState<boolean>(false);

  // Templates State
  const [templates, setTemplates] = useState<Record<string, WhatsAppTemplate>>({});
  const [placeholders, setPlaceholders] = useState<WhatsAppPlaceholder[]>([]);
  const [activeTemplateId, setActiveTemplateId] = useState<string>('checkin_welcome');
  const [editedTemplates, setEditedTemplates] = useState<Record<string, string>>({});
  const [savingTemplateId, setSavingTemplateId] = useState<string | null>(null);
  const [templateSuccessMsg, setTemplateSuccessMsg] = useState<string | null>(null);

  // Live Previews
  const [previewText, setPreviewText] = useState<string>('');
  const [isPreviewLoading, setIsPreviewLoading] = useState<boolean>(false);

  // Test Dispatch Modal
  const [testPhone, setTestPhone] = useState<string>('');
  const [isSendingTest, setIsSendingTest] = useState<boolean>(false);
  const [testResult, setTestResult] = useState<{ success: boolean; message: string } | null>(null);

  // Logs State
  const [logs, setLogs] = useState<WhatsAppLogEntry[]>([]);
  const [isLoadingLogs, setIsLoadingLogs] = useState<boolean>(false);

  // Copied placeholder indicator
  const [copiedPlaceholder, setCopiedPlaceholder] = useState<string | null>(null);

  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Fetch status & templates on mount
  useEffect(() => {
    fetchStatus();
    fetchTemplates();
    fetchLogs();
  }, []);

  // Poll status when QR is active or initializing
  useEffect(() => {
    if (!statusData) return;
    const isPending =
      statusData.status === 'QR_READY' ||
      statusData.status === 'INITIALIZING' ||
      statusData.status === 'AUTHENTICATED';

    if (isPending) {
      const interval = setInterval(() => {
        fetchStatus(true);
      }, 3500);
      return () => clearInterval(interval);
    }
  }, [statusData?.status]);

  // Update live preview when active template or its text changes
  useEffect(() => {
    updatePreview();
  }, [activeTemplateId, editedTemplates, templates, currentProperty.name]);

  const fetchStatus = async (silent = false) => {
    if (!silent) setIsLoadingStatus(true);
    try {
      const data = await getWhatsAppStatus();
      setStatusData(data);
      if (data.supportedPlaceholders) {
        setPlaceholders(data.supportedPlaceholders);
      }
    } catch (err: any) {
      console.warn('[WhatsApp] Could not fetch status:', err.message);
    } finally {
      if (!silent) setIsLoadingStatus(false);
    }
  };

  const fetchTemplates = async () => {
    try {
      const data = await getWhatsAppTemplates();
      setTemplates(data.templates);
      if (data.placeholders) setPlaceholders(data.placeholders);

      const initialEdits: Record<string, string> = {};
      for (const [id, t] of Object.entries(data.templates)) {
        initialEdits[id] = t.template;
      }
      setEditedTemplates(initialEdits);
    } catch (err: any) {
      console.warn('[WhatsApp] Could not fetch templates:', err.message);
    }
  };

  const fetchLogs = async () => {
    setIsLoadingLogs(true);
    try {
      const data = await getWhatsAppLogs(30);
      setLogs(data);
    } catch (err: any) {
      console.warn('[WhatsApp] Could not fetch logs:', err.message);
    } finally {
      setIsLoadingLogs(false);
    }
  };

  const handleConnect = async () => {
    setIsConnecting(true);
    try {
      await connectWhatsApp();
      await fetchStatus();
    } catch (err: any) {
      alert(`Connect error: ${err.message}`);
    } finally {
      setIsConnecting(false);
    }
  };

  const handleDisconnect = async () => {
    if (!window.confirm('Are you sure you want to unlink the hotel WhatsApp account? Automated messages will pause until reconnected.')) {
      return;
    }
    setIsDisconnecting(true);
    try {
      await disconnectWhatsApp();
      await fetchStatus();
    } catch (err: any) {
      alert(`Disconnect error: ${err.message}`);
    } finally {
      setIsDisconnecting(false);
    }
  };

  const handleToggleTemplate = async (templateId: string, currentEnabled: boolean) => {
    try {
      const res = await updateWhatsAppTemplate(templateId, { enabled: !currentEnabled });
      if (res.success) {
        setTemplates((prev) => ({
          ...prev,
          [templateId]: res.template,
        }));
      }
    } catch (err: any) {
      alert(`Could not toggle template: ${err.message}`);
    }
  };

  const handleSaveTemplate = async (templateId: string) => {
    setSavingTemplateId(templateId);
    setTemplateSuccessMsg(null);
    try {
      const newText = editedTemplates[templateId] ?? templates[templateId]?.template;
      const res = await updateWhatsAppTemplate(templateId, { template: newText });
      if (res.success) {
        setTemplates((prev) => ({
          ...prev,
          [templateId]: res.template,
        }));
        setTemplateSuccessMsg('Template saved successfully!');
        setTimeout(() => setTemplateSuccessMsg(null), 3000);
      }
    } catch (err: any) {
      alert(`Could not save template: ${err.message}`);
    } finally {
      setSavingTemplateId(null);
    }
  };

  const handleResetTemplates = async () => {
    if (!window.confirm('Reset all 4 templates to standard EaseInn factory templates? Any custom text will be replaced.')) {
      return;
    }
    try {
      const res = await resetWhatsAppTemplates();
      if (res.success) {
        setTemplates(res.templates);
        const edits: Record<string, string> = {};
        for (const [id, t] of Object.entries(res.templates)) {
          edits[id] = t.template;
        }
        setEditedTemplates(edits);
        setTemplateSuccessMsg('Factory templates restored.');
        setTimeout(() => setTemplateSuccessMsg(null), 3000);
      }
    } catch (err: any) {
      alert(`Could not reset templates: ${err.message}`);
    }
  };

  const updatePreview = async () => {
    const raw = editedTemplates[activeTemplateId] ?? templates[activeTemplateId]?.template;
    if (!raw) return;

    setIsPreviewLoading(true);
    try {
      const preview = await previewWhatsAppTemplate(activeTemplateId, {
        guestName: 'Vikram Aditya Singh',
        hotelName: currentProperty.name,
        roomNumber: '102',
        checkInDate: '16 Oct 2026, 12:00 PM',
        checkOutDate: '18 Oct 2026, 11:00 AM',
      }, raw);
      setPreviewText(preview);
    } catch (_) {
      // Fallback local interpolation
      let fallback = raw
        .replace('{guestName}', 'Vikram Aditya Singh')
        .replace('{hotelName}', currentProperty.name)
        .replace('{roomNumber}', '102')
        .replace('{checkInDate}', '16 Oct 2026, 12:00 PM')
        .replace('{checkOutDate}', '18 Oct 2026, 11:00 AM');
      setPreviewText(fallback);
    } finally {
      setIsPreviewLoading(false);
    }
  };

  const handleInsertPlaceholder = (placeholderKey: string) => {
    const textarea = textareaRef.current;
    const currentVal = editedTemplates[activeTemplateId] ?? templates[activeTemplateId]?.template ?? '';

    if (!textarea) {
      setEditedTemplates((prev) => ({
        ...prev,
        [activeTemplateId]: currentVal + ' ' + placeholderKey,
      }));
      return;
    }

    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const updated = currentVal.substring(0, start) + placeholderKey + currentVal.substring(end);

    setEditedTemplates((prev) => ({
      ...prev,
      [activeTemplateId]: updated,
    }));

    setCopiedPlaceholder(placeholderKey);
    setTimeout(() => setCopiedPlaceholder(null), 2000);

    setTimeout(() => {
      textarea.focus();
      textarea.setSelectionRange(start + placeholderKey.length, start + placeholderKey.length);
    }, 0);
  };

  const handleSendTestMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!testPhone.trim()) {
      alert('Please enter a valid phone number with country code (e.g. +91 98450 11223)');
      return;
    }

    setIsSendingTest(true);
    setTestResult(null);

    try {
      const res = await sendWhatsAppMessage({
        templateId: activeTemplateId,
        recipientPhone: testPhone.trim(),
        bypassDuplicateCheck: true,
        context: {
          guestName: 'Test Guest',
          hotelName: currentProperty.name,
          roomNumber: '999',
          checkInDate: new Date().toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }),
          checkOutDate: new Date(Date.now() + 86400000).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }),
        },
      });

      if (res.success) {
        setTestResult({
          success: true,
          message: `Delivered successfully to ${res.recipient}! Check WhatsApp on recipient device.`,
        });
        fetchLogs();
      } else {
        setTestResult({
          success: false,
          message: res.error || res.message || 'Delivery failed.',
        });
        fetchLogs();
      }
    } catch (err: any) {
      setTestResult({
        success: false,
        message: err.message,
      });
    } finally {
      setIsSendingTest(false);
    }
  };

  const activeTemplate = templates[activeTemplateId];
  const activeTemplateText = editedTemplates[activeTemplateId] ?? activeTemplate?.template ?? '';

  return (
    <div className="max-w-6xl mx-auto space-y-8 pb-16">
      {/* Page Header */}
      <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2.5">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-emerald-600 to-teal-500 flex items-center justify-center text-white shadow-lg shadow-emerald-600/20">
              <MessageSquare className="w-5 h-5" />
            </div>
            <div>
              <h1 className="text-2xl font-bold font-outfit text-slate-900 tracking-tight flex items-center gap-2">
                WhatsApp Automated Messaging
                <span className="text-xs font-semibold px-2.5 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200">
                  One-Way
                </span>
              </h1>
              <p className="text-xs text-slate-500">
                Automated guest notifications on check-in, checkout, and reservations powered by WhatsApp Web
              </p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={() => fetchStatus()}
            disabled={isLoadingStatus}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-slate-600 bg-white hover:bg-slate-50 border border-slate-200 rounded-xl shadow-sm transition disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isLoadingStatus ? 'animate-spin' : ''}`} />
            Refresh
          </button>
        </div>
      </div>

      {/* ── 1. WHATSAPP ACCOUNT CONNECTION CARD ── */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden">
        <div className="p-6 md:p-8">
          <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6 pb-6 border-b border-slate-100">
            <div className="space-y-1">
              <div className="flex items-center gap-3">
                <span className="text-sm font-bold text-slate-900">Hotel WhatsApp Connection Status:</span>
                {statusData?.isConnected ? (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                    <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                    Connected & Ready
                  </span>
                ) : statusData?.status === 'QR_READY' ? (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold bg-sky-50 text-sky-700 border border-sky-200">
                    <span className="w-2 h-2 rounded-full bg-sky-500 animate-pulse" />
                    Waiting for Phone QR Scan
                  </span>
                ) : statusData?.status === 'INITIALIZING' ? (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold bg-amber-50 text-amber-700 border border-amber-200">
                    <span className="w-2 h-2 rounded-full bg-amber-500 animate-spin" />
                    Starting WhatsApp Browser...
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold bg-slate-100 text-slate-600 border border-slate-200">
                    <span className="w-2 h-2 rounded-full bg-slate-400" />
                    Disconnected
                  </span>
                )}
              </div>

              <p className="text-xs text-slate-500">
                {statusData?.isConnected ? (
                  <>
                    Logged in via {statusData.connectedPushname ? `"${statusData.connectedPushname}"` : 'Hotel Device'}
                    {statusData.connectedNumber && ` (+${statusData.connectedNumber})`}. Session is persisted securely in local auth storage.
                  </>
                ) : (
                  'Link your hotel front-desk or management WhatsApp number by scanning the QR code below.'
                )}
              </p>
            </div>

            <div className="flex items-center gap-3">
              {statusData?.isConnected ? (
                <button
                  onClick={handleDisconnect}
                  disabled={isDisconnecting}
                  className="flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-bold text-red-600 bg-red-50 hover:bg-red-100 border border-red-200 transition"
                >
                  <LogOut className="w-4 h-4" />
                  {isDisconnecting ? 'Unlinking...' : 'Disconnect Account'}
                </button>
              ) : (
                <button
                  onClick={handleConnect}
                  disabled={isConnecting || statusData?.status === 'INITIALIZING'}
                  className="flex items-center gap-2 px-5 py-2.5 rounded-xl text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 shadow-md shadow-emerald-600/20 transition disabled:opacity-50"
                >
                  <QrCode className="w-4 h-4" />
                  {isConnecting || statusData?.status === 'INITIALIZING'
                    ? 'Starting Browser...'
                    : statusData?.status === 'QR_READY'
                    ? 'Regenerate QR Code'
                    : 'Connect WhatsApp via QR'}
                </button>
              )}
            </div>
          </div>

          {/* QR Code Container when not connected */}
          {!statusData?.isConnected && (
            <div className="mt-6 pt-2">
              {statusData?.qrCodeDataUrl ? (
                <div className="flex flex-col md:flex-row items-center gap-8 bg-slate-50 p-6 md:p-8 rounded-2xl border border-slate-200">
                  <div className="bg-white p-4 rounded-2xl shadow-md border border-slate-200 flex-shrink-0">
                    <img
                      src={statusData.qrCodeDataUrl}
                      alt="WhatsApp Web QR Code"
                      className="w-56 h-56 object-contain"
                    />
                    <div className="mt-2 text-center">
                      <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">
                        Scan with WhatsApp
                      </span>
                    </div>
                  </div>

                  <div className="space-y-4 max-w-md">
                    <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                      <Smartphone className="w-5 h-5 text-emerald-600" />
                      How to Link Hotel WhatsApp:
                    </h3>
                    <ol className="text-xs text-slate-600 space-y-2.5 list-decimal list-inside font-medium leading-relaxed">
                      <li>Open <strong>WhatsApp</strong> on your hotel smartphone.</li>
                      <li>Tap <strong>Settings</strong> (iOS) or <strong>Menu ⋮</strong> (Android) &gt; <strong>Linked Devices</strong>.</li>
                      <li>Tap <strong>Link a Device</strong> and point your camera at this QR code.</li>
                      <li>Keep the phone connected to internet during initial synchronization.</li>
                    </ol>

                    <div className="p-3 bg-emerald-50/80 border border-emerald-200/60 rounded-xl text-[11px] text-emerald-800 flex items-start gap-2">
                      <CheckCircle2 className="w-4 h-4 text-emerald-600 flex-shrink-0 mt-0.5" />
                      <span>
                        Once paired, your session is saved in <code>.wwebjs_auth</code>. You will not need to scan again unless unlinked.
                      </span>
                    </div>
                  </div>
                </div>
              ) : (
                <div className="text-center py-8 bg-slate-50/60 rounded-2xl border border-dashed border-slate-200">
                  <QrCode className="w-12 h-12 text-slate-300 mx-auto mb-2" />
                  <p className="text-sm font-semibold text-slate-700">WhatsApp is Currently Disconnected</p>
                  <p className="text-xs text-slate-500 max-w-md mx-auto mt-1 mb-4">
                    Click "Connect WhatsApp via QR" to launch the headless session and generate an authentication QR code.
                  </p>
                  <button
                    onClick={handleConnect}
                    disabled={isConnecting}
                    className="inline-flex items-center gap-2 px-4 py-2 text-xs font-bold text-emerald-700 bg-emerald-100/80 hover:bg-emerald-100 border border-emerald-300/60 rounded-xl transition"
                  >
                    <QrCode className="w-3.5 h-3.5" />
                    Launch QR Scanner
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* ── 2. UNOFFICIAL AUTOMATION RISK & COMPLIANCE CALLOUT ── */}
      <div className="p-5 rounded-2xl bg-gradient-to-r from-amber-50 to-orange-50 border border-amber-200/80 text-amber-900 shadow-sm">
        <div className="flex items-start gap-3">
          <ShieldAlert className="w-5 h-5 text-amber-600 flex-shrink-0 mt-0.5" />
          <div className="space-y-1.5 text-xs">
            <h4 className="font-bold text-amber-950 text-sm">
              Operational Notice: Unofficial WhatsApp Web Automation Guidelines
            </h4>
            <p className="text-amber-800 leading-relaxed">
              EaseInn utilizes <code>whatsapp-web.js</code>, an open-source Puppeteer automation client that connects to WhatsApp Web without paid API subscription fees. To protect the hotel’s WhatsApp number against temporary blocks or spam penalties:
            </p>
            <ul className="list-disc list-inside space-y-1 text-amber-800/90 pl-1">
              <li>
                <strong>One-way transactional notices only:</strong> Send exclusively check-in greetings, checkout invoices, and confirmed booking vouchers.
              </li>
              <li>
                <strong>No promotional blasts:</strong> Never use this integration for bulk marketing or promotional spam.
              </li>
              <li>
                <strong>Built-in duplicate protection:</strong> EaseInn automatically suppresses identical triggers within 10 minutes to prevent accidental double-messages.
              </li>
            </ul>
          </div>
        </div>
      </div>

      {/* ── 3. TEMPLATES MANAGEMENT SECTION ── */}
      <div className="space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h2 className="text-lg font-bold text-slate-900 font-outfit">
              Notification Templates & Triggers
            </h2>
            <p className="text-xs text-slate-500">
              Customize dynamic messages and toggle automation for each stage of the guest journey.
            </p>
          </div>

          <button
            onClick={handleResetTemplates}
            className="self-start sm:self-auto text-xs font-semibold text-slate-500 hover:text-slate-700 underline transition"
          >
            Reset All to Defaults
          </button>
        </div>

        {/* Template Selectors */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {Object.values(templates).map((tpl) => {
            const isSelected = tpl.id === activeTemplateId;
            return (
              <div
                key={tpl.id}
                onClick={() => setActiveTemplateId(tpl.id)}
                className={`cursor-pointer p-4 rounded-2xl border transition-all relative ${
                  isSelected
                    ? 'bg-brand-50/70 border-brand-500 shadow-sm ring-1 ring-brand-500/30'
                    : 'bg-white hover:bg-slate-50/80 border-slate-200'
                }`}
              >
                <div className="flex items-center justify-between gap-2 mb-1.5">
                  <span className={`text-xs font-bold ${isSelected ? 'text-brand-900' : 'text-slate-800'}`}>
                    {tpl.name}
                  </span>
                  <label
                    onClick={(e) => e.stopPropagation()}
                    className="relative inline-flex items-center cursor-pointer"
                    title={tpl.enabled ? 'Enabled' : 'Disabled'}
                  >
                    <input
                      type="checkbox"
                      checked={tpl.enabled}
                      onChange={() => handleToggleTemplate(tpl.id, tpl.enabled)}
                      className="sr-only peer"
                    />
                    <div className="w-8 h-4.5 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-3.5 after:w-3.5 after:transition-all peer-checked:bg-emerald-500"></div>
                  </label>
                </div>

                <p className="text-[11px] text-slate-500 line-clamp-2 leading-relaxed">
                  {tpl.description}
                </p>

                <div className="mt-3 flex items-center justify-between text-[10px]">
                  <span
                    className={`font-semibold px-2 py-0.5 rounded-full ${
                      tpl.enabled
                        ? 'bg-emerald-100 text-emerald-800'
                        : 'bg-slate-100 text-slate-500'
                    }`}
                  >
                    {tpl.enabled ? 'Active' : 'Disabled'}
                  </span>

                  <span className="text-slate-400 font-medium">
                    {tpl.trigger === 'on_checkin'
                      ? 'Auto: Check-In'
                      : tpl.trigger === 'on_checkout'
                      ? 'Auto: Check-Out'
                      : tpl.trigger === 'on_reservation'
                      ? 'Auto: Reservation'
                      : 'Manual Trigger'}
                  </span>
                </div>
              </div>
            );
          })}
        </div>

        {/* Active Template Editor & Live Preview Card */}
        {activeTemplate && (
          <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden p-6 md:p-8">
            <div className="flex flex-col lg:flex-row gap-8">
              {/* Left Column: Editor & Placeholders */}
              <div className="flex-1 space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="text-base font-bold text-slate-900 font-outfit">
                      Editing: {activeTemplate.name}
                    </h3>
                    <p className="text-xs text-slate-500">{activeTemplate.description}</p>
                  </div>

                  <div className="flex items-center gap-2">
                    <span className="text-xs text-slate-400">
                      {activeTemplateText.length} characters
                    </span>
                  </div>
                </div>

                {/* Placeholder helper chips */}
                <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-200/80">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500 flex items-center gap-1">
                      <Sparkles className="w-3.5 h-3.5 text-brand-600" />
                      Dynamic Placeholders (Click to insert):
                    </span>
                    {copiedPlaceholder && (
                      <span className="text-[10px] text-emerald-600 font-bold flex items-center gap-1">
                        <Check className="w-3 h-3" /> Inserted {copiedPlaceholder}
                      </span>
                    )}
                  </div>

                  <div className="flex flex-wrap gap-1.5">
                    {placeholders.map((p) => (
                      <button
                        key={p.key}
                        type="button"
                        onClick={() => handleInsertPlaceholder(p.key)}
                        className="px-2.5 py-1 text-xs font-mono font-semibold rounded-lg bg-white hover:bg-brand-50 text-slate-700 hover:text-brand-700 border border-slate-200 hover:border-brand-300 transition shadow-2xs"
                        title={`Sample: "${p.sample}"`}
                      >
                        {p.key}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Textarea */}
                <div>
                  <textarea
                    ref={textareaRef}
                    rows={7}
                    value={activeTemplateText}
                    onChange={(e) =>
                      setEditedTemplates((prev) => ({
                        ...prev,
                        [activeTemplateId]: e.target.value,
                      }))
                    }
                    className="w-full text-xs font-mono text-slate-800 bg-white border border-slate-200 rounded-xl p-3.5 focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500 transition leading-relaxed resize-y"
                    placeholder="Enter template message text..."
                  />
                </div>

                {/* Save Button */}
                <div className="flex items-center justify-between pt-2">
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => handleSaveTemplate(activeTemplateId)}
                      disabled={savingTemplateId === activeTemplateId}
                      className="px-5 py-2.5 rounded-xl text-xs font-bold text-white bg-brand-600 hover:bg-brand-700 transition shadow-md shadow-brand-600/20 disabled:opacity-50"
                    >
                      {savingTemplateId === activeTemplateId ? 'Saving...' : 'Save Template Changes'}
                    </button>
                    {templateSuccessMsg && (
                      <span className="text-xs text-emerald-600 font-bold flex items-center gap-1">
                        <CheckCircle2 className="w-4 h-4" /> {templateSuccessMsg}
                      </span>
                    )}
                  </div>
                </div>
              </div>

              {/* Right Column: WhatsApp Chat Bubble Live Preview */}
              <div className="w-full lg:w-96 flex flex-col justify-between rounded-2xl bg-slate-900 border border-slate-800 p-5 shadow-inner">
                <div>
                  <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
                    <div className="flex items-center gap-2">
                      <div className="w-3 h-3 rounded-full bg-emerald-500" />
                      <span className="text-xs font-bold text-slate-200">
                        WhatsApp Guest Preview
                      </span>
                    </div>
                    <span className="text-[10px] text-slate-400">Sample Guest View</span>
                  </div>

                  {/* Simulated WhatsApp Chat Bubble */}
                  <div className="bg-[#DCF8C6] text-slate-900 p-4 rounded-2xl rounded-tr-none shadow-md text-xs leading-relaxed whitespace-pre-wrap font-sans relative">
                    {previewText}
                    <div className="mt-2 text-right">
                      <span className="text-[10px] text-slate-500 font-medium">
                        12:00 PM ✓✓
                      </span>
                    </div>
                  </div>
                </div>

                {/* Test Dispatch Widget */}
                <div className="mt-6 pt-4 border-t border-slate-800 space-y-3">
                  <span className="text-[11px] font-bold text-slate-300 flex items-center gap-1.5">
                    <Send className="w-3.5 h-3.5 text-emerald-400" />
                    Test Dispatch on Real Device:
                  </span>
                  <form onSubmit={handleSendTestMessage} className="space-y-2">
                    <div className="flex gap-2">
                      <input
                        type="text"
                        value={testPhone}
                        onChange={(e) => setTestPhone(e.target.value)}
                        placeholder="+91 98765 43210"
                        className="flex-1 bg-slate-800 border border-slate-700 text-white placeholder-slate-500 text-xs rounded-xl px-3 py-2 focus:outline-none focus:border-emerald-500"
                      />
                      <button
                        type="submit"
                        disabled={isSendingTest || !statusData?.isConnected}
                        className="px-3.5 py-2 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-500 rounded-xl transition disabled:opacity-40"
                        title={!statusData?.isConnected ? 'Connect WhatsApp first' : 'Send Test'}
                      >
                        {isSendingTest ? 'Sending...' : 'Send'}
                      </button>
                    </div>

                    {!statusData?.isConnected && (
                      <p className="text-[10px] text-amber-400/90">
                        * Connect WhatsApp via QR code above to enable live sending.
                      </p>
                    )}

                    {testResult && (
                      <div
                        className={`p-2.5 rounded-xl text-xs font-medium ${
                          testResult.success
                            ? 'bg-emerald-950/60 text-emerald-300 border border-emerald-800'
                            : 'bg-red-950/60 text-red-300 border border-red-800'
                        }`}
                      >
                        {testResult.message}
                      </div>
                    )}
                  </form>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* ── 4. RECENT DISPATCH LOGS ── */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden">
        <div className="p-6 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <History className="w-4 h-4 text-slate-500" />
            <h3 className="text-base font-bold text-slate-900 font-outfit">
              Recent Message Dispatch Log
            </h3>
          </div>

          <button
            onClick={fetchLogs}
            disabled={isLoadingLogs}
            className="text-xs font-semibold text-brand-600 hover:text-brand-700 flex items-center gap-1 transition"
          >
            <RefreshCw className={`w-3 h-3 ${isLoadingLogs ? 'animate-spin' : ''}`} />
            Refresh Logs
          </button>
        </div>

        <div className="divide-y divide-slate-100 max-h-80 overflow-y-auto">
          {logs.length === 0 ? (
            <div className="p-8 text-center text-xs text-slate-400">
              No messages dispatched yet. Trigger a check-in, checkout, or send a test message above.
            </div>
          ) : (
            logs
              .slice()
              .reverse()
              .map((log) => (
                <div key={log.id} className="p-4 flex items-start justify-between gap-4 hover:bg-slate-50/70 transition">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <span className="text-xs font-bold text-slate-800">
                        +{log.recipientPhone}
                      </span>
                      <span className="text-[10px] uppercase font-semibold px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">
                        {log.templateId}
                      </span>
                      <span className="text-[10px] text-slate-400">
                        {new Date(log.timestamp).toLocaleTimeString([], {
                          hour: '2-digit',
                          minute: '2-digit',
                          second: '2-digit',
                        })}
                      </span>
                    </div>

                    {log.preview && (
                      <p className="text-xs text-slate-600 line-clamp-1 font-mono">
                        {log.preview}
                      </p>
                    )}

                    {log.error && (
                      <p className="text-xs text-red-600 font-medium">
                        Error: {log.error}
                      </p>
                    )}
                  </div>

                  <div>
                    {log.status === 'SENT' ? (
                      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                        <CheckCircle2 className="w-3 h-3 text-emerald-600" />
                        Delivered
                      </span>
                    ) : log.status === 'SKIPPED_DUPLICATE' ? (
                      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-sky-50 text-sky-700 border border-sky-200">
                        Skipped (Duplicate)
                      </span>
                    ) : log.status === 'SKIPPED_DISABLED' ? (
                      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-slate-100 text-slate-600 border border-slate-200">
                        Skipped (Disabled)
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-red-50 text-red-700 border border-red-200">
                        Failed
                      </span>
                    )}
                  </div>
                </div>
              ))
          )}
        </div>
      </div>
    </div>
  );
};
