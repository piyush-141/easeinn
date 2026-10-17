import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:camera/camera.dart';

import 'camera_web_bridge/camera_web_bridge.dart';
import 'camera_web_bridge/camera_bridge_interface.dart';
import '../theme/app_theme.dart';

class ChatGptCameraSheet extends StatefulWidget {
  final Function(Uint8List bytes, String filename) onCaptured;
  final String title;

  const ChatGptCameraSheet({
    super.key,
    required this.onCaptured,
    this.title = 'Scan Document',
  });

  static Future<void> show(
    BuildContext context, {
    required Function(Uint8List bytes, String filename) onCaptured,
    String title = 'Scan Document',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChatGptCameraSheet(
        onCaptured: onCaptured,
        title: title,
      ),
    );
  }

  @override
  State<ChatGptCameraSheet> createState() => _ChatGptCameraSheetState();
}

class _ChatGptCameraSheetState extends State<ChatGptCameraSheet> with SingleTickerProviderStateMixin {
  // Web bridge
  final CameraBridge _webCameraBridge = createCameraBridge();
  String? _webViewId;

  // Mobile camera controller (Android / iOS)
  CameraController? _mobileCameraController;

  bool _isCameraReady = false;
  String? _errorMessage;
  bool _isCapturing = false;
  late AnimationController _flashAnimController;

  @override
  void initState() {
    super.initState();
    _flashAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (kIsWeb) {
      await _initWebCamera();
    } else {
      await _initMobileCamera();
    }
  }

  Future<void> _initMobileCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras found on this device.');
      }

      // Prefer back camera for document scanning
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _mobileCameraController = controller;
        _isCameraReady = true;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('[CameraSheet] Mobile Camera init error: $e');
      setState(() {
        _errorMessage = 'Could not access mobile camera. Please allow camera permissions or upload an ID image.';
      });
    }
  }

  Future<void> _initWebCamera() async {
    try {
      final viewId = await _webCameraBridge.initCamera();
      if (viewId == null) {
        throw Exception('Camera device not supported by this browser.');
      }

      setState(() {
        _webViewId = viewId;
        _isCameraReady = true;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('[CameraSheet] Web camera init error: $e');
      setState(() {
        _errorMessage = 'Could not access camera in browser. Please allow camera permissions or upload a file.';
      });
    }
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing || !_isCameraReady) return;

    setState(() => _isCapturing = true);
    _flashAnimController.forward().then((_) => _flashAnimController.reverse());

    try {
      Uint8List? bytes;
      String filename = 'camera_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';

      if (!kIsWeb && _mobileCameraController != null && _mobileCameraController!.value.isInitialized) {
        // Mobile camera capture
        final XFile file = await _mobileCameraController!.takePicture();
        bytes = await file.readAsBytes();
        filename = file.name;
      } else if (kIsWeb) {
        // Web canvas capture
        bytes = await _webCameraBridge.capturePhoto();
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('No image data captured.');
      }

      _stopCamera();
      if (mounted) {
        Navigator.of(context).pop();
        widget.onCaptured(bytes, filename);
      }
    } catch (e) {
      debugPrint('[CameraSheet] Capture error: $e');
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _pickFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          _stopCamera();
          if (mounted) {
            Navigator.of(context).pop();
            widget.onCaptured(file.bytes!, file.name);
          }
        }
      }
    } catch (e) {
      debugPrint('[CameraSheet] File picker error: $e');
    }
  }

  void _stopCamera() {
    if (_mobileCameraController != null) {
      _mobileCameraController!.dispose();
      _mobileCameraController = null;
    }
    _webCameraBridge.stopCamera();
  }

  @override
  void dispose() {
    _stopCamera();
    _flashAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = (screenHeight * 0.75).clamp(460.0, 720.0);

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF141417),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── LIVE CAMERA STREAM ────────────────────────────
          Positioned.fill(
            bottom: 96,
            child: _errorMessage != null
                ? Container(
                    color: const Color(0xFF1C1C22),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 44),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _pickFromFile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandPrimary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.photo_library_rounded, size: 18),
                            label: const Text('Choose from Gallery / Files'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _isCameraReady
                    ? Stack(
                        children: [
                          // Camera Preview Widget
                          Positioned.fill(
                            child: !kIsWeb && _mobileCameraController != null && _mobileCameraController!.value.isInitialized
                                ? LayoutBuilder(
                                    builder: (context, constraints) {
                                      return ClipRRect(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                                        child: SizedBox(
                                          width: constraints.maxWidth,
                                          height: constraints.maxHeight,
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            child: SizedBox(
                                              width: _mobileCameraController!.value.previewSize?.height ?? constraints.maxWidth,
                                              height: _mobileCameraController!.value.previewSize?.width ?? constraints.maxHeight,
                                              child: CameraPreview(_mobileCameraController!),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : (kIsWeb && _webViewId != null)
                                    ? HtmlElementView(viewType: _webViewId!)
                                    : const SizedBox.shrink(),
                          ),

                          // Document Alignment Frame (ID card guide)
                          Center(
                            child: AspectRatio(
                              aspectRatio: 1.58, // Standard credit-card / Aadhaar ratio
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 28),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    width: 1.8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.crop_free_rounded, color: Colors.white70, size: 13),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Align Aadhaar / PAN within frame',
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Opening Camera...',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
          ),

          // ── TOP DRAG HANDLE & TITLE ───────────────────────
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.brandPrimary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.brandPrimary.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'AI Vision Active',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF5AC8FA),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── FLASH ANIMATION OVERLAY ───────────────────────
          Positioned.fill(
            bottom: 96,
            child: AnimatedBuilder(
              animation: _flashAnimController,
              builder: (context, child) {
                return IgnorePointer(
                  child: Container(
                    color: Colors.white.withValues(alpha: _flashAnimController.value * 0.9),
                  ),
                );
              },
            ),
          ),

          // ── BOTTOM CONTROLS (ChatGPT Floating Bar) ────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 96,
            child: Container(
              color: const Color(0xFF141417),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dismiss Button
                  GestureDetector(
                    onTap: () {
                      _stopCamera();
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                    ),
                  ),

                  // Big Center Shutter Button
                  GestureDetector(
                    onTap: _isCameraReady && !_isCapturing ? _capturePhoto : null,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: _isCapturing ? 46 : 54,
                          height: _isCapturing ? 46 : 54,
                          decoration: BoxDecoration(
                            color: _isCapturing ? AppTheme.brandPrimary : Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: _isCapturing
                              ? const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),

                  // File Picker / Gallery Button
                  GestureDetector(
                    onTap: _pickFromFile,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
