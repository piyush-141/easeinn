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
}

class Payment {
  final String id;
  final double amount;
  final String method; // 'cash', 'upi', 'card'
  final String paymentType; // 'advance', 'full'
  final String? reference;
  final DateTime recordedAt;

  Payment({
    required this.id,
    required this.amount,
    required this.method,
    required this.paymentType,
    this.reference,
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();
}

class Bill {
  final String id;
  final String stayId;
  final String billNumber;
  double subtotal;
  double amountPaid;
  double outstanding;
  String status; // 'draft', 'finalized'
  final List<BillLineItem> lineItems;
  final List<Payment> payments;
  final DateTime createdAt;

  Bill({
    required this.id,
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
}
