import 'package:flutter_test/flutter_test.dart';
import 'package:purchase_ledger/core/accounting/accounting_engine.dart';

void main() {
  group('Supplier accounting', () {
    test('three partial payments leave 550,000 YER due', () {
      final position = AccountingEngine.supplierPosition(
        creditPurchasesMinor: 100000000,
        paymentsMinor: 45000000,
      );
      expect(position.netBalanceMinor, 55000000);
      expect(position.dueToSupplierMinor, 55000000);
      expect(position.advanceAtSupplierMinor, 0);
    });

    test('advance is preserved and future invoice reduces it', () {
      final afterAdvance = AccountingEngine.supplierPosition(
        paymentsMinor: 60000000,
      );
      expect(afterAdvance.advanceAtSupplierMinor, 60000000);

      final afterFutureInvoice = AccountingEngine.supplierPosition(
        creditPurchasesMinor: 20000000,
        paymentsMinor: 60000000,
      );
      expect(afterFutureInvoice.advanceAtSupplierMinor, 40000000);
      expect(afterFutureInvoice.dueToSupplierMinor, 0);
    });

    test('positive and negative positions are described separately', () {
      final due = AccountingEngine.supplierPosition(
        openingBalanceMinor: 5000,
        creditPurchasesMinor: 7000,
        paymentsMinor: 2000,
      );
      expect(due.dueToSupplierMinor, 10000);
      expect(due.advanceAtSupplierMinor, 0);

      final advance = AccountingEngine.supplierPosition(
        paymentsMinor: 10000,
        returnsMinor: 2000,
      );
      expect(advance.dueToSupplierMinor, 0);
      expect(advance.advanceAtSupplierMinor, 12000);
    });
  });

  group('Invoice allocation', () {
    test('one payment can cover multiple invoices and retain an advance', () {
      final plan = AccountingEngine.planPaymentAllocations(
        paymentAmountMinor: 60000,
        supplierId: 7,
        currency: 'YER',
        invoices: const [
          InvoiceOpenBalance(
            invoiceId: 10,
            supplierId: 7,
            currency: 'YER',
            outstandingMinor: 20000,
          ),
          InvoiceOpenBalance(
            invoiceId: 11,
            supplierId: 7,
            currency: 'YER',
            outstandingMinor: 25000,
          ),
        ],
        requested: const [
          RequestedInvoiceAllocation(invoiceId: 10, amountMinor: 20000),
          RequestedInvoiceAllocation(invoiceId: 11, amountMinor: 25000),
        ],
      );

      expect(plan.allocatedMinor, 45000);
      expect(plan.unallocatedAdvanceMinor, 15000);
      expect(plan.allocations, {10: 20000, 11: 25000});
    });

    test('rejects allocation to another supplier or currency', () {
      expect(
        () => AccountingEngine.planPaymentAllocations(
          paymentAmountMinor: 10000,
          supplierId: 7,
          currency: 'YER',
          invoices: const [
            InvoiceOpenBalance(
              invoiceId: 10,
              supplierId: 8,
              currency: 'YER',
              outstandingMinor: 10000,
            ),
          ],
          requested: const [
            RequestedInvoiceAllocation(invoiceId: 10, amountMinor: 10000),
          ],
        ),
        throwsStateError,
      );
    });

    test('rejects allocation greater than invoice outstanding', () {
      expect(
        () => AccountingEngine.planPaymentAllocations(
          paymentAmountMinor: 30000,
          supplierId: 7,
          currency: 'YER',
          invoices: const [
            InvoiceOpenBalance(
              invoiceId: 10,
              supplierId: 7,
              currency: 'YER',
              outstandingMinor: 20000,
            ),
          ],
          requested: const [
            RequestedInvoiceAllocation(invoiceId: 10, amountMinor: 25000),
          ],
        ),
        throwsStateError,
      );
    });

    test('rejects duplicate invoice allocations', () {
      expect(
        () => AccountingEngine.planPaymentAllocations(
          paymentAmountMinor: 30000,
          supplierId: 7,
          currency: 'YER',
          invoices: const [
            InvoiceOpenBalance(
              invoiceId: 10,
              supplierId: 7,
              currency: 'YER',
              outstandingMinor: 30000,
            ),
          ],
          requested: const [
            RequestedInvoiceAllocation(invoiceId: 10, amountMinor: 10000),
            RequestedInvoiceAllocation(invoiceId: 10, amountMinor: 10000),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Daily purchases', () {
    test('computes outstanding independently from supplier account', () {
      expect(
        AccountingEngine.dailyOutstanding(
          totalMinor: 500000,
          paidAtPurchaseMinor: 100000,
          laterPaymentsMinor: 50000,
        ),
        350000,
      );
    });

    test('rejects overpayment in daily outstanding ledger', () {
      expect(
        () => AccountingEngine.dailyOutstanding(
          totalMinor: 100000,
          paidAtPurchaseMinor: 50000,
          laterPaymentsMinor: 60000,
        ),
        throwsStateError,
      );
    });
  });
}
