import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/app_settings.dart';
import '../core/theme/app_theme.dart';
import 'app_router.dart';

class PurchaseLedgerApp extends ConsumerWidget {
  const PurchaseLedgerApp({super.key});

  static final ThemeData _light = AppTheme.light();
  static final ThemeData _dark = AppTheme.dark();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp.router(
      title: 'Purchase Ledger',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      locale: settings.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _light,
      darkTheme: _dark,
      themeMode: settings.themeMode,
      // Avoid rebuilding the overlay/render tree halfway through an animated
      // theme transition while a popup route is closing.
      themeAnimationDuration: Duration.zero,
    );
  }
}
