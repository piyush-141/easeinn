import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';

import 'camera_web_bridge/camera_web_bridge.dart';
import 'camera_web_bridge/camera_bridge_interface.dart';

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
  final CameraBridge _cameraBridge = createCameraBridge();
  String? _viewId;
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
    if (kIsWeb && _cameraBridge.isSupported) {
      _initWebCamera();
    } else {
      setState(() {
        _errorMessage = 'In-app camera is currently optimized for Web. Use file upload on mobile.';
      });
    }
  }

  Future<void> _initWebCamera() async {
    try {
      final viewId = await _cameraBridge.initCamera();
      if (viewId == null) {
        throw Exception('Camera device not supported by this browser.');
      }

      setState(() {
        _viewId = viewId;
        _isCameraReady = true;
      });
    } catch (e) {
      debugPrint('[CameraSheet] Camera init error: $e');
      setState(() {
        _errorMessage = 'Could not access camera. Please allow camera permissions or upload a file.';
      });
    }
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;

    if (_isCameraReady) {
      setState(() => _isCapturing = true);
      _flashAnimController.forward().then((_) => _flashAnimController.reverse());

      try {
        final Uint8List? bytes = await _cameraBridge.capturePhoto();
        if (bytes == null) throw Exception('No image captured');

        _stopCamera();
        if (mounted) {
          Navigator.of(context).pop();
          widget.onCaptured(bytes, 'camera_capture_${DateTime.now().millisecondsSinceEpoch}.jpg');
        }
      } catch (e) {
        debugPrint('[CameraSheet] Capture error: $e');
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
    _cameraBridge.stopCamera();
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
    // Cover ~60% of the screen like ChatGPT
    final sheetHeight = (screenHeight * 0.62).clamp(420.0, 680.0);

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
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.folder_open_rounded, size: 18),
                            label: const Text('Choose from Files'),
                          ),
                        ],
                      ),
                    ),
                  )
                : (_isCameraReady && _viewId != null)
                    ? Stack(
                        children: [
                          HtmlElementView(viewType: _viewId!),

                          // Document Alignment Frame (Subtle ID card guide)
                          Center(
                            child: AspectRatio(
                              aspectRatio: 1.58, // Standard credit-card ratio
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 32),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Fit document within frame',
                                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
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
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── FLASH ANIMATION EFFECT ────────────────────────
          AnimatedBuilder(
            animation: _flashAnimController,
            builder: (context, child) {
              return IgnorePointer(
                child: Container(
                  color: Colors.white.withValues(alpha: _flashAnimController.value * 0.8),
                ),
              );
            },
          ),

          // ── BOTTOM CONTROLS (ChatGPT Style) ───────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 96,
              color: const Color(0xFF141417),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Back / Close Button
                  InkWell(
                    onTap: () {
                      _stopCamera();
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),

                  // Center Shutter Button (Large White Circle like ChatGPT)
                  GestureDetector(
                    onTap: _isCameraReady ? _capturePhoto : null,
                    child: Container(
                      width: 72,
                      height: 72,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _isCapturing
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),

                  // Gallery / File Picker Button
                  InkWell(
                    onTap: _pickFromFile,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
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
