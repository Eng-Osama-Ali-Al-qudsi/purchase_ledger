import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:purchase_ledger/app/providers.dart';
import 'package:purchase_ledger/features/purchases/domain/purchase_models.dart';
import 'package:purchase_ledger/features/purchases/presentation/credit_invoices_screen.dart';

void main() {
  testWidgets('overdue dashboard destination filters settled and future invoices',
      (tester) async {
    final invoices = [
      const InvoiceSummary(
        id: 1, supplierId: 9, invoiceNumber: 'OVERDUE-001',
        supplierName: 'مورد تجريبي', invoiceDate: '2024-01-01',
        currency: 'YER', totalMinor: 10000, paidMinor: 3000,
        returnedMinor: 0, dueDate: '2024-02-01',
      ),
      const InvoiceSummary(
        id: 2, supplierId: 9, invoiceNumber: 'SETTLED-002',
        supplierName: 'مورد تجريبي', invoiceDate: '2024-01-01',
        currency: 'YER', totalMinor: 10000, paidMinor: 10000,
        returnedMinor: 0, dueDate: '2024-02-01',
      ),
      const InvoiceSummary(
        id: 3, supplierId: 9, invoiceNumber: 'FUTURE-003',
        supplierName: 'مورد تجريبي', invoiceDate: '2024-01-01',
        currency: 'YER', totalMinor: 10000, paidMinor: 0,
        returnedMinor: 0, dueDate: '2099-01-01',
      ),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        creditInvoicesProvider.overrideWith((ref) async => invoices),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        home: Scaffold(body: CreditInvoicesScreen(overdueOnly: true)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('OVERDUE-001'), findsOneWidget);
    expect(find.textContaining('SETTLED-002'), findsNothing);
    expect(find.textContaining('FUTURE-003'), findsNothing);
  });
}
