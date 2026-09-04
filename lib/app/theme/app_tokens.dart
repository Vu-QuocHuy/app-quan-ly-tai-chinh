import 'package:flutter/material.dart';

/// Nguồn sự thật duy nhất cho spacing, bo góc, kích thước icon, độ nổi và motion.
///
/// ## Kỹ thuật bị cấm trong toàn bộ lib/ — điều khoản có hiệu lực, không phải gợi ý
///
/// Repo này hôm nay có 0 `BoxShadow`, 0 `BackdropFilter`, 0 `ClipRRect`. Đó là
/// lợi thế hiệu năng trên máy Android tầm trung (Mali-G52 / Snapdragon 680) và
/// nó phải được giữ. KHÔNG được thêm:
///
/// * `BackdropFilter` / `ImageFilter.blur` — mỗi rect bị blur là một lần render
///   offscreen toàn màn hình mỗi frame. Cách nhanh nhất để mất 60fps.
/// * `ClipRRect` bọc nội dung cuộn — buộc `saveLayer` trên mỗi frame cuộn.
/// * `AnimationController` lặp vô hạn trên route thường trực (Dashboard, danh
///   sách hóa đơn). Ngoài chi phí GPU, nó làm `tester.pumpAndSettle()` treo.
/// * `shimmer` / `skeletonizer` — cùng lý do. Skeleton trong app này là khối
///   tĩnh `surfaceContainerHigh`, crossfade bằng `AnimatedSwitcher`.
///
/// Nếu thiết kế đòi cảm giác "kính mờ", câu trả lời là `LinearGradient` dọc ~4%
/// trong `ShapeDecoration` (miễn phí về shader), không phải blur.
abstract final class AppSpacing {
  /// Lưới 4pt nghiêm ngặt. Thay 11 độ lớn spacing và 139 `SizedBox` hardcode.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Khoảng cách giữa hai section trên cùng một trang cuộn.
  static const double section = 40;

  /// Lề ngang của trang. Rộng hơn 16 hiện tại — lề rộng là cách rẻ nhất để
  /// trông đắt tiền.
  static const double gutter = 20;

  /// Thụt lề kẻ tóc trong danh sách: canh theo CỘT CHỮ, không theo avatar.
  /// = gutter(20) + avatar(40) + gap(8). Đây là "hanging indent" của nghề in.
  static const double dividerIndent = 68;
}

abstract final class AppShapes {
  static const double xs = 8; // chip dày đặc, đầu cột biểu đồ
  static const double sm = 12; // input, button, ink của list tile, snackbar
  static const double md = 20; // thẻ, dialog, menu (M3 "large")
  static const double lg = 28; // bottom sheet, hero (M3 "extra-large")

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(sm),
  );

  static const RoundedRectangleBorder card = RoundedRectangleBorder(
    borderRadius: cardRadius,
  );
  static const RoundedRectangleBorder control = RoundedRectangleBorder(
    borderRadius: controlRadius,
  );
  static const RoundedRectangleBorder sheet = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(lg)),
  );

  /// Hình khối biểu cảm DUY NHẤT trong app. Chỉ dùng cho hero Dashboard.
  /// Nó chỉ biểu cảm khi nó khan hiếm — đừng dùng ở chỗ thứ hai.
  static const RoundedRectangleBorder hero = RoundedRectangleBorder(
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(lg),
      topRight: Radius.circular(xs),
      bottomLeft: Radius.circular(lg),
      bottomRight: Radius.circular(lg),
    ),
  );

  /// Nav indicator, badge, thanh tiến trình — thay cho `circular(999)`.
  static const StadiumBorder pill = StadiumBorder();
}

abstract final class AppIconSizes {
  static const double sm = 18; // inline cùng dòng chữ
  static const double md = 22; // leading của list, action của app bar
  static const double lg = 44; // empty state
}

abstract final class AppElevations {
  /// Độ nổi chỉ dùng đúng ba chỗ, tất cả M3-native: NavigationBar (để có
  /// scroll-under tint), FAB, và AppBar khi cuộn.
  static const double none = 0;
  static const double raised = 3;
  static const double raisedHover = 4;
}

/// Token motion. Mọi `duration:` phải đi qua `AppMotion.of(context, ...)`.
abstract final class AppMotion {
  static const Duration fast = Durations.short4; // 200ms — crossfade trạng thái
  static const Duration base = Durations.medium2; // 300ms — chuyển tab
  static const Duration page = Durations.medium4; // 400ms — push/pop
  static const Duration slow = Durations.long2; // 500ms — đếm số, ngân sách

  static const Curve enter = Easing.emphasizedDecelerate;
  static const Curve exit = Easing.emphasizedAccelerate;
  static const Curve standard = Easing.standard;
  static const Curve standardDecelerate = Easing.standardDecelerate;

  /// LƯU Ý: `Easing.emphasized` KHÔNG tồn tại trong Flutter (đã kiểm chứng trên
  /// 3.47.1: `material/motion.dart` chỉ có `emphasizedAccelerate` và
  /// `emphasizedDecelerate`). Đường cong "emphasized" đầy đủ của M3 là
  /// `Curves.easeInOutCubicEmphasized` (một `ThreePointCubic`).
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Cổng giảm chuyển động. SHIP TRƯỚC khi thêm bất kỳ animation nào.
  static bool isReduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration of(BuildContext context, Duration duration) =>
      isReduced(context) ? Duration.zero : duration;
}

abstract final class AppBreakpoints {
  static const double compact = 600; // điện thoại
  static const double medium = 840; // tablet dọc / foldable -> NavigationRail
  static const double expanded = 1240; // desktop / web rộng

  /// Bề rộng đọc tối đa cho nội dung một cột. Không có ràng buộc này thì một
  /// `ListTile` Cài đặt rộng ~1300dp trên cửa sổ web 1440dp.
  static const double readingWidth = 720;
  static const double twoColumnWidth = 1200;

  static bool useRail(double width) => width >= medium;
}

/// L1/L2/L3 — dùng extension này, đừng gõ thẳng vai `surfaceContainer*`.
extension AppSurfaces on ColorScheme {
  /// L1 — nền thẻ. Bất đối xứng có chủ đích giữa hai brightness.
  Color get cardSurface => brightness == Brightness.light
      ? surfaceContainerLowest
      : surfaceContainer;

  /// L2 — lõm bên trong thẻ.
  Color get insetSurface => surfaceContainerHigh;

  /// L3 — nổi lên trên thẻ.
  Color get liftedSurface => surfaceContainerHighest;
}
