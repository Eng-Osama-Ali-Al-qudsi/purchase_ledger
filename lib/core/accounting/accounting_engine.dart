/// Pure accounting rules shared by repositories, reports, and tests.
///
/// All money values are integer minor units. No floating-point arithmetic is
/// permitted in this layer.
class SupplierPosition {
  const SupplierPosition({
    required this.netBalanceMinor,
    required this.dueToSupplierMinor,
    required this.advanceAtSupplierMinor,
  });

  final int netBalanceMinor;
  final int dueToSupplierMinor;
  final int advanceAtSupplierMinor;

  bool get isSettled => netBalanceMinor == 0;
  bool get hasAdvance => advanceAtSupplierMinor > 0;
}

class InvoiceOpenBalance {
  const InvoiceOpenBalance({
    required this.invoiceId,
    required this.supplierId,
    required this.currency,
    required this.outstandingMinor,
  });

  final int invoiceId;
  final int supplierId;
  final String currency;
  final int outstandingMinor;
}

class RequestedInvoiceAllocation {
  const RequestedInvoiceAllocation({
    required this.invoiceId,
    required this.amountMinor,
  });

  final int invoiceId;
  final int amountMinor;
}

class PaymentAllocationPlan {
  const PaymentAllocationPlan({
    required this.allocations,
    required this.allocatedMinor,
    required this.unallocatedAdvanceMinor,
  });

  final Map<int, int> allocations;
  final int allocatedMinor;
  final int unallocatedAdvanceMinor;
}

class AccountingEngine {
  AccountingEngine._();

  /// Positive means the shop owes the supplier; negative means an advance.
  static SupplierPosition supplierPosition({
    int openingBalanceMinor = 0,
    int creditPurchasesMinor = 0,
    int linkedDailyPurchasesMinor = 0,
    int paymentsMinor = 0,
    int returnsMinor = 0,
    int signedAdjustmentsMinor = 0,
  }) {
    final inputs = [
      openingBalanceMinor,
      creditPurchasesMinor,
      linkedDailyPurchasesMinor,
      paymentsMinor,
      returnsMinor,
    ];
    if (inputs.any((value) => value < 0)) {
      throw ArgumentError('Supplier movement inputs cannot be negative');
    }
    final net = openingBalanceMinor +
        creditPurchasesMinor +
        linkedDailyPurchasesMinor +
        signedAdjustmentsMinor -
        paymentsMinor -
        returnsMinor;
    return SupplierPosition(
      netBalanceMinor: net,
      dueToSupplierMinor: net > 0 ? net : 0,
      advanceAtSupplierMinor: net < 0 ? -net : 0,
    );
  }

  static int invoiceOutstanding({
    required int invoiceTotalMinor,
    required int allocatedPaymentsMinor,
    required int returnsMinor,
  }) {
    if (invoiceTotalMinor < 0 ||
        allocatedPaymentsMinor < 0 ||
        returnsMinor < 0) {
      throw ArgumentError('Invoice amounts cannot be negative');
    }
    if (allocatedPaymentsMinor + returnsMinor > invoiceTotalMinor) {
      throw StateError('Payments and returns exceed the invoice total');
    }
    return invoiceTotalMinor - allocatedPaymentsMinor - returnsMinor;
  }

  /// Validates user-selected allocations. Any unallocated part of the payment
  /// remains an advance on the supplier account and is not discarded.
  static PaymentAllocationPlan planPaymentAllocations({
    required int paymentAmountMinor,
    required int supplierId,
    required String currency,
    required List<InvoiceOpenBalance> invoices,
    required List<RequestedInvoiceAllocation> requested,
  }) {
    if (paymentAmountMinor <= 0) {
      throw ArgumentError('Payment must be greater than zero');
    }
    final byId = <int, InvoiceOpenBalance>{
      for (final invoice in invoices) invoice.invoiceId: invoice,
    };
    final result = <int, int>{};
    var allocated = 0;
    for (final item in requested) {
      if (item.amountMinor <= 0) {
        throw ArgumentError('Allocation must be greater than zero');
      }
      if (result.containsKey(item.invoiceId)) {
        throw ArgumentError(
            'An invoice cannot be allocated twice in one payment');
      }
      final invoice = byId[item.invoiceId];
      if (invoice == null)
        throw StateError('Invoice is not available for allocation');
      if (invoice.supplierId != supplierId || invoice.currency != currency) {
        throw StateError('Supplier and currency must match the payment');
      }
      if (item.amountMinor > invoice.outstandingMinor) {
        throw StateError('Allocation exceeds invoice outstanding');
      }
      allocated += item.amountMinor;
      if (allocated > paymentAmountMinor) {
        throw StateError('Allocations exceed payment amount');
      }
      result[item.invoiceId] = item.amountMinor;
    }
    return PaymentAllocationPlan(
      allocations: Map.unmodifiable(result),
      allocatedMinor: allocated,
      unallocatedAdvanceMinor: paymentAmountMinor - allocated,
    );
  }

  static int dailyOutstanding({
    required int totalMinor,
    required int paidAtPurchaseMinor,
    required int laterPaymentsMinor,
    int approvedReturnsMinor = 0,
    int signedAdjustmentsMinor = 0,
  }) {
    if (totalMinor < 0 ||
        paidAtPurchaseMinor < 0 ||
        laterPaymentsMinor < 0 ||
        approvedReturnsMinor < 0) {
      throw ArgumentError('Daily purchase amounts cannot be negative');
    }
    if (paidAtPurchaseMinor > totalMinor) {
      throw StateError('Initial payment exceeds daily purchase total');
    }
    final result = totalMinor -
        paidAtPurchaseMinor -
        laterPaymentsMinor -
        approvedReturnsMinor +
        signedAdjustmentsMinor;
    if (result < 0) {
      throw StateError(
          'Payments and credits exceed the daily purchase balance');
    }
    return result;
  }
}
