import '../../invoices/domain/invoice_models.dart';
import '../../invoices/domain/invoice_repository.dart';
import '../data/drift_sync_cursor_store.dart';
import '../data/invoice_sync_codec.dart';
import '../data/reference_sync_codec.dart';
import '../domain/sync_gateway.dart';
import '../domain/sync_models.dart';

class SyncPullCoordinator {
  const SyncPullCoordinator({
    required InvoiceRepository repository,
    required DriftSyncCursorStore cursors,
    required SyncPullGateway gateway,
    this.aggregateType = 'invoice',
  }) : _repository = repository,
       _cursors = cursors,
       _gateway = gateway;

  final InvoiceRepository _repository;
  final DriftSyncCursorStore _cursors;
  final SyncPullGateway _gateway;
  final String aggregateType;

  Future<SyncPullResult> runOnce({
    required String userId,
    int batchSize = 50,
    int maxPages = 10,
  }) async {
    var cursor = await _cursors.read(
      userId: userId,
      aggregateType: aggregateType,
    );
    var applied = 0;
    var skipped = 0;
    var conflicts = 0;
    var hasMore = false;

    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      final page = await _gateway.pull(
        userId: userId,
        aggregateType: aggregateType,
        cursor: cursor,
        limit: batchSize,
      );
      hasMore = page.hasMore;
      if (page.changes.isEmpty) {
        hasMore = false;
        break;
      }

      for (final change in page.changes) {
        if (aggregateType == 'invoice') {
          final incoming = InvoiceSyncCodec.fromPayload({
            ...change.payload,
            'id': change.payload['id'] ?? change.id,
          }, revision: change.revision);
          if (incoming.id.isEmpty) {
            throw const FormatException('Invoice delta thiếu id.');
          }
          final existing = await _repository.findById(incoming.id);
          if (existing == null || change.revision > existing.revision) {
            await _repository.saveRemoteInvoice(incoming);
            applied++;
          } else if (change.revision < existing.revision) {
            skipped++;
          } else if (_sameContent(existing, incoming)) {
            await _repository.saveRemoteInvoice(incoming);
            applied++;
          } else {
            await _repository.markInvoiceConflict(
              incoming.id,
              remote: incoming,
            );
            conflicts++;
          }
        } else {
          await _applyReference(change);
          applied++;
        }

        cursor = change.cursor;
        await _cursors.write(
          userId: userId,
          aggregateType: aggregateType,
          cursor: cursor,
        );
      }

      if (!page.hasMore) break;
    }

    return SyncPullResult(
      applied: applied,
      skipped: skipped,
      conflicts: conflicts,
      hasMore: hasMore,
    );
  }

  Future<void> _applyReference(SyncPullChange change) async {
    final id = '${change.payload['id'] ?? ''}'.trim();
    if (id.isEmpty) throw const FormatException('Reference delta thiếu id.');
    if (change.operation == 'delete') {
      switch (aggregateType) {
        case 'category':
          await _repository.deleteRemoteCategory(id);
        case 'budget':
          await _repository.deleteRemoteBudget(id);
        case 'merchant_rule':
          await _repository.deleteRemoteMerchantRule(id);
        default:
          throw FormatException('Aggregate không hỗ trợ: $aggregateType');
      }
      return;
    }
    switch (aggregateType) {
      case 'category':
        await _repository.saveRemoteCategory(
          ReferenceSyncCodec.categoryFromPayload(change.payload),
        );
      case 'budget':
        await _repository.saveRemoteBudget(
          ReferenceSyncCodec.budgetFromPayload(change.payload),
        );
      case 'merchant_rule':
        await _repository.saveRemoteMerchantRule(
          ReferenceSyncCodec.merchantRuleFromPayload(change.payload),
        );
      default:
        throw FormatException('Aggregate không hỗ trợ: $aggregateType');
    }
  }

  bool _sameContent(InvoiceEntity left, InvoiceEntity right) {
    if (left.id != right.id ||
        left.sellerName != right.sellerName ||
        left.sellerTaxCode != right.sellerTaxCode ||
        left.invoiceNumber != right.invoiceNumber ||
        left.invoiceSymbol != right.invoiceSymbol ||
        left.issuedAt != right.issuedAt ||
        left.currencyCode != right.currencyCode ||
        left.subtotalMinor != right.subtotalMinor ||
        left.taxMinor != right.taxMinor ||
        left.totalMinor != right.totalMinor ||
        left.sourceType != right.sourceType ||
        left.sourceHash != right.sourceHash ||
        left.status != right.status ||
        left.categoryId != right.categoryId ||
        left.notes != right.notes ||
        !_sameList(left.tags, right.tags) ||
        left.createdAt != right.createdAt ||
        left.updatedAt != right.updatedAt ||
        left.confirmedAt != right.confirmedAt ||
        left.deletedAt != right.deletedAt ||
        !_sameLines(left.lines, right.lines) ||
        !_sameEvidence(left.evidence, right.evidence)) {
      return false;
    }
    return true;
  }

  bool _sameList<T>(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  bool _sameLines(List<InvoiceLineEntity> left, List<InvoiceLineEntity> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.description != b.description ||
          a.quantity != b.quantity ||
          a.unitPriceMinor != b.unitPriceMinor ||
          a.taxRate != b.taxRate ||
          a.totalMinor != b.totalMinor) {
        return false;
      }
    }
    return true;
  }

  bool _sameEvidence(
    List<FieldEvidenceEntity> left,
    List<FieldEvidenceEntity> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.fieldName != b.fieldName ||
          a.rawValue != b.rawValue ||
          a.normalizedValue != b.normalizedValue ||
          a.source != b.source ||
          a.confidence != b.confidence ||
          a.correctedByUser != b.correctedByUser) {
        return false;
      }
    }
    return true;
  }
}
