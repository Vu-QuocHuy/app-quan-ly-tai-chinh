import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/qr_payment_draft_store.dart';
import '../domain/qr_payment_draft.dart';

final qrPaymentDraftStoreProvider = Provider<QrPaymentDraftStore>((ref) {
  final userId = ref.watch(authUserProvider).value?.id;
  return QrPaymentDraftStore(scope: userId);
});

final pendingQrPaymentDraftProvider = FutureProvider<QrPaymentDraft?>((ref) {
  return ref.watch(qrPaymentDraftStoreProvider).readDraft();
});
