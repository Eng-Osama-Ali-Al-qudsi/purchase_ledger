import '../../../core/attachments/attachment_service.dart';
import 'purchase_line.dart';
import 'purchase_models.dart';

abstract interface class PurchaseRepository {
  Future<List<InvoiceSummary>> getCreditInvoices();
  Future<List<DailyPurchaseSummary>> getDailyPurchases();
  Future<int> createCreditInvoice({
    required int supplierId,
    required String invoiceNumber,
    required String invoiceDate,
    String? dueDate,
    required String currency,
    required List<PurchaseLine> lines,
    int paidMinor = 0,
    String initialPaymentMethod = 'cash',
    String? notes,
    int? branchId,
    int? employeeId,
    String? receivedAt,
    AttachmentDraft? attachment,
  });
  Future<int> recordPurchaseReturn({
    required int supplierId,
    required int invoiceId,
    required String returnNumber,
    required String returnDate,
    required String currency,
    required List<PurchaseLine> lines,
    String? notes,
  });
  Future<int> recordSupplierPayment({
    required int supplierId,
    required int amountMinor,
    required String currency,
    required String paymentDate,
    required String method,
    int? invoiceId,
    String? receiptNumber,
    String? notes,
    String? idempotencyKey,
    AttachmentDraft? attachment,
    bool allowAdvance = false,
    int? expectedDueMinor,
  });
  Future<int> createDailyPurchase({
    required String purchaseDate,
    String? sellerName,
    required String currency,
    required List<PurchaseLine> lines,
    int paidMinor = 0,
    String paymentMethod = 'cash',
    String? dueDate,
    String? notes,
  });
  Future<void> recordDailyPurchasePayment({
    required int purchaseId,
    required int amountMinor,
    required String paymentDate,
    required String method,
    String? notes,
  });
  Future<DashboardSummary> getDashboardSummary();
}
