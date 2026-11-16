import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchase_ledger/features/dashboard/presentation/about_developer_screen.dart';
import 'package:purchase_ledger/features/suppliers/domain/supplier_accounting_models.dart';

Widget developerPage(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AboutDeveloperScreen(),
    );

void main() {
  testWidgets('developer page follows English language', (tester) async {
    await tester.pumpWidget(developerPage(const Locale('en')));
    expect(find.text('About the Developer'), findsOneWidget);
    expect(find.text('Eng. Osama Ali Al-Qudsi'), findsOneWidget);
    expect(find.text('Application Developer'), findsOneWidget);
    expect(find.textContaining('Software Engineer'), findsOneWidget);
  });

  testWidgets('developer page follows Arabic language', (tester) async {
    await tester.pumpWidget(developerPage(const Locale('ar')));
    expect(find.text('عن المطور'), findsOneWidget);
    expect(find.text('المهندس أسامة علي القدسي'), findsOneWidget);
    expect(find.text('مطور التطبيق'), findsOneWidget);
  });

  test('invoice status derives from effective allocations and returns', () {
    SupplierInvoiceBalance invoice(int allocated, int returned) =>
        SupplierInvoiceBalance(
          id: 1,
          invoiceNumber: 'INV-01',
          invoiceDate: '2026-11-15',
          currency: 'YER',
          totalMinor: 10000,
          allocatedMinor: allocated,
          returnedMinor: returned,
          outstandingMinor: 10000 - allocated - returned,
          dueDate: null,
        );

    expect(invoice(0, 0).status, 'unpaid');
    expect(invoice(3000, 0).status, 'partial');
    expect(invoice(3000, 7000).status, 'paid');
  });
}
