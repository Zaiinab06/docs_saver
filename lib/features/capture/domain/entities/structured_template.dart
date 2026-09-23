import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Supported structured template types
class TemplateTypes {
  static const String bankCard = 'bank_card';
  static const String bill = 'bill';
}

/// Domain model for Bank Card Template
class BankCardTemplate extends Equatable {
  final String cardholderName;
  final String cardNumber;
  final String bankName;
  final String cardType;
  final String expiryDate;
  final String? notes;

  const BankCardTemplate({
    required this.cardholderName,
    required this.cardNumber,
    required this.bankName,
    required this.cardType,
    required this.expiryDate,
    this.notes,
  });

  /// Formats raw digits with space every 4 digits: "1234 5678 9012 3456"
  static String formatCardNumber(String raw) {
    final clean = raw.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(clean[i]);
    }
    return buffer.toString();
  }

  /// Masks card number showing only last 4 digits: "•••• •••• •••• 3456"
  static String maskCardNumber(String formatted) {
    final clean = formatted.replaceAll(RegExp(r'\s'), '');
    if (clean.length <= 4) return formatted;
    final visible = clean.substring(clean.length - 4);
    final maskedLength = clean.length - 4;
    final masked = List.filled(maskedLength, '•').join();
    final full = '$masked$visible';
    final buffer = StringBuffer();
    for (int i = 0; i < full.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(full[i]);
    }
    return buffer.toString();
  }

  String get maskedCardNumber => maskCardNumber(cardNumber);

  String get last4 {
    final clean = cardNumber.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 4) return clean;
    return clean.substring(clean.length - 4);
  }

  String toMarkdownBody() {
    final buffer = StringBuffer();
    buffer.writeln('🏦 Bank: $bankName');
    buffer.writeln('💳 Card Type: $cardType');
    buffer.writeln('👤 Cardholder: $cardholderName');
    buffer.writeln('🔢 Card Number: $maskedCardNumber');
    buffer.writeln('📅 Expiry: $expiryDate');
    if (notes != null && notes!.trim().isNotEmpty) {
      buffer.writeln('📝 Notes: ${notes!.trim()}');
    }
    return buffer.toString().trim();
  }

  Map<String, dynamic> toJson() => {
    'template': TemplateTypes.bankCard,
    'cardholder_name': cardholderName,
    'card_number': maskedCardNumber,
    'bank_name': bankName,
    'card_type': cardType,
    'expiry_date': expiryDate,
    'notes': notes ?? '',
  };

  String toSerializedContent() {
    final body = toMarkdownBody();
    final jsonStr = jsonEncode(toJson());
    return '$body\n\n<!--template_metadata:$jsonStr-->';
  }

  factory BankCardTemplate.fromJson(Map<String, dynamic> json) {
    return BankCardTemplate(
      cardholderName: (json['cardholder_name'] ?? '').toString(),
      cardNumber: (json['card_number'] ?? '').toString(),
      bankName: (json['bank_name'] ?? '').toString(),
      cardType: (json['card_type'] ?? 'Visa').toString(),
      expiryDate: (json['expiry_date'] ?? '').toString(),
      notes: json['notes']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    cardholderName,
    cardNumber,
    bankName,
    cardType,
    expiryDate,
    notes,
  ];
}

/// Domain model for Utility & Financial Bill Template
class BillTemplate extends Equatable {
  final String billType;
  final String consumerNumber;
  final String amount;
  final String dueDate;
  final bool isPaid;
  final String? notes;

  const BillTemplate({
    required this.billType,
    required this.consumerNumber,
    required this.amount,
    required this.dueDate,
    this.isPaid = false,
    this.notes,
  });

  BillTemplate copyWith({
    String? billType,
    String? consumerNumber,
    String? amount,
    String? dueDate,
    bool? isPaid,
    String? notes,
  }) {
    return BillTemplate(
      billType: billType ?? this.billType,
      consumerNumber: consumerNumber ?? this.consumerNumber,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      isPaid: isPaid ?? this.isPaid,
      notes: notes ?? this.notes,
    );
  }

  String toMarkdownBody() {
    final buffer = StringBuffer();
    buffer.writeln('📄 Bill Type: $billType');
    buffer.writeln('🏢 Consumer / Ref #: $consumerNumber');
    buffer.writeln('💰 Amount: $amount');
    buffer.writeln('📅 Due Date: $dueDate');
    buffer.writeln('📌 Status: ${isPaid ? "Paid ✅" : "Unpaid ⏳"}');
    if (notes != null && notes!.trim().isNotEmpty) {
      buffer.writeln('📝 Notes: ${notes!.trim()}');
    }
    return buffer.toString().trim();
  }

  Map<String, dynamic> toJson() => {
    'template': TemplateTypes.bill,
    'bill_type': billType,
    'consumer_number': consumerNumber,
    'amount': amount,
    'due_date': dueDate,
    'is_paid': isPaid,
    'notes': notes ?? '',
  };

  String toSerializedContent() {
    final body = toMarkdownBody();
    final jsonStr = jsonEncode(toJson());
    return '$body\n\n<!--template_metadata:$jsonStr-->';
  }

  factory BillTemplate.fromJson(Map<String, dynamic> json) {
    return BillTemplate(
      billType: (json['bill_type'] ?? 'Electricity').toString(),
      consumerNumber: (json['consumer_number'] ?? '').toString(),
      amount: (json['amount'] ?? '').toString(),
      dueDate: (json['due_date'] ?? '').toString(),
      isPaid: json['is_paid'] as bool? ?? false,
      notes: json['notes']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    billType,
    consumerNumber,
    amount,
    dueDate,
    isPaid,
    notes,
  ];
}
