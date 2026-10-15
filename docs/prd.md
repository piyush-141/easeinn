# EaseInn Mobile PMS — Product Requirements Document (PRD)

**Document Version:** 2.0  
**Target Platform:** Mobile App (Flutter — iOS & Android) + Responsive Tablet  
**Backend:** Supabase PostgreSQL + Express IITR OCR Server  

---

## 1. Executive Summary

EaseInn is a modern, mobile-first hotel Property Management System (PMS) tailored for boutique hotels, guest houses, and mid-sized properties in India. It streamlines front-desk operations with a fast 3-step check-in wizard powered by an automated Indian ID OCR extraction engine (supporting dual-side Aadhaar, PAN card, and Passports), real-time floor-wise room housekeeping management, and transparent billing settlement.

---

## 2. Core Personas

1. **Front Desk Receptionist (Primary User)**:
   - Needs to check in walk-in and arriving guests in under 2 minutes.
   - Relies on OCR to eliminate tedious manual typing of 12-digit Aadhaar numbers and addresses.
   - Manages check-outs, collects advance and remaining balance payments, and issues receipts.
2. **Hotel Housekeeper / Supervisor**:
   - Views floor grids to identify rooms requiring turnover cleaning.
   - Updates room status from "Needs Cleaning" to "Vacant" with a single tap.
3. **Hotel Manager / Owner**:
   - Monitors true live occupancy, daily collections, and multi-property branch performance.

---

## 3. Product Principles & Non-Negotiables

1. **True Dynamic Data Integrity**:
   - Zero hardcoded or fabricated statistics. If rooms are empty, occupancy is 0%.
   - Every check-in and check-out operation updates room state, guest archives, and billing totals reactively.
2. **Strict Mobile Screen Adaptability**:
   - No `RenderFlex` overflow errors on any device screen size (small phones to large tablets).
   - Safe area handling, scrollable viewports, and clean touch targets (minimum 44x44 dp).
3. **Reliable OCR Pipeline**:
   - Communicates with the IITR OCR server (`POST /api/scan-document`).
   - For Aadhaar: requires both **Front** and **Back** images to construct complete guest records (Front: Name, DOB, Gender, Aadhaar ID; Back: Address, Pincode, Guardian/Father).
   - Provides seamless offline/demo fallback mode for uninterrupted testing.

---

## 4. Key Functional Features

### 4.1 Authentication & Property Selection
- Sample login screen with 1-tap quick sign-in for front desk staff (`Devika Rao`).
- Property switcher supporting multiple hotel branches (`EaseInn Boutique & Suites`).

### 4.2 Dashboard (Live Overview)
- Dynamic KPI metrics computed directly from state:
  - Total Rooms, Occupied Rooms, Vacant Available, Needs Cleaning.
  - Occupancy percentage (`(occupied / total) * 100`).
  - Today's Arrivals, Departures, Active Guests, and Cash/UPI Collection total.
- Quick action navigation cards (Check-In, Housekeeping, Check-Out, Guests).
- Live active in-house guest list.

### 4.3 Room Status & Housekeeping
- Floor-by-floor room grid (Floor 1 & Floor 2).
- Status filtering: All, Vacant (Green), Occupied (Violet), Needs Cleaning (Amber), Reserved (Sky).
- Room card actions:
  - Vacant -> Tap to launch Check-In with room pre-selected.
  - Needs Cleaning -> 1-tap "Mark Clean" to return room to inventory.
  - Occupied -> View occupant details and quick link to checkout.

### 4.4 Automated OCR Check-In Wizard (Core Flow)
- **Step 1: Room & Stay**: Select vacant room, check-out date picker, guest count, nightly rate calculation.
- **Step 2: ID OCR & Guest Details**:
  - Document type selector (Aadhaar, PAN, Passport, DL, Voter ID).
  - Dual upload zones for Aadhaar (Front Side + Back Side).
  - 1-tap test demo ID loader.
  - Laser scan animation while OCR processes.
  - Auto-fills: Full Name, ID Number, DOB, Gender, Permanent Address, Pincode, Guardian Name.
  - Receptionist can review and edit any field.
- **Step 3: Advance Payment & Confirmation**:
  - Nightly rate × nights stayed = estimated folio.
  - Advance payment input (Cash, UPI, Card).
  - Confirmation modal with generated invoice number (`INV-2026-XXXX`).
  - Automatically flips room status to Occupied.

### 4.5 Check-Out & Folio Settlement
- Active stay selector.
- Line-item stay breakdown: Room nights stayed, advance payment credit, net balance due.
- Payment method selector for settling remaining dues.
- Completing check-out automatically marks room as "Needs Cleaning" and issues receipt.

### 4.6 Guest Archive & Profiles
- Searchable guest directory (by name, phone, ID, or city).
- Filter by Currently In-House vs Past Guests.
- Detailed profile modal showing verified government ID badge, masked ID number, address, and stay history.

### 4.7 Multi-Hotel Management
- Property overview cards with room counts, address, and active shift indicators.
- "Add New Hotel" modal form for onboarding new branches.
