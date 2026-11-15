import '../../../core/database/app_database.dart';

class BusinessProfileRepository {
  BusinessProfileRepository(this._database);
  final AppDatabase _database;

  Future<Map<String, Object?>?> getProfile() async {
    final db = await _database.database;
    final rows = await db.query('business_profiles', where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveProfile({
    required String shopName,
    String? commercialNumber,
    String? shopNumber,
    String? logoPath,
    String? ownerName,
    String? managerName,
    String? buyerName,
    String? phone,
    String? address,
    String? city,
    required String defaultCurrency,
  }) async {
    if (shopName.trim().isEmpty) throw ArgumentError('Shop name is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final values = <String, Object?>{
        'shop_name': shopName.trim(),
        'commercial_number': _clean(commercialNumber),
        'shop_number': _clean(shopNumber),
        'logo_path': _clean(logoPath),
        'owner_name': _clean(ownerName),
        'manager_name': _clean(managerName),
        'buyer_name': _clean(buyerName),
        'phone': _clean(phone),
        'address': _clean(address),
        'city': _clean(city),
        'default_currency': defaultCurrency,
        'updated_at': now,
      };
      final existing = await txn.query(
        'business_profiles',
        columns: ['id'],
        where: 'id = 1',
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('business_profiles', {
          'id': 1,
          ...values,
          'created_at': now,
        });
      } else {
        await txn.update(
          'business_profiles',
          values,
          where: 'id = 1',
        );
      }
      await txn.insert('audit_logs', {
        'action': 'save',
        'entity_type': 'business_profile',
        'entity_id': 1,
        'details_json': '{"shop_name":"${_jsonEscape(shopName.trim())}"}',
        'created_at': now,
      });
    });
  }

  String? _clean(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }

  String _jsonEscape(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
