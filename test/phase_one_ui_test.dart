import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:purchase_ledger/app/providers.dart';
import 'package:purchase_ledger/features/dashboard/presentation/business_directory_screen.dart';
import 'package:purchase_ledger/features/dashboard/presentation/home_shell.dart';
import 'package:purchase_ledger/features/purchases/presentation/purchase_entry_dialog.dart';

/// Creates a test application with full Arabic localization.
///
/// All widget tests use the same localization configuration,
/// ensuring that Arabic text and RTL layout are tested consistently.
Widget buildArabicTestApp(Widget home) {
  return MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: const [
      Locale('ar'),
      Locale('en'),
    ],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    debugShowCheckedModeBanner: false,
    home: home,
  );
}

void main() {
  final emptyRows = <Map<String, Object?>>[];

  // ============================================================
  // TEST 1: MAIN NAVIGATION
  // ============================================================

  testWidgets(
    'all five navigation destinations display their own content',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            branchesProvider.overrideWith(
              (ref) async => emptyRows,
            ),
            employeesProvider(null).overrideWith(
              (ref) async => emptyRows,
            ),
            purchaseCategoriesProvider.overrideWith(
              (ref) async => emptyRows,
            ),
            purchaseProductsProvider.overrideWith(
              (ref) async => emptyRows,
            ),
          ],
          child: buildArabicTestApp(
            const HomeShell(),
          ),
        ),
      );

      await tester.pump();

      final destinations = <(int, String)>[
        (1, 'الموردون'),
        (2, 'المشتريات الآجلة'),
        (3, 'المشتريات اليومية'),
        (4, 'الإعدادات'),
        (0, 'لوحة التحكم'),
      ];

      for (final entry in destinations) {
        final navigationBar = tester.widget<NavigationBar>(
          find.byType(NavigationBar),
        );

        navigationBar.onDestinationSelected!(entry.$1);

        await tester.pump();

        final updatedNavigationBar = tester.widget<NavigationBar>(
          find.byType(NavigationBar),
        );

        expect(
          updatedNavigationBar.selectedIndex,
          entry.$1,
        );

        expect(
          find.text(entry.$2),
          findsWidgets,
        );
      }
    },
  );

  // ============================================================
  // TEST 2: PRODUCT DIALOG
  // ============================================================

  testWidgets(
    'cancelling a product dialog repeatedly does not crash',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            branchesProvider.overrideWith(
              (ref) async => emptyRows,
            ),
            employeesProvider(null).overrideWith(
              (ref) async => emptyRows,
            ),
            purchaseCategoriesProvider.overrideWith(
              (ref) async => emptyRows,
            ),
            purchaseProductsProvider.overrideWith(
              (ref) async => emptyRows,
            ),
          ],
          child: buildArabicTestApp(
            const BusinessDirectoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open products tab.
      await tester.tap(
        find.text('الأصناف'),
      );

      await tester.pumpAndSettle();

      // Repeatedly open and cancel the add-product dialog.
      for (var i = 0; i < 3; i++) {
        await tester.tap(
          find.text('إضافة'),
        );

        await tester.pumpAndSettle();

        expect(
          find.text('إضافة صنف'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byType(TextFormField).first,
          'اختبار',
        );

        await tester.tap(
          find.text('إلغاء'),
        );

        await tester.pumpAndSettle();

        expect(
          find.text('إضافة صنف'),
          findsNothing,
        );

        expect(
          tester.takeException(),
          isNull,
        );
      }
    },
  );

  // ============================================================
  // TEST 3: CREDIT PURCHASE UNITS
  // ============================================================

  testWidgets(
    'credit invoice uses registered units and hides tax/discount',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessProfileProvider.overrideWith(
              (ref) async => null,
            ),
            branchesProvider.overrideWith(
              (ref) async => emptyRows,
            ),
            employeesProvider(null).overrideWith(
              (ref) async => emptyRows,
            ),
            creditMeasurementUnitsProvider.overrideWith(
              (ref) async => [
                {
                  'id': 1,
                  'name': 'قطعة',
                  'scope': 'credit',
                  'is_active': 1,
                },
                {
                  'id': 2,
                  'name': 'كرتون',
                  'scope': 'credit',
                  'is_active': 1,
                },
              ],
            ),
          ],
          child: buildArabicTestApp(
            const Scaffold(
              body: PurchaseEntryDialog(
                isCredit: true,
              ),
            ),
          ),
        ),
      );

      // Wait for the asynchronous providers and initial UI.
      await tester.pumpAndSettle();

      // Credit invoices must not display tax or discount.
      expect(
        find.text('الخصم'),
        findsNothing,
      );

      expect(
        find.text('الضريبة'),
        findsNothing,
      );

      // Credit invoice must display the registered unit field.
      expect(
        find.text('الوحدة *'),
        findsOneWidget,
      );

      // Registered measurement units must be available.
      expect(
        find.text('قطعة'),
        findsWidgets,
      );
    },
  );
}
