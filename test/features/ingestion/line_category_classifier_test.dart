import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/domain/line_category_classifier.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  const classifier = LineCategoryClassifier();
  const categories = [
    CategoryEntity(
      id: 'food',
      name: 'Ăn uống',
      iconName: 'restaurant',
      colorValue: 0,
    ),
    CategoryEntity(
      id: 'shopping',
      name: 'Mua sắm',
      iconName: 'shopping_bag',
      colorValue: 0,
    ),
  ];

  test('classifies grocery lines and keeps unknown items reviewable', () {
    final result = classifier.classify([
      const InvoiceLineEntity(
        id: '1',
        description: 'Thịt heo',
        totalMinor: 120000,
      ),
      const InvoiceLineEntity(
        id: '2',
        description: 'Sản phẩm khác',
        totalMinor: 50000,
      ),
    ], categories);

    expect(result[0].categoryId, 'food');
    expect(result[1].categoryId, isNull);
  });
}
