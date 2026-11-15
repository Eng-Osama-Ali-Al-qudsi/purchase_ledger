import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/settings/app_settings.dart';
import '../../../app/providers.dart';
import 'business_profile_dialog.dart';
import 'business_directory_screen.dart';
import 'dashboard_screen.dart';
import 'app_settings_screen.dart';
import '../../purchases/presentation/credit_invoices_screen.dart';
import '../../purchases/presentation/daily_purchases_screen.dart';
import '../../suppliers/presentation/suppliers_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  // Preserve each tab's State (scroll position, form state and loaded results)
  // when selecting a different destination or changing the app theme.
  final List<Widget> _pages = const [
    DashboardScreen(),
    SuppliersScreen(),
    CreditInvoicesScreen(),
    DailyPurchasesScreen(),
    AppSettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final titles = [
      tr(context, 'لوحة التحكم', 'Dashboard'),
      tr(context, 'الموردون', 'Suppliers'),
      tr(context, 'المشتريات الآجلة', 'Credit purchases'),
      tr(context, 'المشتريات اليومية', 'Daily purchases'),
      tr(context, 'الإعدادات', 'Settings'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[_index],
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              tr(context, 'دفتر المشتريات', 'Purchase Ledger'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: tr(context, 'الإعدادات السريعة', 'Quick settings'),
            icon: const Icon(Icons.tune_rounded),
            onSelected: (value) async {
              final notifier = ref.read(appSettingsProvider.notifier);
              if (value == 'ar' || value == 'en') {
                await notifier.setLanguage(value);
              } else if (value == 'profile') {
                final profile = await ref.read(businessProfileProvider.future);
                if (!context.mounted) return;
                await showDialog<bool>(
                  context: context,
                  builder: (_) => BusinessProfileDialog(profile: profile),
                );
                if (!context.mounted) return;
                ref.invalidate(businessProfileProvider);
              } else if (value == 'directory') {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const BusinessDirectoryScreen(),
                ));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'ar', child: Text('العربية')),
              PopupMenuItem(value: 'en', child: Text('English')),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: 'profile',
                  child: Text(tr(context, 'بيانات المحل', 'Business profile'))),
              PopupMenuItem(
                  value: 'directory',
                  child: Text(tr(context, 'الفروع والموظفون والأصناف',
                      'Branches, staff and products'))),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(
        key: const ValueKey('purchase-ledger-tabs'),
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard_rounded),
            label: tr(context, 'الرئيسية', 'Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            selectedIcon: const Icon(Icons.storefront_rounded),
            label: tr(context, 'الموردون', 'Suppliers'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long_rounded),
            label: tr(context, 'الآجلة', 'Credit'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.shopping_basket_outlined),
            selectedIcon: const Icon(Icons.shopping_basket_rounded),
            label: tr(context, 'اليومية', 'Daily'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: tr(context, 'الإعدادات', 'Settings'),
          ),
        ],
      ),
    );
  }
}
