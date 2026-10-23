import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../services/hotel_store.dart';
import '../services/ocr_service.dart';
import '../models/room.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/chatgpt_camera_sheet.dart';
import '../widgets/pressable_scale.dart';
import 'home_shell.dart';

// Formats digits into DD/MM/YYYY with automatic slash insertion
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) {
        buffer.write('/');
      }
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

enum BookingMode { checkIn, reservation }

class CheckInScreen extends StatefulWidget {
  final String? preselectedRoomId;
  final VoidCallback? onReturnHome;
  final VoidCallback? onBack;
  final BookingMode initialMode;
  const CheckInScreen({
    super.key,
    this.preselectedRoomId,
    this.onReturnHome,
    this.onBack,
    this.initialMode = BookingMode.checkIn,
  });

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  int _currentStep = 1; // 1: Room, 2: Guest & OCR, 3: Payment & Confirm
  late BookingMode _bookingMode; // checkIn vs reservation

  // Step 1: Airbnb Chooser State
  String? _selectedRoomId;
  DateTime _checkInDate = DateTime.now();
  DateTime _expectedCheckOut = DateTime.now().add(const Duration(days: 1));
  int _numAdults = 1; // Default 1 adult
  int _numKids = 0;
  int _selectedFloorFilter = 0; // 0 = all floors

  // Additional guests (beyond primary guest)
  final List<_ExtraGuest> _extraGuests = [];

  int get _totalGuests => _numAdults + _numKids;

  // Step 2: Document & OCR
  String _idType =
      'aadhaar'; // 'aadhaar', 'pan', 'passport', 'voter_id', 'driving_license'
  bool _hasFrontUploaded = false;
  bool _hasBackUploaded = false;
  Uint8List? _frontBytes;
  String? _frontFilename;
  Uint8List? _backBytes;
  String? _backFilename;
  bool _isScanning = false;
  bool _scanDone = false;
  bool _scanSuccess = false;
  int _primaryScanToken = 0;

  // Form Controllers (Auto-filled by OCR)
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  String _formatPhoneForStorage(String input) {
    final clean = input.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return '';
    if (clean.length == 10) {
      return '+91 $clean';
    } else if (clean.length == 12 && clean.startsWith('91')) {
      return '+91 ${clean.substring(2)}';
    }
    return input.startsWith('+') ? input : '+91 $clean';
  }

  final _idNumberController = TextEditingController();
  final _dobController = TextEditingController();
  final _genderController = TextEditingController(text: 'Male');
  final _addressController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _fatherNameController = TextEditingController();

  // Field Verification Helpers
  bool _isNameValid(String name) => name.trim().length >= 2;

  bool _isIdValid(String id, String type) {
    final clean = id.replaceAll(RegExp(r'\s+|-'), '').trim();
    if (clean.isEmpty) return false;
    final lower = type.toLowerCase();
    if (lower.contains('aadhaar')) {
      return RegExp(r'^\d{12}$').hasMatch(clean);
    } else if (lower.contains('pan')) {
      return RegExp(
        r'^[A-Z]{5}[0-9]{4}[A-Z]$',
        caseSensitive: false,
      ).hasMatch(clean);
    } else {
      return clean.length >= 5;
    }
  }

  bool _isDobValid(String dob) {
    final trimmed = dob.trim();
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(trimmed);
    if (match == null) return false;
    final day = int.tryParse(match.group(1)!) ?? 0;
    final month = int.tryParse(match.group(2)!) ?? 0;
    final year = int.tryParse(match.group(3)!) ?? 0;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    final currentYear = DateTime.now().year;
    if (year < 1900 || year > currentYear) return false;
    return true;
  }

  bool _isAddressValid(String address) => address.trim().length >= 4;

  bool _isPincodeValid(String pin) {
    final clean = pin.replaceAll(RegExp(r'\D'), '');
    return clean.length == 6;
  }

  bool _isPhoneValid(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    return clean.length == 10;
  }

  bool _isEmailValid(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return true; // Optional field
    return RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(trimmed);
  }

  Widget? _buildVerificationSuffix({
    required bool isValid,
    required bool isNotEmpty,
  }) {
    if (!isNotEmpty) return null;
    if (isValid) {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: Color(0xFF16A34A),
        ),
      );
    } else {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: Icon(
          Icons.error_outline_rounded,
          size: 15,
          color: Color(0xFFEF4444),
        ),
      );
    }
  }

  // Step 3: Payment & Flexible Pricing
  final _advanceController = TextEditingController();
  bool _hasManualAdvance = false;
  String _paymentMethod = 'upi'; // 'upi', 'cash', 'card'
  final _paymentRefController = TextEditingController();
  bool _sendWhatsAppMessage = true;

  // Flexible Pricing / Bargaining
  bool _isCustomPricing = false;
  double? _customTotalAmount;
  double? _customNightlyRate;

  @override
  void initState() {
    super.initState();
    _bookingMode = widget.initialMode;
    _selectedRoomId = widget.preselectedRoomId;
    final now = DateTime.now();
    _checkInDate = DateTime(now.year, now.month, now.day);
    if (_bookingMode == BookingMode.checkIn) {
      // Past 12 AM midnight, 1 night means today morning/afternoon check-out
      _expectedCheckOut = now.hour < 12
          ? _checkInDate
          : _checkInDate.add(const Duration(days: 1));
    } else {
      _expectedCheckOut = _checkInDate.add(const Duration(days: 1));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<HotelStore>();
    if (_selectedRoomId == null) {
      final available = _bookingMode == BookingMode.checkIn
          ? store.rooms.where((r) => r.status == RoomStatus.vacant).toList()
          : store.getAvailableRoomsForRange(_checkInDate, _expectedCheckOut);
      if (available.isNotEmpty) {
        _selectedRoomId = available.first.id;
      }
    }
  }

  @override
  void didUpdateWidget(covariant CheckInScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMode != oldWidget.initialMode) {
      setState(() {
        _bookingMode = widget.initialMode;
      });
    }
    if (widget.preselectedRoomId != null &&
        widget.preselectedRoomId != oldWidget.preselectedRoomId) {
      setState(() {
        _selectedRoomId = widget.preselectedRoomId;
        _currentStep = 1;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _idNumberController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    _fatherNameController.dispose();
    _advanceController.dispose();
    _paymentRefController.dispose();
    for (final g in _extraGuests) {
      g.disposeControllers();
    }
    super.dispose();
  }

  void _addExtraGuest() {
    setState(() {
      _extraGuests.add(_ExtraGuest());
    });
  }

  void _removeExtraGuest(int index) {
    setState(() {
      _extraGuests[index].disposeControllers();
      _extraGuests.removeAt(index);
    });
  }

  // ── Per-guest OCR helpers ────────────────────────────────────────────────

  void _openCameraForGuest(int index, {bool isBack = false}) {
    final g = _extraGuests[index];
    ChatGptCameraSheet.show(
      context,
      title:
          'Scan Guest ${index + 2} ${g.idType.toUpperCase()}${isBack ? ' (Back)' : ''}',
      onCaptured: (bytes, filename) {
        setState(() {
          if (isBack) {
            g.backBytes = bytes;
            g.backFilename = filename;
            g.hasBackUploaded = true;
          } else {
            g.frontBytes = bytes;
            g.frontFilename = filename;
            g.hasFrontUploaded = true;
          }
        });
        _runOcrScanForGuest(index, mergeOnly: isBack);
      },
    );
  }

  Future<void> _pickFrontFileForGuest(int index) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first;
        if (picked.bytes != null) {
          setState(() {
            _extraGuests[index].frontBytes = picked.bytes;
            _extraGuests[index].frontFilename = picked.name;
            _extraGuests[index].hasFrontUploaded = true;
          });
          _runOcrScanForGuest(index);
        }
      }
    } catch (e) {
      debugPrint('[CheckIn] FilePicker error (guest $index): $e');
    }
  }

  Future<void> _pickBackFileForGuest(int index) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first;
        if (picked.bytes != null) {
          setState(() {
            _extraGuests[index].backBytes = picked.bytes;
            _extraGuests[index].backFilename = picked.name;
            _extraGuests[index].hasBackUploaded = true;
          });
          _runOcrScanForGuest(index, mergeOnly: true);
        }
      }
    } catch (e) {
      debugPrint('[CheckIn] FilePicker error (guest $index back): $e');
    }
  }

  void _cancelExtraGuestScan(int index) {
    if (index < 0 || index >= _extraGuests.length) return;
    final g = _extraGuests[index];
    setState(() {
      g.scanToken++;
      g.isScanning = false;
      g.scanDone = true;
      g.scanSuccess = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Guest ${index + 2} scan cancelled. You can enter details manually or retry.',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _runOcrScanForGuest(int index, {bool mergeOnly = false}) async {
    if (index < 0 || index >= _extraGuests.length) return;
    final g = _extraGuests[index];
    if (!g.hasFrontUploaded || g.frontBytes == null) return;

    final token = ++g.scanToken;
    setState(() {
      g.isScanning = true;
      if (!mergeOnly) {
        g.scanDone = false;
        g.scanSuccess = false;
      }
    });

    final result = await OcrService.scanDocument(
      documentType: g.idType,
      frontBytes: g.frontBytes,
      frontFilename: g.frontFilename ?? 'document_front.jpg',
      backBytes: g.hasBackUploaded ? g.backBytes : null,
      backFilename: g.hasBackUploaded
          ? (g.backFilename ?? 'document_back.jpg')
          : null,
    );

    if (!mounted) return;
    if (token != g.scanToken) {
      // User cancelled midway, ignore response
      return;
    }

    setState(() {
      g.isScanning = false;
      g.scanDone = true;
      if (result.success) {
        g.scanSuccess = true;
        void fill(
          TextEditingController ctrl,
          String? val, {
          bool alwaysUpdate = false,
        }) {
          if (val == null || val.isEmpty) return;
          if (alwaysUpdate || ctrl.text.isEmpty) ctrl.text = val;
        }

        fill(g.nameCtrl, result.fullName);
        fill(g.idNumberCtrl, result.idNumber);
        fill(g.dobCtrl, result.dateOfBirth);
        fill(g.addressCtrl, result.address);
        fill(g.pincodeCtrl, result.pincode);
        fill(g.fatherNameCtrl, result.fatherName);
        if (result.gender != null && result.gender!.isNotEmpty) {
          final resolved = result.gender!.toLowerCase().startsWith('f')
              ? 'Female'
              : 'Male';
          if (g.genderCtrl.text.isEmpty) g.genderCtrl.text = resolved;
        }
      } else {
        if (!mergeOnly) g.scanSuccess = false;
      }
    });
  }

  // Open ChatGPT-style bottom camera sheet
  void _openCamera({bool isBack = false}) {
    ChatGptCameraSheet.show(
      context,
      title: 'Scan ${_idType.toUpperCase()}${isBack ? ' (Back)' : ''}',
      onCaptured: (bytes, filename) {
        setState(() {
          if (isBack) {
            _backBytes = bytes;
            _backFilename = filename;
            _hasBackUploaded = true;
          } else {
            _frontBytes = bytes;
            _frontFilename = filename;
            _hasFrontUploaded = true;
          }
        });
        _runOcrScan(mergeOnly: isBack);
      },
    );
  }

  // Pick real Front image from device
  Future<void> _pickFrontFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first;
        if (picked.bytes != null) {
          setState(() {
            _frontBytes = picked.bytes;
            _frontFilename = picked.name;
            _hasFrontUploaded = true;
          });
          _runOcrScan();
        }
      }
    } catch (e) {
      debugPrint('[CheckIn] FilePicker error: $e');
    }
  }

  // Pick Back image from device — triggers a merge re-scan
  Future<void> _pickBackFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first;
        if (picked.bytes != null) {
          setState(() {
            _backBytes = picked.bytes;
            _backFilename = picked.name;
            _hasBackUploaded = true;
          });
          _runOcrScan(mergeOnly: true);
        }
      }
    } catch (e) {
      debugPrint('[CheckIn] FilePicker error: $e');
    }
  }

  // Remove Back image so front-only / vertical Aadhaar is processed
  void _clearBackFile() {
    setState(() {
      _backBytes = null;
      _backFilename = null;
      _hasBackUploaded = false;
    });
  }

  void _cancelPrimaryScan() {
    setState(() {
      _primaryScanToken++;
      _isScanning = false;
      _scanDone = true;
      _scanSuccess = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Scanning cancelled. You can enter details manually or retry.',
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Run OCR Scan with REAL images.
  // [mergeOnly] = true means a back-side was just added;
  //   keep existing non-empty fields, only fill/overwrite blanks or better data.
  Future<void> _runOcrScan({bool mergeOnly = false}) async {
    if (!_hasFrontUploaded || _frontBytes == null) return;

    final token = ++_primaryScanToken;
    setState(() {
      _isScanning = true;
      if (!mergeOnly) {
        // Fresh scan — clear previous results
        _scanDone = false;
        _scanSuccess = false;
      }
    });

    final result = await OcrService.scanDocument(
      documentType: _idType,
      frontBytes: _frontBytes,
      frontFilename: _frontFilename ?? 'document_front.jpg',
      backBytes: _hasBackUploaded ? _backBytes : null,
      backFilename: _hasBackUploaded
          ? (_backFilename ?? 'document_back.jpg')
          : null,
    );

    if (!mounted) return;
    if (token != _primaryScanToken) {
      // User cancelled midway, ignore response
      return;
    }

    setState(() {
      _isScanning = false;
      _scanDone = true;

      if (result.success) {
        _scanSuccess = true;

        // Helper: overwrite only if new value is non-empty.
        // In mergeOnly mode we only fill blanks, except address/pincode
        // which are always updated when back is provided (they come from back).
        void fill(
          TextEditingController ctrl,
          String? val, {
          bool alwaysUpdate = false,
        }) {
          if (val == null || val.isEmpty) return;
          if (alwaysUpdate || ctrl.text.isEmpty) ctrl.text = val;
        }

        fill(_nameController, result.fullName);
        fill(_idNumberController, result.idNumber);
        fill(_dobController, result.dateOfBirth);
        if (result.gender != null && result.gender!.isNotEmpty) {
          final g = result.gender!.toLowerCase();
          final resolved = g.startsWith('f') ? 'Female' : 'Male';
          if (_genderController.text.isEmpty) _genderController.text = resolved;
        }
        // Address & pincode — always update from back scan
        fill(
          _addressController,
          result.address,
          alwaysUpdate: _hasBackUploaded,
        );
        fill(
          _pincodeController,
          result.pincode,
          alwaysUpdate: _hasBackUploaded,
        );
        fill(_fatherNameController, result.fatherName);
      } else {
        if (!mergeOnly)
          _scanSuccess = false; // keep success if it was already set
      }
    });
  }

  void _resetForm() {
    setState(() {
      _primaryScanToken++;
      _currentStep = 1;
      _nameController.clear();
      _phoneController.clear();
      _emailController.clear();
      _idNumberController.clear();
      _dobController.clear();
      _genderController.text = 'Male';
      _addressController.clear();
      _pincodeController.clear();
      _fatherNameController.clear();
      _advanceController.clear();
      _paymentRefController.clear();
      _frontBytes = null;
      _frontFilename = null;
      _hasFrontUploaded = false;
      _backBytes = null;
      _backFilename = null;
      _hasBackUploaded = false;
      _scanDone = false;
      _scanSuccess = false;
      for (final g in _extraGuests) {
        g.disposeControllers();
      }
      _extraGuests.clear();
      _numAdults = 1;
      _numKids = 0;
      _isCustomPricing = false;
      _customTotalAmount = null;
      _customNightlyRate = null;
      _hasManualAdvance = false;
      final now = DateTime.now();
      _checkInDate = DateTime(now.year, now.month, now.day);
      _expectedCheckOut = (_bookingMode == BookingMode.checkIn && now.hour < 12)
          ? _checkInDate
          : _checkInDate.add(const Duration(days: 1));
    });
  }

  // ignore: unused_element
  void _showEditBranchUpiDialog(BuildContext context, HotelStore store) {
    final prop = store.currentProperty;
    final upiCtrl = TextEditingController(text: prop.upiId);
    final payeeCtrl = TextEditingController(text: prop.upiPayeeName);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                color: Color(0xFF16A34A),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Branch Bank & UPI ID',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the UPI VPA / Bank ID for ${prop.name}. Guest QR payments will directly route to this account.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'UPI VPA / Bank ID *',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: upiCtrl,
              style: const TextStyle(fontSize: 13, color: AppTheme.slateDark),
              decoration: InputDecoration(
                hintText: 'e.g. piyushpal427@okaxis',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.slateMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.slateBorder),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Payee Account Name *',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: payeeCtrl,
              style: const TextStyle(fontSize: 13, color: AppTheme.slateDark),
              decoration: InputDecoration(
                hintText: 'e.g. Piyush Pal',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.slateMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.slateBorder),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.slateMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (upiCtrl.text.trim().isEmpty) return;
              store.updatePropertyUpi(
                propertyId: prop.id,
                upiId: upiCtrl.text.trim(),
                payeeName: payeeCtrl.text.trim().isEmpty
                    ? prop.name
                    : payeeCtrl.text.trim(),
              );
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Updated UPI ID to ${upiCtrl.text.trim()}'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Save Bank Details'),
          ),
        ],
      ),
    );
  }

  void _handlePaymentAndCheckIn(
    HotelStore store,
    Room selectedRoom,
    double totalEstimatedAmount,
  ) {
    final advance =
        double.tryParse(_advanceController.text) ?? selectedRoom.baseRate;
    if (_paymentMethod == 'upi') {
      _showUpiQrPaymentDialog(
        context,
        store,
        selectedRoom,
        totalEstimatedAmount,
        advance,
      );
    } else {
      _finalizeCheckIn(store, selectedRoom, totalEstimatedAmount, advance);
    }
  }

  void _showUpiQrPaymentDialog(
    BuildContext context,
    HotelStore store,
    Room selectedRoom,
    double totalEstimatedAmount,
    double advance,
  ) {
    final currentProp = store.currentProperty;
    final upiId = currentProp.upiId.trim().isNotEmpty
        ? currentProp.upiId.trim()
        : 'piyushpal427@okaxis';
    final payeeName = currentProp.upiPayeeName.trim().isNotEmpty
        ? currentProp.upiPayeeName.trim()
        : (currentProp.name.isNotEmpty ? currentProp.name : 'Piyush Pal');
    final formattedAmt = advance.toStringAsFixed(2);
    // Standard UPI URI format: upi://pay?pa=piyushpal427@okaxis&pn=Piyush%20Pal&am=2200.00&cu=INR
    final upiUri =
        'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(payeeName)}&am=$formattedAmt&cu=INR';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (qrDialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Top branding badge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 14,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'UPI Fast Pay',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Amount Display
            Text(
              '₹$formattedAmt',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Advance Payment • Room ${selectedRoom.roomNumber}',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),

            // QR Code in sleek rounded container
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SizedBox(
                width: 190,
                height: 190,
                child: QrImageView(
                  data: upiUri,
                  version: QrVersions.auto,
                  size: 190.0,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1E293B),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Account / Payee details chip
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.account_balance_outlined,
                        size: 12,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'VPA: ',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          upiId,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Payee: $payeeName',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: const Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Scan with GPay, PhonePe, Paytm, BHIM, or any UPI app',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: const Color(0xFF94A3B8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(qrDialogCtx).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(qrDialogCtx).pop();
                    _finalizeCheckIn(
                      store,
                      selectedRoom,
                      totalEstimatedAmount,
                      advance,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: Text(
                    'Payment Received (OK)',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _finalizeCheckIn(
    HotelStore store,
    Room selectedRoom,
    double totalEstimatedAmount,
    double advance,
  ) {
    final coGuestsData = _extraGuests
        .map(
          (g) => {
            'fullName': g.nameCtrl.text.trim(),
            'phone': _formatPhoneForStorage(g.phoneCtrl.text.trim()),
            'email': g.emailCtrl.text.trim().isNotEmpty
                ? g.emailCtrl.text.trim()
                : null,
            'idType': g.idType,
            'idNumber': g.idNumberCtrl.text.trim(),
            'dateOfBirth': g.dobCtrl.text.trim(),
            'gender': g.genderCtrl.text.trim(),
            'address': g.addressCtrl.text.trim(),
            'pincode': g.pincodeCtrl.text.trim(),
            'fatherName': g.fatherNameCtrl.text.trim(),
          },
        )
        .toList();

    final primaryEmail = _emailController.text.trim().isNotEmpty
        ? _emailController.text.trim()
        : null;
    final primaryPhone = _formatPhoneForStorage(_phoneController.text.trim());

    final diffDays = _expectedCheckOut.difference(_checkInDate).inDays;
    final nights = diffDays <= 0 ? 1 : diffDays.clamp(1, 365);
    final defaultTotal = nights * selectedRoom.baseRate;
    final totalStay = (_isCustomPricing && _customTotalAmount != null && _customTotalAmount! > 0)
        ? _customTotalAmount!
        : defaultTotal;
    final effectiveNightlyRate = totalStay / nights;

    late final Map<String, dynamic> result;
    try {
      result = _bookingMode == BookingMode.reservation
          ? store.reserveRoom(
              roomId: selectedRoom.id,
              checkInDate: _checkInDate,
              checkOutDate: _expectedCheckOut,
              numGuests: _totalGuests,
              numAdults: _numAdults,
              numKids: _numKids,
              nightlyRate: effectiveNightlyRate,
              totalStayAmount: totalStay,
              fullName: _nameController.text.trim(),
              phone: primaryPhone,
              email: primaryEmail,
              idType: _idType,
              idNumber: _idNumberController.text.trim(),
              dateOfBirth: _dobController.text.trim(),
              gender: _genderController.text.trim(),
              address: _addressController.text.trim(),
              pincode: _pincodeController.text.trim(),
              fatherName: _fatherNameController.text.trim(),
              advanceAmount: advance,
              paymentMethod: _paymentMethod,
              paymentRef: _paymentRefController.text.trim(),
              coGuests: coGuestsData,
              sendWhatsApp: _sendWhatsAppMessage,
            )
          : store.checkInGuest(
              roomId: selectedRoom.id,
              expectedCheckOut: _expectedCheckOut,
              numGuests: _totalGuests,
              numAdults: _numAdults,
              numKids: _numKids,
              nightlyRate: effectiveNightlyRate,
              totalStayAmount: totalStay,
              fullName: _nameController.text.trim(),
              phone: primaryPhone,
              email: primaryEmail,
              idType: _idType,
              idNumber: _idNumberController.text.trim(),
              dateOfBirth: _dobController.text.trim(),
              gender: _genderController.text.trim(),
              address: _addressController.text.trim(),
              pincode: _pincodeController.text.trim(),
              fatherName: _fatherNameController.text.trim(),
              advanceAmount: advance,
              paymentMethod: _paymentMethod,
              paymentRef: _paymentRefController.text.trim(),
              coGuests: coGuestsData,
              sendWhatsApp: _sendWhatsAppMessage,
            );
    } catch (error) {
      if (!mounted) return;
      final details = error.toString().replaceFirst('Exception: ', '');
      final message = details.contains('already reserved or occupied')
          ? 'This room is no longer available for these dates. Choose another room or dates.'
          : 'Could not complete ${_bookingMode == BookingMode.reservation ? 'the reservation' : 'check-in'}: $details';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final isReservation = _bookingMode == BookingMode.reservation;

    // Show Confirmation Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isReservation
                    ? AppTheme.statusReservedBg
                    : AppTheme.statusVacantBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isReservation
                    ? Icons.event_available_rounded
                    : Icons.check_circle_rounded,
                color: isReservation
                    ? AppTheme.statusReserved
                    : AppTheme.statusVacant,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isReservation ? 'Reservation Confirmed!' : 'Check-In Successful!',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isReservation
                  ? 'Room ${result['roomNumber']} reserved for ${DateFormat('d MMM').format(result['checkInAt'] as DateTime)} – ${DateFormat('d MMM yyyy').format(result['expectedCheckOut'] as DateTime)}'
                  : 'Room ${result['roomNumber']} is now marked Occupied',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.slateBorder),
              ),
              child: Column(
                children: [
                  _buildSummaryRow('Guest', result['guestName']),
                  _buildSummaryRow(
                    'Guests',
                    '$_totalGuests guest(s) ($_numAdults Adult${_numAdults > 1 ? "s" : ""}${_numKids > 0 ? ", $_numKids Kid${_numKids > 1 ? "s" : ""}" : ""})',
                  ),
                  if ((result['coGuestsCount'] as int? ?? 0) > 0)
                    _buildSummaryRow(
                      'Additional Guests',
                      '${result['coGuestsCount']} co-guest(s) registered',
                    ),
                  _buildSummaryRow(
                    isReservation ? 'Reserved Check-In' : 'Check-In',
                    DateFormat('d MMM yyyy, hh:mm a').format(
                      result['checkInAt'] as DateTime? ?? DateTime.now(),
                    ),
                  ),
                  _buildSummaryRow(
                    isReservation ? 'Reserved Check-Out' : 'Expected Check-Out',
                    DateFormat('d MMM yyyy, hh:mm a').format(
                      result['expectedCheckOut'] as DateTime? ??
                          _expectedCheckOut,
                    ),
                  ),
                  _buildSummaryRow(
                    isReservation ? 'Voucher #' : 'Invoice #',
                    result['billNumber'],
                  ),
                  _buildSummaryRow(
                    isReservation ? 'Advance Deposit' : 'Advance Paid',
                    '₹${(result['advancePaid'] as double).toInt()} (${_paymentMethod.toUpperCase()})',
                  ),
                  if (isReservation)
                    _buildSummaryRow(
                      'Status',
                      'Scheduled (Check-in on arrival)',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _resetForm();
                if (widget.onReturnHome != null) {
                  widget.onReturnHome!();
                } else if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const HomeShell(initialIndex: 0),
                    ),
                    (r) => false,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.slateDark,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Done • Return to Home',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final availableRooms = _bookingMode == BookingMode.checkIn
        ? store.rooms.where((r) => r.status == RoomStatus.vacant).toList()
        : store.getAvailableRoomsForRange(_checkInDate, _expectedCheckOut);

    final selectedRoom = availableRooms.cast<Room?>().firstWhere(
      (room) => room?.id == _selectedRoomId,
      orElse: () => availableRooms.isEmpty ? null : availableRooms.first,
    );

    final diffDays = _expectedCheckOut
        .difference(_checkInDate)
        .inDays;
    final nights = diffDays <= 0 ? 1 : diffDays.clamp(1, 365);
    final baseNightlyRate = selectedRoom?.baseRate ?? 2200.0;
    final defaultTotal = nights * baseNightlyRate;
    final totalEstimatedAmount = (_isCustomPricing && _customTotalAmount != null && _customTotalAmount! > 0)
        ? _customTotalAmount!
        : defaultTotal;
    final effectiveNightlyRate = totalEstimatedAmount / nights;

    // Set default advance if empty and not manually set
    if (!_hasManualAdvance && _advanceController.text.isEmpty && selectedRoom != null) {
      _advanceController.text = effectiveNightlyRate.toInt().toString();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: null,
      bottomNavigationBar: _buildUnifiedStickyFooter(
        selectedRoom: selectedRoom,
        nights: nights,
        totalEstimatedAmount: totalEstimatedAmount,
        effectiveNightlyRate: effectiveNightlyRate,
        isNoRooms: availableRooms.isEmpty,
        store: store,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Back Button Bar if navigated from rooms or previous tab
              if (widget.onBack != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: widget.onBack,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.slateBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.arrow_back_rounded,
                            size: 14,
                            color: AppTheme.slateDark,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Back to Rooms',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              Row(
                children: [
                  if (widget.onBack != null ||
                      widget.onReturnHome != null ||
                      Navigator.of(context).canPop()) ...[
                    IconButton(
                      onPressed: () {
                        if (widget.onBack != null) {
                          widget.onBack!();
                        } else if (widget.onReturnHome != null) {
                          widget.onReturnHome!();
                        } else if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppTheme.slateDark,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _bookingMode == BookingMode.checkIn
                          ? 'Check-In'
                          : 'Reservation',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                  ),
                  Text(
                    'Step $_currentStep of 3',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── BOOKING MODE SWITCHER (Immediate Walk-In vs Future Advance Reservation) ──
              if (_currentStep == 1) ...[
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slateBorder),
                  ),
                  child: Row(
                    children: [
                      // Option 1: Immediate Check-In
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_bookingMode != BookingMode.checkIn) {
                              final now = DateTime.now();
                              setState(() {
                                _bookingMode = BookingMode.checkIn;
                                _checkInDate = DateTime(
                                  now.year,
                                  now.month,
                                  now.day,
                                );
                                _expectedCheckOut = now.hour < 12
                                    ? _checkInDate
                                    : _checkInDate.add(const Duration(days: 1));
                              });
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _bookingMode == BookingMode.checkIn
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: _bookingMode == BookingMode.checkIn
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.how_to_reg_rounded,
                                  size: 16,
                                  color: _bookingMode == BookingMode.checkIn
                                      ? AppTheme.brandPrimary
                                      : AppTheme.slateMuted,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Check-In Now',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight:
                                        _bookingMode == BookingMode.checkIn
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: _bookingMode == BookingMode.checkIn
                                        ? AppTheme.slateDark
                                        : AppTheme.slateMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Option 2: Future Reservation
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_bookingMode != BookingMode.reservation) {
                              final now = DateTime.now();
                              setState(() {
                                _bookingMode = BookingMode.reservation;
                                // Keep next day by default, but user is free to change to today
                                final todayDate = DateTime(now.year, now.month, now.day);
                                if (_checkInDate.isBefore(todayDate)) {
                                  _checkInDate = DateTime(
                                    now.year,
                                    now.month,
                                    now.day + 1,
                                  );
                                  _expectedCheckOut = _checkInDate.add(
                                    const Duration(days: 1),
                                  );
                                } else if (_checkInDate == todayDate) {
                                  // Default reservation to tomorrow, but allow today
                                  _checkInDate = DateTime(
                                    now.year,
                                    now.month,
                                    now.day + 1,
                                  );
                                  _expectedCheckOut = _checkInDate.add(
                                    const Duration(days: 1),
                                  );
                                }
                              });
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _bookingMode == BookingMode.reservation
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: _bookingMode == BookingMode.reservation
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_available_rounded,
                                  size: 16,
                                  color: _bookingMode == BookingMode.reservation
                                      ? AppTheme.brandPrimary
                                      : AppTheme.slateMuted,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Reservation',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight:
                                        _bookingMode == BookingMode.reservation
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color:
                                        _bookingMode == BookingMode.reservation
                                        ? AppTheme.slateDark
                                        : AppTheme.slateMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // ==========================================
              // STEP 1: AIRBNB-STYLE CHOOSER (WHERE • WHEN • WHO)
              // ==========================================
              if (_currentStep == 1) ...[
                _buildWizardSectionCard(
                  child: _buildCompactRoomChooser(
                    availableRooms,
                    selectedRoom,
                    store,
                  ),
                ),
                const SizedBox(height: 8),
                _buildWizardSectionCard(
                  child: _buildCompactStaySelector(nights, store),
                ),
                const SizedBox(height: 8),
                _buildWizardSectionCard(child: _buildCompactGuestSelector()),
                const SizedBox(height: 8),
                _buildWizardSectionCard(
                  child: _buildPricingSummaryCard(
                    selectedRoom: selectedRoom,
                    nights: nights,
                    totalEstimatedAmount: totalEstimatedAmount,
                    effectiveNightlyRate: effectiveNightlyRate,
                  ),
                ),
                const SizedBox(height: 4),
              ],

              // ==========================================
              // STEP 2: GUEST DETAILS & DUAL-SIDE OCR
              // ==========================================
              if (_currentStep == 2) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.slateBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.badge_outlined,
                                color: AppTheme.brandPrimary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '2. Guest ID Verification',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: _addExtraGuest,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.brandLight,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.brandPrimary.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.add_rounded,
                                    size: 14,
                                    color: AppTheme.brandPrimary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Add Guest',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.brandPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Consolidated Primary Guest Card (identical to attached screenshot)
                      _buildPrimaryGuestCard(),

                      // ── Additional Guests ────────────────────────────────
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.group_add_rounded,
                                size: 15,
                                color: AppTheme.slateMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Additional Guests',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                              if (_extraGuests.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.brandPrimary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_extraGuests.length}',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          InkWell(
                            onTap: _addExtraGuest,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.brandLight,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.brandPrimary.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.add_rounded,
                                    size: 14,
                                    color: AppTheme.brandPrimary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Add Guest',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.brandPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_extraGuests.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Tap "Add Guest" to register additional co-guests.',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        )
                      else
                        ...List.generate(
                          _extraGuests.length,
                          (i) => _buildExtraGuestCard(i),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ==========================================
              // STEP 3: ADVANCE PAYMENT & CONFIRMATION
              // ==========================================
              if (_currentStep == 3) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.slateBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _bookingMode == BookingMode.reservation
                                ? Icons.event_available_rounded
                                : Icons.credit_card_rounded,
                            color: AppTheme.brandPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _bookingMode == BookingMode.reservation
                                ? '3. Advance Deposit & Reservation'
                                : '3. Advance Payment & Folio',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Folio Summary
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.slateDark, Color(0xFF1E1B4B)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            _buildDarkSummaryRow(
                              'Assigned Room',
                              'Room ${selectedRoom?.roomNumber} (${selectedRoom?.categoryName})',
                            ),
                            _buildDarkSummaryRow('Guest', _nameController.text),
                            _buildDarkSummaryRow(
                              _bookingMode == BookingMode.reservation
                                  ? 'Reserved Check-In'
                                  : 'Check-In Time',
                              DateFormat('d MMM yyyy, hh:mm a').format(
                                _bookingMode == BookingMode.reservation
                                    ? store.applyDefaultCheckInTime(
                                        _checkInDate,
                                      )
                                    : DateTime.now(),
                              ),
                            ),
                            _buildDarkSummaryRow(
                              'Expected Check-Out',
                              DateFormat('d MMM yyyy, hh:mm a').format(
                                store.applyDefaultCheckOutTime(
                                  _expectedCheckOut,
                                ),
                              ),
                            ),
                            _buildDarkSummaryRow(
                              'Stay Duration',
                              '$nights Night(s)',
                            ),
                            _buildDarkSummaryRow(
                              'Nightly Rate',
                              _isCustomPricing
                                  ? '₹${effectiveNightlyRate.toInt()} (Agreed Rate)'
                                  : '₹${baseNightlyRate.toInt()}',
                            ),
                            const Divider(color: Colors.white24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _bookingMode == BookingMode.reservation
                                          ? 'Total Reservation Bill'
                                          : 'Total Estimated Stay',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (_isCustomPricing) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                                        ),
                                        child: const Text(
                                          'AGREED',
                                          style: TextStyle(
                                            color: Color(0xFF34D399),
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                InkWell(
                                  onTap: () => _openPriceAdjustmentSheet(
                                    selectedRoom: selectedRoom,
                                    nights: nights,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '₹${totalEstimatedAmount.toInt()}',
                                        style: GoogleFonts.outfit(
                                          color: AppTheme.brandAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.edit_outlined,
                                        color: AppTheme.brandAccent,
                                        size: 14,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Advance Amount Paid
                      Text(
                        _bookingMode == BookingMode.reservation
                            ? 'Booking Deposit / Advance Received (₹)'
                            : 'Advance Amount Collected (₹)',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _advanceController,
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          setState(() {
                            _hasManualAdvance = true;
                          });
                        },
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                        decoration: InputDecoration(
                          prefixText: '₹ ',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppTheme.slateBorder,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildAdvanceChip(
                            'Full Stay (₹${totalEstimatedAmount.toInt()})',
                            () {
                              setState(() {
                                _advanceController.text = totalEstimatedAmount.toInt().toString();
                                _hasManualAdvance = true;
                              });
                            },
                            isSelected: double.tryParse(_advanceController.text) == totalEstimatedAmount,
                          ),
                          const SizedBox(width: 6),
                          if (nights > 1) ...[
                            _buildAdvanceChip(
                              '1 Night (₹${effectiveNightlyRate.toInt()})',
                              () {
                                setState(() {
                                  _advanceController.text = effectiveNightlyRate.toInt().toString();
                                  _hasManualAdvance = true;
                                });
                              },
                              isSelected: double.tryParse(_advanceController.text) == effectiveNightlyRate,
                            ),
                            const SizedBox(width: 6),
                          ],
                          _buildAdvanceChip(
                            'No Advance (₹0)',
                            () {
                              setState(() {
                                _advanceController.text = '0';
                                _hasManualAdvance = true;
                              });
                            },
                            isSelected: double.tryParse(_advanceController.text) == 0,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Payment Method
                      Text(
                        'Payment Method',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _buildPaymentMethodButton(
                            'upi',
                            'UPI / QR Code',
                            Icons.qr_code_2_rounded,
                          ),
                          const SizedBox(width: 8),
                          _buildPaymentMethodButton(
                            'cash',
                            'Cash',
                            Icons.payments_outlined,
                          ),
                          const SizedBox(width: 8),
                          _buildPaymentMethodButton(
                            'card',
                            'Card',
                            Icons.credit_card_rounded,
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // WhatsApp notification minimal row
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _sendWhatsAppMessage
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _sendWhatsAppMessage
                                ? const Color(0xFFBBF7D0)
                                : AppTheme.slateBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.chat_rounded,
                              size: 15,
                              color: _sendWhatsAppMessage
                                  ? const Color(0xFF16A34A)
                                  : AppTheme.slateMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _bookingMode == BookingMode.reservation
                                    ? 'Send WhatsApp Reservation'
                                    : 'Send WhatsApp Check-in',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 28,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: Switch.adaptive(
                                  value: _sendWhatsAppMessage,
                                  activeTrackColor: const Color(0xFF16A34A),
                                  activeThumbColor: Colors.white,
                                  onChanged: (val) =>
                                      setState(() => _sendWhatsAppMessage = val),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // [Bank info commented out for now - will relocate later]
                      /*
                      if (_paymentMethod == 'upi') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.qr_code_2_rounded, size: 18, color: Color(0xFF16A34A)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Branch UPI: ',
                                          style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF166534), fontWeight: FontWeight.w600),
                                        ),
                                        Flexible(
                                          child: Text(
                                            store.currentProperty.upiId,
                                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF14532D)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'Payee: ${store.currentProperty.upiPayeeName} • Dynamic QR generated upon clicking button below',
                                      style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF166534)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF16A34A)),
                                tooltip: 'Edit Branch UPI ID',
                                onPressed: () => _showEditBranchUpiDialog(context, store),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                      ],
                      */
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Primary Guest Card (consolidated identical to attached screenshot) ──
  Widget _buildPrimaryGuestCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row matching attached screenshot
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppTheme.brandLight,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '1',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Guest 1 (Primary)',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(width: 8),
                if (_scanSuccess)
                  const Icon(
                    Icons.verified_rounded,
                    size: 13,
                    color: Color(0xFF16A34A),
                  ),
                const Spacer(),
                // Doc type mini-picker
                ...['aadhaar', 'pan', 'passport'].map((dt) {
                  final isSel = _idType == dt;
                  return GestureDetector(
                    onTap: () => setState(() => _idType = dt),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? AppTheme.brandPrimary
                            : AppTheme.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSel
                              ? AppTheme.brandPrimary
                              : AppTheme.slateBorder,
                        ),
                      ),
                      child: Text(
                        dt == 'aadhaar'
                            ? 'Aad'
                            : dt == 'pan'
                            ? 'PAN'
                            : 'Pass',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isSel ? Colors.white : AppTheme.slateMuted,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.slateBorder),
          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Scan buttons or compact green status card
                if (!_hasFrontUploaded)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openCamera(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt_rounded, size: 15),
                          label: Text(
                            'Scan ID',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFrontFile,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.slateDark,
                            side: const BorderSide(color: AppTheme.slateBorder),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.upload_file_rounded,
                            size: 15,
                            color: AppTheme.slateMuted,
                          ),
                          label: Text(
                            'Upload',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  // Compact status row (exact match to screenshot)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _scanSuccess
                          ? const Color(0xFFF0FDF4)
                          : (_isScanning
                                ? AppTheme.brandLight
                                : const Color(0xFFFFFBEB)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _scanSuccess
                            ? const Color(0xFFBBF7D0)
                            : (_isScanning
                                  ? AppTheme.brandPrimary.withValues(alpha: 0.3)
                                  : const Color(0xFFFDE68A)),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            _frontBytes!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isScanning
                                ? 'Scanning ID...'
                                : _scanSuccess
                                ? 'ID verified ✓'
                                : (_scanDone
                                      ? 'Scan cancelled / incomplete'
                                      : 'Ready to scan'),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _scanSuccess
                                  ? const Color(0xFF15803D)
                                  : (_isScanning
                                        ? AppTheme.brandPrimary
                                        : const Color(0xFF92400E)),
                            ),
                          ),
                        ),
                        if (_isScanning)
                          InkWell(
                            onTap: _cancelPrimaryScan,
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Color(0xFFF87171),
                              ),
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_scanSuccess && _hasFrontUploaded)
                                InkWell(
                                  onTap: () => _runOcrScan(),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.brandLight,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppTheme.brandPrimary.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.refresh_rounded,
                                          size: 12,
                                          color: AppTheme.brandPrimary,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Retry',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.brandPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              InkWell(
                                onTap: () => setState(() {
                                  _primaryScanToken++;
                                  _frontBytes = null;
                                  _frontFilename = null;
                                  _backBytes = null;
                                  _backFilename = null;
                                  _hasFrontUploaded = false;
                                  _hasBackUploaded = false;
                                  _scanDone = false;
                                  _scanSuccess = false;
                                }),
                                child: const Padding(
                                  padding: EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Back side row (exact match to screenshot)
                  if (!_hasBackUploaded)
                    Row(
                      children: [
                        const Icon(
                          Icons.flip_rounded,
                          size: 12,
                          color: AppTheme.slateMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Back side',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _openCamera(isBack: true),
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.brandLight,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: AppTheme.brandPrimary.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 11,
                                  color: AppTheme.brandPrimary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Camera',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.brandPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: _pickBackFile,
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: AppTheme.slateBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.upload_file_rounded,
                                  size: 11,
                                  color: AppTheme.slateMuted,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'File',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.slateDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 12,
                          color: Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Back added',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF15803D),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (!_isScanning)
                          InkWell(
                            onTap: _clearBackFile,
                            child: Text(
                              'Remove',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.red[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],

                const SizedBox(height: 10),

                // 1. Full Name
                TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slateDark,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Full Name',
                    hintStyle: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      size: 15,
                      color: AppTheme.slateMuted,
                    ),
                    suffixIcon: _buildVerificationSuffix(
                      isValid: _isNameValid(_nameController.text),
                      isNotEmpty: _nameController.text.trim().isNotEmpty,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _nameController.text.trim().isEmpty
                            ? AppTheme.slateBorder
                            : (_isNameValid(_nameController.text)
                                  ? const Color(0xFF16A34A).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 2. ID Number
                TextField(
                  controller: _idNumberController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slateDark,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ID Number (${_idType.toUpperCase()})',
                    hintStyle: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      size: 15,
                      color: AppTheme.slateMuted,
                    ),
                    suffixIcon: _buildVerificationSuffix(
                      isValid: _isIdValid(_idNumberController.text, _idType),
                      isNotEmpty: _idNumberController.text.trim().isNotEmpty,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _idNumberController.text.trim().isEmpty
                            ? AppTheme.slateBorder
                            : (_isIdValid(_idNumberController.text, _idType)
                                  ? const Color(0xFF16A34A).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 3. DOB & Gender (Option selector)
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _dobController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                          DateInputFormatter(),
                        ],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateDark,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'DOB (DD/MM/YYYY)',
                          hintStyle: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.slateMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 13,
                            color: AppTheme.slateMuted,
                          ),
                          suffixIcon: _buildVerificationSuffix(
                            isValid: _isDobValid(_dobController.text),
                            isNotEmpty: _dobController.text.trim().isNotEmpty,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.slateBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _dobController.text.trim().isEmpty
                                  ? AppTheme.slateBorder
                                  : (_isDobValid(_dobController.text)
                                        ? const Color(
                                            0xFF16A34A,
                                          ).withOpacity(0.5)
                                        : const Color(
                                            0xFFEF4444,
                                          ).withOpacity(0.5)),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.slateBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value:
                                [
                                  'Male',
                                  'Female',
                                  'Other',
                                  'Kids',
                                ].contains(_genderController.text)
                                ? _genderController.text
                                : 'Male',
                            icon: const Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 18,
                              color: AppTheme.slateMuted,
                            ),
                            isExpanded: true,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.slateDark,
                              fontWeight: FontWeight.w600,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Male',
                                child: Text('Male'),
                              ),
                              DropdownMenuItem(
                                value: 'Female',
                                child: Text('Female'),
                              ),
                              DropdownMenuItem(
                                value: 'Other',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null)
                                setState(() => _genderController.text = val);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // 4. Address from back & Pincode
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _addressController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateDark,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Address (from back of ID)',
                          hintStyle: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.slateMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.home_outlined,
                            size: 13,
                            color: AppTheme.slateMuted,
                          ),
                          suffixIcon: _buildVerificationSuffix(
                            isValid: _isAddressValid(_addressController.text),
                            isNotEmpty: _addressController.text
                                .trim()
                                .isNotEmpty,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.slateBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _addressController.text.trim().isEmpty
                                  ? AppTheme.slateBorder
                                  : (_isAddressValid(_addressController.text)
                                        ? const Color(
                                            0xFF16A34A,
                                          ).withOpacity(0.5)
                                        : const Color(
                                            0xFFEF4444,
                                          ).withOpacity(0.5)),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _pincodeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateDark,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Pincode',
                          hintStyle: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.slateMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: AppTheme.slateMuted,
                          ),
                          suffixIcon: _buildVerificationSuffix(
                            isValid: _isPincodeValid(_pincodeController.text),
                            isNotEmpty: _pincodeController.text
                                .trim()
                                .isNotEmpty,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.slateBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _pincodeController.text.trim().isEmpty
                                  ? AppTheme.slateBorder
                                  : (_isPincodeValid(_pincodeController.text)
                                        ? const Color(
                                            0xFF16A34A,
                                          ).withOpacity(0.5)
                                        : const Color(
                                            0xFFEF4444,
                                          ).withOpacity(0.5)),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // 5. Divider
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: AppTheme.slateBorder),
                ),

                // 6. Phone No (Same as WhatsApp live test)
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slateDark,
                    letterSpacing: 0.8,
                  ),
                  decoration: InputDecoration(
                    hintText: '99XXX XXXXX',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                      letterSpacing: 0.8,
                    ),
                    prefixIcon: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 7,
                      ),
                      margin: const EdgeInsets.only(right: 8),
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
                          const Text('🇮🇳', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          Text(
                            '+91',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    suffixIcon: _buildVerificationSuffix(
                      isValid: _isPhoneValid(_phoneController.text),
                      isNotEmpty: _phoneController.text.trim().isNotEmpty,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _phoneController.text.trim().isEmpty
                            ? AppTheme.slateBorder
                            : (_isPhoneValid(_phoneController.text)
                                  ? const Color(0xFF16A34A).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 7. Email (Optional)
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slateDark,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Email (Optional)',
                    hintStyle: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.slateMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      size: 13,
                      color: AppTheme.slateMuted,
                    ),
                    suffixIcon: _buildVerificationSuffix(
                      isValid: _isEmailValid(_emailController.text),
                      isNotEmpty: _emailController.text.trim().isNotEmpty,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: _emailController.text.trim().isEmpty
                            ? AppTheme.slateBorder
                            : (_isEmailValid(_emailController.text)
                                  ? const Color(0xFF16A34A).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ── Extra Guest Card (full OCR) ────────────────────────────────────────
  Widget _buildExtraGuestCard(int i) {
    final g = _extraGuests[i];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppTheme.brandLight,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${i + 2}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Guest ${i + 2}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(width: 8),
                if (g.scanSuccess)
                  const Icon(
                    Icons.verified_rounded,
                    size: 13,
                    color: Color(0xFF16A34A),
                  ),
                const Spacer(),
                // Doc type mini-picker
                ...['aadhaar', 'pan', 'passport'].map((dt) {
                  final isSel = g.idType == dt;
                  return GestureDetector(
                    onTap: () => setState(() => g.idType = dt),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSel
                            ? AppTheme.brandPrimary
                            : AppTheme.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSel
                              ? AppTheme.brandPrimary
                              : AppTheme.slateBorder,
                        ),
                      ),
                      child: Text(
                        dt == 'aadhaar'
                            ? 'Aad'
                            : dt == 'pan'
                            ? 'PAN'
                            : 'Pass',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isSel ? Colors.white : AppTheme.slateMuted,
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _removeExtraGuest(i),
                  borderRadius: BorderRadius.circular(6),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppTheme.slateMuted,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.slateBorder),
          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Scan area
                if (!g.hasFrontUploaded)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openCameraForGuest(i),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt_rounded, size: 15),
                          label: Text(
                            'Scan ID',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickFrontFileForGuest(i),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.slateDark,
                            side: const BorderSide(color: AppTheme.slateBorder),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.upload_file_rounded,
                            size: 15,
                            color: AppTheme.slateMuted,
                          ),
                          label: Text(
                            'Upload',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  // Compact status row
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: g.scanSuccess
                          ? const Color(0xFFF0FDF4)
                          : (g.isScanning
                                ? AppTheme.brandLight
                                : const Color(0xFFFFFBEB)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: g.scanSuccess
                            ? const Color(0xFFBBF7D0)
                            : (g.isScanning
                                  ? AppTheme.brandPrimary.withValues(alpha: 0.3)
                                  : const Color(0xFFFDE68A)),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            g.frontBytes!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            g.isScanning
                                ? 'Scanning ID...'
                                : g.scanSuccess
                                ? 'ID verified ✓'
                                : (g.scanDone
                                      ? 'Scan cancelled / incomplete'
                                      : 'Ready to scan'),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: g.scanSuccess
                                  ? const Color(0xFF15803D)
                                  : (g.isScanning
                                        ? AppTheme.brandPrimary
                                        : const Color(0xFF92400E)),
                            ),
                          ),
                        ),
                        if (g.isScanning)
                          InkWell(
                            onTap: () => _cancelExtraGuestScan(i),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Color(0xFFF87171),
                              ),
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!g.scanSuccess && g.hasFrontUploaded)
                                InkWell(
                                  onTap: () => _runOcrScanForGuest(i),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.brandLight,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppTheme.brandPrimary.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.refresh_rounded,
                                          size: 12,
                                          color: AppTheme.brandPrimary,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Retry',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.brandPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              InkWell(
                                onTap: () => setState(() {
                                  g.scanToken++;
                                  g.frontBytes = null;
                                  g.frontFilename = null;
                                  g.backBytes = null;
                                  g.backFilename = null;
                                  g.hasFrontUploaded = false;
                                  g.hasBackUploaded = false;
                                  g.scanDone = false;
                                  g.scanSuccess = false;
                                }),
                                child: const Padding(
                                  padding: EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Back side row
                  if (!g.hasBackUploaded)
                    Row(
                      children: [
                        const Icon(
                          Icons.flip_rounded,
                          size: 12,
                          color: AppTheme.slateMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Back side',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _openCameraForGuest(i, isBack: true),
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.brandLight,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: AppTheme.brandPrimary.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 11,
                                  color: AppTheme.brandPrimary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Camera',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.brandPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _pickBackFileForGuest(i),
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: AppTheme.slateBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.upload_file_rounded,
                                  size: 11,
                                  color: AppTheme.slateMuted,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'File',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.slateDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 12,
                          color: Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Back added',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF15803D),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (!g.isScanning)
                          InkWell(
                            onTap: () => setState(() {
                              g.backBytes = null;
                              g.backFilename = null;
                              g.hasBackUploaded = false;
                            }),
                            child: Text(
                              'Remove',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.red[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],

                const SizedBox(height: 10),

                // 1. Full Name
                TextField(
                  controller: g.nameCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slateDark,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Full Name',
                    hintStyle: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      size: 15,
                      color: AppTheme.slateMuted,
                    ),
                    suffixIcon: _buildVerificationSuffix(
                      isValid: _isNameValid(g.nameCtrl.text),
                      isNotEmpty: g.nameCtrl.text.trim().isNotEmpty,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: g.nameCtrl.text.trim().isEmpty
                            ? AppTheme.slateBorder
                            : (_isNameValid(g.nameCtrl.text)
                                  ? const Color(0xFF16A34A).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 2. ID Number
                TextField(
                  controller: g.idNumberCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slateDark,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ID Number (${g.idType.toUpperCase()})',
                    hintStyle: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      size: 15,
                      color: AppTheme.slateMuted,
                    ),
                    suffixIcon: _buildVerificationSuffix(
                      isValid: _isIdValid(g.idNumberCtrl.text, g.idType),
                      isNotEmpty: g.idNumberCtrl.text.trim().isNotEmpty,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: g.idNumberCtrl.text.trim().isEmpty
                            ? AppTheme.slateBorder
                            : (_isIdValid(g.idNumberCtrl.text, g.idType)
                                  ? const Color(0xFF16A34A).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 3. DOB & Gender (Option selector)
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: g.dobCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                          DateInputFormatter(),
                        ],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateDark,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'DOB (DD/MM/YYYY)',
                          hintStyle: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.slateMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 13,
                            color: AppTheme.slateMuted,
                          ),
                          suffixIcon: _buildVerificationSuffix(
                            isValid: _isDobValid(g.dobCtrl.text),
                            isNotEmpty: g.dobCtrl.text.trim().isNotEmpty,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.slateBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: g.dobCtrl.text.trim().isEmpty
                                  ? AppTheme.slateBorder
                                  : (_isDobValid(g.dobCtrl.text)
                                        ? const Color(
                                            0xFF16A34A,
                                          ).withOpacity(0.5)
                                        : const Color(
                                            0xFFEF4444,
                                          ).withOpacity(0.5)),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.slateBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value:
                                [
                                  'Male',
                                  'Female',
                                  'Other',
                                  'Kids',
                                ].contains(g.genderCtrl.text)
                                ? g.genderCtrl.text
                                : 'Male',
                            icon: const Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 18,
                              color: AppTheme.slateMuted,
                            ),
                            isExpanded: true,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.slateDark,
                              fontWeight: FontWeight.w600,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Male',
                                child: Text('Male'),
                              ),
                              DropdownMenuItem(
                                value: 'Female',
                                child: Text('Female'),
                              ),
                              DropdownMenuItem(
                                value: 'Other',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null)
                                setState(() => g.genderCtrl.text = val);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // 4. Address from back & Pincode
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: g.addressCtrl,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateDark,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Address (from back of ID)',
                          hintStyle: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.slateMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.home_outlined,
                            size: 13,
                            color: AppTheme.slateMuted,
                          ),
                          suffixIcon: _buildVerificationSuffix(
                            isValid: _isAddressValid(g.addressCtrl.text),
                            isNotEmpty: g.addressCtrl.text.trim().isNotEmpty,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.slateBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: g.addressCtrl.text.trim().isEmpty
                                  ? AppTheme.slateBorder
                                  : (_isAddressValid(g.addressCtrl.text)
                                        ? const Color(
                                            0xFF16A34A,
                                          ).withOpacity(0.5)
                                        : const Color(
                                            0xFFEF4444,
                                          ).withOpacity(0.5)),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: g.pincodeCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateDark,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Pincode',
                          hintStyle: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.slateMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: AppTheme.slateMuted,
                          ),
                          suffixIcon: _buildVerificationSuffix(
                            isValid: _isPincodeValid(g.pincodeCtrl.text),
                            isNotEmpty: g.pincodeCtrl.text.trim().isNotEmpty,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.slateBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: g.pincodeCtrl.text.trim().isEmpty
                                  ? AppTheme.slateBorder
                                  : (_isPincodeValid(g.pincodeCtrl.text)
                                        ? const Color(
                                            0xFF16A34A,
                                          ).withOpacity(0.5)
                                        : const Color(
                                            0xFFEF4444,
                                          ).withOpacity(0.5)),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppTheme.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // 5. Divider
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: AppTheme.slateBorder),
                ),

                // 6. Phone No (Same as WhatsApp live test)
                TextField(
                  controller: g.phoneCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slateDark,
                    letterSpacing: 0.8,
                  ),
                  decoration: InputDecoration(
                    hintText: '99XXX XXXXX',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                      letterSpacing: 0.8,
                    ),
                    prefixIcon: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 7,
                      ),
                      margin: const EdgeInsets.only(right: 8),
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
                          const Text('🇮🇳', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          Text(
                            '+91',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    suffixIcon: _buildVerificationSuffix(
                      isValid: _isPhoneValid(g.phoneCtrl.text),
                      isNotEmpty: g.phoneCtrl.text.trim().isNotEmpty,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: g.phoneCtrl.text.trim().isEmpty
                            ? AppTheme.slateBorder
                            : (_isPhoneValid(g.phoneCtrl.text)
                                  ? const Color(0xFF16A34A).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 7. Email (Optional)
                TextField(
                  controller: g.emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slateDark,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Email (Optional)',
                    hintStyle: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.slateMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      size: 13,
                      color: AppTheme.slateMuted,
                    ),
                    suffixIcon: _buildVerificationSuffix(
                      isValid: _isEmailValid(g.emailCtrl.text),
                      isNotEmpty: g.emailCtrl.text.trim().isNotEmpty,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: g.emailCtrl.text.trim().isEmpty
                            ? AppTheme.slateBorder
                            : (_isEmailValid(g.emailCtrl.text)
                                  ? const Color(0xFF16A34A).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodButton(String id, String label, IconData icon) {
    final isSel = _paymentMethod == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _paymentMethod = id),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSel ? AppTheme.brandLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSel ? AppTheme.brandPrimary : AppTheme.slateBorder,
              width: isSel ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSel ? AppTheme.brandPrimary : AppTheme.slateMuted,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSel ? AppTheme.brandPrimary : AppTheme.slateDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDarkSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AIRBNB STEP 1 CHOOSER HELPER METHODS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWizardSectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slateBorder.withValues(alpha: .8)),
      ),
      child: child,
    );
  }

  Widget _buildCompactRoomChooser(
    List<Room> availableRooms,
    Room? selectedRoom,
    HotelStore store,
  ) {
    final filtered = _selectedFloorFilter == 0
        ? availableRooms
        : availableRooms
              .where((room) => room.floor == _selectedFloorFilter)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedRoom != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.bed_rounded,
                  size: 17,
                  color: AppTheme.brandPrimary,
                ),
                const SizedBox(width: 7),
                Text(
                  'Room ${selectedRoom.roomNumber}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${selectedRoom.categoryName} · Floor ${selectedRoom.floor}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildFilterPill(
                'All (${availableRooms.length})',
                _selectedFloorFilter == 0,
                () => setState(() => _selectedFloorFilter = 0),
              ),
              ...store.floors.map((floor) {
                final count = availableRooms
                    .where((room) => room.floor == floor)
                    .length;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildFilterPill(
                    'Floor $floor ($count)',
                    _selectedFloorFilter == floor,
                    () => setState(() => _selectedFloorFilter = floor),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (availableRooms.isEmpty)
          Container(
            height: 86,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _bookingMode == BookingMode.reservation
                  ? 'No rooms available for these dates.'
                  : 'No vacant rooms available right now.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.red.shade800,
              ),
            ),
          )
        else if (filtered.isEmpty)
          SizedBox(
            height: 86,
            child: Center(
              child: Text(
                'No rooms on this floor',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.slateMuted,
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final room = filtered[index];
                final selected = room.id == selectedRoom?.id;
                return InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => setState(() {
                    _selectedRoomId = room.id;
                    _isCustomPricing = false;
                    _customTotalAmount = null;
                    _customNightlyRate = null;
                    _hasManualAdvance = false;
                    _advanceController.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 130,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.brandLight.withValues(alpha: .35)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: selected
                            ? AppTheme.brandPrimary
                            : AppTheme.slateBorder,
                        width: selected ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              room.roomNumber,
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            Text(
                              'Fl ${room.floor}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          room.categoryName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        Text(
                          '₹${room.baseRate.toInt()}/n',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<DateTime?> _showDatePickerSheet({
    required String title,
    required DateTime initialDate,
    required DateTime firstDate,
  }) {
    final today = DateTime.now();
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.slateBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.slateMuted),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              CalendarDatePicker(
                initialDate: initialDate.isBefore(firstDate)
                    ? firstDate
                    : initialDate,
                firstDate: firstDate,
                lastDate: DateTime(today.year + 3, today.month, today.day),
                onDateChanged: (date) => Navigator.of(sheetContext).pop(date),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickArrivalDate() async {
    final today = DateTime.now();
    // Reservations can be done for today or any future date
    final firstDate = DateTime(today.year, today.month, today.day);
    final picked = await _showDatePickerSheet(
      title: 'Check-in date',
      initialDate: _checkInDate,
      firstDate: firstDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkInDate = DateTime(picked.year, picked.month, picked.day);
      if (_expectedCheckOut.isBefore(_checkInDate)) {
        _expectedCheckOut = _checkInDate.add(const Duration(days: 1));
      }
      final diff = _expectedCheckOut.difference(_checkInDate).inDays;
      final newNights = diff <= 0 ? 1 : diff.clamp(1, 365);
      if (_isCustomPricing && _customNightlyRate != null) {
        _customTotalAmount = newNights * _customNightlyRate!;
      }
    });
  }

  Future<void> _pickCheckoutDate() async {
    // For check-in, guest can checkout on the same day (e.g. midnight check-in, morning check-out)
    // For reservations, checkout must be on or after check-in date
    final firstDate = _bookingMode == BookingMode.checkIn
        ? _checkInDate
        : _checkInDate;
    final picked = await _showDatePickerSheet(
      title: 'Check-out date',
      initialDate: _expectedCheckOut,
      firstDate: firstDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _expectedCheckOut = DateTime(picked.year, picked.month, picked.day);
      final diff = _expectedCheckOut.difference(_checkInDate).inDays;
      final newNights = diff <= 0 ? 1 : diff.clamp(1, 365);
      if (_isCustomPricing && _customNightlyRate != null) {
        _customTotalAmount = newNights * _customNightlyRate!;
      }
    });
  }

  Widget _buildCompactStaySelector(int nights, HotelStore store) {
    final durations = const [(1, '1 Night'), (2, '2 Nights'), (3, '3 Nights')];
    final today = DateTime.now();
    final checkInLabel = _bookingMode == BookingMode.checkIn
        ? 'Today · ${DateFormat('EEE, d MMM').format(_checkInDate)}'
        : DateFormat('EEE, d MMM').format(_checkInDate);

    final checkInTimeStr = _bookingMode == BookingMode.checkIn
        ? DateFormat('hh:mm a').format(today)
        : store.defaultCheckInTime;
    final checkOutTimeStr = store.defaultCheckOutTime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _bookingMode == BookingMode.reservation
                    ? _pickArrivalDate
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHECK-IN',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slateMuted,
                          letterSpacing: .4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        checkInLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: AppTheme.slateMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            checkInTimeStr,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: AppTheme.slateMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _pickCheckoutDate,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHECK-OUT',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slateMuted,
                          letterSpacing: .4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('EEE, d MMM').format(_expectedCheckOut),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: AppTheme.slateMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            checkOutTimeStr,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < durations.length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              Expanded(
                child: _buildDurationChip(
                  durations[i].$2,
                  nights == durations[i].$1,
                  () => setState(() {
                    final newNights = durations[i].$1;
                    if (_bookingMode == BookingMode.checkIn) {
                      _checkInDate = DateTime(
                        today.year,
                        today.month,
                        today.day,
                      );
                      // If post-midnight (< 12 PM), 1 night means checkout today
                      final addDays = (durations[i].$1 == 1 && today.hour < 12)
                          ? 0
                          : durations[i].$1;
                      _expectedCheckOut = _checkInDate.add(Duration(days: addDays));
                    } else {
                      _expectedCheckOut = _checkInDate.add(
                        Duration(days: durations[i].$1),
                      );
                    }
                    if (_isCustomPricing && _customNightlyRate != null) {
                      _customTotalAmount = newNights * _customNightlyRate!;
                    }
                  }),
                ),
              ),
            ],
            const SizedBox(width: 7),
            Expanded(
              child: _buildDurationChip(
                'Custom',
                nights < 1 || nights > 3,
                _pickCheckoutDate,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDurationChip(String label, bool selected, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.brandLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.brandPrimary : AppTheme.slateBorder,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? AppTheme.brandDark : AppTheme.slateDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactGuestSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 38,
          child: Row(
            children: [
              const Icon(
                Icons.people_alt_outlined,
                size: 18,
                color: AppTheme.brandPrimary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '$_totalGuests ${_totalGuests == 1 ? 'guest' : 'guests'}  ·  $_numAdults ${_numAdults == 1 ? 'adult' : 'adults'}${_numKids > 0 ? '  ·  $_numKids ${_numKids == 1 ? 'child' : 'children'}' : ''}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slateDark,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: AppTheme.slateMuted,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 27),
          child: Column(
            children: [
              _buildCompactGuestCounter(
                'Adults',
                _numAdults,
                _numAdults > 1,
                _numAdults < 10,
                () => setState(() => _numAdults--),
                () => setState(() => _numAdults++),
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),
              _buildCompactGuestCounter(
                'Children',
                _numKids,
                _numKids > 0,
                _numKids < 10,
                () => setState(() => _numKids--),
                () => setState(() => _numKids++),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactGuestCounter(
    String label,
    int count,
    bool canDecrease,
    bool canIncrease,
    VoidCallback decrease,
    VoidCallback increase,
  ) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.slateDark,
              ),
            ),
          ),
          _buildAirbnbCounterButton(
            icon: Icons.remove_rounded,
            enabled: canDecrease,
            onTap: decrease,
          ),
          SizedBox(
            width: 38,
            child: Center(
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slateDark,
                ),
              ),
            ),
          ),
          _buildAirbnbCounterButton(
            icon: Icons.add_rounded,
            enabled: canIncrease,
            onTap: increase,
          ),
        ],
      ),
    );
  }

  Widget _buildAirbnbCounterButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? AppTheme.brandLight : const Color(0xFFF1F5F9),
          border: Border.all(
            color: enabled
                ? AppTheme.brandPrimary.withValues(alpha: 0.35)
                : AppTheme.slateBorder,
            width: 1.2,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 16,
            color: enabled ? AppTheme.brandPrimary : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.brandPrimary : AppTheme.slateBorder,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.22),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppTheme.slateDark,
          ),
        ),
      ),
    );
  }

  void _openPriceAdjustmentSheet({
    required Room? selectedRoom,
    required int nights,
  }) {
    final baseRate = selectedRoom?.baseRate ?? 2200.0;
    final defaultTotal = nights * baseRate;
    final initialTotal = (_isCustomPricing && _customTotalAmount != null && _customTotalAmount! > 0)
        ? _customTotalAmount!
        : defaultTotal;
    final initialRate = initialTotal / nights;

    double agreedRate = initialRate;
    bool isEditingExact = false;
    final exactRateCtrl = TextEditingController(text: agreedRate.round().toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final currentTotal = agreedRate * nights;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 12,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.slateBorder,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Header with close button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'Agreed Price',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.slateDark,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.slateMuted),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Price Display Center Block
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Price per night',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.slateMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (!isEditingExact)
                              InkWell(
                                onTap: () {
                                  exactRateCtrl.text = agreedRate.round().toString();
                                  setSheetState(() => isEditingExact = true);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        '₹${agreedRate.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.slateDark,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                        color: AppTheme.brandPrimary,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else ...[
                              SizedBox(
                                width: 170,
                                child: TextField(
                                  controller: exactRateCtrl,
                                  keyboardType: TextInputType.number,
                                  autofocus: true,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.slateDark,
                                  ),
                                  decoration: InputDecoration(
                                    prefixText: '₹ ',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(color: AppTheme.brandPrimary),
                                    ),
                                  ),
                                  onSubmitted: (val) {
                                    final parsed = double.tryParse(val.replaceAll(',', '').trim());
                                    final finalVal = (parsed != null && parsed >= 0) ? parsed : agreedRate;
                                    final chosenTotal = finalVal * nights;
                                    Navigator.pop(sheetContext);
                                    setState(() {
                                      if ((finalVal - baseRate).abs() < 0.5) {
                                        _isCustomPricing = false;
                                        _customTotalAmount = null;
                                        _customNightlyRate = null;
                                      } else {
                                        _isCustomPricing = true;
                                        _customTotalAmount = chosenTotal;
                                        _customNightlyRate = finalVal;
                                        if (!_hasManualAdvance) {
                                          _advanceController.text = finalVal.round().toString();
                                        }
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  final parsed = double.tryParse(exactRateCtrl.text.replaceAll(',', '').trim());
                                  final finalVal = (parsed != null && parsed >= 0) ? parsed : agreedRate;
                                  final chosenTotal = finalVal * nights;
                                  Navigator.pop(sheetContext);
                                  setState(() {
                                    if ((finalVal - baseRate).abs() < 0.5) {
                                      _isCustomPricing = false;
                                      _customTotalAmount = null;
                                      _customNightlyRate = null;
                                    } else {
                                      _isCustomPricing = true;
                                      _customTotalAmount = chosenTotal;
                                      _customNightlyRate = finalVal;
                                      if (!_hasManualAdvance) {
                                        _advanceController.text = finalVal.round().toString();
                                      }
                                    }
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _isCustomPricing
                                            ? 'Agreed price applied: ₹${finalVal.round()}/night (Total: ₹${chosenTotal.round()})'
                                            : 'Standard room rate applied (₹${baseRate.round()}/night)',
                                      ),
                                      backgroundColor: AppTheme.slateDark,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  child: Text(
                                    'Done editing',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (!isEditingExact) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Tap amount to enter exact price',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                            ],
                            if (nights > 1) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Total stay: ₹${currentTotal.round()} ($nights nights)',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.brandPrimary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 3-column × 2-row grid of adjustments
                      // Row 1: Decrease controls
                      Row(
                        children: [
                          Expanded(
                            child: _buildAdjustmentPill(
                              label: '− ₹100',
                              textColor: const Color(0xFFC94C4C),
                              bgColor: const Color(0xFFFFF4F4),
                              borderColor: const Color(0xFFF0DADA),
                              onTap: () {
                                setSheetState(() {
                                  agreedRate = (agreedRate - 100).clamp(0.0, 999999.0);
                                  exactRateCtrl.text = agreedRate.round().toString();
                                  isEditingExact = false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAdjustmentPill(
                              label: '− ₹200',
                              textColor: const Color(0xFFC94C4C),
                              bgColor: const Color(0xFFFFF4F4),
                              borderColor: const Color(0xFFF0DADA),
                              onTap: () {
                                setSheetState(() {
                                  agreedRate = (agreedRate - 200).clamp(0.0, 999999.0);
                                  exactRateCtrl.text = agreedRate.round().toString();
                                  isEditingExact = false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAdjustmentPill(
                              label: '− ₹500',
                              textColor: const Color(0xFFC94C4C),
                              bgColor: const Color(0xFFFFF4F4),
                              borderColor: const Color(0xFFF0DADA),
                              onTap: () {
                                setSheetState(() {
                                  agreedRate = (agreedRate - 500).clamp(0.0, 999999.0);
                                  exactRateCtrl.text = agreedRate.round().toString();
                                  isEditingExact = false;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Row 2: Increase controls
                      Row(
                        children: [
                          Expanded(
                            child: _buildAdjustmentPill(
                              label: '+ ₹100',
                              textColor: const Color(0xFF278653),
                              bgColor: const Color(0xFFF1F8F3),
                              borderColor: const Color(0xFFD6E9DC),
                              onTap: () {
                                setSheetState(() {
                                  agreedRate = (agreedRate + 100).clamp(0.0, 999999.0);
                                  exactRateCtrl.text = agreedRate.round().toString();
                                  isEditingExact = false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAdjustmentPill(
                              label: '+ ₹200',
                              textColor: const Color(0xFF278653),
                              bgColor: const Color(0xFFF1F8F3),
                              borderColor: const Color(0xFFD6E9DC),
                              onTap: () {
                                setSheetState(() {
                                  agreedRate = (agreedRate + 200).clamp(0.0, 999999.0);
                                  exactRateCtrl.text = agreedRate.round().toString();
                                  isEditingExact = false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAdjustmentPill(
                              label: '+ ₹500',
                              textColor: const Color(0xFF278653),
                              bgColor: const Color(0xFFF1F8F3),
                              borderColor: const Color(0xFFD6E9DC),
                              onTap: () {
                                setSheetState(() {
                                  agreedRate = (agreedRate + 500).clamp(0.0, 999999.0);
                                  exactRateCtrl.text = agreedRate.round().toString();
                                  isEditingExact = false;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Apply button
                      ElevatedButton(
                        onPressed: () {
                          if (isEditingExact) {
                            final parsed = double.tryParse(exactRateCtrl.text.replaceAll(',', '').trim());
                            if (parsed != null && parsed >= 0) {
                              agreedRate = parsed;
                            }
                          }
                          final chosenTotal = agreedRate * nights;
                          Navigator.pop(sheetContext);
                          setState(() {
                            if ((agreedRate - baseRate).abs() < 0.5) {
                              _isCustomPricing = false;
                              _customTotalAmount = null;
                              _customNightlyRate = null;
                            } else {
                              _isCustomPricing = true;
                              _customTotalAmount = chosenTotal;
                              _customNightlyRate = agreedRate;
                              if (!_hasManualAdvance) {
                                _advanceController.text = agreedRate.round().toString();
                              }
                            }
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _isCustomPricing
                                    ? 'Agreed price applied: ₹${agreedRate.round()}/night (Total: ₹${chosenTotal.round()})'
                                    : 'Standard room rate applied (₹${baseRate.round()}/night)',
                              ),
                              backgroundColor: AppTheme.slateDark,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          'Apply ₹${agreedRate.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}/night',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAdjustmentPill({
    required String label,
    required Color textColor,
    required Color bgColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildPricingSummaryCard({
    required Room? selectedRoom,
    required int nights,
    required double totalEstimatedAmount,
    required double effectiveNightlyRate,
  }) {
    final baseRate = selectedRoom?.baseRate ?? 2200.0;
    final defaultTotal = nights * baseRate;
    final diff = totalEstimatedAmount - defaultTotal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _isCustomPricing ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isCustomPricing ? const Color(0xFF86EFAC) : AppTheme.slateBorder,
          width: _isCustomPricing ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isCustomPricing ? Icons.handshake_rounded : Icons.payments_outlined,
                    size: 16,
                    color: _isCustomPricing ? const Color(0xFF16A34A) : AppTheme.brandPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isCustomPricing ? 'AGREED STAY PRICING' : 'ESTIMATED STAY PRICING',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: _isCustomPricing ? const Color(0xFF15803D) : AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
              if (_isCustomPricing)
                InkWell(
                  onTap: () {
                    setState(() {
                      _isCustomPricing = false;
                      _customTotalAmount = null;
                      _customNightlyRate = null;
                      if (!_hasManualAdvance) {
                        _advanceController.text = (defaultTotal / nights).toInt().toString();
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Reset to Standard',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCustomPricing
                        ? 'Agreed: ₹${effectiveNightlyRate.toInt()}/night ($nights night${nights > 1 ? "s" : ""})'
                        : 'Standard: ₹${baseRate.toInt()}/night ($nights night${nights > 1 ? "s" : ""})',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (_isCustomPricing)
                    Text(
                      diff < 0
                          ? 'Guest discount of ₹${(-diff).toInt()} applied'
                          : 'Custom rate applied (+₹${diff.toInt()})',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: diff < 0 ? const Color(0xFF16A34A) : AppTheme.slateMuted,
                      ),
                    )
                  else
                    Text(
                      'Guest bargaining? Tap button to customize rate',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                ],
              ),
              InkWell(
                onTap: () => _openPriceAdjustmentSheet(
                  selectedRoom: selectedRoom,
                  nights: nights,
                ),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isCustomPricing ? const Color(0xFFDCFCE7) : AppTheme.brandLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isCustomPricing
                          ? const Color(0xFF16A34A).withValues(alpha: 0.3)
                          : AppTheme.brandPrimary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCustomPricing ? Icons.edit_rounded : Icons.local_offer_outlined,
                        size: 13,
                        color: _isCustomPricing ? const Color(0xFF15803D) : AppTheme.brandPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isCustomPricing ? 'Edit Price' : 'Bargain Rate',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _isCustomPricing ? const Color(0xFF15803D) : AppTheme.brandPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvanceChip(
    String label,
    VoidCallback onTap, {
    required bool isSelected,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.brandLight : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.brandPrimary : AppTheme.slateBorder,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? AppTheme.brandPrimary : AppTheme.slateDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedStickyFooter({
    required Room? selectedRoom,
    required int nights,
    required double totalEstimatedAmount,
    required double effectiveNightlyRate,
    required bool isNoRooms,
    required HotelStore store,
  }) {
    final double advanceAmt =
        double.tryParse(_advanceController.text) ?? totalEstimatedAmount;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppTheme.slateBorder, width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Left summary (context-aware per step & tap to edit pricing)
            Expanded(
              child: InkWell(
                onTap: () => _openPriceAdjustmentSheet(
                  selectedRoom: selectedRoom,
                  nights: nights,
                ),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '₹${totalEstimatedAmount.toInt()}',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _isCustomPricing ? const Color(0xFF0F766E) : AppTheme.slateDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: _isCustomPricing ? const Color(0xFF0F766E) : AppTheme.slateMuted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _currentStep == 1
                            ? '${selectedRoom != null ? "Room ${selectedRoom.roomNumber}" : "Select room"} • $nights night${nights > 1 ? "s" : ""} • $_totalGuests guest${_totalGuests > 1 ? "s" : ""}'
                            : _currentStep == 2
                            ? '${selectedRoom != null ? "Room ${selectedRoom.roomNumber}" : ""} • ${_nameController.text.trim().isNotEmpty ? _nameController.text.trim() : "Primary Guest"} • $nights night${nights > 1 ? "s" : ""}'
                            : '${selectedRoom != null ? "Room ${selectedRoom.roomNumber}" : ""} • ${_paymentMethod.toUpperCase()} • Bal: ₹${(totalEstimatedAmount - advanceAmt).clamp(0, 999999).toInt()}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Right Action Button(s) based on _currentStep
            if (_currentStep == 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onBack != null ||
                      Navigator.of(context).canPop()) ...[
                    OutlinedButton(
                      onPressed: () {
                        if (widget.onBack != null) {
                          widget.onBack!();
                        } else if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(
                          color: AppTheme.slateBorder,
                          width: 1.2,
                        ),
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.slateDark,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.arrow_back_rounded,
                            size: 14,
                            color: AppTheme.slateDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Back',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  PressableScale(
                    pressedScale: 0.95,
                    child: ElevatedButton(
                      onPressed: isNoRooms
                          ? null
                          : () => setState(() => _currentStep = 2),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Next: Guest',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.arrow_forward_rounded, size: 15),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else if (_currentStep == 2)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _currentStep = 1),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(
                        color: AppTheme.slateBorder,
                        width: 1.2,
                      ),
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.slateDark,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_back_rounded,
                          size: 14,
                          color: AppTheme.slateDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Back',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  PressableScale(
                    pressedScale: 0.95,
                    child: ElevatedButton(
                      onPressed: () {
                        if (!_isNameValid(_nameController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid guest name (minimum 2 characters)',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_dobController.text.trim().isNotEmpty &&
                            !_isDobValid(_dobController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid DOB in DD/MM/YYYY format',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_phoneController.text
                                .replaceAll(RegExp(r'\D'), '')
                                .isNotEmpty &&
                            !_isPhoneValid(_phoneController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid 10-digit phone number',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_pincodeController.text
                                .replaceAll(RegExp(r'\D'), '')
                                .isNotEmpty &&
                            !_isPincodeValid(_pincodeController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid 6-digit pincode',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_emailController.text.trim().isNotEmpty &&
                            !_isEmailValid(_emailController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid email address',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        setState(() => _currentStep = 3);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _bookingMode == BookingMode.reservation
                                ? 'Next: Deposit'
                                : 'Next: Payment',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.arrow_forward_rounded, size: 15),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else if (_currentStep == 3)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _currentStep = 2),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(
                        color: AppTheme.slateBorder,
                        width: 1.2,
                      ),
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.slateDark,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_back_rounded,
                          size: 14,
                          color: AppTheme.slateDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Back',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  PressableScale(
                    pressedScale: 0.95,
                    child: ElevatedButton.icon(
                      onPressed: selectedRoom == null
                          ? null
                          : () => _handlePaymentAndCheckIn(
                              store,
                              selectedRoom,
                              totalEstimatedAmount,
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _paymentMethod == 'upi'
                            ? const Color(0xFF16A34A)
                            : AppTheme.brandPrimary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: Icon(
                        _paymentMethod == 'upi'
                            ? Icons.qr_code_2_rounded
                            : (_bookingMode == BookingMode.reservation
                                  ? Icons.event_available_rounded
                                  : Icons.check_circle_rounded),
                        size: 15,
                      ),
                      label: Text(
                        _paymentMethod == 'upi'
                            ? (_bookingMode == BookingMode.reservation
                                  ? 'Show QR & Pay Deposit'
                                  : 'Show QR & Pay')
                            : (_bookingMode == BookingMode.reservation
                                  ? 'Confirm Reservation'
                                  : 'Complete Check-In'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Data holder for an additional (co-)guest with full OCR state.
class _ExtraGuest {
  String idType = 'aadhaar';

  // Image bytes
  Uint8List? frontBytes;
  String? frontFilename;
  Uint8List? backBytes;
  String? backFilename;
  bool hasFrontUploaded = false;
  bool hasBackUploaded = false;

  // Scan state
  bool isScanning = false;
  bool scanDone = false;
  bool scanSuccess = false;
  int scanToken = 0;

  // Form controllers (auto-filled by OCR + manual phone/email)
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController idNumberCtrl = TextEditingController();
  final TextEditingController dobCtrl = TextEditingController();
  final TextEditingController genderCtrl = TextEditingController(text: 'Male');
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController pincodeCtrl = TextEditingController();
  final TextEditingController fatherNameCtrl = TextEditingController();

  void disposeControllers() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    idNumberCtrl.dispose();
    dobCtrl.dispose();
    genderCtrl.dispose();
    addressCtrl.dispose();
    pincodeCtrl.dispose();
    fatherNameCtrl.dispose();
  }
}
