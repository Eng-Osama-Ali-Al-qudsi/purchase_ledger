import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:purchase_ledger/app/providers.dart';
import 'package:purchase_ledger/features/dashboard/presentation/business_directory_screen.dart';
import 'package:purchase_ledger/features/dashboard/presentation/home_shell.dart';
import 'package:purchase_ledger/features/purchases/presentation/purchase_entry_dialog.dart';

void main() {
  final emptyRows = <Map<String, Object?>>[];

  testWidgets('all five navigation destinations display their own content',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        branchesProvider.overrideWith((ref) async => emptyRows),
        employeesProvider(null).overrideWith((ref) async => emptyRows),
        purchaseCategoriesProvider.overrideWith((ref) async => emptyRows),
        purchaseProductsProvider.overrideWith((ref) async => emptyRows),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: HomeShell(),
      ),
    ));
    await tester.pump();
    for (final entry in <(int, String)>[
      (1, 'الموردون'),
      (2, 'المشتريات الآجلة'),
      (3, 'المشتريات اليومية'),
      (4, 'الإعدادات'),
      (0, 'لوحة التحكم'),
    ]) {
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      nav.onDestinationSelected!(entry.$1);
      await tester.pump();
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar))
          .selectedIndex, entry.$1);
      expect(find.text(entry.$2), findsWidgets);
    }
  });

  testWidgets('cancelling a product dialog repeatedly does not crash',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        branchesProvider.overrideWith((ref) async => emptyRows),
        employeesProvider(null).overrideWith((ref) async => emptyRows),
        purchaseCategoriesProvider.overrideWith((ref) async => emptyRows),
        purchaseProductsProvider.overrideWith((ref) async => emptyRows),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: BusinessDirectoryScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأصناف'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('إضافة'));
      await tester.pumpAndSettle();
      expect(find.text('إضافة صنف'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'اختبار');
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('إضافة صنف'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('credit invoice uses registered units and hides tax/discount',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        businessProfileProvider.overrideWith((ref) async => null),
        branchesProvider.overrideWith((ref) async => emptyRows),
        employeesProvider(null).overrideWith((ref) async => emptyRows),
        creditMeasurementUnitsProvider.overrideWith((ref) async => [
              {'id': 1, 'name': 'قطعة', 'scope': 'credit', 'is_active': 1},
              {'id': 2, 'name': 'كرتون', 'scope': 'credit', 'is_active': 1},
            ]),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: Scaffold(body: PurchaseEntryDialog(isCredit: true)),
      ),
    ));
    await tester.pump();
    expect(find.text('الخصم'), findsNothing);
    expect(find.text('الضريبة'), findsNothing);
    expect(find.text('الوحدة *'), findsOneWidget);
    expect(find.text('قطعة'), findsWidgets);
  });
}
