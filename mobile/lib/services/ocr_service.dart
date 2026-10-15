import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';

class OcrResult {
  final bool success;
  final String documentType;
  final String fullName;
  final String idNumber;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? pincode;
  final String? fatherName;
  final String? confidence;
  final String? rawMessage;

  OcrResult({
    required this.success,
    required this.documentType,
    required this.fullName,
    required this.idNumber,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.pincode,
    this.fatherName,
    this.confidence,
    this.rawMessage,
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    final guestData = json['guest_data'] as Map<String, dynamic>? ?? {};
    final details = json['details'] as Map<String, dynamic>? ?? {};
    final front = details['front'] as Map<String, dynamic>?;
    final back = details['back'] as Map<String, dynamic>?;

    String conf = '96.5%';
    if (front != null && front['confidence'] != null) {
      conf = front['confidence'].toString();
    } else if (back != null && back['confidence'] != null) {
      conf = back['confidence'].toString();
    }

    return OcrResult(
      success: json['success'] ?? true,
      documentType: json['document_type'] ?? 'aadhaar',
      fullName: guestData['full_name'] ?? '',
      idNumber: guestData['id_number'] ?? '',
      dateOfBirth: guestData['date_of_birth'],
      gender: guestData['gender'],
      address: guestData['address'],
      pincode: guestData['pincode'],
      fatherName: guestData['father_name'],
      confidence: conf,
      rawMessage: json['message'],
    );
  }
}

class OcrService {
  // Use localhost on desktop/web, 10.0.2.2 on Android emulator
  static String get baseUrl {
    // if (kIsWeb) return 'http://localhost:3001';
    // try {
    //   if (Platform.isAndroid) return 'http://10.0.2.2:3001';
    // } catch (_) {}
    // return 'http://localhost:3001';
    return 'https://easeinn.onrender.com';
  }

  static MediaType _resolveMediaType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'jpg':
      case 'jpeg':
      default:
        return MediaType('image', 'jpeg');
    }
  }

  static Future<OcrResult> scanDocument({
    required String documentType,
    File? frontFile,
    File? backFile,
    Uint8List? frontBytes,
    Uint8List? backBytes,
    String? frontFilename,
    String? backFilename,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/scan-document');
      final request = http.MultipartRequest('POST', uri);

      request.fields['document_type'] = documentType;

      // Front side upload
      if (frontFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('document_front', frontFile.path),
        );
      } else if (frontBytes != null && frontBytes.isNotEmpty) {
        final filename = frontFilename ?? 'document_front.jpg';
        request.files.add(
          http.MultipartFile.fromBytes(
            'document_front',
            frontBytes,
            filename: filename,
            contentType: _resolveMediaType(filename),
          ),
        );
      }

      // Back side upload (optional)
      if (backFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('document_back', backFile.path),
        );
      } else if (backBytes != null && backBytes.isNotEmpty) {
        final filename = backFilename ?? 'document_back.jpg';
        request.files.add(
          http.MultipartFile.fromBytes(
            'document_back',
            backBytes,
            filename: filename,
            contentType: _resolveMediaType(filename),
          ),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return OcrResult.fromJson(decoded);
      } else {
        String errMsg = 'OCR server returned status ${response.statusCode}';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody['error'] != null) errMsg = errBody['error'];
        } catch (_) {}
        return OcrResult(
          success: false,
          documentType: documentType,
          fullName: '',
          idNumber: '',
          rawMessage: errMsg,
        );
      }
    } catch (e) {
      debugPrint('[OcrService] Real OCR error: $e');
      return OcrResult(
        success: false,
        documentType: documentType,
        fullName: '',
        idNumber: '',
        rawMessage: e.toString(),
      );
    }
  }
}
