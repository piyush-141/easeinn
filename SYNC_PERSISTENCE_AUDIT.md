# EaseInn Sync, Local Persistence & Multi-Device Architecture Audit

## 1. Executive Summary

This document audits the current synchronization, local storage, and multi-device interaction architecture in **EaseInn** (Flutter client + Supabase backend), identifying architectural bottlenecks, edge-case bugs (including offline data loss), and outlining a step-by-step roadmap to transition from the current 3-second polling mechanism to an **event-triggered, incremental sync engine with a durable local outbox queue**.

---

## 2. Current Architecture & Mechanism Analysis

Persistence and synchronization are currently divided across three layers:
1. **In-Memory Store:** `mobile/lib/services/hotel_store.dart` maintains core entities (`_rooms`, `_guests`, `_stays`, `_bills`, `_payments`, `_expenses`) in Dart process memory.
2. **Local Storage:** `mobile/lib/services/local_store_service.dart` handles monolithic JSON state dumps to local flash storage and Android `SharedPreferences`.
3. **Cloud Backend:** `mobile/lib/services/supabase_sync_service.dart` executes direct REST calls and opens a Realtime WebSocket channel with Supabase.

---

## 3. How the Current Sync System Actually Works

### A. The 3-Second Polling Loop
In `mobile/lib/services/hotel_store.dart` (lines 192–195):
```dart
_autoSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
  _backgroundPollForChanges();
});
```
Every 3 seconds (20 times per minute, 1,200 times per hour, per active device):
1. `_backgroundPollForChanges()` invokes `SupabaseSyncService.pullRemoteData(propertyId)`.
2. `pullRemoteData()` fires **6 parallel queries across all tables** (`rooms`, `guests`, `stays`, `expenses`, `bills`, `payments`), plus a **7th secondary query** for `bill_line_items`.
3. It downloads the **entire database table contents from scratch** over HTTP, parses all rows into memory, and passes the entire payload to `_applyRemoteData()`.
4. `_applyRemoteData()` traverses every room, stay, guest, and bill to calculate diffs. If any diff is detected, it flags `hasRemoteChanges = true`, re-serializes and rewrites the entire local disk cache, and invokes `notifyListeners()`.

### B. The Realtime WebSocket Layer
In `mobile/lib/services/hotel_store.dart` (lines 213–258), a Supabase Realtime channel is configured to listen to Postgres changes on `rooms`, `stays`, `guests`, `bills`, `payments`, `expenses`.
- When an event arrives, it triggers `_triggerDebouncedSyncWithBanner()` (debounced to 400ms).
- **The Issue:** The incoming WebSocket payload is discarded. The callback simply invokes the same monolithic `pullRemoteData()` full-table dump.

### C. Outgoing Local Mutations (Push)
When a user performs an action (e.g., Check-in, Check-out, Add Expense, Record Payment):
1. The in-memory state is updated immediately.
2. `saveToLocalStorage()` is called immediately.
3. The outgoing network push is fired as an unmonitored background microtask:
   ```dart
   Future.microtask(() async {
     await SupabaseSyncService.syncGuest(newGuest);
     await SupabaseSyncService.syncStay(newStay, knownRooms: _rooms);
     await SupabaseSyncService.syncBill(newBill, _currentProperty.id);
     await SupabaseSyncService.updateRoomStatus(_currentProperty.id, targetRoom.roomNumber, RoomStatus.occupied);
   });
   ```
4. **No Queue or Retry Mechanism:** If the device is offline, experiencing packet loss, or in airplane mode, the internal `try/catch` in `SupabaseSyncService` logs an error to the console and the mutation is lost forever.

---

## 4. Local Persistence Analysis

Local saving is performed, but as an **un-indexed monolithic JSON snapshot**, rather than an ACID database or mutation journal.

In `mobile/lib/services/local_store_service.dart` & `mobile/lib/services/hotel_store.dart` (line 2064):
- On any modification (invoked >30 times across `hotel_store.dart`), `exportState()` converts all properties, rooms, guests, stays, bills, line items, payments, and expenses into one massive Map.
- That Map is encoded into a single JSON string.
- It is saved to two destinations:
  1. A flat JSON file on disk: `easeinn_store_<propertyId>.json`.
  2. A raw string in Android/iOS `SharedPreferences`: `easeinn_local_cache_<propertyId>`.

### Critical Flaws of this Approach:
1. **Lack of Mutation Outbox:** The snapshot only stores "the current snapshot of the app". It does not store *what mutated*, *which records are pending cloud acknowledgement*, or *the chronological sequence of events*.
2. **Main Thread Blocking & IO Thrashing:** Re-encoding and writing entire multi-megabyte JSON files on every single button press or room status toggle locks the UI thread and increases flash storage wear.
3. **Abuse of SharedPreferences:** `SharedPreferences` is intended for lightweight key-value preferences. Storing large JSON payloads in `SharedPreferences` causes high memory overhead during Android app cold starts and risks Application Not Responding (ANR) warnings.

---

## 5. Multi-Device Behavior & Edge Cases

### Case 1: Device A is Online, Device B is Online
- Device A creates a check-in. It pushes to Supabase via individual REST calls.
- Device B's 3-second poller (or Realtime WebSocket) detects that remote data differs.
- Device B pulls the entire dataset and executes `_applyRemoteData()`.
- Device B's in-memory store is updated to reflect the new stay and occupied room.
- **The UX Glitch:** Despite having *already updated* Device B's state, `_applyRemoteData()` flags `hasRemoteChanges = true`. A banner appears on Device B stating: *"Remote changes detected. Tap to sync."* If the user taps it, it triggers `acknowledgeAndSync()`, which runs `pushAllData()` — **pushing all of Device B's data back up to the server unnecessarily.**

### Case 2: Device A is Offline (The Data-Loss Wipe Bug)
This is the most critical bug identified in the codebase:
1. **Device A is offline:** Receptionist checks in a guest.
2. `checkInGuest` assigns UUIDs to the stay and bill (`SupabaseSyncService.generateUuid()`).
3. The stay is stored in local memory and saved to the local JSON file. The network push fails silently in `Future.microtask`.
4. **Device A reconnects to Wi-Fi / cellular:**
5. The 3-second poller `_backgroundPollForChanges()` fires **immediately** (it only pulls, never pushes pending changes).
6. `pullRemoteData()` fetches data from Supabase. Because Device A has not pushed its offline stay yet, the stay does not exist on the server.
7. `_applyRemoteData()` executes:
   ```dart
   final beforeStayCount = _stays.length;
   _stays.removeWhere((s) =>
       s.propertyId == _currentProperty.id &&
       SupabaseSyncService.isValidUuid(s.id) &&
       !remoteStayIds.contains(s.id));
   ```
8. **Result:** `_applyRemoteData` assumes that because the stay UUID is absent from the server, another device deleted it. **It deletes the offline stay, deletes the offline bill, deletes the offline expense, and writes the wiped state back to disk.**
9. The offline check-in is permanently erased without trace.

### Case 3: Concurrent Updates (No Conflict Resolution)
- Device A updates Room 101 to `occupied` while offline.
- Device B updates Room 101 to `maintenance` while online.
- When Device A triggers a sync, `pushAllData()` runs an unrestricted `upsert` across all rooms, stays, and bills without checking `updated_at`.
- Whichever device pushes last silently overwrites the other. There is no Last-Write-Wins (LWW) timestamp check or field-level conflict merge.

---

## 6. Full Inventory of Issues

| Category | Identified Issue in Codebase | Consequence / Impact |
| :--- | :--- | :--- |
| **Network Efficiency** | 3-second hardcoded timer calling 7 tables (`hotel_store.dart:193`) | 8,400 queries/hour per device. Drains battery, wastes mobile bandwidth, hits Supabase free tier rate limits. |
| **Data Safety** | Blind remote deletion prune in `_applyRemoteData` (`hotel_store.dart:2176-2180`) | **Offline data wiped** as soon as the app reconnects to the network. |
| **Reliability** | Fire-and-forget pushes (`Future.microtask` in `hotel_store.dart:1304`) | No retry on network drop, no exponential backoff, no queue. Mutations are dropped permanently. |
| **Realtime PubSub** | Tables missing from Postgres publication | In Supabase, Postgres tables are not broadcast over WebSocket unless registered in `supabase_realtime`. The app never receives real-time events without this publication. |
| **Database Schema** | Missing `updated_at` on key tables | `stays`, `payments`, `bill_line_items`, and `expenses` lack `updated_at` columns or auto-updating triggers in `00001_initial_schema.sql` and `00008_expenses_table.sql`. Incremental queries (`WHERE updated_at > :cursor`) cannot be performed. |
| **Local Storage** | Monolithic JSON dump to disk & `SharedPreferences` | Memory bloat, UI frame drops on writes, and lack of transaction safety. |
| **UI State / UX** | Inaccurate "Remote Changes" banner | Banner appears even when local data has already been updated, prompting the user to push all local data back up. |

---

## 7. Target Architecture: Event-Triggered, Incremental Sync Engine

```mermaid
flowchart TD
    subgraph Device [Mobile Device Client]
        UI[User Action / UI] -->|1. Mutate State| Store[Hotel Store In-Memory]
        Store -->|2. Enqueue Mutation| Outbox[Durable Local Outbox Queue]
        Outbox -->|3. Persist State + Queue| LocalDB[(Local Durable Storage)]
        
        Outbox -->|4. Trigger Immediate Flush| SyncEngine[Sync Engine]
        NetListener[Connectivity Listener] -->|On Reconnect| SyncEngine
        RealtimeWS[Supabase Realtime WS] -->|On Remote Event| SyncEngine
        SafetyTimer[Conservative Heartbeat 5-15 min] -->|Fallback Check| SyncEngine
    end

    subgraph Cloud [Supabase Backend]
        SyncEngine -->|5a. Drain Outbox (Push Pending)| REST[REST API / RPC]
        REST --> Postgres[(PostgreSQL DB)]
        Postgres -->|5b. Return Updated Rows (Incremental Pull: updated_at > cursor)| SyncEngine
        Postgres -->|PubSub Event| RealtimeWS
    end
```

### Core Architecture Components:

#### 1. Durable Local Outbox (Mutation Queue)
- Every mutation (e.g. `CREATE_STAY`, `UPDATE_ROOM_STATUS`, `RECORD_PAYMENT`, `ADD_EXPENSE`) is assigned a client-generated UUID, an idempotency key, a monotonic sequence number, and stored in a durable `sync_outbox` journal.
- Mutations remain in the queue until acknowledged (`200 OK`) by Supabase.
- While offline, items accumulate safely. Local entities carry a `sync_status = 'pending'` flag.

#### 2. Safe Reconciliation (Eliminating Offline Wipes)
- Remote pruning logic (`removeWhere(!remoteIds.contains(id))`) will **never** delete any record that has a pending operation in the outbox or a `sync_status == 'pending'` flag.

#### 3. Cursor-Based Incremental Pull
- Add `updated_at` (with auto-update triggers) to `stays`, `payments`, `bill_line_items`, and `expenses`.
- Maintain a local `last_synced_at` cursor per property.
- When pulling remote data, fetch only updated rows:
  ```sql
  SELECT * FROM stays WHERE property_id = :propId AND updated_at > :last_synced_at;
  ```
- Replaces 7 full-table scans. Bandwidth and query volume drop by >99%.

#### 4. Event Triggers (Eliminating the 3-Second Loop)
Sync checks will occur **only** on four specific triggers:
1. **User Action:** As soon as an action is queued, the engine attempts an immediate opportunistic flush.
2. **Realtime Event:** Supabase WebSocket notifies the client that a specific table row changed, triggering a targeted incremental pull.
3. **Connectivity Restoration:** When `connectivity_plus` detects connection change from offline to online, the engine flushes the outbox and pulls delta changes.
4. **Conservative Heartbeat:** An idle safety check running once every 10–15 minutes (or on app foreground resume), instead of every 3 seconds.

---

## 8. Implementation Plan

1. **Step 1: Database Migration (`supabase/migrations/`)**
   - Add `updated_at` timestamp columns and auto-update trigger functions across `stays`, `bills`, `bill_line_items`, `payments`, and `expenses`.
   - Ensure all tables are explicitly added to `supabase_realtime` publication:
     ```sql
     ALTER PUBLICATION supabase_realtime ADD TABLE rooms, guests, stays, bills, bill_line_items, payments, expenses;
     ```

2. **Step 2: Local Outbox Queue Service (`mobile/lib/services/outbox_queue_service.dart`)**
   - Create a durable local queue for pending mutations (`id`, `property_id`, `action`, `payload`, `created_at`, `status`).
   - Store the outbox persistently so mutations survive app restarts or device reboots.

3. **Step 3: Fix Reconciliation Wipe Bug in `hotel_store.dart`**
   - Protect local pending entities from being deleted during remote pruning.
   - Flush outbox *before* pulling remote updates.

4. **Step 4: Incremental Delta Pulling in `supabase_sync_service.dart`**
   - Implement `pullIncrementalChanges(propertyId, since)` using `updated_at > since`.
   - Apply only deltas (upsert modified rows, delete tombstoned rows).

5. **Step 5: Event-Driven Triggers & Deletion of 3s Poller**
   - Remove `Timer.periodic(const Duration(seconds: 3))` from `hotel_store.dart`.
   - Hook outbox flush and incremental pull to:
     - Local mutation completion
     - Supabase Realtime WebSocket messages
     - `connectivity_plus` reconnection events
     - App lifecycle resume (`AppLifecycleState.resumed`)
