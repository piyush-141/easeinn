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

enum _AirbnbStep1Section { where, when, who }

class _CheckInScreenState extends State<CheckInScreen> {
  int _currentStep = 1; // 1: Room, 2: Guest & OCR, 3: Payment & Confirm
  late BookingMode _bookingMode; // checkIn vs reservation

  // Step 1: Airbnb Chooser State
  String? _selectedRoomId;
  DateTime _checkInDate = DateTime.now();
  DateTime _expectedCheckOut = DateTime.now().add(const Duration(days: 1));
  int _numAdults = 1; // Default 1 adult
  int _numKids = 0;
  _AirbnbStep1Section _activeSection = _AirbnbStep1Section.where;
  int _selectedFloorFilter = 0; // 0 = all floors
  late DateTime _calendarMonth;
  bool _pickingStartDate = true;

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
      return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$', caseSensitive: false).hasMatch(clean);
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

  Widget? _buildVerificationSuffix({required bool isValid, required bool isNotEmpty}) {
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

  // Step 3: Payment
  final _advanceController = TextEditingController();
  String _paymentMethod = 'upi'; // 'upi', 'cash', 'card'
  final _paymentRefController = TextEditingController();
  bool _sendWhatsAppMessage = true;

  @override
  void initState() {
    super.initState();
    _bookingMode = widget.initialMode;
    _selectedRoomId = widget.preselectedRoomId;
    final now = DateTime.now();
    _checkInDate = DateTime(now.year, now.month, now.day);
    _expectedCheckOut = _checkInDate.add(
      const Duration(days: 1),
    ); // Default: just tonight (today and tomorrow)
    _calendarMonth = DateTime(_checkInDate.year, _checkInDate.month, 1);
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
        _activeSection = _AirbnbStep1Section.when;
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
      _activeSection = _AirbnbStep1Section.where;
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
      final now = DateTime.now();
      _checkInDate = DateTime(now.year, now.month, now.day);
      _expectedCheckOut = _checkInDate.add(const Duration(days: 1));
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

    final result = _bookingMode == BookingMode.reservation
        ? store.reserveRoom(
            roomId: selectedRoom.id,
            checkInDate: _checkInDate,
            checkOutDate: _expectedCheckOut,
            numGuests: _totalGuests,
            numAdults: _numAdults,
            numKids: _numKids,
            nightlyRate: selectedRoom.baseRate,
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
            nightlyRate: selectedRoom.baseRate,
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

    Room? selectedRoom;
    if (_selectedRoomId != null) {
      try {
        selectedRoom = store.rooms.firstWhere((r) => r.id == _selectedRoomId);
      } catch (_) {
        selectedRoom = availableRooms.isNotEmpty ? availableRooms.first : null;
      }
    } else if (availableRooms.isNotEmpty) {
      selectedRoom = availableRooms.first;
    }

    final nights = _expectedCheckOut
        .difference(_checkInDate)
        .inDays
        .clamp(1, 365);
    final nightlyRate = selectedRoom?.baseRate ?? 2200.0;
    final totalEstimatedAmount = nights * nightlyRate;

    // Set default advance if empty
    if (_advanceController.text.isEmpty && selectedRoom != null) {
      _advanceController.text = nightlyRate.toInt().toString();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: Navigator.of(context).canPop()
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.slateDark,
                ),
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
              title: Text(
                _bookingMode == BookingMode.checkIn
                    ? 'Check-In Wizard'
                    : 'Reservation Wizard',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.slateDark,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(color: AppTheme.slateBorder, height: 1),
              ),
            )
          : null,
      bottomNavigationBar: _buildUnifiedStickyFooter(
        selectedRoom: selectedRoom,
        nights: nights,
        totalEstimatedAmount: totalEstimatedAmount,
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

              // Wizard Header & Stepper
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (widget.onBack == null &&
                          Navigator.of(context).canPop()) ...[
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _bookingMode == BookingMode.checkIn
                                ? 'Check-In Wizard'
                                : 'Reservation Wizard',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          Text(
                            'Step $_currentStep of 3 • ${_currentStep == 1
                                ? "Room & Dates"
                                : _currentStep == 2
                                ? "Guest ID Verification"
                                : (_bookingMode == BookingMode.checkIn ? "Payment & Finalize" : "Deposit & Confirm")}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.slateMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [1, 2, 3].map((step) {
                      final isCurrent = _currentStep == step;
                      final isDone = _currentStep > step;
                      return Container(
                        margin: const EdgeInsets.only(left: 4),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? AppTheme.brandPrimary
                              : (isDone
                                    ? AppTheme.statusVacant
                                    : AppTheme.slateBorder),
                        ),
                        child: Center(
                          child: Text(
                            '$step',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

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
                                _expectedCheckOut = _checkInDate.add(
                                  const Duration(days: 1),
                                );
                                _activeSection = _AirbnbStep1Section.where;
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
                                  'Immediate Check-In',
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
                                if (_checkInDate.isBefore(now)) {
                                  _checkInDate = DateTime(
                                    now.year,
                                    now.month,
                                    now.day + 1,
                                  );
                                  _expectedCheckOut = _checkInDate.add(
                                    const Duration(days: 2),
                                  );
                                }
                                _activeSection = _AirbnbStep1Section
                                    .when; // Manager should select future dates first
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
                                  'Future Reservation',
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
                // Context helper banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _bookingMode == BookingMode.checkIn
                        ? AppTheme.brandLight.withValues(alpha: 0.5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.slateBorder.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _bookingMode == BookingMode.checkIn
                            ? Icons.flash_on_rounded
                            : Icons.date_range_rounded,
                        size: 14,
                        color: AppTheme.brandPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _bookingMode == BookingMode.checkIn
                              ? 'Walk-in guest arriving now • Instant room key assignment'
                              : 'Advance booking • Select any future start & end dates',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ==========================================
              // STEP 1: AIRBNB-STYLE CHOOSER (WHERE • WHEN • WHO)
              // ==========================================
              if (_currentStep == 1) ...[
                _buildAirbnbWhereSection(availableRooms, selectedRoom),
                const SizedBox(height: 12),
                _buildAirbnbWhenSection(store, nights),
                const SizedBox(height: 12),
                _buildAirbnbWhoSection(),
                const SizedBox(height: 32),
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
                              '₹${nightlyRate.toInt()}',
                            ),
                            const Divider(color: Colors.white24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                Text(
                                  '₹${totalEstimatedAmount.toInt()}',
                                  style: GoogleFonts.outfit(
                                    color: AppTheme.brandAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
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

                      const SizedBox(height: 18),

                      // WhatsApp notification on success toggle
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _sendWhatsAppMessage
                              ? const Color(0xFFF0FDF4)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _sendWhatsAppMessage
                                ? const Color(0xFFBBF7D0)
                                : AppTheme.slateBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: _sendWhatsAppMessage
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.chat_rounded,
                                size: 18,
                                color: _sendWhatsAppMessage
                                    ? const Color(0xFF16A34A)
                                    : AppTheme.slateMuted,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _bookingMode == BookingMode.reservation
                                        ? 'Send WhatsApp Reservation Confirmation'
                                        : 'Send WhatsApp Check-in Welcome',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    _sendWhatsAppMessage
                                        ? 'Automatic confirmation will be sent to guest on success'
                                        : 'No automated message will be sent for this booking',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _sendWhatsAppMessage,
                              activeTrackColor: const Color(0xFF16A34A),
                              activeThumbColor: Colors.white,
                              onChanged: (val) =>
                                  setState(() => _sendWhatsAppMessage = val),
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
                            isNotEmpty: _addressController.text.trim().isNotEmpty,
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
                            isNotEmpty: _pincodeController.text.trim().isNotEmpty,
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

  Widget _buildAirbnbWhereSection(
    List<Room> availableRooms,
    Room? selectedRoom,
  ) {
    final isExpanded = _activeSection == _AirbnbStep1Section.where;
    final isReservation = _bookingMode == BookingMode.reservation;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isExpanded ? 24 : 20),
        border: Border.all(
          color: isExpanded ? AppTheme.brandPrimary : AppTheme.slateBorder,
          width: isExpanded ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? AppTheme.brandPrimary.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.025),
            blurRadius: isExpanded ? 16 : 8,
            offset: Offset(0, isExpanded ? 4 : 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(isExpanded ? 24 : 20),
          onTap: isExpanded
              ? null
              : () =>
                    setState(() => _activeSection = _AirbnbStep1Section.where),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.brandLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isReservation
                          ? Icons.event_available_rounded
                          : Icons.hotel_rounded,
                      size: 20,
                      color: AppTheme.brandPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isReservation
                              ? 'WHERE • AVAILABLE ROOM'
                              : 'WHERE • VACANT ROOM',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selectedRoom != null
                              ? 'Room ${selectedRoom.roomNumber} • ${selectedRoom.categoryName} (Floor ${selectedRoom.floor})'
                              : (isReservation
                                    ? 'Choose an available room for dates'
                                    : 'Choose a vacant room'),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.slateMuted,
                  ),
                ],
              ),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isReservation
                            ? 'Rooms Available for Dates'
                            : 'Where will the guest stay?',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: AppTheme.slateMuted,
                        ),
                        onPressed: () => setState(
                          () => _activeSection = _AirbnbStep1Section.when,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isReservation
                        ? 'Showing inventory free for ${DateFormat('d MMM').format(_checkInDate)} – ${DateFormat('d MMM').format(_expectedCheckOut)}'
                        : 'Tap any vacant room to assign (automatically moves to When)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Floor Filter Pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill(
                          'All (${availableRooms.length})',
                          _selectedFloorFilter == 0,
                          () {
                            setState(() => _selectedFloorFilter = 0);
                          },
                        ),
                        ...context.read<HotelStore>().floors.map((fl) {
                          final count = availableRooms
                              .where((r) => r.floor == fl)
                              .length;
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _buildFilterPill(
                              'Floor $fl ($count)',
                              _selectedFloorFilter == fl,
                              () {
                                setState(() => _selectedFloorFilter = fl);
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Vacant / Available Rooms List
                  if (availableRooms.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isReservation
                                  ? 'No rooms available for ${DateFormat('d MMM').format(_checkInDate)} – ${DateFormat('d MMM').format(_expectedCheckOut)}. Please select different dates in "When".'
                                  : 'No vacant rooms available right now. Please mark a room as cleaned.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.red.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Builder(
                      builder: (context) {
                        final filtered = _selectedFloorFilter == 0
                            ? availableRooms
                            : availableRooms
                                  .where((r) => r.floor == _selectedFloorFilter)
                                  .toList();

                        if (filtered.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                'No available rooms on Floor $_selectedFloorFilter',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                            ),
                          );
                        }

                        return SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, i) {
                              final room = filtered[i];
                              final isSelected = room.id == _selectedRoomId;

                              return GestureDetector(
                                onTap: () {
                                  // SELECT ROOM AND AUTOMATICALLY MOVE TO WHEN!
                                  setState(() {
                                    _selectedRoomId = room.id;
                                    _activeSection = _AirbnbStep1Section.when;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 130,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.brandLight.withValues(
                                            alpha: 0.35,
                                          )
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.brandPrimary
                                          : AppTheme.slateBorder,
                                      width: isSelected ? 2.0 : 1.0,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.brandPrimary
                                                  .withValues(alpha: 0.12),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ]
                                        : [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.02,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            room.roomNumber,
                                            style: GoogleFonts.outfit(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? AppTheme.brandDark
                                                  : AppTheme.slateDark,
                                            ),
                                          ),
                                          if (isSelected)
                                            Container(
                                              padding: const EdgeInsets.all(3),
                                              decoration: const BoxDecoration(
                                                color: AppTheme.brandPrimary,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.check_rounded,
                                                size: 10,
                                                color: Colors.white,
                                              ),
                                            )
                                          else
                                            Text(
                                              'Fl ${room.floor}',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                color: AppTheme.slateMuted,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                      Text(
                                        room.categoryName,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isSelected
                                              ? AppTheme.brandPrimary
                                              : AppTheme.slateMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '₹${room.baseRate.toInt()}/n',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? AppTheme.brandDark
                                                  : AppTheme.slateDark,
                                            ),
                                          ),
                                          if (isReservation)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF0FDF4),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Free',
                                                style: GoogleFonts.inter(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(
                                                    0xFF16A34A,
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
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAirbnbWhenSection(HotelStore store, int nights) {
    final isExpanded = _activeSection == _AirbnbStep1Section.when;
    final isReservation = _bookingMode == BookingMode.reservation;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isExpanded ? 24 : 20),
        border: Border.all(
          color: isExpanded ? AppTheme.brandPrimary : AppTheme.slateBorder,
          width: isExpanded ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? AppTheme.brandPrimary.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.025),
            blurRadius: isExpanded ? 16 : 8,
            offset: Offset(0, isExpanded ? 4 : 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(isExpanded ? 24 : 20),
          onTap: isExpanded
              ? null
              : () => setState(() => _activeSection = _AirbnbStep1Section.when),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.brandLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isReservation
                          ? Icons.date_range_rounded
                          : Icons.calendar_today_rounded,
                      size: 18,
                      color: AppTheme.brandPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isReservation
                              ? 'WHEN • RESERVATION PERIOD'
                              : 'WHEN • DURATION (CHECK-IN TODAY)',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat('d MMM').format(_checkInDate)} – ${DateFormat('d MMM').format(_expectedCheckOut)} ($nights night${nights > 1 ? "s" : ""})',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.slateMuted,
                  ),
                ],
              ),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isReservation
                            ? 'Select Reservation Period'
                            : "When's the stay?",
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: AppTheme.slateMuted,
                        ),
                        onPressed: () => setState(
                          () => _activeSection = _AirbnbStep1Section.who,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isReservation
                        ? 'Select both start and end dates anytime in the future.'
                        : 'Immediate check-in starts today. Choose departure date or duration below.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // For Reservation: Arrival & Departure Interactive Selector
                  if (isReservation) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.slateBorder),
                      ),
                      child: Row(
                        children: [
                          // Arrival Date Box
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _pickingStartDate = true),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _pickingStartDate
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _pickingStartDate
                                        ? AppTheme.brandPrimary
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                  boxShadow: _pickingStartDate
                                      ? [
                                          BoxShadow(
                                            color: AppTheme.brandPrimary
                                                .withValues(alpha: 0.1),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.flight_land_rounded,
                                          size: 13,
                                          color: _pickingStartDate
                                              ? AppTheme.brandPrimary
                                              : AppTheme.slateMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'CHECK-IN',
                                          style: GoogleFonts.inter(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: _pickingStartDate
                                                ? AppTheme.brandPrimary
                                                : AppTheme.slateMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      DateFormat(
                                        'EEE, d MMM',
                                      ).format(_checkInDate),
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                          // Departure Date Box
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _pickingStartDate = false),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: !_pickingStartDate
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: !_pickingStartDate
                                        ? AppTheme.brandPrimary
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                  boxShadow: !_pickingStartDate
                                      ? [
                                          BoxShadow(
                                            color: AppTheme.brandPrimary
                                                .withValues(alpha: 0.1),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.flight_takeoff_rounded,
                                          size: 13,
                                          color: !_pickingStartDate
                                              ? AppTheme.brandPrimary
                                              : AppTheme.slateMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'CHECK-OUT',
                                          style: GoogleFonts.inter(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: !_pickingStartDate
                                                ? AppTheme.brandPrimary
                                                : AppTheme.slateMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      DateFormat(
                                        'EEE, d MMM',
                                      ).format(_expectedCheckOut),
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Quick Stay Presets
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: isReservation
                          ? [
                              // RESERVATION PRESETS
                              _buildPresetChip('This Weekend', false, () {
                                final now = DateTime.now();
                                final daysToFri =
                                    (DateTime.friday - now.weekday + 7) % 7;
                                final start = DateTime(
                                  now.year,
                                  now.month,
                                  now.day + (daysToFri == 0 ? 7 : daysToFri),
                                );
                                final end = start.add(const Duration(days: 2));
                                setState(() {
                                  _checkInDate = start;
                                  _expectedCheckOut = end;
                                  _pickingStartDate = true;
                                });
                              }),
                              const SizedBox(width: 8),
                              _buildPresetChip('Next Week (4N)', false, () {
                                final now = DateTime.now();
                                final daysToMon =
                                    (DateTime.monday - now.weekday + 7) % 7;
                                final start = DateTime(
                                  now.year,
                                  now.month,
                                  now.day + (daysToMon == 0 ? 7 : daysToMon),
                                );
                                final end = start.add(const Duration(days: 4));
                                setState(() {
                                  _checkInDate = start;
                                  _expectedCheckOut = end;
                                  _pickingStartDate = true;
                                });
                              }),
                              const SizedBox(width: 8),
                              _buildPresetChip('In 2 Weeks (3N)', false, () {
                                final now = DateTime.now();
                                final start = DateTime(
                                  now.year,
                                  now.month,
                                  now.day + 14,
                                );
                                final end = start.add(const Duration(days: 3));
                                setState(() {
                                  _checkInDate = start;
                                  _expectedCheckOut = end;
                                  _pickingStartDate = true;
                                });
                              }),
                              const SizedBox(width: 8),
                              _buildPresetChip('Next Month (3N)', false, () {
                                final now = DateTime.now();
                                final start = DateTime(
                                  now.year,
                                  now.month + 1,
                                  1,
                                );
                                final end = start.add(const Duration(days: 3));
                                setState(() {
                                  _calendarMonth = DateTime(
                                    start.year,
                                    start.month,
                                    1,
                                  );
                                  _checkInDate = start;
                                  _expectedCheckOut = end;
                                  _pickingStartDate = true;
                                });
                              }),
                            ]
                          : [
                              // IMMEDIATE CHECK-IN PRESETS
                              _buildPresetChip('Tonight (1N)', nights == 1, () {
                                final today = DateTime.now();
                                setState(() {
                                  _checkInDate = DateTime(
                                    today.year,
                                    today.month,
                                    today.day,
                                  );
                                  _expectedCheckOut = _checkInDate.add(
                                    const Duration(days: 1),
                                  );
                                  _activeSection = _AirbnbStep1Section.who;
                                });
                              }),
                              const SizedBox(width: 8),
                              _buildPresetChip('2 Nights', nights == 2, () {
                                final today = DateTime.now();
                                setState(() {
                                  _checkInDate = DateTime(
                                    today.year,
                                    today.month,
                                    today.day,
                                  );
                                  _expectedCheckOut = _checkInDate.add(
                                    const Duration(days: 2),
                                  );
                                  _activeSection = _AirbnbStep1Section.who;
                                });
                              }),
                              const SizedBox(width: 8),
                              _buildPresetChip('3 Nights', nights == 3, () {
                                final today = DateTime.now();
                                setState(() {
                                  _checkInDate = DateTime(
                                    today.year,
                                    today.month,
                                    today.day,
                                  );
                                  _expectedCheckOut = _checkInDate.add(
                                    const Duration(days: 3),
                                  );
                                  _activeSection = _AirbnbStep1Section.who;
                                });
                              }),
                              const SizedBox(width: 8),
                              _buildPresetChip('1 Week', nights == 7, () {
                                final today = DateTime.now();
                                setState(() {
                                  _checkInDate = DateTime(
                                    today.year,
                                    today.month,
                                    today.day,
                                  );
                                  _expectedCheckOut = _checkInDate.add(
                                    const Duration(days: 7),
                                  );
                                  _activeSection = _AirbnbStep1Section.who;
                                });
                              }),
                            ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Embedded Minimal Calendar Grid
                  _buildEmbeddedAirbnbCalendar(),

                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(
                        () => _activeSection = _AirbnbStep1Section.who,
                      ),
                      icon: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: AppTheme.brandPrimary,
                      ),
                      label: Text(
                        'Confirm Dates & Continue to Who',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brandPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmbeddedAirbnbCalendar() {
    final daysInMonth = DateTime(
      _calendarMonth.year,
      _calendarMonth.month + 1,
      0,
    ).day;
    final firstWeekday =
        DateTime(_calendarMonth.year, _calendarMonth.month, 1).weekday %
        7; // 0 = Sun
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        children: [
          // Month header & Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: AppTheme.slateDark,
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _calendarMonth = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month - 1,
                      1,
                    );
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(_calendarMonth),
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.slateDark,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.slateDark,
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _calendarMonth = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month + 1,
                      1,
                    );
                  });
                },
              ),
            ],
          ),

          // Weekday header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) {
                return SizedBox(
                  width: 32,
                  child: Center(
                    child: Text(
                      d,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Days grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.1,
            ),
            itemBuilder: (context, i) {
              final dayNum = i - firstWeekday + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(
                _calendarMonth.year,
                _calendarMonth.month,
                dayNum,
              );
              final isPast = date.isBefore(today);

              final isStart = date.isAtSameMomentAs(_checkInDate);
              final isEnd = date.isAtSameMomentAs(_expectedCheckOut);
              final isMiddle =
                  date.isAfter(_checkInDate) &&
                  date.isBefore(_expectedCheckOut);
              final isSelected = isStart || isEnd;

              Widget? bridge;
              if (_expectedCheckOut.isAfter(_checkInDate)) {
                if (isStart) {
                  bridge = Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 20,
                      height: 32,
                      color: AppTheme.brandLight,
                    ),
                  );
                } else if (isEnd) {
                  bridge = Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 20,
                      height: 32,
                      color: AppTheme.brandLight,
                    ),
                  );
                } else if (isMiddle) {
                  bridge = Container(height: 32, color: AppTheme.brandLight);
                }
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isPast
                    ? null
                    : () {
                        setState(() {
                          if (_bookingMode == BookingMode.checkIn) {
                            // Immediate Check-In: check-in is today, date picked is checkout!
                            if (date.isAtSameMomentAs(today)) {
                              _checkInDate = today;
                              _expectedCheckOut = today.add(
                                const Duration(days: 1),
                              );
                            } else {
                              _checkInDate = today;
                              _expectedCheckOut = date;
                            }
                            Future.delayed(
                              const Duration(milliseconds: 260),
                              () {
                                if (mounted)
                                  setState(
                                    () => _activeSection =
                                        _AirbnbStep1Section.who,
                                  );
                              },
                            );
                          } else {
                            // Advance Reservation: can pick any future start and end date!
                            if (_pickingStartDate) {
                              _checkInDate = date;
                              if (!_expectedCheckOut.isAfter(date)) {
                                _expectedCheckOut = date.add(
                                  const Duration(days: 1),
                                );
                              }
                              _pickingStartDate = false;
                            } else {
                              if (date.isAfter(_checkInDate)) {
                                _expectedCheckOut = date;
                                _pickingStartDate = true;
                                Future.delayed(
                                  const Duration(milliseconds: 260),
                                  () {
                                    if (mounted)
                                      setState(
                                        () => _activeSection =
                                            _AirbnbStep1Section.who,
                                      );
                                  },
                                );
                              } else {
                                _checkInDate = date;
                                _expectedCheckOut = date.add(
                                  const Duration(days: 1),
                                );
                                _pickingStartDate = false;
                              }
                            }
                          }
                        });
                      },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (bridge != null) bridge,
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.brandPrimary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: (date.isAtSameMomentAs(today) && !isSelected)
                            ? Border.all(
                                color: AppTheme.brandPrimary,
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$dayNum',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : (isPast
                                      ? const Color(0xFFCBD5E1)
                                      : (isMiddle
                                            ? AppTheme.brandDark
                                            : AppTheme.slateDark)),
                            decoration: isPast
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: const Color(0xFFCBD5E1),
                          ),
                        ),
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

  Widget _buildAirbnbWhoSection() {
    final isExpanded = _activeSection == _AirbnbStep1Section.who;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isExpanded ? 24 : 20),
        border: Border.all(
          color: isExpanded ? AppTheme.brandPrimary : AppTheme.slateBorder,
          width: isExpanded ? 1.8 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? AppTheme.brandPrimary.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.025),
            blurRadius: isExpanded ? 16 : 8,
            offset: Offset(0, isExpanded ? 4 : 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(isExpanded ? 24 : 20),
          onTap: isExpanded
              ? null
              : () => setState(() => _activeSection = _AirbnbStep1Section.who),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.brandLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.group_outlined,
                      size: 18,
                      color: AppTheme.brandPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WHO',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_totalGuests guest(s) ($_numAdults Adult${_numAdults > 1 ? "s" : ""}${_numKids > 0 ? ", $_numKids Kid${_numKids > 1 ? "s" : ""}" : ""})',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.slateMuted,
                  ),
                ],
              ),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Who's checking in?",
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.brandLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_totalGuests guest${_totalGuests > 1 ? "s" : ""}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '1 adult is selected by default',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Adults row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adults',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          Text(
                            'Ages 13 or above',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _buildAirbnbCounterButton(
                            icon: Icons.remove_rounded,
                            enabled: _numAdults > 1,
                            onTap: () => setState(
                              () => _numAdults = (_numAdults - 1).clamp(1, 10),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: Center(
                              child: Text(
                                '$_numAdults',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ),
                          ),
                          _buildAirbnbCounterButton(
                            icon: Icons.add_rounded,
                            enabled: _numAdults < 10,
                            onTap: () => setState(
                              () => _numAdults = (_numAdults + 1).clamp(1, 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: AppTheme.slateBorder),

                  // Children row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Children',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          Text(
                            'Ages 0 to 12',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _buildAirbnbCounterButton(
                            icon: Icons.remove_rounded,
                            enabled: _numKids > 0,
                            onTap: () => setState(
                              () => _numKids = (_numKids - 1).clamp(0, 10),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: Center(
                              child: Text(
                                '$_numKids',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ),
                          ),
                          _buildAirbnbCounterButton(
                            icon: Icons.add_rounded,
                            enabled: _numKids < 10,
                            onTap: () => setState(
                              () => _numKids = (_numKids + 1).clamp(0, 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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

  Widget _buildPresetChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20),
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
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppTheme.slateDark,
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedStickyFooter({
    required Room? selectedRoom,
    required int nights,
    required double totalEstimatedAmount,
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
            // Left summary (context-aware per step)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '₹${totalEstimatedAmount.toInt()}',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'TOTAL',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: const Color(0xFF16A34A),
                          ),
                        ),
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
                              content: Text('Please enter a valid guest name (minimum 2 characters)'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_dobController.text.trim().isNotEmpty && !_isDobValid(_dobController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid DOB in DD/MM/YYYY format'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_phoneController.text.replaceAll(RegExp(r'\D'), '').isNotEmpty &&
                            !_isPhoneValid(_phoneController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid 10-digit phone number'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_pincodeController.text.replaceAll(RegExp(r'\D'), '').isNotEmpty &&
                            !_isPincodeValid(_pincodeController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid 6-digit pincode'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        if (_emailController.text.trim().isNotEmpty && !_isEmailValid(_emailController.text)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid email address'),
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
