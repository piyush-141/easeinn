class Guest {
  final String id;
  final String propertyId;
  final String fullName;
  final String phone;
  final String? email;
  final String idType;
  final String idNumberMasked;
  final String? idNumber;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? pincode;
  final String? fatherName;
  final String? notes;
  final int staysCount;
  final DateTime createdAt;

  Guest({
    required this.id,
    required this.propertyId,
    required this.fullName,
    required this.phone,
    this.email,
    required this.idType,
    required this.idNumberMasked,
    this.idNumber,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.pincode,
    this.fatherName,
    this.notes,
    this.staysCount = 1,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Returns the full ID number if recorded, otherwise falls back to masked ID
  String get displayIdNumber => (idNumber != null && idNumber!.trim().isNotEmpty) ? idNumber!.trim() : idNumberMasked;

  Map<String, dynamic> toJson() => {
    'id': id,
    'property_id': propertyId,
    'full_name': fullName,
    'phone': phone,
    'email': email,
    'id_type': idType,
    'id_number_masked': idNumberMasked,
    'id_number': idNumber,
    'date_of_birth': dateOfBirth,
    'gender': gender,
    'address': address,
    'pincode': pincode,
    'father_name': fatherName,
    'notes': notes,
    'stays_count': staysCount,
    'created_at': createdAt.toIso8601String(),
  };

  factory Guest.fromJson(Map<String, dynamic> json) => Guest(
    id: json['id'] ?? '',
    propertyId: json['property_id'] ?? '',
    fullName: json['full_name'] ?? '',
    phone: json['phone'] ?? '',
    email: json['email'],
    idType: json['id_type'] ?? 'aadhaar',
    idNumberMasked: json['id_number_masked'] ?? 'XXXX',
    idNumber: json['id_number'],
    dateOfBirth: json['date_of_birth'],
    gender: json['gender'],
    address: json['address'],
    pincode: json['pincode'],
    fatherName: json['father_name'],
    notes: json['notes'],
    staysCount: json['stays_count'] ?? 1,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
  );
}
