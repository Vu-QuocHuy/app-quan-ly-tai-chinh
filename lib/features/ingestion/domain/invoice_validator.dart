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

  InvoiceValidationResult validate(InvoiceEntity invoice) {
    final errors = <String>[];
    final warnings = <String>[];
    if (invoice.sellerName.trim().isEmpty) {
      errors.add('Thiếu tên người bán.');
    }
    if (invoice.totalMinor <= 0) {
      errors.add('Tổng tiền phải lớn hơn 0.');
    }
    final computed = invoice.subtotalMinor + invoice.taxMinor;
    if (invoice.subtotalMinor > 0 &&
        (computed - invoice.totalMinor).abs() >
            AppConstants.moneyToleranceMinor) {
      warnings.add('Tổng trước thuế và thuế chưa khớp với tổng thanh toán.');
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
    if (invoice.invoiceNumber == null || invoice.invoiceNumber!.isEmpty) {
      warnings.add('Không tìm thấy số hóa đơn.');
    }
    if (invoice.issuedAt == null) {
      warnings.add('Không tìm thấy ngày lập hóa đơn.');
    }
    if (invoice.evidence.any((item) => item.confidence < 0.75)) {
      warnings.add('Có trường dữ liệu có độ tin cậy thấp.');
    }
    return InvoiceValidationResult(errors, warnings);
  }
}
