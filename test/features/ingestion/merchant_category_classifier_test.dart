import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/domain/line_category_classifier.dart';
import 'package:hoadon_insight/features/ingestion/domain/merchant_category_classifier.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  const merchants = MerchantCategoryClassifier();

  test('matches merchant-rules-v1 for typical sellers', () {
    expect(merchants.classify('Highlands Coffee Quận 1'), 'food');
    expect(merchants.classify('NHÀ HÀNG Biển Đông'), 'food');
    expect(merchants.classify('Grab Vietnam'), 'transport');
    expect(merchants.classify('Cửa hàng xăng dầu số 5'), 'transport');
    expect(merchants.classify('Điện lực Hà Nội'), 'utilities');
    expect(merchants.classify('Nhà thuốc Long Châu'), 'health');
    expect(merchants.classify('CGV Cinema'), 'entertainment');
    expect(merchants.classify('Vincom Mall'), 'shopping');
  });

  test('returns null when no rule matches (server would answer other)', () {
    expect(merchants.classify('Công ty TNHH ABC'), isNull);
    expect(merchants.classify('   '), isNull);
  });

  group('line classifier no longer matches short syllables', () {
    const lines = LineCategoryClassifier();
    final categories = [
      for (final id in [
        'food',
        'education',
        'utilities',
        'health',
        'transport',
        'entertainment',
      ])
        CategoryEntity(id: id, name: id, iconName: 'x', colorValue: 0),
    ];

    String? classify(String description) => lines
        .classify([
          InvoiceLineEntity(id: '1', description: description, totalMinor: 1),
        ], categories)
        .single
        .categoryId;

    test('former false positives stay unclassified', () {
      // "ca" in "card", "mi" in "mini", "qua" in "quà tặng", "vo" in "voucher",
      // "but" in "button", "cu" in "cục sạc".
      expect(classify('Thẻ card điện thoại'), isNull);
      expect(classify('Quạt mini'), isNull);
      expect(classify('Quà tặng sinh nhật'), isNull);
      expect(classify('Voucher giảm giá'), isNull);
      expect(classify('Áo button'), isNull);
      expect(classify('Cục sạc nhanh'), isNull);
    });

    test('multi-syllable replacements still classify real items', () {
      expect(classify('Cá hồi phi lê'), 'food');
      expect(classify('Mì tôm Hảo Hảo'), 'food');
      expect(classify('Trái cây tươi'), 'food');
      expect(classify('Tập vở 96 trang'), 'education');
      expect(classify('Bút bi Thiên Long'), 'education');
      expect(classify('Thịt heo xay'), 'food');
    });
  });
}
