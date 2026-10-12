import 'dart:math' as math;

import 'package:flutter/foundation.dart';

const maxPlanMoney = 9007199254740991;

enum BillFrequency { weekly, monthly, yearly }

@immutable
sealed class PlanItem {
  const PlanItem({required this.id, required this.updatedAt});

  final String id;
  final DateTime updatedAt;

  String get kind;
  Map<String, Object?> toPayload();

  static PlanItem fromPayload(Map<String, dynamic> payload) {
    final id = _string(payload['id'], 'Mã kế hoạch', 128);
    final updatedAt = _timestamp(payload['updatedAt'], 'Ngày cập nhật');
    return switch (payload['kind']) {
      'bill' => RecurringBill(
        id: id,
        title: _string(payload['title'], 'Tên khoản định kỳ', 120),
        amountMinor: _money(payload['amountMinor'], 'Số tiền', positive: true),
        frequency: _frequency(payload['frequency']),
        anchorDate: _date(payload['anchorDate'], 'Ngày bắt đầu'),
        nextDueDate: _date(payload['nextDueDate'], 'Ngày đến hạn'),
        categoryId: _optionalString(payload['categoryId'], 128),
        updatedAt: updatedAt,
      ),
      'income' => RecurringIncome(
        id: id,
        title: _string(payload['title'], 'Tên khoản thu', 120),
        amountMinor: _money(payload['amountMinor'], 'Số tiền', positive: true),
        categoryId: _string(payload['categoryId'], 'Danh mục thu', 128),
        anchorDate: _date(payload['anchorDate'], 'Ngày bắt đầu'),
        nextDueDate: _date(payload['nextDueDate'], 'Ngày nhận tiếp theo'),
        updatedAt: updatedAt,
      ),
      'goal' => SavingsGoal(
        id: id,
        name: _string(payload['name'], 'Tên mục tiêu', 120),
        targetMinor: _money(
          payload['targetMinor'],
          'Số tiền mục tiêu',
          positive: true,
        ),
        savedMinor: _money(payload['savedMinor'], 'Đã để dành'),
        targetDate: _date(payload['targetDate'], 'Ngày hoàn thành'),
        updatedAt: updatedAt,
      ),
      _ => throw const FormatException('Loại kế hoạch không hợp lệ.'),
    };
  }
}

@immutable
class RecurringBill extends PlanItem {
  const RecurringBill({
    required super.id,
    required super.updatedAt,
    required this.title,
    required this.amountMinor,
    required this.frequency,
    required this.anchorDate,
    required this.nextDueDate,
    this.categoryId,
  });

  final String title;
  final int amountMinor;
  final BillFrequency frequency;
  final DateTime anchorDate;
  final DateTime nextDueDate;
  final String? categoryId;

  @override
  String get kind => 'bill';

  @override
  Map<String, Object?> toPayload() => {
    'id': id,
    'kind': kind,
    'title': title,
    'amountMinor': amountMinor,
    'frequency': frequency.name,
    'anchorDate': _dateKey(anchorDate),
    'nextDueDate': _dateKey(nextDueDate),
    'categoryId': categoryId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  RecurringBill copyWith({
    String? title,
    int? amountMinor,
    BillFrequency? frequency,
    DateTime? anchorDate,
    DateTime? nextDueDate,
    String? categoryId,
    bool clearCategory = false,
    DateTime? updatedAt,
  }) => RecurringBill(
    id: id,
    title: title ?? this.title,
    amountMinor: amountMinor ?? this.amountMinor,
    frequency: frequency ?? this.frequency,
    anchorDate: anchorDate ?? this.anchorDate,
    nextDueDate: nextDueDate ?? this.nextDueDate,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  DateTime get followingDueDate => switch (frequency) {
    BillFrequency.weekly => DateTime(
      nextDueDate.year,
      nextDueDate.month,
      nextDueDate.day + 7,
    ),
    BillFrequency.monthly => _clampedDate(
      nextDueDate.year,
      nextDueDate.month + 1,
      anchorDate.day,
    ),
    BillFrequency.yearly => _clampedDate(
      nextDueDate.year + 1,
      anchorDate.month,
      anchorDate.day,
    ),
  };
}

@immutable
class RecurringIncome extends PlanItem {
  const RecurringIncome({
    required super.id,
    required super.updatedAt,
    required this.title,
    required this.amountMinor,
    required this.categoryId,
    required this.anchorDate,
    required this.nextDueDate,
  });

  final String title;
  final int amountMinor;
  final String categoryId;
  final DateTime anchorDate;
  final DateTime nextDueDate;

  @override
  String get kind => 'income';

  @override
  Map<String, Object?> toPayload() => {
    'id': id,
    'kind': kind,
    'title': title,
    'amountMinor': amountMinor,
    'categoryId': categoryId,
    'anchorDate': _dateKey(anchorDate),
    'nextDueDate': _dateKey(nextDueDate),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  RecurringIncome copyWith({
    String? title,
    int? amountMinor,
    String? categoryId,
    DateTime? anchorDate,
    DateTime? nextDueDate,
    DateTime? updatedAt,
  }) => RecurringIncome(
    id: id,
    title: title ?? this.title,
    amountMinor: amountMinor ?? this.amountMinor,
    categoryId: categoryId ?? this.categoryId,
    anchorDate: anchorDate ?? this.anchorDate,
    nextDueDate: nextDueDate ?? this.nextDueDate,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  DateTime get followingDueDate =>
      _clampedDate(nextDueDate.year, nextDueDate.month + 1, anchorDate.day);
}

@immutable
class SavingsGoal extends PlanItem {
  const SavingsGoal({
    required super.id,
    required super.updatedAt,
    required this.name,
    required this.targetMinor,
    required this.savedMinor,
    required this.targetDate,
  });

  final String name;
  final int targetMinor;
  final int savedMinor;
  final DateTime targetDate;

  int get remainingMinor => math.max(0, targetMinor - savedMinor);
  double get progress => targetMinor == 0 ? 0 : savedMinor / targetMinor;

  int monthlyNeeded(DateTime now) {
    if (remainingMinor == 0) return 0;
    final months =
        (targetDate.year - now.year) * 12 + targetDate.month - now.month + 1;
    if (months <= 0) return remainingMinor;
    return (remainingMinor / months).ceil();
  }

  @override
  String get kind => 'goal';

  @override
  Map<String, Object?> toPayload() => {
    'id': id,
    'kind': kind,
    'name': name,
    'targetMinor': targetMinor,
    'savedMinor': savedMinor,
    'targetDate': _dateKey(targetDate),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  SavingsGoal copyWith({
    String? name,
    int? targetMinor,
    int? savedMinor,
    DateTime? targetDate,
    DateTime? updatedAt,
  }) => SavingsGoal(
    id: id,
    name: name ?? this.name,
    targetMinor: targetMinor ?? this.targetMinor,
    savedMinor: savedMinor ?? this.savedMinor,
    targetDate: targetDate ?? this.targetDate,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

DateTime _clampedDate(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min(day, lastDay));
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _string(Object? value, String field, int maxLength) {
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('$field không hợp lệ.');
  }
  return value.trim();
}

String? _optionalString(Object? value, int maxLength) {
  if (value == null) return null;
  return _string(value, 'Danh mục', maxLength);
}

int _money(Object? value, String field, {bool positive = false}) {
  if (value is! int || value < (positive ? 1 : 0) || value > maxPlanMoney) {
    throw FormatException('$field không hợp lệ.');
  }
  return value;
}

DateTime _date(Object? value, String field) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('$field không hợp lệ.');
  }
  final date = DateTime.tryParse(value);
  if (date == null || _dateKey(date) != value) {
    throw FormatException('$field không hợp lệ.');
  }
  return date;
}

DateTime _timestamp(Object? value, String field) {
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) throw FormatException('$field không hợp lệ.');
  return date.toLocal();
}

BillFrequency _frequency(Object? value) {
  for (final frequency in BillFrequency.values) {
    if (frequency.name == value) return frequency;
  }
  throw const FormatException('Chu kỳ khoản định kỳ không hợp lệ.');
}
