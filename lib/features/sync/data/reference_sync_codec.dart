import '../../invoices/domain/invoice_models.dart';

abstract final class ReferenceSyncCodec {
  static CategoryEntity categoryFromPayload(Map<String, dynamic> payload) {
    return CategoryEntity(
      id: _requiredString(payload['id']),
      name: _string(payload['name']) ?? '',
      iconName: _string(payload['iconName']) ?? 'category',
      colorValue: _int(payload['colorValue']),
      isSystem: payload['isSystem'] == true,
    );
  }

  static BudgetEntity budgetFromPayload(Map<String, dynamic> payload) {
    return BudgetEntity(
      id: _requiredString(payload['id']),
      monthKey: _requiredString(payload['monthKey']),
      categoryId: _requiredString(payload['categoryId']),
      limitMinor: _int(payload['limitMinor']),
    );
  }

  static MerchantRuleEntity merchantRuleFromPayload(
    Map<String, dynamic> payload,
  ) {
    final normalized = _requiredString(
      payload['normalizedMerchant'] ?? payload['id'],
    );
    return MerchantRuleEntity(
      normalizedMerchant: normalized,
      categoryId: _requiredString(payload['categoryId']),
      updatedAt: DateTime.tryParse('${payload['updatedAt']}') ?? DateTime.now(),
    );
  }

  static String _requiredString(Object? value) {
    final result = _string(value);
    if (result == null || result.isEmpty) {
      throw const FormatException('Reference delta thiếu id.');
    }
    return result;
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final result = '$value';
    return result.isEmpty ? null : result;
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
