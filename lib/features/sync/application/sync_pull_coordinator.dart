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
    if (!isSupportedSyncAggregateType(aggregateType)) {
      throw FormatException('Aggregate không hỗ trợ: $aggregateType');
    }
    if (userId.trim().isEmpty) {
      throw const FormatException('Tài khoản đồng bộ không hợp lệ.');
    }
    if (batchSize < 1 || maxPages < 1) {
      throw const FormatException('Tham số đồng bộ không hợp lệ.');
    }
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
      _validatePage(page, cursor);

      for (final change in page.changes) {
        if (aggregateType == 'invoice') {
          if (change.operation == 'delete') {
            final existing = await _repository.findById(change.id);
            if (existing == null || change.revision >= existing.revision) {
              await _repository.deleteRemoteInvoice(
                change.id,
                revision: change.revision,
                updatedAt: change.updatedAt,
                deletedAt: _optionalDate(change.payload['deletedAt']),
              );
              applied++;
            } else {
              skipped++;
            }
            cursor = change.cursor;
            await _cursors.write(
              userId: userId,
              aggregateType: aggregateType,
              cursor: cursor,
            );
            continue;
          }
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

  void _validatePage(SyncPullPage page, SyncCursor? cursor) {
    var previous = cursor;
    for (final change in page.changes) {
      if (change.aggregateType != aggregateType ||
          !isSupportedSyncAggregateType(change.aggregateType)) {
        throw const FormatException('Delta record sai aggregate.');
      }
      if (change.id.trim().isEmpty || change.revision < 1) {
        throw const FormatException('Delta record không hợp lệ.');
      }
      if (change.operation != 'upsert' && change.operation != 'delete') {
        throw const FormatException('Delta operation không hợp lệ.');
      }
      final payloadId = change.payload['id'];
      if (aggregateType == 'invoice' &&
          payloadId != null &&
          (payloadId is! String || payloadId.trim() != change.id)) {
        throw const FormatException('Delta invoice sai id.');
      }
      if (aggregateType == 'invoice' && change.operation == 'delete') {
        final deletedAt = change.payload['deletedAt'];
        if (deletedAt != null &&
            (deletedAt is! String || DateTime.tryParse(deletedAt) == null)) {
          throw const FormatException('Invoice tombstone không hợp lệ.');
        }
      }
      if (aggregateType != 'invoice') {
        if (payloadId is! String || payloadId.trim().isEmpty) {
          throw const FormatException('Reference delta thiếu id.');
        }
      }
      if (previous != null && !_isAfter(change.cursor, previous)) {
        throw const FormatException('Delta cursor không tăng dần.');
      }
      previous = change.cursor;
    }
  }

  bool _isAfter(SyncCursor current, SyncCursor previous) {
    final currentTime = current.updatedAt;
    final previousTime = previous.updatedAt;
    if (currentTime == null || previousTime == null) return false;
    final timeComparison = currentTime.compareTo(previousTime);
    if (timeComparison != 0) return timeComparison > 0;
    return (current.updatedId ?? '').compareTo(previous.updatedId ?? '') > 0;
  }

  DateTime? _optionalDate(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Invoice tombstone không hợp lệ.');
    }
    final result = DateTime.tryParse(value);
    if (result == null) {
      throw const FormatException('Invoice tombstone không hợp lệ.');
    }
    return result.toLocal();
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
          a.totalMinor != b.totalMinor ||
          a.categoryId != b.categoryId) {
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
