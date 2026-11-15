import 'package:flutter_test/flutter_test.dart';

import 'package:purchase_ledger/core/utils/money.dart';

void main() {
  group('Money parsing and calculation', () {
    test('parses decimal amounts without floating point arithmetic', () {
      expect(Money.parseMinor('1234.56'), 123456);
      expect(Money.parseMinor('١٬٢٣٤٫٥٠'), 123450);
      expect(Money.parseMinor('-0.50'), -50);
    });

    test('rejects invalid monetary input', () {
      expect(() => Money.parseMinor('12.345'), throwsFormatException);
      expect(() => Money.parseMinor('abc'), throwsFormatException);
    });

    test('calculates a quantity-based line total in minor units', () {
      expect(
        Money.lineTotalMinor(
          quantityMilli: 1500,
          unitPriceMinor: 2000,
          discountMinor: 200,
          taxMinor: 100,
        ),
        2900,
      );
    });

    test('does not permit a negative line total', () {
      expect(
        () => Money.lineTotalMinor(
          quantityMilli: 1000,
          unitPriceMinor: 100,
          discountMinor: 101,
        ),
        throwsArgumentError,
      );
    });

    test('formats a negative balance without floating point conversion', () {
      expect(Money.format(-123456, 'YER', locale: 'en'), '-1,234.56 YER');
    });
  });
}
