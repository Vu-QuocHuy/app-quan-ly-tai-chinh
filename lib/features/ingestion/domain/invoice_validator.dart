import '../../../core/constants/app_constants.dart';
import '../../invoices/domain/invoice_models.dart';

class InvoiceValidationResult {
  const InvoiceValidationResult(this.errors, this.warnings);

  final List<String> errors;
  final List<String> warnings;

  bool get isValid => errors.isEmpty;
  bool get requiresReview => errors.isNotEmpty || warnings.isNotEmpty;
}

class InvoiceValidator {
  const InvoiceValidator();

  /// Confidence assigned to a field once a deterministic arithmetic or date
  /// check contradicts it. Below the review screen's 0.75 highlight threshold.
  static const ruleFailedConfidence = 0.5;

  /// Replaces the model's fixed confidence with rule-based evidence: if line
  /// items, subtotal, tax and discount do not reconcile with the total, the
  /// `totalMinor` evidence is downgraded so the review screen highlights it.
  InvoiceEntity applyRuleConfidence(InvoiceEntity invoice) {
    if (invoice.evidence.isEmpty || !_totalsMismatch(invoice)) return invoice;
    return invoice.copyWith(
      evidence: [
        for (final item in invoice.evidence)
          item.fieldName == 'totalMinor' &&
                  item.confidence > ruleFailedConfidence
              ? FieldEvidenceEntity(
                  id: item.id,
                  fieldName: item.fieldName,
                  rawValue: item.rawValue,
                  normalizedValue: item.normalizedValue,
                  source: item.source,
                  confidence: ruleFailedConfidence,
                  correctedByUser: item.correctedByUser,
                )
              : item,
      ],
    );
  }

  bool _totalsMismatch(InvoiceEntity invoice) {
    const tolerance = AppConstants.moneyToleranceMinor;
    final computed =
        invoice.subtotalMinor + invoice.taxMinor - invoice.discountMinor;
    if (invoice.subtotalMinor > 0 &&
        (computed - invoice.totalMinor).abs() > tolerance) {
      return true;
    }
    if (invoice.lines.isEmpty) return false;
    final lineTotal = invoice.lines.fold<int>(
      0,
      (sum, line) => sum + line.totalMinor,
    );
    final expected = invoice.subtotalMinor > 0
        ? invoice.subtotalMinor
        : invoice.totalMinor - invoice.taxMinor + invoice.discountMinor;
    return (lineTotal - expected).abs() > tolerance;
  }

  InvoiceValidationResult validate(InvoiceEntity invoice) {
    final errors = <String>[];
    final warnings = <String>[];
    if (invoice.sellerName.trim().isEmpty) {
      errors.add('Thiếu tên người bán.');
    }
    if (invoice.totalMinor <= 0) {
      errors.add('Tổng tiền phải lớn hơn 0.');
    }
    if (invoice.discountMinor < 0) {
      errors.add('Số tiền giảm giá không hợp lệ.');
    }
    final computed =
        invoice.subtotalMinor + invoice.taxMinor - invoice.discountMinor;
    if (invoice.subtotalMinor > 0 &&
        (computed - invoice.totalMinor).abs() >
            AppConstants.moneyToleranceMinor) {
      warnings.add(
        invoice.discountMinor > 0
            ? 'Tiền trước thuế, thuế và giảm giá chưa khớp với tổng thanh toán.'
            : 'Tổng trước thuế và thuế chưa khớp với tổng thanh toán.',
      );
    }
    if (invoice.lines.isNotEmpty) {
      final lineTotal = invoice.lines.fold<int>(
        0,
        (sum, line) => sum + line.totalMinor,
      );
      if ((lineTotal - invoice.subtotalMinor).abs() >
          AppConstants.moneyToleranceMinor) {
        warnings.add('Tổng các dòng hàng chưa khớp với tiền trước thuế.');
      }
    }
    if (invoice.issuedAt == null) {
      warnings.add('Không tìm thấy ngày lập hóa đơn.');
    } else {
      final today = DateTime.now();
      final issued = invoice.issuedAt!;
      if (DateTime(
        issued.year,
        issued.month,
        issued.day,
      ).isAfter(DateTime(today.year, today.month, today.day))) {
        warnings.add('Ngày lập hóa đơn nằm trong tương lai.');
      }
    }
    if (invoice.evidence.any((item) => item.confidence < 0.75)) {
      warnings.add('Có trường dữ liệu có độ tin cậy thấp.');
    }
    return InvoiceValidationResult(errors, warnings);
  }
}
