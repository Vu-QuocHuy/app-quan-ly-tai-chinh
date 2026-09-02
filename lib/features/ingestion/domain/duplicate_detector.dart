import '../../invoices/domain/invoice_models.dart';

class DuplicateMatch {
  const DuplicateMatch({
    required this.invoiceId,
    required this.score,
    required this.reasons,
  });

  final String invoiceId;
  final double score;
  final List<String> reasons;
}

class DuplicateDetector {
  const DuplicateDetector();

  DuplicateMatch? findLikelyDuplicate(
    InvoiceEntity candidate,
    Iterable<InvoiceEntity> existing,
  ) {
    DuplicateMatch? best;
    for (final invoice in existing) {
      final reasons = <String>[];
      var score = 0.0;
      if (candidate.sourceHash != null &&
          candidate.sourceHash == invoice.sourceHash) {
        return DuplicateMatch(
          invoiceId: invoice.id,
          score: 1,
          reasons: const ['File có cùng fingerprint'],
        );
      }
      if (_sameNonEmpty(candidate.sellerTaxCode, invoice.sellerTaxCode)) {
        score += 0.25;
        reasons.add('Cùng mã số thuế');
      }
      if (_sameNonEmpty(candidate.invoiceNumber, invoice.invoiceNumber)) {
        score += 0.35;
        reasons.add('Cùng số hóa đơn');
      }
      if (candidate.totalMinor == invoice.totalMinor) {
        score += 0.2;
        reasons.add('Cùng tổng tiền');
      }
      final candidateDate = candidate.issuedAt;
      final existingDate = invoice.issuedAt;
      if (candidateDate != null &&
          existingDate != null &&
          candidateDate.year == existingDate.year &&
          candidateDate.month == existingDate.month &&
          candidateDate.day == existingDate.day) {
        score += 0.2;
        reasons.add('Cùng ngày lập');
      }
      if (score >= 0.7 && (best == null || score > best.score)) {
        best = DuplicateMatch(
          invoiceId: invoice.id,
          score: score,
          reasons: reasons,
        );
      }
    }
    return best;
  }

  bool _sameNonEmpty(String? left, String? right) =>
      left != null && left.isNotEmpty && right != null && left == right;
}
