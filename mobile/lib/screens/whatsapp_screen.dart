import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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

class _WhatsAppScreenState extends State<WhatsAppScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _statusPoller;

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
  String _testTemplateId = 'checkin_welcome';

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
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedTemplateId = _templateIdForIndex(_tabController.index);
        });
      }
    });

    _initData();

    // Auto-poll status every 4 seconds while screen is open (to catch QR scans)
    _statusPoller = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _fetchStatus(silent: true);
    });
  }

  @override
  void dispose() {
    _statusPoller?.cancel();
    _tabController.dispose();
    for (final c in _templateControllers.values) {
      c.dispose();
    }
    _testPhoneController.dispose();
    _testCustomMsgController.dispose();
    super.dispose();
  }

  String _templateIdForIndex(int index) {
    switch (index) {
      case 0:
        return 'checkin_welcome';
      case 1:
        return 'checkout_thankyou';
      case 2:
        return 'booking_confirmation';
      case 3:
      default:
        return 'custom_notification';
    }
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
            _templateControllers[entry.key] = TextEditingController(text: entry.value.template);
          } else {
            _templateControllers[entry.key]!.text = entry.value.template;
          }
          _templateEnabledState[entry.key] = entry.value.enabled;
        }
      });
    }
  }

  Future<void> _fetchLogs() async {
    final logs = await WhatsAppService.getLogs();
    if (mounted) {
      setState(() => _logs = logs);
    }
  }

  Future<void> _handleConnect() async {
    setState(() => _isConnecting = true);
    final ok = await WhatsAppService.connect();
    await _fetchStatus(silent: true);
    if (mounted) {
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Generating WhatsApp QR Code...' : 'Failed to connect. Check server URL.'),
          backgroundColor: ok ? const Color(0xFF10B981) : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleDisconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Disconnect WhatsApp?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: const Text(
          'This will terminate the active WhatsApp Web session and clear stored session tokens. You will need to re-scan the QR code to re-enable automated messaging.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
          content: Text(ok ? 'WhatsApp session disconnected.' : 'Failed to disconnect session.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSaveTemplate() async {
    final template = _templates[_selectedTemplateId];
    final ctrl = _templateControllers[_selectedTemplateId];
    if (template == null || ctrl == null) return;

    setState(() => _isSavingTemplate = true);
    final updated = template.copyWith(
      template: ctrl.text.trim(),
      enabled: _templateEnabledState[_selectedTemplateId] ?? true,
    );

    final ok = await WhatsAppService.updateTemplate(updated);
    if (mounted) {
      setState(() => _isSavingTemplate = false);
      if (ok) {
        _templates[_selectedTemplateId] = updated;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved "${updated.name}" template successfully!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save template. Check server connection.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleResetTemplates() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset All Templates?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: const Text(
          'This will revert all 4 WhatsApp templates back to factory default wording. Any customizations will be lost.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brandPrimary, foregroundColor: Colors.white),
            child: const Text('Reset to Defaults'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All templates reset to factory defaults.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSendTestMessage() async {
    final phone = _testPhoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a recipient phone number.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final store = context.read<HotelStore>();
    setState(() => _isSendingTest = true);

    final sampleContext = {
      'guestName': 'Devika Rao',
      'hotelName': store.currentProperty.name,
      'roomNumber': '104',
      'checkInDate': DateFormat('dd MMM yyyy').format(DateTime.now()),
      'checkOutDate': DateFormat('dd MMM yyyy').format(DateTime.now().add(const Duration(days: 1))),
    };

    final res = await WhatsAppService.sendTestMessage(
      recipientPhone: phone,
      templateId: _testTemplateId == 'custom' ? null : _testTemplateId,
      customMessage: _testTemplateId == 'custom' ? _testCustomMsgController.text.trim() : null,
      context: sampleContext,
    );

    if (mounted) {
      setState(() => _isSendingTest = false);
      _fetchLogs();
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test WhatsApp message delivered to $phone!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['error'] ?? 'Failed to send WhatsApp message.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _insertPlaceholder(String placeholder) {
    final ctrl = _templateControllers[_selectedTemplateId];
    if (ctrl == null) return;

    final text = ctrl.text;
    final selection = ctrl.selection;

    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, placeholder);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + placeholder.length),
      );
    } else {
      ctrl.text = '$text $placeholder';
    }
    setState(() {});
  }

  String _renderInterpolatedPreview(String rawTemplate) {
    final store = context.read<HotelStore>();
    final hotelName = store.currentProperty.name;
    final now = DateTime.now();
    final checkIn = DateFormat('dd MMM yyyy').format(now);
    final checkOut = DateFormat('dd MMM yyyy').format(now.add(const Duration(days: 1)));

    return rawTemplate
        .replaceAll('{guestName}', 'Ananya Deshmukh')
        .replaceAll('{hotelName}', hotelName)
        .replaceAll('{roomNumber}', '104')
        .replaceAll('{checkInDate}', checkIn)
        .replaceAll('{checkOutDate}', checkOut);
  }

  void _showServerSettingsDialog() {
    final current = WhatsAppService.baseUrl;
    final customCtrl = TextEditingController(text: current);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.dns_rounded, color: AppTheme.brandPrimary, size: 20),
            const SizedBox(width: 8),
            Text('WhatsApp Backend URL', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select the backend address where EaseInn ocr-server is running:',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Emulator (10.0.2.2:3001)', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    customCtrl.text = 'http://10.0.2.2:3001';
                  },
                ),
                ActionChip(
                  label: const Text('Localhost (3001)', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    customCtrl.text = 'http://localhost:3001';
                  },
                ),
                ActionChip(
                  label: const Text('LAN (192.168.104.223)', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    customCtrl.text = 'http://192.168.104.223:3001';
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: customCtrl,
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Server Base URL',
                labelStyle: GoogleFonts.inter(fontSize: 12),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (customCtrl.text.trim().isNotEmpty) {
                await WhatsAppService.setBaseUrl(customCtrl.text.trim());
                if (mounted) {
                  Navigator.pop(ctx);
                  _initData();
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brandPrimary, foregroundColor: Colors.white),
            child: const Text('Save & Reconnect'),
          ),
        ],
      ),
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
              child: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WhatsApp Automation',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: AppTheme.slateDark),
                ),
                Text(
                  'One-Way Transactional Messaging',
                  style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.slateMuted, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Server Connection Settings',
            icon: const Icon(Icons.settings_ethernet_rounded, color: AppTheme.slateMuted, size: 22),
            onPressed: _showServerSettingsDialog,
          ),
          IconButton(
            tooltip: 'Refresh Status',
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brandPrimary),
                  )
                : const Icon(Icons.refresh_rounded, color: AppTheme.brandPrimary, size: 22),
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. WhatsApp Pairing & Status Card
                    _buildPairingCard(),

                    const SizedBox(height: 16),

                    // 2. Risk Advisory Card
                    _buildRiskNoticeCard(),

                    const SizedBox(height: 20),

                    // 3. Template Editor Section
                    _buildTemplateSection(),

                    const SizedBox(height: 20),

                    // 4. Test Dispatcher
                    _buildTestDispatcherCard(),

                    const SizedBox(height: 20),

                    // 5. Audit & Delivery Logs
                    _buildLogsCard(),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ── 1. PAIRING & STATUS CARD ──
  Widget _buildPairingCard() {
    final isReady = _status.isReady;
    final hasQr = _status.hasActiveQr && _status.qrCodeDataUrl != null;

    Color badgeBg;
    Color badgeText;
    String statusTitle;
    IconData statusIcon;

    if (isReady) {
      badgeBg = const Color(0xFFDCFCE7);
      badgeText = const Color(0xFF15803D);
      statusTitle = 'Connected & Active';
      statusIcon = Icons.check_circle_rounded;
    } else if (_status.status == 'AUTHENTICATING') {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFB45309);
      statusTitle = 'Authenticating...';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (hasQr) {
      badgeBg = const Color(0xFFE0F2FE);
      badgeText = const Color(0xFF0369A1);
      statusTitle = 'QR Code Ready to Scan';
      statusIcon = Icons.qr_code_scanner_rounded;
    } else {
      badgeBg = const Color(0xFFF1F5F9);
      badgeText = const Color(0xFF64748B);
      statusTitle = 'Disconnected';
      statusIcon = Icons.link_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isReady ? const Color(0xFF86EFAC) : AppTheme.slateBorder, width: isReady ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row with status badge
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp Account Pairing',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.slateDark),
                      ),
                      Text(
                        'Session: LocalAuth (.wwebjs_auth)',
                        style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.slateMuted),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: badgeText, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      statusTitle,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: badgeText),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // If connected
          if (isReady) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _status.connectedPushname?.isNotEmpty == true
                              ? _status.connectedPushname!
                              : 'Linked Hotel Account',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF14532D)),
                        ),
                        Text(
                          _status.connectedNumber != null ? '+${_status.connectedNumber}' : 'Session active & authenticated',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF15803D)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: PressableScale(
                pressedScale: 0.96,
                child: OutlinedButton.icon(
                  onPressed: _isDisconnecting ? null : _handleDisconnect,
                  icon: _isDisconnecting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text('Disconnect / Switch Account'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ] else if (hasQr) ...[
            // QR Code rendering
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.slateBorder, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _renderQrImage(_status.qrCodeDataUrl!),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Scan with WhatsApp on your phone',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slateDark),
                  ),
                  Text(
                    'WhatsApp > Linked Devices > Link a Device',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PressableScale(
                    pressedScale: 0.96,
                    child: ElevatedButton.icon(
                      onPressed: _isConnecting ? null : _handleConnect,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('Refresh QR Code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Disconnected State
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.slateBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: AppTheme.slateMuted, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No Active WhatsApp Session',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.slateDark),
                        ),
                        Text(
                          'Tap below to initialize Puppeteer and generate a pairing QR code.',
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: PressableScale(
                pressedScale: 0.96,
                child: ElevatedButton.icon(
                  onPressed: _isConnecting ? null : _handleConnect,
                  icon: _isConnecting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.qr_code_rounded, size: 18),
                  label: Text(_isConnecting ? 'Launching Session...' : 'Connect WhatsApp & Show QR Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _renderQrImage(String dataUrl) {
    try {
      final base64String = dataUrl.split(',').last;
      final bytes = base64Decode(base64String);
      return Image.memory(
        bytes,
        width: 190,
        height: 190,
        fit: BoxFit.contain,
      );
    } catch (_) {
      return Container(
        width: 190,
        height: 190,
        color: const Color(0xFFF1F5F9),
        child: const Center(
          child: Text('QR Code format error', style: TextStyle(fontSize: 11, color: AppTheme.slateMuted)),
        ),
      );
    }
  }

  // ── 2. RISK NOTICE ADVISORY ──
  Widget _buildRiskNoticeCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unofficial WhatsApp Automation Notice',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF92400E)),
                ),
                const SizedBox(height: 2),
                Text(
                  'This service connects via whatsapp-web.js with zero third-party API fees. Use strictly for 1-to-1 operational guest notices (check-in, check-out, bookings). Avoid bulk marketing spam to safeguard your WhatsApp account from rate-limiting or restrictions.',
                  style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFFB45309), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. TEMPLATE MANAGEMENT SECTION ──
  Widget _buildTemplateSection() {
    final currentTemplate = _templates[_selectedTemplateId];
    final ctrl = _templateControllers[_selectedTemplateId];
    final isEnabled = _templateEnabledState[_selectedTemplateId] ?? true;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              Text(
                'Editable Message Templates (4)',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.slateDark),
              ),
              InkWell(
                onTap: _handleResetTemplates,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Reset Defaults',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.brandPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tab Bar for 4 Templates
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.brandPrimary,
            unselectedLabelColor: AppTheme.slateMuted,
            labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
            indicatorColor: AppTheme.brandPrimary,
            indicatorWeight: 2.5,
            tabs: const [
              Tab(text: 'Check-in Welcome'),
              Tab(text: 'Checkout Thank-you'),
              Tab(text: 'Booking Confirmation'),
              Tab(text: 'Custom Notice'),
            ],
          ),

          const SizedBox(height: 14),

          if (currentTemplate != null && ctrl != null) ...[
            // Enable / Disable Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slateBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.between,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentTemplate.name,
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slateDark),
                      ),
                      Text(
                        currentTemplate.description,
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.slateMuted),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        isEnabled ? 'ACTIVE' : 'MUTED',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? const Color(0xFF16A34A) : AppTheme.slateMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Switch(
                        value: isEnabled,
                        activeThumbColor: const Color(0xFF25D366),
                        onChanged: (val) {
                          setState(() {
                            _templateEnabledState[_selectedTemplateId] = val;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Dynamic Placeholder Chips
            Text(
              'Dynamic Placeholders (Tap to insert):',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _placeholders.map((p) {
                return ActionChip(
                  label: Text('${p['key']} • ${p['label']}'),
                  labelStyle: GoogleFonts.mono(fontSize: 10, color: AppTheme.brandDark, fontWeight: FontWeight.w600),
                  backgroundColor: AppTheme.brandLight,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  onPressed: () => _insertPlaceholder(p['key']!),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // Template Text Area
            TextField(
              controller: ctrl,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.slateDark, height: 1.4),
              decoration: InputDecoration(
                hintText: 'Type your WhatsApp template text here...',
                contentPadding: const EdgeInsets.all(12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.slateBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.slateBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.brandPrimary)),
              ),
            ),

            const SizedBox(height: 14),

            // WhatsApp Bubble Simulation Preview
            Text(
              'Live Guest Preview (WhatsApp simulation):',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFEAE2), // WhatsApp chat wallpaper color
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5DDD5)),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 290),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCF8C6), // WhatsApp sent bubble
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                      bottomLeft: Radius.circular(3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _renderInterpolatedPreview(ctrl.text),
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF111827), height: 1.35),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            DateFormat('hh:mm a').format(DateTime.now()),
                            style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF6B7280)),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF34B7F1)), // Blue ticks
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Save Template Button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: PressableScale(
                pressedScale: 0.96,
                child: ElevatedButton.icon(
                  onPressed: _isSavingTemplate ? null : _handleSaveTemplate,
                  icon: _isSavingTemplate
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 17),
                  label: Text(_isSavingTemplate ? 'Saving...' : 'Save Template Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 4. TEST DISPATCHER CARD ──
  Widget _buildTestDispatcherCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.send_rounded, color: Color(0xFF2563EB), size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'Live Test Message Dispatcher',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.slateDark),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Recipient Phone
          TextField(
            controller: _testPhoneController,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Recipient WhatsApp Number *',
              hintText: '+91 9876543210',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),

          // Template Selector
          DropdownButtonFormField<String>(
            value: _testTemplateId,
            style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.slateDark),
            decoration: InputDecoration(
              labelText: 'Select Template to Test',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: const [
              DropdownMenuItem(value: 'checkin_welcome', child: Text('Check-in Welcome')),
              DropdownMenuItem(value: 'checkout_thankyou', child: Text('Checkout Thank-you')),
              DropdownMenuItem(value: 'booking_confirmation', child: Text('Booking Confirmation')),
              DropdownMenuItem(value: 'custom', child: Text('Custom Text Message')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _testTemplateId = val);
            },
          ),

          if (_testTemplateId == 'custom') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _testCustomMsgController,
              maxLines: 3,
              style: GoogleFonts.inter(fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'Enter custom test message...',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 42,
            child: PressableScale(
              pressedScale: 0.96,
              child: ElevatedButton.icon(
                onPressed: _isSendingTest ? null : _handleSendTestMessage,
                icon: _isSendingTest
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(_isSendingTest ? 'Sending Test...' : 'Send Test WhatsApp Message'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 5. AUDIT LOGS CARD ──
  Widget _buildLogsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              Text(
                'Recent Delivery Logs (${_logs.length})',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.slateDark),
              ),
              InkWell(
                onTap: _fetchLogs,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Refresh',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No WhatsApp messages logged yet.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _logs.take(6).length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFFF1F5F9), height: 1),
              itemBuilder: (ctx, i) {
                final log = _logs[i];
                final isSent = log.status == 'SENT';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isSent ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isSent ? Icons.check_rounded : Icons.close_rounded,
                          color: isSent ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.between,
                              children: [
                                Text(
                                  log.recipientPhone,
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.slateDark),
                                ),
                                Text(
                                  _formatLogTime(log.timestamp),
                                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.slateMuted),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Template: ${log.templateId} • ${log.messageText}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.slateMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
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
