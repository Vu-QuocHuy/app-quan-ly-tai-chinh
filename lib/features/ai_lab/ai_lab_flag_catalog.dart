import '../../core/config/feature_flags.dart';

/// Nhóm hiển thị của 10 cờ tối ưu (docs/ai-optimization/ailab-protocol.md §4).
enum AiLabFlagGroup {
  extract('Đọc hóa đơn'),
  chat('Chat'),
  platform('Nền tảng');

  const AiLabFlagGroup(this.title);

  final String title;
}

/// Một cờ tối ưu như hiển thị trên panel AI Lab.
class AiLabFlagInfo {
  const AiLabFlagInfo(this.flag, this.group, this.name, {required this.server});

  final AiOptimizationFlag flag;
  final AiLabFlagGroup group;

  /// Tên tiếng Việt thống nhất giữa app và các trang web demo.
  final String name;

  /// `true` nếu cờ có hiệu lực ở server (qua header `x-finmi-flags`), `false`
  /// nếu có hiệu lực ngay trên máy.
  final bool server;

  String get where => server ? 'server' : 'máy';
}

const aiLabFlagCatalog = <AiLabFlagInfo>[
  AiLabFlagInfo(
    AiOptimizationFlag.extractThinkingLow,
    AiLabFlagGroup.extract,
    'Giảm suy luận của AI',
    server: true,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.extractImage1600,
    AiLabFlagGroup.extract,
    'Thu nhỏ ảnh về 1600 px',
    server: false,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.extractPrecheckDedup,
    AiLabFlagGroup.extract,
    'Chặn ảnh trùng trước khi gọi AI',
    server: false,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.extractValidator,
    AiLabFlagGroup.extract,
    'Hậu kiểm số học hóa đơn',
    server: false,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.chatLocalRouter,
    AiLabFlagGroup.chat,
    'Trả lời câu tra cứu trên máy',
    server: false,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.chatMergeCalls,
    AiLabFlagGroup.chat,
    'Gộp lượt gọi chat',
    server: false,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.chatPromptV2,
    AiLabFlagGroup.chat,
    'Prompt chat rút gọn',
    server: true,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.classifyLocal,
    AiLabFlagGroup.chat,
    'Phân loại cửa hàng trên máy',
    server: false,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.routerFailover,
    AiLabFlagGroup.platform,
    'Dự phòng 9Router → Gemini',
    server: true,
  ),
  AiLabFlagInfo(
    AiOptimizationFlag.telemetryUpload,
    AiLabFlagGroup.platform,
    'Gửi telemetry lên server',
    server: false,
  ),
];
