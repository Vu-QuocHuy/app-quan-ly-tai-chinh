import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/qr_payment_draft.dart';

class SupabaseQrPaymentHistoryStore {
  SupabaseQrPaymentHistoryStore(this._client, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  bool get canSync =>
      _client.auth.currentSession != null && _client.auth.currentUser != null;

  Future<void> record(
    QrPaymentDraft draft,
    String eventType, {
    String? invoiceId,
  }) async {
    if (!canSync) throw const AuthException('Hãy đăng nhập để đồng bộ QR.');
    await _client.rpc(
      'record_qr_payment_event',
      params: {
        'p_event_id': _uuid.v4(),
        'p_session_id': draft.id,
        'p_event_type': eventType,
        'p_bank_bin': draft.bankBin,
        'p_account_number': draft.accountNumber,
        'p_recipient_name': draft.recipientName,
        'p_memo': draft.memo,
        'p_amount_vnd': draft.amountVnd,
        'p_category_id': draft.categoryId,
        'p_bank_app_id': draft.bankAppId,
        'p_invoice_id': invoiceId,
      },
    );
  }
}
