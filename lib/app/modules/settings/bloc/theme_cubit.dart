import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeState {
  final ThemeMode themeMode;
  final Color seedColor;

  ThemeState({required this.themeMode, required this.seedColor});

  ThemeState copyWith({ThemeMode? themeMode, Color? seedColor}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
    );
  }
}

class ThemeCubit extends Cubit<ThemeState> {
  static const _keyThemeModeIndex = 'theme_mode_index';
  static const _keySeedColorValue = 'seed_color_value';

  ThemeCubit()
      : super(ThemeState(
          themeMode: ThemeMode.system,
          seedColor: const Color(0xFF0ABAB5),
        ));

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_keyThemeModeIndex) ?? ThemeMode.system.index;
    final seedValue = prefs.getInt(_keySeedColorValue) ?? 0xFF0ABAB5;

    ThemeMode mode = ThemeMode.values.elementAt(
      modeIndex.clamp(0, ThemeMode.values.length - 1),
    );

    final newColor = Color(seedValue);
    debugPrint('ThemeCubit.loadTheme -> mode=$mode seedColor=${newColor.value.toRadixString(16)}');
    emit(state.copyWith(themeMode: mode, seedColor: newColor));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    debugPrint('ThemeCubit.setThemeMode -> $mode');
    emit(state.copyWith(themeMode: mode));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeModeIndex, ThemeMode.values.indexOf(mode));
  }

  Future<void> setSeedColor(Color color) async {
    debugPrint('ThemeCubit.setSeedColor -> ${color.value.toRadixString(16)}');
    emit(state.copyWith(seedColor: color));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeedColorValue, color.value);
  }
}
