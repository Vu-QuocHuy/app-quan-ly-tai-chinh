import '../../features/invoices/domain/invoice_models.dart';

/// Tìm danh mục theo id, an toàn với id `null` và id không còn tồn tại.
///
/// Thay bốn biến thể trước đây, trong đó có hai bản dùng
/// `where(...).firstOrNull` ngay trong `itemBuilder` — cấp phát một Iterable
/// trung gian cho MỌI dòng, MỌI frame cuộn.
CategoryEntity? findCategory(List<CategoryEntity> categories, String? id) {
  if (id == null) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
}
