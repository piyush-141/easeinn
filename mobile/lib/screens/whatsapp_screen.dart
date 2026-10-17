import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/hotel_store.dart';
import '../services/whatsapp_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_scale.dart';

class WhatsAppScreen extends StatefulWidget {
  const WhatsAppScreen({super.key});

  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen>
    with SingleTickerProviderStateMixin {
  Timer? _statusPoller;
  Timer? _deliveryPoller;
  bool _isRefreshingLogs = false;

  WhatsAppStatusData _status = WhatsAppStatusData.initial();
  Map<String, WhatsAppTemplateData> _templates = {};
  List<WhatsAppLogItem> _logs = [];

  bool _isLoading = true;
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  bool _isSavingTemplate = false;
  bool _isSendingTest = false;

  // Selected template editor state
  String _selectedTemplateId = 'checkin_welcome';
  final Map<String, TextEditingController> _templateControllers = {};
  final Map<String, bool> _templateEnabledState = {};

  // Test message dispatcher state
  final _testPhoneController = TextEditingController();
  final _testCustomMsgController = TextEditingController();
  final _liveDispatchMsgController = TextEditingController();
  bool _hasManualLiveEdit = false;
  String _testTemplateId = 'checkin_welcome';
  String? _dispatcherFeedbackMessage;
  bool _dispatcherFeedbackIsError = false;

  final List<Map<String, String>> _placeholders = [
    {'key': '{guestName}', 'label': 'Guest Name'},
    {'key': '{hotelName}', 'label': 'Hotel Name'},
    {'key': '{roomNumber}', 'label': 'Room Number'},
    {'key': '{checkInDate}', 'label': 'Check-In Date'},
    {'key': '{checkOutDate}', 'label': 'Check-Out Date'},
  ];

  @override
  void initState() {
    super.initState();
    _initData();

    // Keep status current without repeatedly hitting the remote auth/API stack.
    _statusPoller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _fetchStatus(silent: true);
    });
    _deliveryPoller = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _isRefreshingLogs) return;
      final hasRecentPending = _logs.any((log) {
        final accepted = log.status == 'ACCEPTED' || log.status == 'SENT';
        final confirmed =
            log.delivered ||
            log.deliveryStatus == 'DELIVERED' ||
            log.deliveryStatus == 'READ';
        final timestamp = DateTime.tryParse(log.timestamp);
        final age = timestamp == null
            ? const Duration(days: 1)
            : DateTime.now().difference(timestamp);
        return accepted &&
            !confirmed &&
            age >= Duration.zero &&
            age < const Duration(minutes: 2);
      });
      if (hasRecentPending) _fetchLogs();
    });
  }

  @override
  void dispose() {
    _statusPoller?.cancel();
    _deliveryPoller?.cancel();
    for (final c in _templateControllers.values) {
      c.dispose();
    }
    _testPhoneController.dispose();
    _testCustomMsgController.dispose();
    _liveDispatchMsgController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    await WhatsAppService.loadBaseUrl();
    await Future.wait([
      _fetchStatus(silent: true),
      _fetchTemplates(),
      _fetchLogs(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchStatus({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final status = await WhatsAppService.getStatus();
    if (mounted) {
      setState(() {
        _status = status;
        if (!silent) _isLoading = false;
      });
    }
  }

  Future<void> _fetchTemplates() async {
    final templates = await WhatsAppService.getTemplates();
    if (mounted && templates.isNotEmpty) {
      setState(() {
        _templates = templates;
        for (final entry in templates.entries) {
          if (!_templateControllers.containsKey(entry.key)) {
            _templateControllers[entry.key] = TextEditingController(
              text: entry.value.template,
            );
          } else {
            _templateControllers[entry.key]!.text = entry.value.template;
          }
          _templateEnabledState[entry.key] = entry.value.enabled;
        }
      });
    }
  }

  Future<void> _fetchLogs() async {
    if (_isRefreshingLogs) return;
    _isRefreshingLogs = true;
    try {
      final logs = await WhatsAppService.getLogs();
      logs.sort((a, b) {
        final dateA =
            DateTime.tryParse(a.timestamp) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateB =
            DateTime.tryParse(b.timestamp) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
      if (mounted) setState(() => _logs = logs);
    } finally {
      _isRefreshingLogs = false;
    }
  }

  Future<void> _handleConnect() async {
    setState(() => _isConnecting = true);
    final ok = await WhatsAppService.connect();
    if (!ok) {
      if (mounted) {
        setState(() => _isConnecting = false);
        final details =
            WhatsAppService.lastConnectError ?? _status.initializationError;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              details == null || details.isEmpty
                  ? 'Could not reach WhatsApp service. Check your connection and try again.'
                  : 'WhatsApp: $details',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Poll while the WhatsApp socket initializes and generates a QR code.
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) break;
      await _fetchStatus(silent: true);
      if (_status.hasActiveQr || _status.isReady) {
        break;
      }
    }

    if (mounted) {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _handleDisconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Disconnect WhatsApp?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will unlink your hotel WhatsApp session. Automated guest messages will be paused until you re-link your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDisconnecting = true);
    final ok = await WhatsAppService.disconnect();
    await _fetchStatus(silent: true);
    if (mounted) {
      setState(() => _isDisconnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'WhatsApp session disconnected.'
                : 'Failed to disconnect session.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSaveTemplate(
    String templateId,
    StateSetter setModalState,
  ) async {
    final template = _templates[templateId];
    final ctrl = _templateControllers[templateId];
    if (template == null || ctrl == null) return;

    setState(() => _isSavingTemplate = true);
    setModalState(() {});

    final updated = template.copyWith(
      template: ctrl.text.trim(),
      enabled: _templateEnabledState[templateId] ?? true,
    );

    final ok = await WhatsAppService.updateTemplate(updated);
    if (mounted) {
      setState(() {
        _isSavingTemplate = false;
        if (ok) {
          _templates[templateId] = updated;
        }
      });
      setModalState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Template "${updated.name}" saved successfully!'
                : 'Failed to save template.',
          ),
          backgroundColor: ok ? const Color(0xFF10B981) : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleResetTemplates(StateSetter setModalState) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Reset All Templates?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will restore all WhatsApp message templates back to their factory default wording.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset Defaults'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    await WhatsAppService.resetTemplates();
    await _fetchTemplates();
    if (mounted) {
      setState(() => _isLoading = false);
      setModalState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All templates have been reset to factory defaults.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSendTestMessage(StateSetter setModalState) async {
    String rawDigits = _testPhoneController.text.replaceAll(RegExp(r'\D'), '');
    if (rawDigits.length == 12 && rawDigits.startsWith('91')) {
      rawDigits = rawDigits.substring(2);
    } else if (rawDigits.length == 11 && rawDigits.startsWith('0')) {
      rawDigits = rawDigits.substring(1);
    }

    if (rawDigits.length != 10) {
      _dispatcherFeedbackMessage =
          'Please enter a valid 10-digit Indian mobile number.';
      _dispatcherFeedbackIsError = true;
      setModalState(() {});
      return;
    }

    // Keep the clean 10 digits in controller
    _testPhoneController.text = rawDigits;
    final phone = '+91$rawDigits';

    final store = context.read<HotelStore>();
    setState(() => _isSendingTest = true);
    _dispatcherFeedbackMessage = null;
    setModalState(() {});

    final sampleContext = {
      'guestName': 'Devika Rao',
      'hotelName': store.currentProperty.name,
      'roomNumber': '104',
      'checkInDate': DateFormat('dd MMM yyyy').format(DateTime.now()),
      'checkOutDate': DateFormat(
        'dd MMM yyyy',
      ).format(DateTime.now().add(const Duration(days: 1))),
    };

    final messageToSend = _testTemplateId == 'custom'
        ? _testCustomMsgController.text.trim()
        : _liveDispatchMsgController.text.trim();

    final res = await WhatsAppService.sendTestMessage(
      recipientPhone: phone,
      templateId:
          null, // send as customized message so single-send edits are delivered exactly as edited
      customMessage: messageToSend,
      context: sampleContext,
    );

    if (mounted) {
      setState(() => _isSendingTest = false);
      if (res['success'] == true &&
          res['accepted'] == true &&
          res['suppressed'] != true) {
        _dispatcherFeedbackMessage = res['selfSend'] == true
            ? 'WhatsApp accepted this message to the connected number. Delivery is not independently confirmed; test another WhatsApp number to verify recipient delivery.'
            : 'WhatsApp accepted the message for $phone. Recipient delivery is not confirmed.';
        _dispatcherFeedbackIsError = false;
      } else if (res['suppressed'] == true) {
        _dispatcherFeedbackMessage =
            res['message'] ??
            'Duplicate skipped — this number already received that template recently.';
        _dispatcherFeedbackIsError = true;
      } else {
        _dispatcherFeedbackMessage =
            res['error'] ??
            res['message'] ??
            'Failed to send WhatsApp message. Ensure session is connected.';
        _dispatcherFeedbackIsError = true;
      }
      setModalState(() {});
      _fetchLogs().then((_) {
        if (mounted) setModalState(() {});
      });
    }
  }

  void _insertPlaceholder(
    String templateId,
    String placeholder,
    StateSetter setModalState,
  ) {
    final ctrl = _templateControllers[templateId];
    if (ctrl == null) return;

    final text = ctrl.text;
    final selection = ctrl.selection;

    if (selection.start >= 0) {
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        placeholder,
      );
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + placeholder.length,
        ),
      );
    } else {
      ctrl.text = '$text $placeholder';
    }
    setState(() {});
    setModalState(() {});
  }

  String _renderInterpolatedPreview(String rawTemplate) {
    final store = context.read<HotelStore>();
    final hotelName = store.currentProperty.name;
    final now = DateTime.now();
    final checkIn = DateFormat('dd MMM yyyy').format(now);
    final checkOut = DateFormat(
      'dd MMM yyyy',
    ).format(now.add(const Duration(days: 1)));

    return rawTemplate
        .replaceAll('{guestName}', 'Ananya Deshmukh')
        .replaceAll('{hotelName}', hotelName)
        .replaceAll('{roomNumber}', '104')
        .replaceAll('{checkInDate}', checkIn)
        .replaceAll('{checkOutDate}', checkOut);
  }

  // ── BEST PRACTICES & GUIDELINES MODAL ──
  void _showGuidelinesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.slateBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp Automation Guidelines',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      Text(
                        'Best practices for hotel guest messaging',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildGuidelineItem(
              icon: Icons.check_circle_outline_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Operational Messages Only',
              description:
                  'Use strictly for 1-on-1 guest interactions such as check-in welcomes, room keys, and checkout invoices.',
            ),
            const SizedBox(height: 12),
            _buildGuidelineItem(
              icon: Icons.block_flipped,
              iconColor: const Color(0xFFEF4444),
              title: 'Avoid Bulk Spam',
              description:
                  'Never use this account for bulk advertising or unsolicited marketing blasts to protect your number from restrictions.',
            ),
            const SizedBox(height: 12),
            _buildGuidelineItem(
              icon: Icons.verified_user_outlined,
              iconColor: const Color(0xFF25D366),
              title: 'Direct Phone Link',
              description:
                  'Messages are dispatched directly from your linked WhatsApp instance without third-party recurring API fees.',
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.slateDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Understood'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidelineItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: AppTheme.slateMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── FULL PAGE DRAWER 1: EDIT MESSAGE TEMPLATES ──
  void _openTemplateEditorDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final template = _templates[_selectedTemplateId];
            final ctrl = _templateControllers[_selectedTemplateId];
            final isEnabled =
                _templateEnabledState[_selectedTemplateId] ?? true;

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Drawer drag handle & header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppTheme.slateBorder,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppTheme.brandPrimary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.edit_note_rounded,
                                color: AppTheme.brandPrimary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Message Templates',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                  Text(
                                    'Customize automated guest notifications',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _handleResetTemplates(setModalState),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                'Reset Defaults',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.brandPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppTheme.slateMuted,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: AppTheme.slateBorder),

                  // Template selection pill tabs
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTemplateTabItem(
                            'checkin_welcome',
                            'Check-in Welcome',
                            setModalState,
                          ),
                          const SizedBox(width: 8),
                          _buildTemplateTabItem(
                            'checkout_thankyou',
                            'Checkout Thank-you',
                            setModalState,
                          ),
                          const SizedBox(width: 8),
                          _buildTemplateTabItem(
                            'booking_confirmation',
                            'Booking Confirmed',
                            setModalState,
                          ),
                          const SizedBox(width: 8),
                          _buildTemplateTabItem(
                            'custom_notification',
                            'Custom Notice',
                            setModalState,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(height: 1, color: AppTheme.slateBorder),

                  // Drawer scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (template != null && ctrl != null) ...[
                            // Active status & toggle
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.slateBorder),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          template.name,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                            color: AppTheme.slateDark,
                                          ),
                                        ),
                                        Text(
                                          template.description,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppTheme.slateMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    children: [
                                      Text(
                                        isEnabled ? 'ACTIVE' : 'MUTED',
                                        style: GoogleFonts.inter(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isEnabled
                                              ? const Color(0xFF16A34A)
                                              : AppTheme.slateMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Switch(
                                        value: isEnabled,
                                        activeThumbColor: const Color(
                                          0xFF25D366,
                                        ),
                                        onChanged: (val) {
                                          setState(() {
                                            _templateEnabledState[_selectedTemplateId] =
                                                val;
                                          });
                                          setModalState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 1. Template Wording Editor
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Template Wording:',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slateDark,
                                  ),
                                ),
                                Text(
                                  '${ctrl.text.length} chars',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: ctrl,
                              maxLines: 5,
                              onChanged: (_) {
                                setState(() {});
                                setModalState(() {});
                              },
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.slateDark,
                                height: 1.4,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Type your WhatsApp template message...',
                                contentPadding: const EdgeInsets.all(14),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: AppTheme.slateBorder,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: AppTheme.slateBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: AppTheme.brandPrimary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // 2. Minimized Horizontal Variables Row (Below Template Wording)
                            Row(
                              children: [
                                Text(
                                  'Insert: ',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Row(
                                      children: _placeholders.map((p) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: ActionChip(
                                            label: Text(p['key']!),
                                            labelStyle: GoogleFonts.robotoMono(
                                              fontSize: 10,
                                              color: AppTheme.brandDark,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            backgroundColor:
                                                AppTheme.brandLight,
                                            side: BorderSide.none,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 0,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => _insertPlaceholder(
                                              _selectedTemplateId,
                                              p['key']!,
                                              setModalState,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // WhatsApp Chat Bubble Preview
                            Text(
                              'Guest WhatsApp Preview:',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFEAE2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE5DDD5),
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 300,
                                  ),
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    14,
                                    8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCF8C6),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(14),
                                      topRight: Radius.circular(14),
                                      bottomRight: Radius.circular(14),
                                      bottomLeft: Radius.circular(3),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _renderInterpolatedPreview(ctrl.text),
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: const Color(0xFF111827),
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            DateFormat(
                                              'hh:mm a',
                                            ).format(DateTime.now()),
                                            style: GoogleFonts.inter(
                                              fontSize: 9.5,
                                              color: const Color(0xFF6B7280),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.done_all_rounded,
                                            size: 14,
                                            color: Color(0xFF34B7F1),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Bottom Save Action
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: const Border(
                        top: BorderSide(color: AppTheme.slateBorder),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          offset: const Offset(0, -2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: PressableScale(
                        pressedScale: 0.97,
                        child: ElevatedButton.icon(
                          onPressed: _isSavingTemplate
                              ? null
                              : () => _handleSaveTemplate(
                                  _selectedTemplateId,
                                  setModalState,
                                ),
                          icon: _isSavingTemplate
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                            _isSavingTemplate
                                ? 'Saving Changes...'
                                : 'Save Template Changes',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTemplateTabItem(
    String id,
    String title,
    StateSetter setModalState,
  ) {
    final isSelected = _selectedTemplateId == id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTemplateId = id;
        });
        setModalState(() {});
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.brandPrimary : AppTheme.slateBorder,
          ),
        ),
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.slateDark,
          ),
        ),
      ),
    );
  }

  // ── FULL PAGE DRAWER 2: SEND LIVE MESSAGE & DELIVERY AUDIT LOGS ──
  void _openLiveDispatcherDrawer() {
    if (!_hasManualLiveEdit || _liveDispatchMsgController.text.trim().isEmpty) {
      if (_testTemplateId != 'custom') {
        _liveDispatchMsgController.text = _renderInterpolatedPreview(
          _templates[_testTemplateId]?.template ?? '',
        );
        _hasManualLiveEdit = false;
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isConnected = _status.isReady;

            return DefaultTabController(
              length: 2,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.92,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Drag handle & Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppTheme.slateBorder,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Color(0xFF10B981),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Live WhatsApp Dispatcher',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                    Text(
                                      'Send a test message and see acceptance and recipient receipts',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: AppTheme.slateMuted,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Top Tab Bar for Compose vs Logs
                    TabBar(
                      labelColor: AppTheme.brandPrimary,
                      unselectedLabelColor: AppTheme.slateMuted,
                      labelStyle: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
                      indicatorColor: AppTheme.brandPrimary,
                      indicatorWeight: 2.5,
                      tabs: [
                        const Tab(text: 'Compose & Send'),
                        Tab(text: 'Delivery Logs (${_logs.length})'),
                      ],
                    ),

                    const Divider(height: 1, color: AppTheme.slateBorder),

                    // Tab View
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Tab 1: Compose & Send
                          SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!isConnected)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFFECACA),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: Color(0xFFDC2626),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'WhatsApp is currently disconnected. Link your WhatsApp account first to send live messages.',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              color: const Color(0xFF991B1B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Recipient Phone Number
                                Text(
                                  'Guest Mobile Number (10 digits) *',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slateDark,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _testPhoneController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.1,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '99XXX XXXXX',
                                    hintStyle: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      color: AppTheme.slateMuted,
                                      letterSpacing: 1,
                                    ),
                                    prefixIcon: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      margin: const EdgeInsets.only(right: 10),
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: AppTheme.slateBorder,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            '🇮🇳',
                                            style: TextStyle(fontSize: 15),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '+91',
                                            style: GoogleFonts.inter(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.slateDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.slateBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.slateBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.brandPrimary,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Template Selection
                                Text(
                                  'Select Message Template',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slateDark,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _testTemplateId,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppTheme.slateDark,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.slateBorder,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.slateBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: AppTheme.brandPrimary,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'checkin_welcome',
                                      child: Text('Check-in Welcome'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'checkout_thankyou',
                                      child: Text('Checkout Thank-you'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'booking_confirmation',
                                      child: Text('Booking Confirmation'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'custom',
                                      child: Text('Custom Text Notice'),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _testTemplateId = val;
                                        if (val != 'custom') {
                                          _liveDispatchMsgController.text =
                                              _renderInterpolatedPreview(
                                                _templates[val]?.template ?? '',
                                              );
                                          _hasManualLiveEdit = false;
                                        }
                                      });
                                      setModalState(() {});
                                    }
                                  },
                                ),

                                if (_testTemplateId == 'custom') ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    'Custom Message Text',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _testCustomMsgController,
                                    maxLines: 4,
                                    style: GoogleFonts.inter(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Enter your custom message to dispatch...',
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppTheme.slateBorder,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppTheme.slateBorder,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppTheme.brandPrimary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    'Message Content',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _liveDispatchMsgController,
                                    maxLines: 5,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: AppTheme.slateDark,
                                      height: 1.35,
                                    ),
                                    onChanged: (_) {
                                      _hasManualLiveEdit = true;
                                    },
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppTheme.slateBorder,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppTheme.slateBorder,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: AppTheme.brandPrimary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],

                                if (_dispatcherFeedbackMessage != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _dispatcherFeedbackIsError
                                          ? const Color(0xFFFEF2F2)
                                          : const Color(0xFFF0FDF4),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _dispatcherFeedbackIsError
                                            ? const Color(0xFFFECACA)
                                            : const Color(0xFFBBF7D0),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          _dispatcherFeedbackIsError
                                              ? Icons.error_outline_rounded
                                              : Icons.check_circle_rounded,
                                          color: _dispatcherFeedbackIsError
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFF16A34A),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _dispatcherFeedbackMessage!,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: _dispatcherFeedbackIsError
                                                  ? const Color(0xFF991B1B)
                                                  : const Color(0xFF166534),
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 20),

                                SizedBox(
                                  height: 48,
                                  child: PressableScale(
                                    pressedScale: 0.97,
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          (!isConnected || _isSendingTest)
                                          ? null
                                          : () => _handleSendTestMessage(
                                              setModalState,
                                            ),
                                      icon: _isSendingTest
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.send_rounded,
                                              size: 18,
                                            ),
                                      label: Text(
                                        _isSendingTest
                                            ? 'Sending Message...'
                                            : 'Send WhatsApp Message Now',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF10B981,
                                        ),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Tab 2: Delivery Logs
                          RefreshIndicator(
                            onRefresh: () async {
                              await _fetchLogs();
                              setModalState(() {});
                            },
                            child: _logs.isEmpty
                                ? ListView(
                                    children: [
                                      const SizedBox(height: 60),
                                      Center(
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.mark_email_read_outlined,
                                              size: 48,
                                              color: AppTheme.slateBorder,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'No WhatsApp logs yet',
                                              style: GoogleFonts.outfit(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: AppTheme.slateDark,
                                              ),
                                            ),
                                            Text(
                                              'Dispatched messages will show up here.',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: AppTheme.slateMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: _logs.length,
                                    separatorBuilder: (_, __) => const Divider(
                                      color: Color(0xFFF1F5F9),
                                      height: 1,
                                    ),
                                    itemBuilder: (ctx, i) {
                                      final log = _logs[i];
                                      final isAccepted =
                                          log.status == 'ACCEPTED' ||
                                          log.status == 'SENT';
                                      final isDelivered =
                                          log.delivered ||
                                          log.deliveryStatus == 'DELIVERED' ||
                                          log.deliveryStatus == 'READ';

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              margin: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: isAccepted
                                                    ? const Color(0xFFFEF3C7)
                                                    : const Color(0xFFFEE2E2),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                isDelivered
                                                    ? Icons.done_all_rounded
                                                    : isAccepted
                                                    ? Icons.schedule_rounded
                                                    : Icons.close_rounded,
                                                color: isDelivered
                                                    ? const Color(0xFF16A34A)
                                                    : isAccepted
                                                    ? const Color(0xFFD97706)
                                                    : const Color(0xFFDC2626),
                                                size: 14,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        log.recipientPhone,
                                                        style:
                                                            GoogleFonts.inter(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 13,
                                                              color: AppTheme
                                                                  .slateDark,
                                                            ),
                                                      ),
                                                      Text(
                                                        _formatLogTime(
                                                          log.timestamp,
                                                        ),
                                                        style:
                                                            GoogleFonts.inter(
                                                              fontSize: 10.5,
                                                              color: AppTheme
                                                                  .slateMuted,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '${log.templateId} • ${log.messageText}',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11.5,
                                                      color:
                                                          AppTheme.slateMuted,
                                                      height: 1.3,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    isDelivered
                                                        ? 'Delivered to recipient'
                                                        : isAccepted &&
                                                              DateTime.now().difference(
                                                                    DateTime.tryParse(
                                                                          log.timestamp,
                                                                        ) ??
                                                                        DateTime.now(),
                                                                  ) >=
                                                                  const Duration(
                                                                    minutes: 1,
                                                                  )
                                                        ? 'No delivery receipt after 1 min · delivery unconfirmed'
                                                        : isAccepted
                                                        ? 'Accepted by WhatsApp · awaiting delivery receipt'
                                                        : log.errorMessage ??
                                                              'Not sent',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10.5,
                                                      color: isDelivered
                                                          ? const Color(
                                                              0xFF15803D,
                                                            )
                                                          : isAccepted
                                                          ? const Color(
                                                              0xFFB45309,
                                                            )
                                                          : const Color(
                                                              0xFFB91C1C,
                                                            ),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chat_rounded,
                color: Color(0xFF25D366),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WhatsApp Automation',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: AppTheme.slateDark,
                  ),
                ),
                Text(
                  'Guest Transactional Messaging',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: AppTheme.slateMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Operational Guidelines',
            icon: const Icon(
              Icons.info_outline_rounded,
              color: AppTheme.slateMuted,
              size: 22,
            ),
            onPressed: _showGuidelinesSheet,
          ),
          IconButton(
            tooltip: 'Refresh Status',
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.brandPrimary,
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                    color: AppTheme.brandPrimary,
                    size: 22,
                  ),
            onPressed: () => _initData(),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.slateBorder, height: 1),
        ),
      ),
      body: _isLoading && _templates.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.brandPrimary),
                  SizedBox(height: 12),
                  Text('Loading WhatsApp engine state...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _initData,
              color: AppTheme.brandPrimary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. WhatsApp Connection Hero Card (No overflow, fully responsive)
                    _buildConnectionHeroCard(),

                    const SizedBox(height: 20),

                    // Section Header
                    Text(
                      'Messaging Controls',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 2. Action Card 1: Message Templates
                    _buildTemplateActionCard(),

                    const SizedBox(height: 14),

                    // 3. Action Card 2: Send Live Message Dispatcher
                    _buildLiveDispatcherActionCard(),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  // ── 1. WHATSAPP CONNECTION HERO CARD ──
  Widget _buildConnectionHeroCard() {
    final isReady = _status.isReady;
    final hasQr = _status.hasActiveQr && _status.qrCodeDataUrl != null;

    if (isReady) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Color(0xFF16A34A),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _status.connectedPushname?.isNotEmpty == true
                              ? _status.connectedPushname!
                              : 'Hotel WhatsApp',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: const Color(0xFF14532D),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Active',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _status.connectedNumber != null
                        ? '+${_status.connectedNumber}'
                        : 'Automated messages active',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                  Text(
                    WhatsAppService.baseUrl.replaceFirst(
                      RegExp(r'https?://'),
                      '',
                    ),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: const Color(0xFF86EFAC),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: _isDisconnecting ? null : _handleDisconnect,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  _isDisconnecting ? 'Unlinking...' : 'Disconnect',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFDC2626),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (hasQr) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFBAE6FD), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Scan WhatsApp QR Code',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Open WhatsApp on phone > Settings > Linked Devices > Link a Device',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.slateBorder, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _renderQrImage(_status.qrCodeDataUrl!),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: PressableScale(
                pressedScale: 0.97,
                child: ElevatedButton.icon(
                  onPressed: _isConnecting ? null : _handleConnect,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh QR Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Actively generating QR code state
    if (_isConnecting || _status.status == 'INITIALIZING') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFBAE6FD), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0284C7).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF25D366),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Generating WhatsApp QR Code...',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Initializing secure session. The QR code will appear here in a few seconds.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.slateMuted,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    // Disconnected state
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Color(0xFF25D366),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect WhatsApp',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    Text(
                      'Link your hotel account to automate guest messages',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: PressableScale(
              pressedScale: 0.97,
              child: ElevatedButton.icon(
                onPressed: _isConnecting ? null : _handleConnect,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.qr_code_rounded, size: 18),
                label: Text(
                  _isConnecting
                      ? 'Initializing Session...'
                      : 'Connect WhatsApp & Show QR Code',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderQrImage(String dataUrl) {
    try {
      final base64String = dataUrl.split(',').last;
      final bytes = base64Decode(base64String);
      return Image.memory(bytes, width: 190, height: 190, fit: BoxFit.contain);
    } catch (_) {
      return Container(
        width: 190,
        height: 190,
        color: const Color(0xFFF1F5F9),
        child: const Center(
          child: Text(
            'QR Code format error',
            style: TextStyle(fontSize: 11, color: AppTheme.slateMuted),
          ),
        ),
      );
    }
  }

  // ── 2. CARD: EDIT MESSAGE TEMPLATES (Minimal & Clean) ──
  Widget _buildTemplateActionCard() {
    final activeCount = _templateEnabledState.values.where((v) => v).length;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _openTemplateEditorDrawer,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.slateBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.brandPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: AppTheme.brandPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message Templates',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Check-in, checkout & booking messages',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.brandLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$activeCount/4 Active',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.brandDark,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.slateMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 3. CARD: SEND LIVE MESSAGE DISPATCHER (Minimal & Clean) ──
  Widget _buildLiveDispatcherActionCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _openLiveDispatcherDrawer,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.slateBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send Live Message',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Direct notices, test sends & logs',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_logs.length} Sent Logs',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.slateMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLogTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('hh:mm a, dd MMM').format(dt);
    } catch (_) {
      return isoString;
    }
  }
}
