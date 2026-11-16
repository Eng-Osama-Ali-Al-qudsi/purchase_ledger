import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
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
  bool _overdueOnly = false;

  void _navigateFromDashboard(int index, {bool overdueOnly = false}) {
    setState(() {
      _index = index;
      _overdueOnly = index == 2 && overdueOnly;
    });
  }

  @override
  Widget build(BuildContext context) {
    // An IndexedStack retains the Stateful tab elements across rebuilds.
    final pages = <Widget>[
      DashboardScreen(onNavigate: _navigateFromDashboard),
      const SuppliersScreen(),
      CreditInvoicesScreen(overdueOnly: _overdueOnly),
      const DailyPurchasesScreen(),
      const AppSettingsScreen(),
    ];
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
      ),
      body: SafeArea(top: false, child: IndexedStack(
        key: const ValueKey('purchase-ledger-tabs'),
        index: _index,
        children: pages,
      )),
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        selectedIndex: _index,
        onDestinationSelected: (value) => _navigateFromDashboard(value),
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
