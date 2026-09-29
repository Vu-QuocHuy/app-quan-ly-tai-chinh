import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoadon_insight/features/payments/data/qr_payment_draft_store.dart';
import 'package:hoadon_insight/features/payments/domain/qr_payment_draft.dart';

void main() {
  const userA = '11111111-1111-4111-8111-111111111111';
  const userB = '22222222-2222-4222-8222-222222222222';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'QR drafts and preferred bank app are isolated by signed-in user',
    () async {
      final storeA = QrPaymentDraftStore(scope: userA);
      final storeB = QrPaymentDraftStore(scope: userB);
      final draft = QrPaymentDraft(
        id: 'draft-a',
        createdAt: DateTime.utc(2026, 9, 29),
        bankBin: '970436',
        accountNumber: '123456789',
        recipientName: 'NGUYEN AN',
        memo: 'CA PHE',
        amountVnd: 125000,
        bankAppId: 'bank-a',
      );

      await storeA.writeDraft(draft);
      await storeA.writeLastBankAppId('bank-a');

      expect((await storeA.readDraft())?.accountNumber, '123456789');
      expect(await storeA.readLastBankAppId(), 'bank-a');
      expect(await storeB.readDraft(), isNull);
      expect(await storeB.readLastBankAppId(), isNull);
    },
  );

  test('signed-out scope cannot read a previous user draft', () async {
    final signedInStore = QrPaymentDraftStore(scope: userA);
    await signedInStore.writeDraft(
      QrPaymentDraft(
        id: 'private-draft',
        createdAt: DateTime.utc(2026, 9, 29),
        bankBin: '970436',
        accountNumber: '123456789',
        recipientName: 'NGUYEN AN',
        memo: 'CA PHE',
      ),
    );

    expect(await QrPaymentDraftStore().readDraft(), isNull);
  });
}
