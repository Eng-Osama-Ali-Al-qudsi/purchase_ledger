import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class AppSettings {
  const AppSettings({required this.locale, required this.themeMode});

  final Locale locale;
  final ThemeMode themeMode;

  AppSettings copyWith({Locale? locale, ThemeMode? themeMode}) => AppSettings(
        locale: locale ?? this.locale,
        themeMode: themeMode ?? this.themeMode,
      );
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier()
      : super(const AppSettings(
            locale: Locale('ar'), themeMode: ThemeMode.dark)) {
    _load();
  }

  bool _userChangedSettings = false;

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'app_settings',
        where: 'setting_key IN (?, ?)',
        whereArgs: ['language_code', 'theme_mode'],
      );
      final values = <String, String>{
        for (final row in rows)
          row['setting_key'] as String: row['setting_value'] as String,
      };
      if (_userChangedSettings) return;
      final language = values['language_code'] ?? 'ar';
      final theme = values['theme_mode'] ?? 'dark';
      state = state.copyWith(
        locale: Locale(language),
        themeMode: switch (theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
      );
    } catch (_) {
      // Keep safe defaults; the database gate surfaces database failures to the UI.
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (languageCode != 'ar' && languageCode != 'en') return;
    _userChangedSettings = true;
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'app_settings',
      {
        'setting_key': 'language_code',
        'setting_value': languageCode,
        'updated_at': now
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    state = state.copyWith(locale: Locale(languageCode));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    _userChangedSettings = true;
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'app_settings',
      {'setting_key': 'theme_mode', 'setting_value': value, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    state = state.copyWith(themeMode: mode);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(),
);
