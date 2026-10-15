class Property {
  final String id;
  final String name;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String phone;
  final String email;
  final int totalRooms;

  final String upiId; // Bank UPI VPA, e.g. piyushpal427@okaxis
  final String upiPayeeName; // Payee name, e.g. Piyush Pal
  final String gstNumber; // GSTIN tax identification
  final String defaultCheckInTime; // Default standard check-in, e.g. "12:00 PM"
  final String defaultCheckOutTime; // Default standard check-out, e.g. "11:00 AM"
  final String hotelTier; // e.g. "Boutique Hotel", "Heritage", "Resort"

  Property({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.pincode,
    required this.phone,
    required this.email,
    required this.totalRooms,
    this.upiId = 'piyushpal427@okaxis',
    this.upiPayeeName = 'Piyush Pal',
    this.gstNumber = '29ABCDE1234F1Z5',
    this.defaultCheckInTime = '12:00 PM',
    this.defaultCheckOutTime = '11:00 AM',
    this.hotelTier = 'Boutique Hotel',
  });

  Property copyWith({
    String? id,
    String? name,
    String? address,
    String? city,
    String? state,
    String? pincode,
    String? phone,
    String? email,
    int? totalRooms,
    String? upiId,
    String? upiPayeeName,
    String? gstNumber,
    String? defaultCheckInTime,
    String? defaultCheckOutTime,
    String? hotelTier,
  }) {
    return Property(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      totalRooms: totalRooms ?? this.totalRooms,
      upiId: upiId ?? this.upiId,
      upiPayeeName: upiPayeeName ?? this.upiPayeeName,
      gstNumber: gstNumber ?? this.gstNumber,
      defaultCheckInTime: defaultCheckInTime ?? this.defaultCheckInTime,
      defaultCheckOutTime: defaultCheckOutTime ?? this.defaultCheckOutTime,
      hotelTier: hotelTier ?? this.hotelTier,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'city': city,
    'state': state,
    'pincode': pincode,
    'phone': phone,
    'email': email,
    'total_rooms': totalRooms,
    'upi_id': upiId,
    'upi_payee_name': upiPayeeName,
  };

  factory Property.fromJson(Map<String, dynamic> json) => Property(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    address: json['address'] ?? '',
    city: json['city'] ?? '',
    state: json['state'] ?? '',
    pincode: json['pincode'] ?? '',
    phone: json['phone'] ?? '',
    email: json['email'] ?? '',
    totalRooms: json['total_rooms'] ?? 12,
    upiId: json['upi_id'] ?? 'piyushpal427@okaxis',
    upiPayeeName: json['upi_payee_name'] ?? 'Piyush Pal',
  );
}
