class DailySheetCurrencyTotal {
  const DailySheetCurrencyTotal({
    required this.currency,
    required this.totalMinor,
    required this.cashMinor,
    required this.creditMinor,
    required this.paidMinor,
    required this.outstandingMinor,
    required this.supplierAccountCreditMinor,
  });

  final String currency;
  final int totalMinor;
  final int cashMinor;
  final int creditMinor;
  final int paidMinor;
  final int outstandingMinor;
  final int supplierAccountCreditMinor;
}

class DailySheetSummary {
  const DailySheetSummary({
    required this.id,
    required this.sheetNumber,
    required this.purchaseDate,
    required this.branchName,
    required this.employeeName,
    required this.status,
    required this.operationCount,
    required this.itemCount,
    required this.totalsByCurrency,
  });

  final int id;
  final String sheetNumber;
  final String purchaseDate;
  final String? branchName;
  final String? employeeName;
  final String status;
  final int operationCount;
  final int itemCount;
  final List<DailySheetCurrencyTotal> totalsByCurrency;
}

class DailyPurchaseItem {
  const DailyPurchaseItem({
    required this.id,
    required this.productId,
    required this.categoryId,
    this.categoryName,
    required this.itemName,
    required this.quantityMilli,
    required this.unitName,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.lineTotalMinor,
    required this.sellerName,
    required this.notes,
  });

  final int id;
  final int? productId;
  final int? categoryId;
  final String? categoryName;
  final String itemName;
  final int quantityMilli;
  final String unitName;
  final int unitPriceMinor;
  final int discountMinor;
  final int taxMinor;
  final int lineTotalMinor;
  final String? sellerName;
  final String? notes;
}

class DailyPurchaseOperation {
  const DailyPurchaseOperation({
    required this.id,
    required this.operationNumber,
    required this.supplierId,
    required this.supplierName,
    required this.accountingMode,
    required this.outstandingId,
    required this.sellerName,
    this.recordingCategory,
    this.responsiblePersonName,
    this.responsiblePersonId,
    required this.currency,
    required this.paymentMethod,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.laterPaidMinor,
    required this.outstandingMinor,
    required this.supplierAccountCreditMinor,
    required this.dueDate,
    required this.status,
    required this.notes,
    required this.items,
  });

  final int id;
  final String operationNumber;
  final int? supplierId;
  final String? supplierName;
  final String accountingMode;
  final int? outstandingId;
  final String? sellerName;
  final String? recordingCategory;
  final String? responsiblePersonName;
  final int? responsiblePersonId;
  final String currency;
  final String paymentMethod;
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int totalMinor;
  final int amountPaidMinor;
  final int laterPaidMinor;
  final int outstandingMinor;
  final int supplierAccountCreditMinor;
  final String? dueDate;
  final String status;
  final String? notes;
  final List<DailyPurchaseItem> items;

  bool get isSupplierAccount => accountingMode == 'supplier_account';
}

class DailySheetDetail {
  const DailySheetDetail({
    required this.id,
    required this.sheetNumber,
    required this.purchaseDate,
    required this.branchId,
    required this.branchName,
    required this.employeeId,
    required this.employeeName,
    required this.notes,
    required this.status,
    required this.handedOverAt,
    required this.closedAt,
    required this.headerSnapshotJson,
    required this.totalsSnapshotJson,
    required this.operationsSnapshotJson,
    required this.operations,
    required this.hasOperationHistory,
    this.canEditIdentity = false,
    required this.amendmentCount,
  });

  final int id;
  final String sheetNumber;
  final String purchaseDate;
  final int? branchId;
  final String? branchName;
  final int? employeeId;
  final String? employeeName;
  final String? notes;
  final String status;
  final String? handedOverAt;
  final String? closedAt;
  final String? headerSnapshotJson;
  final String? totalsSnapshotJson;
  final String? operationsSnapshotJson;
  final List<DailyPurchaseOperation> operations;
  final bool hasOperationHistory;
  final bool canEditIdentity;
  final int amendmentCount;

  bool get isEditable => status == 'DRAFT';
  bool get canHandOver => status == 'READY_FOR_HANDOVER';
}

class DailySheetAmendment {
  const DailySheetAmendment({
    required this.id,
    required this.amendmentNumber,
    required this.reason,
    required this.details,
    required this.currency,
    required this.amountDeltaMinor,
    required this.createdAt,
  });

  final int id;
  final String amendmentNumber;
  final String reason;
  final String details;
  final String? currency;
  final int amountDeltaMinor;
  final String createdAt;
}

class DailyHandoverReport {
  const DailyHandoverReport({
    required this.sheet,
    required this.shopName,
    required this.shopLogoPath,
    required this.shopNumber,
    required this.shopAddress,
    required this.shopPhone,
    required this.managerName,
    required this.buyerName,
    required this.branchName,
    required this.branchCode,
    required this.totalsByCurrency,
    required this.amendments,
  });

  final DailySheetDetail sheet;
  final String shopName;
  final String? shopLogoPath;
  final String? shopNumber;
  final String? shopAddress;
  final String? shopPhone;
  final String? managerName;
  final String? buyerName;
  final String? branchName;
  final String? branchCode;
  final List<DailySheetCurrencyTotal> totalsByCurrency;
  final List<DailySheetAmendment> amendments;
}

class DailySheetEvent {
  const DailySheetEvent({
    required this.id,
    required this.eventType,
    required this.fromStatus,
    required this.toStatus,
    required this.detailsJson,
    required this.createdAt,
  });

  final int id;
  final String eventType;
  final String? fromStatus;
  final String? toStatus;
  final String? detailsJson;
  final String createdAt;
}

class DailyOutstandingRecord {
  const DailyOutstandingRecord({
    required this.id,
    required this.operationId,
    required this.operationNumber,
    required this.sheetId,
    required this.sheetNumber,
    required this.purchaseDate,
    required this.dueDate,
    required this.branchName,
    required this.employeeName,
    required this.sellerName,
    this.responsiblePersonId,
    required this.currency,
    required this.originalMinor,
    required this.paidMinor,
    required this.adjustmentDeltaMinor,
    required this.remainingMinor,
    required this.status,
  });

  final int id;
  final int operationId;
  final String operationNumber;
  final int sheetId;
  final String sheetNumber;
  final String purchaseDate;
  final String? dueDate;
  final String? branchName;
  final String? employeeName;
  final String? sellerName;
  final int? responsiblePersonId;
  final String currency;
  final int originalMinor;
  final int paidMinor;
  final int adjustmentDeltaMinor;
  final int remainingMinor;
  final String status;
}

class DailyOutstandingHistoryEntry {
  const DailyOutstandingHistoryEntry({
    required this.id,
    required this.entryDate,
    required this.entryType,
    required this.amountMinor,
    required this.method,
    required this.reference,
    required this.reason,
  });

  final int id;
  final String entryDate;
  final String entryType;
  final int amountMinor;
  final String? method;
  final String? reference;
  final String? reason;
}
