import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents an offline-queued action that must be pushed to Supabase.
class OutboxItem {
  final String id; // Unique operation UUID
  final String propertyId;
  final String action; // e.g. 'upsert_guest', 'upsert_stay', 'upsert_bill', 'update_room_status', 'upsert_expense'
  final Map<String, dynamic> payload;
  final int timestamp; // Milliseconds epoch
  int retryCount;

  OutboxItem({
    required this.id,
    required this.propertyId,
    required this.action,
    required this.payload,
    required this.timestamp,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'propertyId': propertyId,
        'action': action,
        'payload': payload,
        'timestamp': timestamp,
        'retryCount': retryCount,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        id: json['id'] as String,
        propertyId: json['propertyId'] as String,
        action: json['action'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        timestamp: (json['timestamp'] as num).toInt(),
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      );
}

/// Durable local FIFO queue for offline writes.
/// Survives app restarts, process kills, and offline periods.
class OutboxQueueService {
  static const String _storagePrefix = 'easeinn_outbox_queue_';
  static final Map<String, List<OutboxItem>> _memoryQueues = {};
  static bool _isFlushing = false;

  /// Loads queue for a property from persistent storage
  static Future<List<OutboxItem>> loadQueue(String propertyId) async {
    if (_memoryQueues.containsKey(propertyId)) {
      return _memoryQueues[propertyId]!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_storagePrefix$propertyId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        final items = decoded
            .map((e) => OutboxItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _memoryQueues[propertyId] = items;
        return items;
      }
    } catch (e) {
      debugPrint('[OutboxQueue] Error loading queue: $e');
    }

    _memoryQueues[propertyId] = [];
    return [];
  }

  /// Appends a new mutation to the persistent queue.
  static Future<void> enqueue({
    required String propertyId,
    required String action,
    required Map<String, dynamic> payload,
    String? itemId,
  }) async {
    final queue = await loadQueue(propertyId);
    final id = itemId ?? '${action}_${DateTime.now().millisecondsSinceEpoch}_${queue.length}';

    // Avoid duplicate enqueue if same id is already pending
    final existingIndex = queue.indexWhere((it) => it.id == id);
    final newItem = OutboxItem(
      id: id,
      propertyId: propertyId,
      action: action,
      payload: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    if (existingIndex != -1) {
      queue[existingIndex] = newItem;
    } else {
      queue.add(newItem);
    }

    await _saveQueue(propertyId, queue);
    debugPrint('[OutboxQueue] Enqueued "$action" ($id). Total pending: ${queue.length}');
  }

  /// Checks if an entity with this ID is currently in the outbox (i.e. pending server confirmation).
  static bool hasPendingMutation(String propertyId, String entityId) {
    final queue = _memoryQueues[propertyId];
    if (queue == null || queue.isEmpty) return false;
    return queue.any((item) {
      final payloadId = item.payload['id']?.toString();
      return payloadId == entityId;
    });
  }

  /// Count of all pending items
  static int pendingCount(String propertyId) {
    return _memoryQueues[propertyId]?.length ?? 0;
  }

  /// Removes an item after successful push
  static Future<void> remove(String propertyId, String itemId) async {
    final queue = await loadQueue(propertyId);
    queue.removeWhere((it) => it.id == itemId);
    await _saveQueue(propertyId, queue);
  }

  /// Saves the current queue to SharedPreferences
  static Future<void> _saveQueue(String propertyId, List<OutboxItem> queue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(queue.map((e) => e.toJson()).toList());
      await prefs.setString('$_storagePrefix$propertyId', encoded);
    } catch (e) {
      debugPrint('[OutboxQueue] Error saving queue: $e');
    }
  }

  /// Drain/flush the queue using the provided processor callback.
  /// If processor returns true, the item is popped.
  static Future<int> flushQueue({
    required String propertyId,
    required Future<bool> Function(OutboxItem item) processor,
  }) async {
    if (_isFlushing) return 0;
    _isFlushing = true;

    int successCount = 0;
    try {
      final queue = List<OutboxItem>.from(await loadQueue(propertyId));
      if (queue.isEmpty) return 0;

      debugPrint('[OutboxQueue] Starting flush for ${queue.length} pending items...');
      for (final item in queue) {
        try {
          final ok = await processor(item);
          if (ok) {
            await remove(propertyId, item.id);
            successCount++;
          } else {
            // Keep in queue for next cycle, increment retry
            item.retryCount++;
            await _saveQueue(propertyId, _memoryQueues[propertyId] ?? []);
            // Break on first failure to preserve FIFO ordering for dependent records
            break;
          }
        } catch (e) {
          debugPrint('[OutboxQueue] Item ${item.id} flush error: $e');
          break;
        }
      }
    } finally {
      _isFlushing = false;
    }
    return successCount;
  }
}
