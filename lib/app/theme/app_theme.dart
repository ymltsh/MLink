import 'package:flutter/material.dart';

class AppTheme {
  /// Create a ThemeData using Material 3 and a seed color.
  static ThemeData create(Color seed, Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
    );

    // Ensure text colors follow the generated color scheme for contrast
    final textTheme = base.textTheme.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: colorScheme.secondary,
        foregroundColor: colorScheme.onSecondary,
      ),
    );
  }
}
