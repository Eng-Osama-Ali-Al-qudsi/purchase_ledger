class SupplierCurrencySummary {
  const SupplierCurrencySummary({
    required this.currency,
    required this.totalPurchasesMinor,
    required this.totalPaymentsMinor,
    required this.totalReturnsMinor,
    required this.netBalanceMinor,
    required this.dueToSupplierMinor,
    required this.advanceAtSupplierMinor,
  });

  final String currency;
  final int totalPurchasesMinor;
  final int totalPaymentsMinor;
  final int totalReturnsMinor;
  final int netBalanceMinor;
  final int dueToSupplierMinor;
  final int advanceAtSupplierMinor;
}

class SupplierMonthlyActivity {
  const SupplierMonthlyActivity({
    required this.month,
    required this.purchasesMinor,
    required this.paymentsMinor,
    required this.returnsMinor,
  });

  final String month;
  final int purchasesMinor;
  final int paymentsMinor;
  final int returnsMinor;
}

class SupplierDashboard {
  const SupplierDashboard({
    required this.supplierId,
    required this.name,
    required this.phone,
    required this.address,
    required this.companyName,
    required this.activityType,
    required this.notes,
    required this.defaultCurrency,
    required this.currencySummaries,
    required this.invoiceCount,
    required this.receivedLineCount,
    required this.receivedQuantitiesByUnit,
    required this.unpaidInvoiceCount,
    required this.partiallyPaidInvoiceCount,
    required this.paidInvoiceCount,
    required this.lastPurchaseDate,
    required this.lastPaymentDate,
    required this.monthlyActivity,
  });

  final int supplierId;
  final String name;
  final String? phone;
  final String? address;
  final String? companyName;
  final String? activityType;
  final String? notes;
  final String defaultCurrency;
  final List<SupplierCurrencySummary> currencySummaries;
  final int invoiceCount;
  final int receivedLineCount;
  final Map<String, int> receivedQuantitiesByUnit;
  final int unpaidInvoiceCount;
  final int partiallyPaidInvoiceCount;
  final int paidInvoiceCount;
  final String? lastPurchaseDate;
  final String? lastPaymentDate;
  final List<SupplierMonthlyActivity> monthlyActivity;
}

class SupplierInvoiceBalance {
  const SupplierInvoiceBalance({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.currency,
    required this.totalMinor,
    required this.allocatedMinor,
    required this.returnedMinor,
    required this.outstandingMinor,
    required this.dueDate,
  });

  final int id;
  final String invoiceNumber;
  final String invoiceDate;
  final String currency;
  final int totalMinor;
  final int allocatedMinor;
  final int returnedMinor;
  final int outstandingMinor;
  final String? dueDate;

  String get status {
    if (outstandingMinor == 0) return 'paid';
    if (allocatedMinor > 0 || returnedMinor > 0) return 'partial';
    return 'unpaid';
  }
}

class SupplierAdvance {
  const SupplierAdvance({
    required this.paymentId,
    required this.receiptNumber,
    required this.paymentDate,
    required this.currency,
    required this.amountMinor,
    required this.allocatedMinor,
    required this.remainingMinor,
  });

  final int paymentId;
  final String? receiptNumber;
  final String paymentDate;
  final String currency;
  final int amountMinor;
  final int allocatedMinor;
  final int remainingMinor;
}

class SupplierStatementMovement {
  const SupplierStatementMovement({
    required this.id,
    required this.entryDate,
    required this.documentNumber,
    required this.movementType,
    required this.details,
    required this.signedAmountMinor,
    required this.runningBalanceMinor,
  });

  final int id;
  final String entryDate;
  final String documentNumber;
  final String movementType;
  final String details;
  final int signedAmountMinor;
  final int runningBalanceMinor;
}

class SupplierStatement {
  const SupplierStatement({
    required this.supplierId,
    required this.supplierName,
    required this.supplierPhone,
    required this.supplierAddress,
    required this.currency,
    required this.periodFrom,
    required this.periodTo,
    required this.openingBalanceMinor,
    required this.movements,
    required this.closingBalanceMinor,
    required this.totalPurchasesMinor,
    required this.totalPaymentsMinor,
    required this.totalReturnsMinor,
    required this.totalAdjustmentsMinor,
  });

  final int supplierId;
  final String supplierName;
  final String? supplierPhone;
  final String? supplierAddress;
  final String currency;
  final String? periodFrom;
  final String? periodTo;
  final int openingBalanceMinor;
  final List<SupplierStatementMovement> movements;
  final int closingBalanceMinor;
  final int totalPurchasesMinor;
  final int totalPaymentsMinor;
  final int totalReturnsMinor;
  final int totalAdjustmentsMinor;
}

class SupplierPaymentRecord {
  const SupplierPaymentRecord({
    required this.id,
    required this.receiptNumber,
    required this.paymentDate,
    required this.amountMinor,
    required this.currency,
    required this.method,
    required this.allocatedMinor,
    required this.isReversed,
    required this.notes,
  });

  final int id;
  final String? receiptNumber;
  final String paymentDate;
  final int amountMinor;
  final String currency;
  final String method;
  final int allocatedMinor;
  final bool isReversed;
  final String? notes;

  int get unallocatedMinor => isReversed ? 0 : amountMinor - allocatedMinor;
}

class SupplierInvoiceItemDetail {
  const SupplierInvoiceItemDetail({
    required this.id,
    required this.description,
    required this.quantityMilli,
    required this.unitName,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.lineTotalMinor,
    required this.returnedQuantityMilli,
    required this.returnedAmountMinor,
  });

  final int id;
  final String description;
  final int quantityMilli;
  final String unitName;
  final int unitPriceMinor;
  final int discountMinor;
  final int taxMinor;
  final int lineTotalMinor;
  final int returnedQuantityMilli;
  final int returnedAmountMinor;

  int get remainingQuantityMilli => quantityMilli - returnedQuantityMilli;
  int get remainingAmountMinor => lineTotalMinor - returnedAmountMinor;
}

class SupplierInvoiceDetail {
  const SupplierInvoiceDetail({
    required this.id,
    required this.supplierId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.currency,
    required this.totalMinor,
    required this.unlinkedReturnAmountMinor,
    required this.items,
  });

  final int id;
  final int supplierId;
  final String invoiceNumber;
  final String invoiceDate;
  final String currency;
  final int totalMinor;
  final int unlinkedReturnAmountMinor;
  final List<SupplierInvoiceItemDetail> items;
}
