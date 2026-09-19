import 'package:supabase_flutter/supabase_flutter.dart';

import '../../invoices/domain/invoice_models.dart';
import '../domain/shared_bill_models.dart';

class SharedBillService {
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final _emailPattern = RegExp(
    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    caseSensitive: false,
  );
  static const _maxSafeInteger = 9007199254740991;

  const SharedBillService(this._client);

  final SupabaseClient _client;

  String get currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Bạn cần đăng nhập để chia sẻ hóa đơn.');
    return id;
  }

  Future<void> shareInvoiceToGroup({
    required InvoiceEntity invoice,
    required String groupId,
    required List<String> memberIds,
    Map<String, int>? splitAmounts,
  }) async {
    _validateInvoice(invoice);
    _requiredUuid(groupId, 'groupId');
    _validateMemberIds(memberIds);
    final snapshot = invoiceShareSnapshot(invoice);
    if (splitAmounts == null) {
      await _client.rpc(
        'create_group_expense_from_invoice',
        params: {
          'p_group_id': groupId,
          'p_description': _invoiceDescription(invoice),
          'p_total_minor': invoice.totalMinor,
          'p_split_user_ids': memberIds,
          'p_source_invoice_id': invoice.id,
          'p_source_snapshot': snapshot,
        },
      );
      return;
    }
    _validateSplitAmounts(splitAmounts, invoice.totalMinor);
    if (splitAmounts.keys.toSet().difference(memberIds.toSet()).isNotEmpty) {
      throw const FormatException('Phần chia có thành viên không được chọn.');
    }
    await _client.rpc(
      'create_group_expense_custom_from_invoice',
      params: {
        'p_group_id': groupId,
        'p_description': _invoiceDescription(invoice),
        'p_total_minor': invoice.totalMinor,
        'p_splits': [
          for (final entry in splitAmounts.entries)
            {'user_id': entry.key, 'amount_minor': entry.value},
        ],
        'p_source_invoice_id': invoice.id,
        'p_source_snapshot': snapshot,
      },
    );
  }

  Future<void> shareInvoiceToUser({
    required InvoiceEntity invoice,
    required String recipientEmail,
    required int recipientAmountMinor,
  }) async {
    _validateInvoice(invoice);
    final email = recipientEmail.trim().toLowerCase();
    if (email.length > 320 || !_emailPattern.hasMatch(email)) {
      throw const FormatException('Email người nhận không hợp lệ.');
    }
    if (recipientAmountMinor < 0 || recipientAmountMinor > invoice.totalMinor) {
      throw const FormatException('Phần tiền người nhận không hợp lệ.');
    }
    await _client.rpc(
      'create_direct_bill_share',
      params: {
        'p_recipient_email': email,
        'p_source_invoice_id': invoice.id,
        'p_total_minor': invoice.totalMinor,
        'p_recipient_amount_minor': recipientAmountMinor,
        'p_source_snapshot': invoiceShareSnapshot(invoice),
      },
    );
  }

  Future<List<DirectBillShare>> listDirectShares() async {
    final rows = await _client.rpc('list_direct_bill_shares');
    if (rows is! List) {
      throw const FormatException(
        'Backend trả danh sách chia sẻ không hợp lệ.',
      );
    }
    return rows.map(DirectBillShare.fromMap).toList(growable: false);
  }

  Future<void> respondToDirectShare({
    required String shareId,
    required String action,
  }) async {
    _requiredUuid(shareId, 'shareId');
    if (!const {'accept', 'decline', 'revoke'}.contains(action)) {
      throw const FormatException('Hành động chia sẻ không hợp lệ.');
    }
    await _client.rpc(
      'respond_direct_bill_share',
      params: {'p_share_id': shareId, 'p_action': action},
    );
  }

  String _invoiceDescription(InvoiceEntity invoice) {
    final seller = invoice.sellerName.trim();
    return seller.length > 150
        ? 'Hóa đơn ${seller.substring(0, 150)}'
        : 'Hóa đơn $seller';
  }

  void _validateInvoice(InvoiceEntity invoice) {
    if (invoice.id.trim().isEmpty || invoice.id.length > 128) {
      throw const FormatException('Mã hóa đơn không hợp lệ.');
    }
    if (invoice.totalMinor < 1 || invoice.totalMinor > _maxSafeInteger) {
      throw const FormatException('Tổng hóa đơn không hợp lệ.');
    }
    if (invoice.sellerName.trim().isEmpty || invoice.sellerName.length > 240) {
      throw const FormatException('Tên cửa hàng không hợp lệ.');
    }
  }

  void _validateMemberIds(List<String> memberIds) {
    if (memberIds.isEmpty ||
        memberIds.length > 100 ||
        memberIds.toSet().length != memberIds.length) {
      throw const FormatException('Danh sách thành viên không hợp lệ.');
    }
    for (final id in memberIds) {
      _requiredUuid(id, 'memberId');
    }
  }

  void _validateSplitAmounts(Map<String, int> splitAmounts, int totalMinor) {
    if (splitAmounts.isEmpty || splitAmounts.length > 100) {
      throw const FormatException('Danh sách phần chia không hợp lệ.');
    }
    _validateMemberIds(splitAmounts.keys.toList(growable: false));
    var total = 0;
    for (final amount in splitAmounts.values) {
      if (amount < 0 ||
          amount > _maxSafeInteger ||
          total > _maxSafeInteger - amount) {
        throw const FormatException('Số tiền phần chia không hợp lệ.');
      }
      total += amount;
    }
    if (total != totalMinor) {
      throw const FormatException('Tổng phần chia phải bằng tổng hóa đơn.');
    }
  }

  void _requiredUuid(String value, String field) {
    if (!_uuidPattern.hasMatch(value)) {
      throw FormatException('$field không hợp lệ.');
    }
  }
}
