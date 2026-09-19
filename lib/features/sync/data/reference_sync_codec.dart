import '../../invoices/domain/invoice_models.dart';

abstract final class ReferenceSyncCodec {
  static const _maxSafeInteger = 9007199254740991;
  static final _monthPattern = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  static CategoryEntity categoryFromPayload(Map<String, dynamic> payload) {
    return CategoryEntity(
      id: _requiredString(payload['id'], 'category.id', 128),
      name: _requiredString(payload['name'], 'category.name', 80),
      iconName: _requiredString(payload['iconName'], 'category.iconName', 64),
      colorValue: _integer(payload['colorValue'], 'category.colorValue'),
      isSystem: _optionalBool(payload['isSystem'], 'category.isSystem'),
    );
  }

  static BudgetEntity budgetFromPayload(Map<String, dynamic> payload) {
    final monthKey = _requiredString(payload['monthKey'], 'budget.monthKey', 7);
    if (!_monthPattern.hasMatch(monthKey)) {
      throw const FormatException('budget.monthKey không hợp lệ.');
    }
    return BudgetEntity(
      id: _requiredString(payload['id'], 'budget.id', 128),
      monthKey: monthKey,
      categoryId: _requiredString(
        payload['categoryId'],
        'budget.categoryId',
        128,
      ),
      limitMinor: _nonNegativeInteger(
        payload['limitMinor'],
        'budget.limitMinor',
      ),
    );
  }

  static MerchantRuleEntity merchantRuleFromPayload(
    Map<String, dynamic> payload,
  ) {
    final normalizedMerchant = _requiredString(
      payload['normalizedMerchant'] ?? payload['id'],
      'merchantRule.normalizedMerchant',
      300,
    );
    return MerchantRuleEntity(
      normalizedMerchant: normalizedMerchant,
      categoryId: _requiredString(
        payload['categoryId'],
        'merchantRule.categoryId',
        128,
      ),
      updatedAt: _requiredDate(payload['updatedAt'], 'merchantRule.updatedAt'),
    );
  }

  static String _requiredString(Object? value, String field, int maxLength) {
    if (value is! String || value.length > maxLength || value.trim().isEmpty) {
      throw FormatException('$field không hợp lệ.');
    }
    return value;
  }

  static int _nonNegativeInteger(Object? value, String field) {
    final result = _integer(value, field);
    if (result < 0) {
      throw FormatException('$field không được âm.');
    }
    return result;
  }

  static int _integer(Object? value, String field) {
    if (value is! num || !value.toDouble().isFinite) {
      throw FormatException('$field không phải số nguyên.');
    }
    if (value < 0 || value > _maxSafeInteger || value != value.truncate()) {
      throw FormatException('$field không phải số nguyên hợp lệ.');
    }
    return value.toInt();
  }

  static bool _optionalBool(Object? value, String field) {
    if (value == null) return false;
    if (value is! bool) {
      throw FormatException('$field không hợp lệ.');
    }
    return value;
  }

  static DateTime _requiredDate(Object? value, String field) {
    if (value is! String) {
      throw FormatException('$field không hợp lệ.');
    }
    final result = DateTime.tryParse(value);
    if (result == null) {
      throw FormatException('$field không hợp lệ.');
    }
    return result.toLocal();
  }
}
