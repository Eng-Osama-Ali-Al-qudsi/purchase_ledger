import 'package:intl/intl.dart';

/// Exact money helpers. All persisted values are integer hundredths of a unit.
class Money {
  Money._();

  static int parseMinor(String input) {
    var value = input.trim();
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(arabicDigits[i], '$i');
      value = value.replaceAll(persianDigits[i], '$i');
    }
    value = value.replaceAll('٫', '.').replaceAll('٬', ',');
    value = value.replaceAll(',', '').replaceAll(' ', '');
    if (value.isEmpty) return 0;
    final match = RegExp(r'^([+-]?\d+)(?:\.(\d{0,2}))?$').firstMatch(value);
    if (match == null) {
      throw const FormatException('Invalid monetary amount');
    }
    final signedWhole = int.parse(match.group(1)!);
    final negative = match.group(1)!.startsWith('-');
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    final fractionalMinor = fraction.isEmpty ? 0 : int.parse(fraction);
    final absoluteMinor = signedWhole.abs() * 100 + fractionalMinor;
    return negative ? -absoluteMinor : absoluteMinor;
  }

  static int lineTotalMinor({
    required int quantityMilli,
    required int unitPriceMinor,
    int discountMinor = 0,
    int taxMinor = 0,
  }) {
    if (quantityMilli <= 0) throw ArgumentError('Quantity must be positive');
    if (unitPriceMinor < 0 || discountMinor < 0 || taxMinor < 0) {
      throw ArgumentError('Money values cannot be negative');
    }
    final gross = (quantityMilli * unitPriceMinor + 500) ~/ 1000;
    final total = gross - discountMinor + taxMinor;
    if (total < 0) throw ArgumentError('Line total cannot be negative');
    return total;
  }

  static String format(int minor, String currency, {String locale = 'ar'}) {
    final negative = minor < 0;
    final absolute = minor.abs();
    final whole = NumberFormat('#,##0', locale).format(absolute ~/ 100);
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$whole.$fraction $currency';
  }

  static String formatQuantity(int quantityMilli) {
    final whole = quantityMilli ~/ 1000;
    final remainder = quantityMilli % 1000;
    if (remainder == 0) return '$whole';
    final fraction =
        remainder.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$fraction';
  }
}
