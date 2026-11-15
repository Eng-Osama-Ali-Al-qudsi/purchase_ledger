import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class BusinessDirectoryRepository {
  BusinessDirectoryRepository(this._database);
  final AppDatabase _database;

  Future<List<Map<String, Object?>>> getBranches() async {
    final db = await _database.database;
    return db.query(
      'branches',
      where: 'is_active = 1',
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getEmployees({int? branchId}) async {
    final db = await _database.database;
    return db.query(
      'employees',
      where: branchId == null
          ? 'is_active = 1'
          : 'is_active = 1 AND (branch_id = ? OR branch_id IS NULL)',
      whereArgs: branchId == null ? null : [branchId],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getCategories(
      {String? categoryType}) async {
    final db = await _database.database;
    return db.query(
      'purchase_categories',
      where: categoryType == null
          ? 'is_active = 1'
          : 'is_active = 1 AND category_type IN (?, ?)',
      whereArgs: categoryType == null ? null : [categoryType, 'both'],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<int> createCategory({
    required String name,
    required String categoryType,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Category name is required');
    if (!['credit', 'daily', 'both'].contains(categoryType)) {
      throw ArgumentError('Invalid category type');
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      final archived = await txn.query('purchase_categories',
          where: 'name = ? AND category_type = ? AND is_active = 0',
          whereArgs: [clean, categoryType],
          limit: 1);
      if (archived.isNotEmpty) {
        final id = archived.first['id'] as int;
        await txn.update('purchase_categories', {'is_active': 1},
            where: 'id = ?', whereArgs: [id]);
        await _audit(txn, 'restore', 'category', id,
            {'name': clean, 'category_type': categoryType});
        return id;
      }
      final id = await txn.insert('purchase_categories', {
        'name': clean,
        'category_type': categoryType,
        'is_active': 1,
      });
      await _audit(txn, 'create', 'category', id,
          {'name': clean, 'category_type': categoryType});
      return id;
    });
  }

  Future<List<Map<String, Object?>>> getProducts() async {
    final db = await _database.database;
    return db.rawQuery('''
      SELECT p.*, c.name AS category_name
      FROM products p
      LEFT JOIN purchase_categories c ON c.id = p.category_id
      WHERE p.is_active = 1
      ORDER BY p.name COLLATE NOCASE
    ''');
  }

  Future<int> createProduct({
    required String name,
    String? sku,
    int? categoryId,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Product name is required');
    final db = await _database.database;
    return db.transaction((txn) async {
      final cleanSku = _clean(sku);
      if (cleanSku != null) {
        final archived = await txn.query('products',
            where: 'sku = ? AND is_active = 0',
            whereArgs: [cleanSku],
            limit: 1);
        if (archived.isNotEmpty) {
          final id = archived.first['id'] as int;
          await txn.update('products', {
            'name': clean, 'category_id': categoryId, 'is_active': 1,
          }, where: 'id = ?', whereArgs: [id]);
          await _audit(txn, 'restore', 'product', id,
              {'name': clean, 'sku': cleanSku, 'category_id': categoryId});
          return id;
        }
      }
      final id = await txn.insert('products', {
        'name': clean,
        'sku': cleanSku,
        'category_id': categoryId,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _audit(txn, 'create', 'product', id,
          {'name': clean, 'sku': cleanSku, 'category_id': categoryId});
      return id;
    });
  }

  Future<int> createBranch({
    required String name,
    String? code,
    String? address,
    String? phone,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Branch name is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    return db.transaction((txn) async {
      final id = await txn.insert('branches', {
        'name': clean,
        'code': _clean(code),
        'address': _clean(address),
        'phone': _clean(phone),
        'created_at': now,
      });
      await txn.insert('audit_logs', {
        'action': 'create',
        'entity_type': 'branch',
        'entity_id': id,
        'details_json': '{"name":"${_escape(clean)}"}',
        'created_at': now,
      });
      return id;
    });
  }

  Future<int> createEmployee({
    required String name,
    int? branchId,
    String? phone,
    String? role,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Employee name is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    return db.transaction((txn) async {
      final id = await txn.insert('employees', {
        'name': clean,
        'branch_id': branchId,
        'phone': _clean(phone),
        'role': _clean(role),
        'created_at': now,
      });
      await txn.insert('audit_logs', {
        'action': 'create',
        'entity_type': 'employee',
        'entity_id': id,
        'details_json': '{"name":"${_escape(clean)}"}',
        'created_at': now,
      });
      return id;
    });
  }

  /// Edits directory metadata only; historical invoices and sheets keep their
  /// original foreign keys and immutable financial snapshots.
  Future<void> updateBranch({
    required int id,
    required String name,
    String? code,
    String? address,
    String? phone,
  }) => _update('branches', 'branch', id, {
        'name': _requiredName(name),
        'code': _clean(code),
        'address': _clean(address),
        'phone': _clean(phone),
      });

  Future<void> updateEmployee({
    required int id,
    required String name,
    int? branchId,
    String? phone,
    String? role,
  }) => _update('employees', 'employee', id, {
        'name': _requiredName(name),
        'branch_id': branchId,
        'phone': _clean(phone),
        'role': _clean(role),
      });

  Future<void> updateCategory({
    required int id,
    required String name,
    required String categoryType,
  }) {
    if (!['credit', 'daily', 'both'].contains(categoryType)) {
      throw ArgumentError('Invalid category type');
    }
    return _update('purchase_categories', 'category', id, {
      'name': _requiredName(name),
      'category_type': categoryType,
    });
  }

  Future<void> updateProduct({
    required int id,
    required String name,
    String? sku,
    int? categoryId,
  }) => _update('products', 'product', id, {
        'name': _requiredName(name),
        'sku': _clean(sku),
        'category_id': categoryId,
      });

  /// Always archives instead of deleting. In particular, product/branch IDs
  /// referenced by old financial records must never disappear.
  Future<void> archiveRecord({
    required String kind,
    required int id,
  }) async {
    const tables = {
      'branch': 'branches',
      'employee': 'employees',
      'category': 'purchase_categories',
      'product': 'products',
    };
    final table = tables[kind];
    if (table == null) throw ArgumentError('Unknown directory entity');
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query(table,
          where: 'id = ? AND is_active = 1', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('Record no longer active');
      final changed = await txn.update(table, {'is_active': 0},
          where: 'id = ? AND is_active = 1', whereArgs: [id]);
      if (changed != 1) throw StateError('Could not archive record');
      await _audit(txn, 'archive', kind, id, {'before': rows.first});
    });
  }

  Future<void> _update(String table, String kind, int id,
      Map<String, Object?> values) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query(table,
          where: 'id = ? AND is_active = 1', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('Record no longer active');
      final changed = await txn.update(table, values,
          where: 'id = ? AND is_active = 1', whereArgs: [id]);
      if (changed != 1) throw StateError('Could not update record');
      await _audit(txn, 'update', kind, id,
          {'before': rows.first, 'changes': values});
    });
  }

  Future<void> _audit(Transaction txn, String action, String kind, int id,
      Map<String, Object?> details) async {
    await txn.insert('audit_logs', {
      'action': action,
      'entity_type': kind,
      'entity_id': id,
      'details_json': jsonEncode(details),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  String _requiredName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) throw ArgumentError('Name is required');
    return clean;
  }

  String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', ' ');
}
