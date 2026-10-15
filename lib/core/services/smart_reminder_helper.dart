import 'package:intl/intl.dart';

class SmartReminderResult {
  final DateTime? dueDateTime;
  final DateTime? reminderDateTime;
  final String? reminderType; // 'bill', 'meeting', 'custom'

  const SmartReminderResult({
    this.dueDateTime,
    this.reminderDateTime,
    this.reminderType,
  });

  bool get hasReminder => dueDateTime != null && reminderDateTime != null;
}

class SmartReminderHelper {
  /// Calculates a default reminder DateTime based on the due date and reminder type.
  /// - Bill: 2 days before due date at 9:00 AM
  /// - Meeting: 1 hour before scheduled time
  /// - Custom/Expiry: 2 days before at 9:00 AM
  static DateTime calculateDefaultReminderDate({
    required DateTime dueDateTime,
    required String reminderType,
  }) {
    final now = DateTime.now();

    if (reminderType == 'meeting') {
      final oneHourBefore = dueDateTime.subtract(const Duration(hours: 1));
      if (oneHourBefore.isAfter(now)) {
        return oneHourBefore;
      }
      final fifteenMinBefore = dueDateTime.subtract(const Duration(minutes: 15));
      if (fifteenMinBefore.isAfter(now)) {
        return fifteenMinBefore;
      }
      return now.add(const Duration(minutes: 10));
    }

    // Bill or Custom / Expiry: default 2 days before due date at 9:00 AM
    final targetDate = DateTime(
      dueDateTime.year,
      dueDateTime.month,
      dueDateTime.day,
      9,
      0,
    );
    final twoDaysBefore = targetDate.subtract(const Duration(days: 2));

    if (twoDaysBefore.isAfter(now)) {
      return twoDaysBefore;
    }

    final oneDayBefore = targetDate.subtract(const Duration(days: 1));
    if (oneDayBefore.isAfter(now)) {
      return oneDayBefore;
    }

    if (dueDateTime.isAfter(now)) {
      // Due today or tomorrow, set for earlier today or in 1 hour
      if (now.hour < 9) {
        return DateTime(now.year, now.month, now.day, 9, 0);
      }
      return now.add(const Duration(hours: 1));
    }

    return targetDate;
  }

  /// Parses date string from AI output or text.
  /// Handles ISO-8601, 'YYYY-MM-DD', 'MM/DD/YYYY', 'DD/MM/YYYY', and common time formats.
  static DateTime? parseFlexibleDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final clean = raw.trim();

    // 1. Try standard DateTime.tryParse (handles ISO-8601 YYYY-MM-DD, YYYY-MM-DDTHH:mm:ss, etc.)
    final isoParsed = DateTime.tryParse(clean);
    if (isoParsed != null) return isoParsed;

    // 2. Try common DateFormat patterns
    final formats = [
      'yyyy-MM-dd HH:mm',
      'yyyy/MM/dd HH:mm',
      'MM/dd/yyyy HH:mm',
      'dd/MM/yyyy HH:mm',
      'MM/dd/yyyy',
      'dd/MM/yyyy',
      'yyyy/MM/dd',
      'MMM dd, yyyy',
      'MMMM dd, yyyy',
      'dd MMM yyyy',
      'dd MMMM yyyy',
      'MM/yy',
      'MM/yyyy',
    ];

    for (final fmt in formats) {
      try {
        final parsed = DateFormat(fmt).parseLoose(clean);
        return parsed;
      } catch (_) {}
    }

    return null;
  }

  /// Extracts smart reminder info from structured metadata, AI data, or text content.
  static SmartReminderResult extractSmartReminder({
    dynamic aiDueDate,
    dynamic aiReminderType,
    String? content,
    String? category,
    List<String> tags = const [],
    Map<String, dynamic>? metadata,
    dynamic dueDateStr,
    dynamic reminderTypeStr,
    String? text,
  }) {
    aiDueDate ??= dueDateStr;
    aiReminderType ??= reminderTypeStr;
    content ??= text;

    DateTime? dueDateTime;
    String? reminderType;

    // 1. Check metadata (e.g. BillTemplate or BankCardTemplate)
    if (metadata != null) {
      if (metadata['due_date'] != null) {
        dueDateTime = parseFlexibleDate(metadata['due_date'].toString());
        reminderType = 'bill';
      } else if (metadata['expiry_date'] != null) {
        dueDateTime = parseFlexibleDate(metadata['expiry_date'].toString());
        reminderType = 'custom';
      }
    }

    // 2. Check AI output fields
    if (dueDateTime == null && aiDueDate != null) {
      dueDateTime = parseFlexibleDate(aiDueDate.toString());
    }

    // Determine / refine reminder type
    if (aiReminderType != null && aiReminderType.toString().trim().isNotEmpty) {
      final t = aiReminderType.toString().trim().toLowerCase();
      if (t == 'bill' || t == 'meeting' || t == 'custom') {
        reminderType = t;
      }
    }

    final lowerContent = (content ?? '').toLowerCase();
    final lowerCat = (category ?? '').toLowerCase();
    final isBillCandidate = lowerCat.contains('finance') ||
        tags.any((t) => t.toLowerCase() == 'bill' || t.toLowerCase() == 'invoice') ||
        lowerContent.contains('bill') ||
        lowerContent.contains('invoice') ||
        lowerContent.contains('due date') ||
        lowerContent.contains('amount due') ||
        lowerContent.contains('utility');

    final isMeetingCandidate = lowerCat.contains('work') ||
        tags.any((t) => t.toLowerCase() == 'meeting' || t.toLowerCase() == 'calendar') ||
        lowerContent.contains('meeting') ||
        lowerContent.contains('zoom') ||
        lowerContent.contains('call scheduled') ||
        lowerContent.contains('appointment');

    if (reminderType == null) {
      if (isBillCandidate) {
        reminderType = 'bill';
      } else if (isMeetingCandidate) {
        reminderType = 'meeting';
      } else if (dueDateTime != null) {
        reminderType = 'custom';
      }
    }

    // 3. Fallback regex extraction from content if due date wasn't directly supplied
    if (dueDateTime == null && content != null && content.isNotEmpty) {
      // Look for "due: YYYY-MM-DD", "due date: ...", "expiry: ...", "date: ..."
      final dueMatch = RegExp(
        r'(?:due(?:\s+date)?|payment\s+due(?:\s+by)?|expires?|expiry(?:\s+date)?|date|scheduled\s+for)[:\s]+([0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{2,4})',
        caseSensitive: false,
      ).firstMatch(content);

      if (dueMatch != null && dueMatch.group(1) != null) {
        dueDateTime = parseFlexibleDate(dueMatch.group(1)!);
        if (dueDateTime != null && reminderType == null) {
          reminderType = isBillCandidate ? 'bill' : 'custom';
        }
      }
    }

    if (dueDateTime != null && reminderType != null) {
      final reminderDate = calculateDefaultReminderDate(
        dueDateTime: dueDateTime,
        reminderType: reminderType,
      );
      return SmartReminderResult(
        dueDateTime: dueDateTime,
        reminderDateTime: reminderDate,
        reminderType: reminderType,
      );
    }

    return const SmartReminderResult();
  }
}
