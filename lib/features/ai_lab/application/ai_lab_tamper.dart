import '../../invoices/domain/invoice_models.dart';

/// AI Lab (debug, demo scene 6): simulates an OCR error by raising the total
/// of [invoice] by 10% (rounded to whole đồng, at least +1). The evidence is
/// left untouched, so only the arithmetic validator can notice the mismatch.
InvoiceEntity tamperInvoiceTotal(InvoiceEntity invoice) {
  final total = invoice.totalMinor;
  final raised = (total * 11 + 5) ~/ 10;
  return invoice.copyWith(totalMinor: raised > total ? raised : total + 1);
}
