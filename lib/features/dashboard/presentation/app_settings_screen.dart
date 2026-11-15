import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/measurement_units_screen.dart';
import 'about_developer_screen.dart';
import 'business_directory_screen.dart';
import 'business_profile_dialog.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 90),
        children: [
          Text(tr(context, 'إدارة التطبيق', 'Manage application'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(tr(context, 'بيانات المحل', 'Business profile')),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () async {
                    final profile = await ref.read(businessProfileProvider.future);
                    if (!context.mounted) return;
                    final saved = await showDialog<bool>(
                      context: context,
                      builder: (_) => BusinessProfileDialog(profile: profile),
                    );
                    if (saved == true) {
                      ref.invalidate(businessProfileProvider);
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(tr(context, 'بيانات التشغيل', 'Business directory')),
                  subtitle: Text(tr(context,
                      'الفروع والموظفون والتصنيفات والأصناف',
                      'Branches, employees, categories and products')),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BusinessDirectoryScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.straighten_outlined),
                  title: Text(tr(context, 'وحدات القياس', 'Measurement units')),
                  subtitle: Text(tr(context, 'وحدات الآجلة واليومية',
                      'Credit and daily units')),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MeasurementUnitsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(tr(context, 'مظهر التطبيق', 'Appearance'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800)),
          Card(
            child: Column(
              children: [
                _themeOption(context, ref, settings.themeMode,
                    ThemeMode.light, Icons.light_mode_outlined,
                    tr(context, 'الوضع الفاتح', 'Light')),
                const Divider(height: 1),
                _themeOption(context, ref, settings.themeMode,
                    ThemeMode.dark, Icons.dark_mode_outlined,
                    tr(context, 'الوضع الداكن', 'Dark')),
                const Divider(height: 1),
                _themeOption(context, ref, settings.themeMode,
                    ThemeMode.system, Icons.settings_brightness_outlined,
                    tr(context, 'حسب النظام', 'Use device setting')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(tr(context, 'اللغة', 'Language'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800)),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('العربية'),
                  trailing: settings.locale.languageCode == 'ar'
                      ? const Icon(Icons.check_circle_outline) : null,
                  onTap: () => ref.read(appSettingsProvider.notifier)
                      .setLanguage('ar'),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('English'),
                  trailing: settings.locale.languageCode == 'en'
                      ? const Icon(Icons.check_circle_outline) : null,
                  onTap: () => ref.read(appSettingsProvider.notifier)
                      .setLanguage('en'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(tr(context, 'عن المطور', 'About developer')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AboutDeveloperScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeOption(BuildContext context, WidgetRef ref,
      ThemeMode current, ThemeMode option, IconData icon, String label) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: current == option,
      trailing: current == option
          ? const Icon(Icons.check_circle_rounded) : null,
      onTap: () async {
        try {
          await ref.read(appSettingsProvider.notifier).setThemeMode(option);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error.toString())),
            );
          }
        }
      },
    );
  }
}
