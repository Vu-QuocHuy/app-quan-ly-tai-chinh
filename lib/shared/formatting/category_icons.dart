import 'package:flutter/material.dart';

/// Danh sách icon người dùng chọn được cho danh mục. Nguồn sự thật duy nhất —
/// picker trong màn Danh mục và mọi nơi render icon đều đọc từ đây.
const List<String> kCategoryIconNames = [
  'category',
  'restaurant',
  'directions_car',
  'shopping_bag',
  'bolt',
  'health_and_safety',
  'school',
  'movie',
  'home',
  'pets',
  'flight',
  'fitness_center',
];

/// Ánh xạ tên icon đã lưu trong DB sang `IconData`.
///
/// Hợp nhất BA bản không khớp nhau trước đây: màn Danh mục nhận đủ 11 case,
/// còn Dashboard và Chi tiết hóa đơn chỉ nhận 7. Hệ quả là người dùng chọn
/// `pets` / `home` / `flight` / `fitness_center` thì thấy đúng icon ở Danh mục
/// nhưng ra `Icons.category` xám ở hai màn còn lại. Bản này giữ đủ 12 case và
/// nhận `null` an toàn.
IconData categoryIconFor(String? name) => switch (name) {
  'restaurant' => Icons.restaurant,
  'directions_car' => Icons.directions_car,
  'shopping_bag' => Icons.shopping_bag,
  'bolt' => Icons.bolt,
  'health_and_safety' => Icons.health_and_safety,
  'school' => Icons.school,
  'movie' => Icons.movie,
  'home' => Icons.home,
  'pets' => Icons.pets,
  'flight' => Icons.flight,
  'fitness_center' => Icons.fitness_center,
  _ => Icons.category,
};

/// Tên tiếng Việt của từng icon.
///
/// Cần thiết vì picker icon dùng `ChoiceChip(label: Icon(...))`: `Icon` không
/// đóng góp semantics nếu không có `semanticLabel`, nên mỗi chip vốn phơi ra
/// một cái tên RỖNG — người dùng TalkBack vuốt qua hàng icon chỉ nghe im lặng.
String categoryIconLabel(String? name) => switch (name) {
  'restaurant' => 'Ăn uống',
  'directions_car' => 'Di chuyển',
  'shopping_bag' => 'Mua sắm',
  'bolt' => 'Tiện ích',
  'health_and_safety' => 'Y tế',
  'school' => 'Giáo dục',
  'movie' => 'Giải trí',
  'home' => 'Nhà cửa',
  'pets' => 'Thú cưng',
  'flight' => 'Du lịch',
  'fitness_center' => 'Thể thao',
  _ => 'Khác',
};
