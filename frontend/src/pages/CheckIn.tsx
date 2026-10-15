import React, { useState, useEffect, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  UserCheck,
  ScanLine,
  Upload,
  CheckCircle2,
  AlertCircle,
  ShieldCheck,
  CreditCard,
  BedDouble,
  Calendar,
  Sparkles,
  ArrowRight,
  ArrowLeft,
  FileText,
  User,
  MapPin,
  Check,
  Eye,
} from 'lucide-react';
import { useHotel } from '../context/HotelContext';
import { scanIdentityDocument } from '../lib/ocrClient';
import { IdType, PaymentMethod, OCRScanResult } from '../types';

export const CheckIn: React.FC = () => {
  const { rooms, checkIn, currentProperty } = useHotel();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  // Current Step: 1 (Room) -> 2 (Guest & OCR) -> 3 (Payment & Confirm)
  const [currentStep, setCurrentStep] = useState<1 | 2 | 3>(1);

  // Step 1 State: Room & Stay
  const preselectedRoomId = searchParams.get('room') || '';
  const vacantRooms = rooms.filter((r) => r.status === 'vacant');
  const [selectedRoomId, setSelectedRoomId] = useState<string>(
    preselectedRoomId || (vacantRooms.length > 0 ? vacantRooms[0].id : '')
  );

  const tomorrow = new Date(Date.now() + 24 * 3600 * 1000).toISOString().split('T')[0];
  const [expectedCheckout, setExpectedCheckout] = useState(tomorrow);
  const [numGuests, setNumGuests] = useState(1);

  // Selected room details
  const selectedRoom = rooms.find((r) => r.id === selectedRoomId);
  const nightlyRate = selectedRoom?.base_rate || 2200;

  // Nights calculation
  const checkInDate = new Date();
  const checkoutDateObj = new Date(expectedCheckout);
  const estimatedNights = Math.max(
    1,
    Math.ceil((checkoutDateObj.getTime() - checkInDate.getTime()) / (1000 * 60 * 60 * 24))
  );
  const totalEstimatedAmount = estimatedNights * nightlyRate;

  // Step 2 State: Document OCR & Guest Fields
  const [idType, setIdType] = useState<IdType>('aadhaar');
  const [frontFile, setFrontFile] = useState<File | null>(null);
  const [backFile, setBackFile] = useState<File | null>(null);
  const [frontPreview, setFrontPreview] = useState<string | null>(null);
  const [backPreview, setBackPreview] = useState<string | null>(null);

  // OCR Processing State
  const [isScanning, setIsScanning] = useState(false);
  const [scanResult, setScanResult] = useState<OCRScanResult | null>(null);
  const [scanMessage, setScanMessage] = useState<string | null>(null);

  // Guest Form Fields (Auto-filled by OCR)
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('+91 ');
  const [email, setEmail] = useState('');
  const [idNumber, setIdNumber] = useState('');
  const [dob, setDob] = useState('');
  const [gender, setGender] = useState('male');
  const [address, setAddress] = useState('');
  const [pincode, setPincode] = useState('');
  const [fatherName, setFatherName] = useState('');

  // Step 3 State: Payment
  const [advanceAmount, setAdvanceAmount] = useState<number>(nightlyRate);
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('upi');
  const [paymentRef, setPaymentRef] = useState('');

  // Confirmation Modal
  const [confirmedData, setConfirmedData] = useState<{ stayId: string; billNumber: string } | null>(null);

  // Image upload handlers
  const handleFrontUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setFrontFile(file);
      setFrontPreview(URL.createObjectURL(file));
    }
  };

  const handleBackUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setBackFile(file);
      setBackPreview(URL.createObjectURL(file));
    }
  };

  // Run OCR Scan
  const handleRunOcr = async () => {
    setIsScanning(true);
    setScanMessage('Preprocessing image variants and running Tesseract OCR...');

    try {
      const result = await scanIdentityDocument({
        documentType: idType,
        frontFile,
        backFile,
        singleFile: frontFile,
      });

      setScanResult(result);

      // AUTO-FILL FIELDS FROM OCR RESULT
      if (result.guest_data) {
        if (result.guest_data.full_name) setFullName(result.guest_data.full_name);
        if (result.guest_data.id_number) setIdNumber(result.guest_data.id_number);
        if (result.guest_data.date_of_birth) setDob(result.guest_data.date_of_birth);
        if (result.guest_data.gender) setGender(result.guest_data.gender);
        if (result.guest_data.address) setAddress(result.guest_data.address);
        if (result.guest_data.pincode) setPincode(result.guest_data.pincode);
        if (result.guest_data.father_name) setFatherName(result.guest_data.father_name);
      }

      setScanMessage('Data extracted and merged successfully!');
    } catch (err: any) {
      setScanMessage(`Scan error: ${err.message}`);
    } finally {
      setIsScanning(false);
    }
  };

  // 1-Click Load Sample Demo ID for quick evaluation
  const loadDemoSample = (type: IdType) => {
    setIdType(type);
    if (type === 'aadhaar') {
      setFrontPreview('https://images.unsplash.com/photo-1544717305-2782549b5136?w=600&auto=format&fit=crop&q=60');
      setBackPreview('https://images.unsplash.com/photo-1589829545856-d10d557cf95f?w=600&auto=format&fit=crop&q=60');
    } else {
      setFrontPreview('https://images.unsplash.com/photo-1544717305-2782549b5136?w=600&auto=format&fit=crop&q=60');
      setBackPreview(null);
    }
    // Auto-run OCR simulation
    setTimeout(() => {
      handleRunOcr();
    }, 100);
  };

  // Final Submit
  const handleFinalCheckIn = () => {
    if (!selectedRoomId || !fullName.trim()) return;

    const res = checkIn({
      roomId: selectedRoomId,
      expectedCheckout,
      numGuests,
      nightlyRate,
      guestData: {
        fullName,
        phone,
        email,
        idType,
        idNumber,
        dob,
        gender,
        address,
        pincode,
        fatherName,
      },
      advanceAmount: Number(advanceAmount),
      paymentMethod,
      paymentReference: paymentRef,
    });

    setConfirmedData(res);
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      {/* Page Title & Stepper Indicator */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="font-outfit text-2xl font-bold text-slate-900 flex items-center gap-2">
            <UserCheck className="w-6 h-6 text-brand-600" />
            Guest Check-In Wizard
          </h1>
          <p className="text-xs text-slate-500">
            Step {currentStep} of 3 • {currentStep === 1 ? 'Room Selection' : currentStep === 2 ? 'Guest ID & OCR Scan' : 'Advance Payment & Confirm'}
          </p>
        </div>

        {/* Stepper Dots */}
        <div className="flex items-center gap-2">
          {[
            { num: 1, label: 'Room' },
            { num: 2, label: 'Guest & OCR' },
            { num: 3, label: 'Payment' },
          ].map((s) => (
            <div
              key={s.num}
              onClick={() => {
                if (currentStep > s.num) setCurrentStep(s.num as any);
              }}
              className={`flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs font-bold cursor-pointer transition ${
                currentStep === s.num
                  ? 'bg-brand-600 text-white shadow-md shadow-brand-500/20'
                  : currentStep > s.num
                  ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                  : 'bg-slate-100 text-slate-400'
              }`}
            >
              <span>{s.num}</span>
              <span className="hidden sm:inline">{s.label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* ======================================================== */}
      {/* STEP 1: ROOM SELECTION & DATES */}
      {/* ======================================================== */}
      {currentStep === 1 && (
        <div className="bg-white rounded-3xl border border-slate-200/90 p-6 shadow-sm space-y-6">
          <h3 className="font-outfit text-lg font-bold text-slate-900 flex items-center gap-2">
            <BedDouble className="w-5 h-5 text-brand-600" />
            1. Select Room & Stay Duration
          </h3>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Vacant Room Selector */}
            <div>
              <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-2">
                Available Vacant Rooms *
              </label>
              {vacantRooms.length === 0 ? (
                <div className="p-4 rounded-2xl bg-amber-50 border border-amber-200 text-amber-800 text-xs flex items-center gap-2">
                  <AlertCircle className="w-4 h-4 flex-shrink-0" />
                  No vacant rooms currently available. Please check room housekeeping.
                </div>
              ) : (
                <div className="grid grid-cols-2 gap-3 max-h-60 overflow-y-auto pr-1">
                  {vacantRooms.map((room) => {
                    const isSelected = selectedRoomId === room.id;
                    return (
                      <div
                        key={room.id}
                        onClick={() => setSelectedRoomId(room.id)}
                        className={`p-3.5 rounded-2xl border cursor-pointer transition flex flex-col justify-between ${
                          isSelected
                            ? 'border-brand-600 bg-brand-50/70 ring-2 ring-brand-500/20 shadow-sm'
                            : 'border-slate-200 hover:border-slate-300 bg-white'
                        }`}
                      >
                        <div className="flex items-center justify-between">
                          <span className="font-outfit text-xl font-bold text-slate-900">
                            {room.room_number}
                          </span>
                          <span className="text-[10px] font-bold text-slate-400">
                            Fl {room.floor}
                          </span>
                        </div>
                        <p className="text-xs font-semibold text-slate-600 truncate mt-1">
                          {room.category_name}
                        </p>
                        <p className="text-xs font-bold text-brand-700 mt-2">
                          ₹{room.base_rate}/night
                        </p>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Dates & Guests */}
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-2">
                  Expected Check-Out Date *
                </label>
                <div className="relative">
                  <Calendar className="w-4 h-4 text-slate-400 absolute left-3 top-3.5" />
                  <input
                    type="date"
                    min={tomorrow}
                    value={expectedCheckout}
                    onChange={(e) => setExpectedCheckout(e.target.value)}
                    className="w-full pl-9 pr-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-semibold text-slate-800"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-2">
                  Number of Guests
                </label>
                <div className="flex items-center gap-3">
                  {[1, 2, 3, 4].map((n) => (
                    <button
                      key={n}
                      type="button"
                      onClick={() => setNumGuests(n)}
                      className={`flex-1 py-2 rounded-xl text-xs font-bold transition ${
                        numGuests === n
                          ? 'bg-brand-600 text-white shadow-sm'
                          : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                      }`}
                    >
                      {n} {n === 1 ? 'Guest' : 'Guests'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Estimate Summary Box */}
              <div className="p-4 rounded-2xl bg-slate-50 border border-slate-200/80 space-y-2 text-xs">
                <div className="flex justify-between text-slate-600">
                  <span>Selected Room:</span>
                  <span className="font-bold text-slate-800">
                    Room {selectedRoom?.room_number} ({selectedRoom?.category_name})
                  </span>
                </div>
                <div className="flex justify-between text-slate-600">
                  <span>Duration:</span>
                  <span className="font-bold text-slate-800">
                    {estimatedNights} night{estimatedNights > 1 ? 's' : ''}
                  </span>
                </div>
                <div className="flex justify-between text-slate-600">
                  <span>Nightly Rate:</span>
                  <span className="font-bold text-slate-800">₹{nightlyRate}</span>
                </div>
                <div className="pt-2 border-t border-slate-200 flex justify-between font-bold text-sm text-slate-900">
                  <span>Estimated Total:</span>
                  <span className="text-brand-600 font-mono">₹{totalEstimatedAmount}</span>
                </div>
              </div>
            </div>
          </div>

          <div className="pt-4 flex justify-end border-t border-slate-100">
            <button
              disabled={!selectedRoomId}
              onClick={() => setCurrentStep(2)}
              className="px-6 py-2.5 rounded-xl bg-gradient-to-r from-brand-600 to-indigo-600 hover:from-brand-700 hover:to-indigo-700 text-white text-xs font-bold shadow-md shadow-brand-500/20 transition flex items-center gap-2"
            >
              <span>Next: Guest & OCR Scanner</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      )}

      {/* ======================================================== */}
      {/* STEP 2: GUEST DETAILS & DUAL-SIDE AADHAAR OCR SCANNER */}
      {/* ======================================================== */}
      {currentStep === 2 && (
        <div className="bg-white rounded-3xl border border-slate-200/90 p-6 shadow-sm space-y-6">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-slate-100 pb-4">
            <div>
              <h3 className="font-outfit text-lg font-bold text-slate-900 flex items-center gap-2">
                <ScanLine className="w-5 h-5 text-brand-600" />
                2. Guest Identity & Automated OCR
              </h3>
              <p className="text-xs text-slate-500">
                Upload front & back ID documents. IITR OCR auto-fills all fields below.
              </p>
            </div>

            {/* Quick Demo Samples */}
            <div className="flex items-center gap-1.5 bg-slate-50 p-1.5 rounded-xl border border-slate-200">
              <span className="text-[10px] font-bold text-slate-400 uppercase px-1">Test Demo ID:</span>
              <button
                type="button"
                onClick={() => loadDemoSample('aadhaar')}
                className="px-2 py-1 rounded-lg text-[10px] font-bold bg-white text-brand-600 border border-brand-200 shadow-sm hover:bg-brand-50 transition"
              >
                Aadhaar (F+B)
              </button>
              <button
                type="button"
                onClick={() => loadDemoSample('pan')}
                className="px-2 py-1 rounded-lg text-[10px] font-bold bg-white text-slate-700 border border-slate-200 hover:bg-slate-50 transition"
              >
                PAN Card
              </button>
            </div>
          </div>

          {/* Document Type Selector */}
          <div>
            <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-2">
              Identity Document Type
            </label>
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-2">
              {[
                { id: 'aadhaar', label: 'Aadhaar Card' },
                { id: 'pan', label: 'PAN Card' },
                { id: 'passport', label: 'Passport' },
                { id: 'driving_license', label: 'Driving License' },
                { id: 'voter_id', label: 'Voter ID' },
              ].map((doc) => (
                <button
                  key={doc.id}
                  type="button"
                  onClick={() => setIdType(doc.id as IdType)}
                  className={`py-2 px-3 rounded-xl text-xs font-bold transition flex items-center justify-center gap-1.5 ${
                    idType === doc.id
                      ? 'bg-brand-600 text-white shadow-sm'
                      : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                  }`}
                >
                  {idType === doc.id && <Check className="w-3.5 h-3.5" />}
                  <span>{doc.label}</span>
                </button>
              ))}
            </div>
          </div>

          {/* UPLOAD ZONES: FRONT + BACK FOR AADHAAR */}
          <div className="p-5 rounded-3xl bg-slate-50/80 border border-indigo-100 space-y-4">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-slate-800 flex items-center gap-2">
                <Sparkles className="w-4 h-4 text-brand-600" />
                {idType === 'aadhaar'
                  ? 'Aadhaar Dual-Side Scan (Front for Identity, Back for Address)'
                  : 'Document Image Scan'}
              </span>
              {idType === 'aadhaar' && (
                <span className="text-[10px] font-bold text-indigo-700 bg-indigo-100 px-2.5 py-0.5 rounded-full">
                  Both Sides Required
                </span>
              )}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* Front Side Upload */}
              <div className="relative group border-2 border-dashed border-slate-300 hover:border-brand-500 rounded-2xl p-4 text-center bg-white transition overflow-hidden">
                {frontPreview ? (
                  <div className="relative">
                    <img
                      src={frontPreview}
                      alt="Front Preview"
                      className="w-full h-36 object-cover rounded-xl"
                    />
                    {isScanning && (
                      <div className="absolute inset-0 bg-brand-900/40 backdrop-blur-[2px] rounded-xl flex items-center justify-center">
                        <div className="w-full h-1 bg-brand-400 absolute top-0 animate-scan shadow-lg shadow-brand-400" />
                        <span className="text-white text-xs font-bold">Scanning...</span>
                      </div>
                    )}
                    <label className="mt-2 inline-block text-[11px] font-bold text-brand-600 hover:text-brand-700 cursor-pointer">
                      Change Front Image
                      <input
                        type="file"
                        accept="image/*,application/pdf"
                        onChange={handleFrontUpload}
                        className="hidden"
                      />
                    </label>
                  </div>
                ) : (
                  <label className="cursor-pointer block py-4">
                    <Upload className="w-8 h-8 text-slate-400 mx-auto mb-2 group-hover:text-brand-600 transition" />
                    <span className="text-xs font-bold text-slate-700 block">
                      {idType === 'aadhaar' ? 'Upload Aadhaar Front' : 'Upload ID Document'}
                    </span>
                    <span className="text-[10px] text-slate-400 block mt-0.5">
                      JPG, PNG or PDF up to 15MB
                    </span>
                    <input
                      type="file"
                      accept="image/*,application/pdf"
                      onChange={handleFrontUpload}
                      className="hidden"
                    />
                  </label>
                )}
              </div>

              {/* Back Side Upload (Only for Aadhaar or dual-sided IDs) */}
              {idType === 'aadhaar' ? (
                <div className="relative group border-2 border-dashed border-slate-300 hover:border-brand-500 rounded-2xl p-4 text-center bg-white transition overflow-hidden">
                  {backPreview ? (
                    <div className="relative">
                      <img
                        src={backPreview}
                        alt="Back Preview"
                        className="w-full h-36 object-cover rounded-xl"
                      />
                      {isScanning && (
                        <div className="absolute inset-0 bg-brand-900/40 backdrop-blur-[2px] rounded-xl flex items-center justify-center">
                          <div className="w-full h-1 bg-brand-400 absolute top-0 animate-scan shadow-lg shadow-brand-400" />
                          <span className="text-white text-xs font-bold">Scanning Back...</span>
                        </div>
                      )}
                      <label className="mt-2 inline-block text-[11px] font-bold text-brand-600 hover:text-brand-700 cursor-pointer">
                        Change Back Image
                        <input
                          type="file"
                          accept="image/*,application/pdf"
                          onChange={handleBackUpload}
                          className="hidden"
                        />
                      </label>
                    </div>
                  ) : (
                    <label className="cursor-pointer block py-4">
                      <Upload className="w-8 h-8 text-slate-400 mx-auto mb-2 group-hover:text-brand-600 transition" />
                      <span className="text-xs font-bold text-slate-700 block">
                        Upload Aadhaar Back (Address Side)
                      </span>
                      <span className="text-[10px] text-slate-400 block mt-0.5">
                        JPG, PNG or PDF up to 15MB
                      </span>
                      <input
                        type="file"
                        accept="image/*,application/pdf"
                        onChange={handleBackUpload}
                        className="hidden"
                      />
                    </label>
                  )}
                </div>
              ) : (
                <div className="border border-slate-200/80 rounded-2xl p-4 bg-white/70 flex flex-col justify-center text-xs text-slate-500">
                  <p className="font-bold text-slate-700 mb-1">Single-Side Document</p>
                  <p className="leading-relaxed text-[11px]">
                    PAN Card and Passport bio pages require only the front face. Aadhaar cards
                    require both front and back to capture address and father/guardian name.
                  </p>
                </div>
              )}
            </div>

            {/* Run OCR Scan Button */}
            <div className="pt-2 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <button
                type="button"
                disabled={isScanning || (!frontFile && !frontPreview)}
                onClick={handleRunOcr}
                className="px-6 py-2.5 rounded-xl bg-slate-900 hover:bg-brand-600 disabled:opacity-40 text-white text-xs font-bold transition flex items-center justify-center gap-2 shadow"
              >
                <ScanLine className="w-4 h-4" />
                <span>{isScanning ? 'Extracting Text with OCR...' : 'Run IITR OCR Extraction'}</span>
              </button>

              {scanMessage && (
                <span className="text-xs font-medium text-brand-700 flex items-center gap-1.5">
                  <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                  {scanMessage}
                </span>
              )}
            </div>
          </div>

          {/* AUTO-FILLED GUEST FORM (EDITABLE BY STAFF) */}
          <div className="space-y-4 pt-2">
            <h4 className="font-outfit text-sm font-bold text-slate-800 flex items-center gap-2">
              <User className="w-4 h-4 text-slate-400" />
              Verified Guest Registration Form
              <span className="text-[10px] font-semibold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                Auto-Filled by OCR
              </span>
            </h4>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Full Name (as per ID) *
                </label>
                <input
                  type="text"
                  required
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  placeholder="e.g. Rahul Sharma"
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  ID Number *
                </label>
                <input
                  type="text"
                  required
                  value={idNumber}
                  onChange={(e) => setIdNumber(e.target.value)}
                  placeholder="e.g. 1234 5678 9012"
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-mono font-medium"
                />
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Date of Birth
                </label>
                <input
                  type="text"
                  value={dob}
                  onChange={(e) => setDob(e.target.value)}
                  placeholder="DD/MM/YYYY or YYYY-MM-DD"
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Gender</label>
                <select
                  value={gender}
                  onChange={(e) => setGender(e.target.value)}
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium bg-white"
                >
                  <option value="male">Male</option>
                  <option value="female">Female</option>
                  <option value="other">Other</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Phone Number *
                </label>
                <input
                  type="text"
                  required
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
                />
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div className="sm:col-span-2">
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Permanent Address (from ID Back)
                </label>
                <input
                  type="text"
                  value={address}
                  onChange={(e) => setAddress(e.target.value)}
                  placeholder="Street, City, State"
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Pincode</label>
                <input
                  type="text"
                  value={pincode}
                  onChange={(e) => setPincode(e.target.value)}
                  placeholder="e.g. 560038"
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-mono font-medium"
                />
              </div>
            </div>

            {fatherName && (
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Father's / Husband's Name (C/O)
                </label>
                <input
                  type="text"
                  value={fatherName}
                  onChange={(e) => setFatherName(e.target.value)}
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-medium"
                />
              </div>
            )}
          </div>

          <div className="pt-4 flex items-center justify-between border-t border-slate-100">
            <button
              type="button"
              onClick={() => setCurrentStep(1)}
              className="px-4 py-2.5 rounded-xl border border-slate-200 hover:bg-slate-50 text-slate-700 text-xs font-bold transition flex items-center gap-1.5"
            >
              <ArrowLeft className="w-4 h-4" />
              <span>Back to Room</span>
            </button>

            <button
              type="button"
              disabled={!fullName.trim()}
              onClick={() => setCurrentStep(3)}
              className="px-6 py-2.5 rounded-xl bg-gradient-to-r from-brand-600 to-indigo-600 hover:from-brand-700 hover:to-indigo-700 text-white text-xs font-bold shadow-md shadow-brand-500/20 transition flex items-center gap-2"
            >
              <span>Next: Advance Payment</span>
              <ArrowRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      )}

      {/* ======================================================== */}
      {/* STEP 3: ADVANCE PAYMENT & CONFIRMATION */}
      {/* ======================================================== */}
      {currentStep === 3 && (
        <div className="bg-white rounded-3xl border border-slate-200/90 p-6 shadow-sm space-y-6">
          <h3 className="font-outfit text-lg font-bold text-slate-900 flex items-center gap-2">
            <CreditCard className="w-5 h-5 text-brand-600" />
            3. Advance Payment & Check-In Confirmation
          </h3>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Stay Summary Card */}
            <div className="p-5 rounded-2xl bg-gradient-to-br from-brand-900 to-indigo-950 text-white space-y-4">
              <div className="flex items-center justify-between border-b border-white/10 pb-3">
                <span className="text-xs uppercase tracking-wider font-semibold text-brand-200">
                  Stay Summary
                </span>
                <span className="text-xs font-bold bg-brand-500/30 px-2 py-0.5 rounded text-brand-200">
                  Room {selectedRoom?.room_number}
                </span>
              </div>

              <div className="space-y-2 text-xs">
                <div className="flex justify-between">
                  <span className="text-slate-300">Guest Name:</span>
                  <span className="font-bold">{fullName}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-300">ID Verified:</span>
                  <span className="font-mono">{idNumber}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-300">Category:</span>
                  <span>{selectedRoom?.category_name}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-300">Duration:</span>
                  <span>{estimatedNights} Night(s)</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-300">Check-Out:</span>
                  <span>{expectedCheckout}</span>
                </div>
              </div>

              <div className="pt-3 border-t border-white/10 flex justify-between items-baseline font-bold">
                <span className="text-sm">Estimated Total:</span>
                <span className="text-2xl font-mono text-brand-300">
                  ₹{totalEstimatedAmount}
                </span>
              </div>
            </div>

            {/* Payment Input */}
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-2">
                  Advance Amount Paid (₹)
                </label>
                <input
                  type="number"
                  min="0"
                  max={totalEstimatedAmount}
                  value={advanceAmount}
                  onChange={(e) => setAdvanceAmount(Number(e.target.value))}
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono text-lg font-bold text-slate-800"
                />
                <span className="text-[11px] text-slate-400 mt-1 block">
                  Remaining balance due at checkout: ₹{Math.max(0, totalEstimatedAmount - advanceAmount)}
                </span>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-2">
                  Payment Mode
                </label>
                <div className="grid grid-cols-3 gap-2">
                  {[
                    { id: 'upi', label: 'UPI / QR' },
                    { id: 'cash', label: 'Cash' },
                    { id: 'card', label: 'Credit Card' },
                  ].map((m) => (
                    <button
                      key={m.id}
                      type="button"
                      onClick={() => setPaymentMethod(m.id as PaymentMethod)}
                      className={`py-2 px-3 rounded-xl text-xs font-bold transition ${
                        paymentMethod === m.id
                          ? 'bg-brand-600 text-white shadow-sm'
                          : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                      }`}
                    >
                      {m.label}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-2">
                  Payment Reference / Transaction ID (Optional)
                </label>
                <input
                  type="text"
                  value={paymentRef}
                  onChange={(e) => setPaymentRef(e.target.value)}
                  placeholder="e.g. UPI-9845112"
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm font-mono"
                />
              </div>
            </div>
          </div>

          <div className="pt-4 flex items-center justify-between border-t border-slate-100">
            <button
              type="button"
              onClick={() => setCurrentStep(2)}
              className="px-4 py-2.5 rounded-xl border border-slate-200 hover:bg-slate-50 text-slate-700 text-xs font-bold transition flex items-center gap-1.5"
            >
              <ArrowLeft className="w-4 h-4" />
              <span>Back to Guest Details</span>
            </button>

            <button
              type="button"
              onClick={handleFinalCheckIn}
              className="px-8 py-3 rounded-xl bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-700 hover:to-teal-700 text-white text-sm font-bold shadow-lg shadow-emerald-500/20 transition transform active:scale-95 flex items-center gap-2"
            >
              <CheckCircle2 className="w-5 h-5" />
              <span>Complete Check-In & Issue Room</span>
            </button>
          </div>
        </div>
      )}

      {/* CONFIRMATION SUCCESS MODAL */}
      {confirmedData && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in zoom-in-95 duration-200">
          <div className="bg-white rounded-3xl shadow-2xl border border-slate-100 max-w-md w-full p-6 text-center space-y-4">
            <div className="w-16 h-16 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center mx-auto shadow-inner">
              <CheckCircle2 className="w-10 h-10" />
            </div>

            <div>
              <h3 className="font-outfit text-xl font-bold text-slate-900">
                Check-In Successful!
              </h3>
              <p className="text-xs text-slate-500 mt-1">
                Room {selectedRoom?.room_number} is now marked as Occupied
              </p>
            </div>

            <div className="p-4 rounded-2xl bg-slate-50 border border-slate-200 text-left space-y-2 text-xs">
              <div className="flex justify-between">
                <span className="text-slate-500">Guest Name:</span>
                <span className="font-bold text-slate-800">{fullName}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Bill Number:</span>
                <span className="font-mono font-bold text-brand-600">{confirmedData.billNumber}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Advance Paid:</span>
                <span className="font-bold text-emerald-600">₹{advanceAmount}</span>
              </div>
            </div>

            <div className="flex gap-3 pt-2">
              <button
                onClick={() => navigate('/rooms')}
                className="flex-1 py-2.5 rounded-xl bg-slate-900 hover:bg-slate-800 text-white text-xs font-bold transition"
              >
                Go to Rooms Grid
              </button>
              <button
                onClick={() => navigate('/')}
                className="flex-1 py-2.5 rounded-xl border border-slate-200 hover:bg-slate-50 text-slate-700 text-xs font-bold transition"
              >
                Dashboard
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
