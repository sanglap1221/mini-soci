import 'package:cloud_firestore/cloud_firestore.dart';

String? formatTimestamp(dynamic timestamp) {
  DateTime? dateTime;
  if (timestamp is Timestamp) {
    dateTime = timestamp.toDate();
  } else if (timestamp is DateTime) {
    dateTime = timestamp;
  } else if (timestamp is int) {
    dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
  } else if (timestamp is String) {
    dateTime = DateTime.tryParse(timestamp);
  }

  if (dateTime == null) return null;

  dateTime = dateTime.toLocal();
  final now = DateTime.now();
  final isSameDay =
      dateTime.year == now.year &&
      dateTime.month == now.month &&
      dateTime.day == now.day;

  if (isSameDay) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  final rawDifference = now.difference(dateTime);
  final difference = rawDifference.isNegative ? Duration.zero : rawDifference;

  if (difference.inDays < 7) {
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdayNames[dateTime.weekday - 1];
  }

  final day = dateTime.day.toString().padLeft(2, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final yearSuffix = dateTime.year == now.year
      ? ''
      : '/${dateTime.year.toString().substring(2)}';
  return '$day/$month$yearSuffix';
}
