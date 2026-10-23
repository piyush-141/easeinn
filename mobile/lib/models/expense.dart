class Expense {
  final String id;
  final String propertyId;
  final double amount;
  final String category; // 'supplies', 'maintenance', 'salary', 'utilities', 'food', 'other'
  final String paymentMethod; // 'cash', 'upi', 'card', 'bank_transfer'
  final String? reference;
  final String? notes;
  final String addedBy;
  final DateTime recordedAt;

  static const List<String> categories = [
    'Supplies',
    'Maintenance',
    'Salary',
    'Utilities',
    'Food & Beverage',
    'Housekeeping',
    'Marketing',
    'Other',
  ];

  static String categoryDbValue(String label) =>
      label.toLowerCase().replaceAll(' & ', '_').replaceAll(' ', '_');

  static String categoryLabel(String dbValue) {
    final map = {
      'supplies': 'Supplies',
      'maintenance': 'Maintenance',
      'salary': 'Salary',
      'utilities': 'Utilities',
      'food_beverage': 'Food & Beverage',
      'housekeeping': 'Housekeeping',
      'marketing': 'Marketing',
      'other': 'Other',
    };
    return map[dbValue] ?? dbValue;
  }

  Expense({
    required this.id,
    required this.propertyId,
    required this.amount,
    required this.category,
    required this.paymentMethod,
    this.reference,
    this.notes,
    this.addedBy = '',
    DateTime? recordedAt,
  }) : recordedAt = recordedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'property_id': propertyId,
        'amount': amount,
        'category': category,
        'payment_method': paymentMethod,
        'reference': reference,
        'notes': notes,
        'added_by': addedBy,
        'recorded_at': recordedAt.toIso8601String(),
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id']?.toString() ?? '',
        propertyId: json['property_id']?.toString() ?? '',
        amount: (json['amount'] is num)
            ? (json['amount'] as num).toDouble()
            : (double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0),
        category: json['category']?.toString() ?? 'other',
        paymentMethod: json['payment_method']?.toString() ?? 'cash',
        reference: json['reference']?.toString(),
        notes: json['notes']?.toString(),
        addedBy: json['added_by']?.toString() ?? '',
        recordedAt: json['recorded_at'] != null
            ? DateTime.tryParse(json['recorded_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}
