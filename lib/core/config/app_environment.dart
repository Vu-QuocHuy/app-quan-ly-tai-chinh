import 'package:flutter/foundation.dart';

enum AppEnvironment {
  dev('Phát triển'),
  staging('Staging'),
  production('Production');

  const AppEnvironment(this.label);

  final String label;

  static AppEnvironment get current {
    const configured = String.fromEnvironment('APP_ENV');
    return switch (configured) {
      'production' => AppEnvironment.production,
      'staging' => AppEnvironment.staging,
      'dev' => AppEnvironment.dev,
      _ => kReleaseMode ? AppEnvironment.production : AppEnvironment.dev,
    };
  }
}
