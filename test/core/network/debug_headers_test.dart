import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_overrides.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/network/debug_headers.dart';

String? _header(String profile) => AiFlagOverrides(
  profile: AiFlagProfile.parse(profile),
  allowChanges: false,
).headerValue;

void main() {
  test('debug + b1 sends the x-finmi-flags header', () {
    final headers = aiDebugHeaders(flagsHeader: _header('b1'), debug: true);

    expect(headers['x-finmi-flags'], AiFlagProfile.parse('b1').headerValue);
  });

  test('runtime toggles are reflected in the header', () {
    final overrides = AiFlagOverrides(
      profile: AiFlagProfile.parse('server'),
      allowChanges: true,
    )..setAll(false);
    final headers = aiDebugHeaders(
      flagsHeader: overrides.headerValue,
      debug: true,
    );

    expect(headers['x-finmi-flags'], isNot(contains('=1')));
    expect(headers['x-finmi-flags']!.split(','), hasLength(10));
  });

  test('release builds never send debug headers', () {
    final headers = aiDebugHeaders(
      flagsHeader: _header('b1'),
      debug: false,
      fault: '429',
    );

    expect(headers, isEmpty);
  });

  test('server profile sends no flags header', () {
    final headers = aiDebugHeaders(flagsHeader: _header('server'), debug: true);

    expect(headers.containsKey('x-finmi-flags'), isFalse);
  });

  test('a simulated fault adds x-finmi-fault', () {
    final headers = aiDebugHeaders(
      flagsHeader: _header('server'),
      debug: true,
      fault: 'timeout',
    );

    expect(headers, {'x-finmi-fault': 'timeout'});
  });

  test('an unsupported fault value is dropped', () {
    final headers = aiDebugHeaders(
      flagsHeader: _header('server'),
      debug: true,
      fault: '404',
    );

    expect(headers, isEmpty);
  });
}
