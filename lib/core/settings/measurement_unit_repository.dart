import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class MeasurementUnitRepository {
  const MeasurementUnitRepository(this._database);
  final AppDatabase _database;

  void _checkScope(String scope) {
    if (scope != 'credit' && scope != 'daily') {
      throw ArgumentError('Invalid measurement unit scope');
    }
  }

  String _name(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) throw ArgumentError('Unit name is required');
    return cleaned;
  }

  Future<List<Map<String, Object?>>> getUnits(String scope) async {
    _checkScope(scope);
    final db = await _database.database;
    return db.query('measurement_units',
        where: 'scope = ? AND is_active = 1',
        whereArgs: [scope],
        orderBy: 'name COLLATE NOCASE');
  }

  Future<void> create(String scope, String name) async {
    _checkScope(scope);
    final cleaned = _name(name);
    final db = await _database.database;
    await db.transaction((txn) async {
      final previous = await txn.query('measurement_units',
          where: 'scope = ? AND name = ?', whereArgs: [scope, cleaned],
          limit: 1);
      if (previous.isNotEmpty) {
        if (previous.first['is_active'] == 1) {
          throw StateError('Unit already exists');
        }
        final id = previous.first['id'] as int;
        await txn.update('measurement_units', {'is_active': 1},
            where: 'id = ?', whereArgs: [id]);
        await _audit(txn, 'restore', id, {'scope': scope, 'name': cleaned});
      } else {
        final id = await txn.insert('measurement_units', {
          'scope': scope,
          'name': cleaned,
          'created_at': DateTime.now().toIso8601String(),
        });
        await _audit(txn, 'create', id, {'scope': scope, 'name': cleaned});
      }
    });
  }

  Future<void> rename(int id, String scope, String name) async {
    _checkScope(scope);
    final cleaned = _name(name);
    final db = await _database.database;
    await db.transaction((txn) async {
      final before = await txn.query('measurement_units',
          where: 'id = ? AND scope = ? AND is_active = 1',
          whereArgs: [id, scope],
          limit: 1);
      if (before.isEmpty) throw StateError('Unit no longer active');
      await txn.update('measurement_units', {'name': cleaned},
          where: 'id = ? AND scope = ? AND is_active = 1',
          whereArgs: [id, scope]);
      await _audit(txn, 'update', id, {
        'scope': scope, 'before': before.first['name'], 'after': cleaned,
      });
    });
  }

  Future<void> archive(int id, String scope) async {
    _checkScope(scope);
    final db = await _database.database;
    await db.transaction((txn) async {
      final before = await txn.query('measurement_units',
          where: 'id = ? AND scope = ? AND is_active = 1',
          whereArgs: [id, scope],
          limit: 1);
      if (before.isEmpty) throw StateError('Unit no longer active');
      await txn.update('measurement_units', {'is_active': 0},
          where: 'id = ? AND scope = ? AND is_active = 1',
          whereArgs: [id, scope]);
      await _audit(txn, 'archive', id, {
        'scope': scope, 'name': before.first['name'],
      });
    });
  }

  Future<void> _audit(Transaction txn, String action, int id,
      Map<String, Object?> details) async {
    await txn.insert('audit_logs', {
      'action': action,
      'entity_type': 'measurement_unit',
      'entity_id': id,
      'details_json': jsonEncode(details),
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
