import 'supplier.dart';

abstract interface class SupplierRepository {
  Future<List<Supplier>> getSuppliers();
  Future<int> createSupplier({
    required String name,
    String? phone,
    String? address,
    String? companyName,
    String? activityType,
    String? notes,
    required String currency,
    int openingBalanceMinor = 0,
  });
  Future<void> archiveSupplier(int supplierId);
}
