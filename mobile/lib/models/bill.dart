class BillLineItem {
  final String id;
  final String description;
  final int quantity;
  final double unitPrice;
  final double amount;

  BillLineItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'quantity': quantity,
    'unit_price': unitPrice,
    'amount': amount,
  };

  factory BillLineItem.fromJson(Map<String, dynamic> json) => BillLineItem(
    id: json['id']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    quantity: json['quantity'] is int ? json['quantity'] : (int.tryParse(json['quantity']?.toString() ?? '1') ?? 1),
    unitPrice: (json['unit_price'] is num) ? (json['unit_price'] as num).toDouble() : (double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0.0),
    amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : (double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0),
  );
}

class Payment {
  String id;
  String? propertyId;
  String? billId;
  final double amount;
  final String method; // 'cash', 'upi', 'card'
  final String paymentType; // 'advance', 'full'
  final String? reference;
  final DateTime recordedAt;

  Payment({
    required this.id,
    this.propertyId,
    this.billId,
    required this.amount,
    required this.method,
    required this.paymentType,
    this.reference,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  Payment copyWith({
    String? id,
    String? propertyId,
    String? billId,
    double? amount,
    String? method,
    String? paymentType,
    String? reference,
    DateTime? recordedAt,
  }) {
    return Payment(
      id: id ?? this.id,
      propertyId: propertyId ?? this.propertyId,
      billId: billId ?? this.billId,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      paymentType: paymentType ?? this.paymentType,
      reference: reference ?? this.reference,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (propertyId != null) 'property_id': propertyId,
    if (billId != null) 'bill_id': billId,
    'amount': amount,
    'method': method,
    'payment_type': paymentType,
    'reference': reference,
    'recorded_at': recordedAt.toIso8601String(),
  };

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: json['id']?.toString() ?? '',
    propertyId: json['property_id']?.toString(),
    billId: json['bill_id']?.toString(),
    amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : (double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0),
    method: json['method']?.toString() ?? 'cash',
    paymentType: json['payment_type']?.toString() ?? 'advance',
    reference: json['reference']?.toString(),
    recordedAt: json['recorded_at'] != null ? DateTime.tryParse(json['recorded_at'].toString()) ?? DateTime.now() : DateTime.now(),
  );
}

class Bill {
  String id;
  String propertyId;
  final String stayId;
  final String billNumber;
  double subtotal;
  double amountPaid;
  double outstanding;
  String status; // 'draft', 'finalized', 'reserved'
  final List<BillLineItem> lineItems;
  final List<Payment> payments;
  final DateTime createdAt;

  Bill({
    required this.id,
    this.propertyId = '',
    required this.stayId,
    required this.billNumber,
    required this.subtotal,
    required this.amountPaid,
    required this.outstanding,
    this.status = 'draft',
    List<BillLineItem>? lineItems,
    List<Payment>? payments,
    DateTime? createdAt,
  })  : lineItems = lineItems ?? [],
        payments = payments ?? [],
        createdAt = createdAt ?? DateTime.now();

  Bill copyWith({
    String? id,
    String? propertyId,
    String? stayId,
    String? billNumber,
    double? subtotal,
    double? amountPaid,
    double? outstanding,
    String? status,
    List<BillLineItem>? lineItems,
    List<Payment>? payments,
    DateTime? createdAt,
  }) {
    return Bill(
      id: id ?? this.id,
      propertyId: propertyId ?? this.propertyId,
      stayId: stayId ?? this.stayId,
      billNumber: billNumber ?? this.billNumber,
      subtotal: subtotal ?? this.subtotal,
      amountPaid: amountPaid ?? this.amountPaid,
      outstanding: outstanding ?? this.outstanding,
      status: status ?? this.status,
      lineItems: lineItems ?? this.lineItems,
      payments: payments ?? this.payments,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'property_id': propertyId,
    'stay_id': stayId,
    'bill_number': billNumber,
    'subtotal': subtotal,
    'amount_paid': amountPaid,
    'outstanding': outstanding,
    'status': status,
    'line_items': lineItems.map((li) => li.toJson()).toList(),
    'payments': payments.map((p) => p.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
  };

  factory Bill.fromJson(Map<String, dynamic> json) {
    final rawLineItems = json['line_items'] as List<dynamic>?;
    final List<BillLineItem> parsedLineItems = [];
    if (rawLineItems != null) {
      for (final item in rawLineItems) {
        if (item is Map<String, dynamic>) {
          parsedLineItems.add(BillLineItem.fromJson(item));
        }
      }
    }

    final rawPayments = json['payments'] as List<dynamic>?;
    final List<Payment> parsedPayments = [];
    if (rawPayments != null) {
      for (final item in rawPayments) {
        if (item is Map<String, dynamic>) {
          parsedPayments.add(Payment.fromJson(item));
        }
      }
    }

    return Bill(
      id: json['id']?.toString() ?? '',
      propertyId: json['property_id']?.toString() ?? '',
      stayId: json['stay_id']?.toString() ?? '',
      billNumber: json['bill_number']?.toString() ?? 'INV-001',
      subtotal: (json['subtotal'] is num) ? (json['subtotal'] as num).toDouble() : (double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0.0),
      amountPaid: (json['amount_paid'] is num) ? (json['amount_paid'] as num).toDouble() : (double.tryParse(json['amount_paid']?.toString() ?? '0') ?? 0.0),
      outstanding: (json['outstanding'] is num) ? (json['outstanding'] as num).toDouble() : (double.tryParse(json['outstanding']?.toString() ?? '0') ?? 0.0),
      status: json['status']?.toString() ?? 'draft',
      lineItems: parsedLineItems,
      payments: parsedPayments,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }
}
