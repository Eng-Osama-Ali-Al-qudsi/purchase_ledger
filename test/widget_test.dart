import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:purchase_ledger/app/providers.dart';
import 'package:purchase_ledger/app/purchase_ledger_app.dart';

void main() {
  testWidgets('shows first-run business setup when no profile exists',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessProfileProvider.overrideWith(
            (ref) => Future<Map<String, Object?>?>.value(null),
          ),
        ],
        child: const PurchaseLedgerApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('مرحباً بك في دفتر المشتريات'), findsOneWidget);
    expect(find.text('إعداد بيانات المحل'), findsOneWidget);
  });
}
