class InvoiceSummary {
  const InvoiceSummary({
    required this.id,
    required this.supplierId,
    required this.invoiceNumber,
    required this.supplierName,
    required this.invoiceDate,
    required this.currency,
    required this.totalMinor,
    required this.paidMinor,
    required this.returnedMinor,
    required this.dueDate,
  });

  final int id;
  final int supplierId;
  final String invoiceNumber;
  final String supplierName;
  final String invoiceDate;
  final String currency;
  final int totalMinor;
  final int paidMinor;
  final int returnedMinor;
  final String? dueDate;

  int get remainingMinor {
    final remaining = totalMinor - paidMinor - returnedMinor;
    return remaining > 0 ? remaining : 0;
  }
}

class DailyPurchaseSummary {
  const DailyPurchaseSummary({
    required this.id,
    required this.purchaseDate,
    required this.sellerName,
    required this.currency,
    required this.totalMinor,
    required this.paidMinor,
    required this.dueDate,
  });

  final int id;
  final String purchaseDate;
  final String? sellerName;
  final String currency;
  final int totalMinor;
  final int paidMinor;
  final String? dueDate;

  int get remainingMinor => totalMinor - paidMinor;
}

class CurrencyTotal {
  const CurrencyTotal({
    required this.currency,
    required this.creditPurchasesMinor,
    required this.dailyPurchasesMinor,
    required this.supplierDueMinor,
    required this.dailyDueMinor,
  });

  final String currency;
  final int creditPurchasesMinor;
  final int dailyPurchasesMinor;
  final int supplierDueMinor;
  final int dailyDueMinor;
}

class DashboardSummary {
  const DashboardSummary({
    required this.supplierCount,
    required this.invoiceCount,
    required this.overdueInvoiceCount,
    required this.dailyPurchaseCount,
    required this.totalsByCurrency,
  });

  final int supplierCount;
  final int invoiceCount;
  final int overdueInvoiceCount;
  final int dailyPurchaseCount;
  final List<CurrencyTotal> totalsByCurrency;
}
