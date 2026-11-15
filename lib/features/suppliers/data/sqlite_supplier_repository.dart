import '../../../core/database/app_database.dart';
import '../domain/supplier.dart';
import '../domain/supplier_repository.dart';

class SqliteSupplierRepository implements SupplierRepository {
  SqliteSupplierRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<Supplier>> getSuppliers() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT s.*,
        (SELECT COUNT(*) FROM credit_purchase_invoices i
          WHERE i.supplier_id = s.id AND i.status = 'posted') AS invoice_count
      FROM suppliers s
      WHERE s.is_archived = 0
      ORDER BY s.name COLLATE NOCASE
    ''');
    final suppliers = <Supplier>[];
    for (final row in rows) {
      final balanceRows = await db.rawQuery('''
        SELECT currency, SUM(signed_amount_minor) AS balance_minor
        FROM supplier_account_movements
        WHERE supplier_id = ?
        GROUP BY currency
        HAVING SUM(signed_amount_minor) <> 0
      ''', [row['id']]);
      final balances = <String, int>{
        for (final balance in balanceRows)
          balance['currency'] as String: balance['balance_minor'] as int,
      };
      suppliers.add(Supplier(
        id: row['id'] as int,
        name: row['name'] as String,
        phone: row['phone'] as String?,
        address: row['address'] as String?,
        companyName: row['company_name'] as String?,
        activityType: row['activity_type'] as String?,
        notes: row['notes'] as String?,
        defaultCurrency: row['default_currency'] as String,
        balancesMinorByCurrency: balances,
        invoiceCount: (row['invoice_count'] as int?) ?? 0,
      ));
    }
    return suppliers;
  }

  @override
  Future<int> createSupplier({
    required String name,
    String? phone,
    String? address,
    String? companyName,
    String? activityType,
    String? notes,
    required String currency,
    int openingBalanceMinor = 0,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Supplier name is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    return db.transaction((txn) async {
      final id = await txn.insert('suppliers', {
        'name': cleanName,
        'phone': _clean(phone),
        'address': _clean(address),
        'company_name': _clean(companyName),
        'activity_type': _clean(activityType),
        'notes': _clean(notes),
        'default_currency': currency,
        'created_at': now,
        'updated_at': now,
      });
      if (openingBalanceMinor != 0) {
        final date = now.substring(0, 10);
        await txn.insert('supplier_opening_balances', {
          'supplier_id': id,
          'currency': currency,
          'amount_minor': openingBalanceMinor.abs(),
          'balance_side': openingBalanceMinor < 0 ? 'advance' : 'due',
          'as_of_date': date,
          'created_at': now,
        });
        await txn.insert('supplier_ledger', {
          'supplier_id': id,
          'currency': currency,
          'entry_type': 'opening_balance',
          'reference_id': id,
          'entry_date': date,
          'signed_amount_minor': openingBalanceMinor,
          'note': openingBalanceMinor < 0
              ? 'Opening advance balance'
              : 'Opening balance due',
          'created_at': now,
        });
        await txn.insert('supplier_account_movements', {
          'supplier_id': id,
          'currency': currency,
          'movement_type': 'opening_balance',
          'source_type': 'opening_balance',
          'source_id': id,
          'entry_date': date,
          'signed_amount_minor': openingBalanceMinor,
          'note': openingBalanceMinor < 0
              ? 'Opening advance balance'
              : 'Opening balance due',
          'created_at': now,
        });
      }
      await txn.insert('audit_logs', {
        'action': 'create',
        'entity_type': 'supplier',
        'entity_id': id,
        'details_json':
            '{"name":"${_jsonEscape(cleanName)}","currency":"${_jsonEscape(currency)}"}',
        'created_at': now,
      });
      return id;
    });
  }

  @override
  Future<void> archiveSupplier(int supplierId) async {
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final openCurrencies = await txn.rawQuery('''
        SELECT currency FROM supplier_account_movements
        WHERE supplier_id = ?
        GROUP BY currency
        HAVING SUM(signed_amount_minor) <> 0
      ''', [supplierId]);
      if (openCurrencies.isNotEmpty) {
        throw StateError(
            'Cannot archive a supplier with an outstanding balance or advance');
      }
      await txn.update(
          'suppliers',
          {
            'is_archived': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [supplierId]);
      await txn.insert('audit_logs', {
        'action': 'archive',
        'entity_type': 'supplier',
        'entity_id': supplierId,
        'created_at': now,
      });
    });
  }

  String? _clean(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }

  String _jsonEscape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', ' ');
}
