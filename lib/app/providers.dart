import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/settings/measurement_unit_repository.dart';
import '../features/dashboard/data/business_profile_repository.dart';
import '../features/dashboard/data/business_directory_repository.dart';
import '../features/purchases/data/sqlite_purchase_repository.dart';
import '../features/purchases/data/daily_purchases_repository.dart';
import '../features/purchases/domain/daily_sheet_models.dart';
import '../features/purchases/domain/purchase_models.dart';
import '../features/purchases/domain/purchase_repository.dart';
import '../features/suppliers/data/sqlite_supplier_repository.dart';
import '../features/suppliers/data/supplier_accounting_repository.dart';
import '../features/suppliers/domain/supplier_accounting_models.dart';
import '../features/suppliers/domain/supplier.dart';
import '../features/suppliers/domain/supplier_repository.dart';

final appDatabaseProvider =
    Provider<AppDatabase>((ref) => AppDatabase.instance);

final supplierRepositoryProvider = Provider<SupplierRepository>(
  (ref) => SqliteSupplierRepository(ref.watch(appDatabaseProvider)),
);

final purchaseRepositoryProvider = Provider<PurchaseRepository>(
  (ref) => SqlitePurchaseRepository(ref.watch(appDatabaseProvider)),
);

final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>(
  (ref) => ref.watch(supplierRepositoryProvider).getSuppliers(),
);

final creditInvoicesProvider = FutureProvider.autoDispose<List<InvoiceSummary>>(
  (ref) => ref.watch(purchaseRepositoryProvider).getCreditInvoices(),
);

final dailyPurchasesProvider =
    FutureProvider.autoDispose<List<DailyPurchaseSummary>>(
  (ref) => ref.watch(purchaseRepositoryProvider).getDailyPurchases(),
);

final dashboardProvider = FutureProvider.autoDispose<DashboardSummary>(
  (ref) => ref.watch(purchaseRepositoryProvider).getDashboardSummary(),
);

final businessProfileRepositoryProvider = Provider<BusinessProfileRepository>(
  (ref) => BusinessProfileRepository(ref.watch(appDatabaseProvider)),
);

final businessProfileProvider =
    FutureProvider.autoDispose<Map<String, Object?>?>(
  (ref) => ref.watch(businessProfileRepositoryProvider).getProfile(),
);

final supplierAccountingRepositoryProvider =
    Provider<SupplierAccountingRepository>(
  (ref) => SupplierAccountingRepository(ref.watch(appDatabaseProvider)),
);

final supplierDashboardProvider =
    FutureProvider.autoDispose.family<SupplierDashboard, int>(
  (ref, supplierId) =>
      ref.watch(supplierAccountingRepositoryProvider).getDashboard(supplierId),
);

final supplierInvoicesProvider =
    FutureProvider.autoDispose.family<List<SupplierInvoiceBalance>, int>(
  (ref, supplierId) =>
      ref.watch(supplierAccountingRepositoryProvider).getInvoices(supplierId),
);

final supplierAdvancesProvider =
    FutureProvider.autoDispose.family<List<SupplierAdvance>, int>(
  (ref, supplierId) => ref
      .watch(supplierAccountingRepositoryProvider)
      .getUnallocatedAdvances(supplierId),
);

final supplierPaymentsProvider =
    FutureProvider.autoDispose.family<List<SupplierPaymentRecord>, int>(
  (ref, supplierId) =>
      ref.watch(supplierAccountingRepositoryProvider).getPayments(supplierId),
);

final dailyPurchasesRepositoryProvider = Provider<DailyPurchasesRepository>(
  (ref) => DailyPurchasesRepository(ref.watch(appDatabaseProvider)),
);

final dailySheetsProvider = FutureProvider.autoDispose<List<DailySheetSummary>>(
  (ref) => ref.watch(dailyPurchasesRepositoryProvider).getSheets(),
);

final dailySheetDetailProvider =
    FutureProvider.autoDispose.family<DailySheetDetail, int>(
  (ref, sheetId) =>
      ref.watch(dailyPurchasesRepositoryProvider).getSheetDetail(sheetId),
);

final businessDirectoryRepositoryProvider =
    Provider<BusinessDirectoryRepository>(
  (ref) => BusinessDirectoryRepository(ref.watch(appDatabaseProvider)),
);

final branchesProvider = FutureProvider.autoDispose<List<Map<String, Object?>>>(
  (ref) => ref.watch(businessDirectoryRepositoryProvider).getBranches(),
);

final employeesProvider =
    FutureProvider.autoDispose.family<List<Map<String, Object?>>, int?>(
  (ref, branchId) => ref
      .watch(businessDirectoryRepositoryProvider)
      .getEmployees(branchId: branchId),
);

final dailyPurchaseCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>(
  (ref) => ref
      .watch(businessDirectoryRepositoryProvider)
      .getCategories(categoryType: 'daily'),
);

final purchaseProductsProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>(
  (ref) => ref.watch(businessDirectoryRepositoryProvider).getProducts(),
);

final purchaseCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>(
  (ref) => ref.watch(businessDirectoryRepositoryProvider).getCategories(),
);

final measurementUnitRepositoryProvider = Provider<MeasurementUnitRepository>(
  (ref) => MeasurementUnitRepository(ref.watch(appDatabaseProvider)),
);

final creditMeasurementUnitsProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>(
  (ref) => ref.watch(measurementUnitRepositoryProvider).getUnits('credit'),
);

final dailyMeasurementUnitsProvider =
    FutureProvider.autoDispose<List<Map<String, Object?>>>(
  (ref) => ref.watch(measurementUnitRepositoryProvider).getUnits('daily'),
);

final dailyOutstandingRecordsProvider =
    FutureProvider.autoDispose<List<DailyOutstandingRecord>>(
  (ref) => ref.watch(dailyPurchasesRepositoryProvider).getOutstandingRecords(),
);

final dailyOutstandingHistoryProvider =
    FutureProvider.autoDispose.family<List<DailyOutstandingHistoryEntry>, int>(
  (ref, outstandingId) => ref
      .watch(dailyPurchasesRepositoryProvider)
      .getOutstandingHistory(outstandingId),
);
