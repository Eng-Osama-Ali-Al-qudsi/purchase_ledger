import '../../../core/utils/money.dart';

class PurchaseLine {
  const PurchaseLine({
    required this.description,
    required this.quantityMilli,
    required this.unitName,
    required this.unitPriceMinor,
    this.discountMinor = 0,
    this.taxMinor = 0,
    this.productId,
    this.categoryId,
    this.sellerName,
    this.notes,
    this.sourceInvoiceItemId,
    this.totalOverrideMinor,
  });

  final String description;
  final int quantityMilli;
  final String unitName;
  final int unitPriceMinor;
  final int discountMinor;
  final int taxMinor;
  final int? productId;
  final int? categoryId;
  final String? sellerName;
  final String? notes;
  final int? sourceInvoiceItemId;
  final int? totalOverrideMinor;

  int get totalMinor =>
      totalOverrideMinor ??
      Money.lineTotalMinor(
        quantityMilli: quantityMilli,
        unitPriceMinor: unitPriceMinor,
        discountMinor: discountMinor,
        taxMinor: taxMinor,
      );
}
