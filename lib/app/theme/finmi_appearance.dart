import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'finmi_theme.dart';

/// The ten approved reference palettes. Pure white is the first-run default.
class FinmiAppearance {
  const FinmiAppearance({
    required this.id,
    required this.name,
    required this.description,
    required this.brightness,
    required this.primary,
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.tokens,
  });
  final String id, name, description;
  final Brightness brightness;
  final Color primary, background, surface, text, muted;
  final FinmiTokens tokens;
  bool get isDark => brightness == Brightness.dark;
  static FinmiAppearance fromId(String? id) => values.firstWhere(
    (item) => item.id == id,
    orElse: () => values.firstWhere((item) => item.id == 'white'),
  );
  static const values = <FinmiAppearance>[
    FinmiAppearance(
      id: 'signature',
      name: 'Finmi signature',
      description: 'Xanh thông · Cân bằng',
      brightness: Brightness.light,
      primary: Color(0xFF123D32),
      background: Color(0xFFF5F7F3),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF172D24),
      muted: Color(0xFF52665A),
      tokens: FinmiTokens(
        accent: Color(0xFFC99B56),
        border: Color(0xFFAABCB0),
        heroBackground: Color(0xFFFFFFFF),
        heroText: Color(0xFF123D32),
        heroSecondary: Color(0xFF52665A),
        cardRadius: 18,
        heroRadius: 22,
      ),
    ),
    FinmiAppearance(
      id: 'pearl',
      name: 'Pearl white',
      description: 'Trắng tinh · Thanh thoát',
      brightness: Brightness.light,
      primary: Color(0xFF123D32),
      background: Color(0xFFEDF0F0),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF17251E),
      muted: Color(0xFF53625B),
      tokens: FinmiTokens(
        accent: Color(0xFFC99B56),
        border: Color(0xFF9EADA3),
        heroBackground: Color(0xFFDFE9E3),
        heroText: Color(0xFF123D32),
        heroSecondary: Color(0xFF3C5A48),
        cardRadius: 22,
        heroRadius: 26,
      ),
    ),
    FinmiAppearance(
      id: 'ivory',
      name: 'Ivory gold',
      description: 'Trắng ngà · Vàng đồng',
      brightness: Brightness.light,
      primary: Color(0xFF123D32),
      background: Color(0xFFF0EBDF),
      surface: Color(0xFFFFFEFA),
      text: Color(0xFF2B3024),
      muted: Color(0xFF696450),
      tokens: FinmiTokens(
        accent: Color(0xFFC99B56),
        border: Color(0xFFAA997A),
        heroBackground: Color(0xFF253D32),
        heroText: Color(0xFFFFFCF4),
        heroSecondary: Color(0xFFE1D9C6),
        cardRadius: 14,
        heroRadius: 18,
      ),
    ),
    FinmiAppearance(
      id: 'sage',
      name: 'Sage calm',
      description: 'Xanh nhạt · Nhẹ nhàng',
      brightness: Brightness.light,
      primary: Color(0xFF234A36),
      background: Color(0xFFE8EEDF),
      surface: Color(0xFFFCFEF9),
      text: Color(0xFF263C25),
      muted: Color(0xFF55674D),
      tokens: FinmiTokens(
        accent: Color(0xFFC99B56),
        border: Color(0xFF8CA27E),
        heroBackground: Color(0xFFD1DFBF),
        heroText: Color(0xFF203F29),
        heroSecondary: Color(0xFF355137),
        cardRadius: 20,
        heroRadius: 24,
      ),
    ),
    FinmiAppearance(
      id: 'graphite',
      name: 'Graphite line',
      description: 'Nét đậm · Gọn gàng',
      brightness: Brightness.light,
      primary: Color(0xFF123D32),
      background: Color(0xFFEDEFEA),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF202720),
      muted: Color(0xFF515B52),
      tokens: FinmiTokens(
        accent: Color(0xFFC99B56),
        border: Color(0xFF7D8D7F),
        heroBackground: Color(0xFF252C27),
        heroText: Color(0xFFFFFFFF),
        heroSecondary: Color(0xFFDAE1D8),
        cardRadius: 10,
        heroRadius: 12,
      ),
    ),
    FinmiAppearance(
      id: 'white',
      name: 'Pure white',
      description: 'Trắng thuần · Xanh thông',
      brightness: Brightness.light,
      primary: Color(0xFF123D32),
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF172D24),
      muted: Color(0xFF52665A),
      tokens: FinmiTokens(
        accent: Color(0xFFC99B56),
        border: Color(0xFF98AA9D),
        heroBackground: Color(0xFF123D32),
        heroText: Color(0xFFFFFFFF),
        heroSecondary: Color(0xFFD8E8DC),
        cardRadius: 16,
        heroRadius: 20,
      ),
    ),
    FinmiAppearance(
      id: 'whitegold',
      name: 'White gold',
      description: 'Trắng thuần · Viền vàng',
      brightness: Brightness.light,
      primary: Color(0xFF123D32),
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF292F24),
      muted: Color(0xFF635F50),
      tokens: FinmiTokens(
        accent: Color(0xFFC99B56),
        border: Color(0xFFAC9872),
        heroBackground: Color(0xFFF2E8D3),
        heroText: Color(0xFF253D2C),
        heroSecondary: Color(0xFF60543B),
        cardRadius: 14,
        heroRadius: 18,
      ),
    ),
    FinmiAppearance(
      id: 'midnight',
      name: 'Midnight forest',
      description: 'Đen xanh · Bạc hà',
      brightness: Brightness.dark,
      primary: Color(0xFFB6DEC4),
      background: Color(0xFF09110D),
      surface: Color(0xFF15221A),
      text: Color(0xFFF0F6EE),
      muted: Color(0xFFBBCBBB),
      tokens: FinmiTokens(
        accent: Color(0xFFD7B373),
        border: Color(0xFF607565),
        heroBackground: Color(0xFF234C38),
        heroText: Color(0xFFFFFFFF),
        heroSecondary: Color(0xFFD4E8D5),
        cardRadius: 18,
        heroRadius: 22,
      ),
    ),
    FinmiAppearance(
      id: 'obsidian',
      name: 'Obsidian gold',
      description: 'Đen thuần · Vàng đồng',
      brightness: Brightness.dark,
      primary: Color(0xFFE0BE7B),
      background: Color(0xFF000000),
      surface: Color(0xFF151714),
      text: Color(0xFFF6F4EC),
      muted: Color(0xFFC4C6B8),
      tokens: FinmiTokens(
        accent: Color(0xFFE0BE7B),
        border: Color(0xFF737A6B),
        heroBackground: Color(0xFF26291F),
        heroText: Color(0xFFF8EDD5),
        heroSecondary: Color(0xFFD6CCB5),
        cardRadius: 12,
        heroRadius: 16,
      ),
    ),
    FinmiAppearance(
      id: 'charcoal',
      name: 'Charcoal soft',
      description: 'Xám than · Trắng bạc',
      brightness: Brightness.dark,
      primary: Color(0xFFC1DAC8),
      background: Color(0xFF151816),
      surface: Color(0xFF242B25),
      text: Color(0xFFF2F5EF),
      muted: Color(0xFFC3CEC1),
      tokens: FinmiTokens(
        accent: Color(0xFFD2B584),
        border: Color(0xFF768678),
        heroBackground: Color(0xFF354338),
        heroText: Color(0xFFFFFFFF),
        heroSecondary: Color(0xFFD8E4D4),
        cardRadius: 22,
        heroRadius: 26,
      ),
    ),
  ];
}

class FinmiAppearanceNotifier extends Notifier<FinmiAppearance> {
  bool _changed = false;
  bool _disposed = false;
  @override
  FinmiAppearance build() {
    ref.onDispose(() => _disposed = true);
    _restore();
    return FinmiAppearance.fromId('white');
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_changed && !_disposed) {
      state = FinmiAppearance.fromId(prefs.getString('app.finmiAppearance'));
    }
  }

  Future<void> set(FinmiAppearance appearance) async {
    _changed = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app.finmiAppearance', appearance.id);
    if (!_disposed) state = appearance;
  }
}

final finmiAppearanceProvider =
    NotifierProvider<FinmiAppearanceNotifier, FinmiAppearance>(
      FinmiAppearanceNotifier.new,
    );
