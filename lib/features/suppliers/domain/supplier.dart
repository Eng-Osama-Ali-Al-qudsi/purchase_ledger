class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.companyName,
    required this.activityType,
    required this.notes,
    required this.defaultCurrency,
    required this.balancesMinorByCurrency,
    required this.invoiceCount,
  });

  final int id;
  final String name;
  final String? phone;
  final String? address;
  final String? companyName;
  final String? activityType;
  final String? notes;
  final String defaultCurrency;
  final Map<String, int> balancesMinorByCurrency;
  final int invoiceCount;

  int get balanceMinor => balancesMinorByCurrency[defaultCurrency] ?? 0;
}
