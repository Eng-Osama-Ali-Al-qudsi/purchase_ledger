import 'package:sqflite/sqflite.dart';

/// Additive unit catalogue. Financial line items keep their own unit_name
/// snapshots, so editing or archiving a catalogue item never rewrites history.
class PurchaseLedgerV5Migration {
  PurchaseLedgerV5Migration._();

  static Future<void> apply(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS measurement_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL CHECK (scope IN ('credit','daily')),
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
        created_at TEXT NOT NULL,
        UNIQUE(scope, name)
      )
    ''');
    final now = DateTime.now().toIso8601String();
    for (final scope in ['credit', 'daily']) {
      for (final name in ['قطعة', 'كرتون', 'سلة', 'دبة', 'كيلو']) {
        await db.insert(
          'measurement_units',
          {'scope': scope, 'name': name, 'created_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // Historical custom unit names become selectable, but no old line or
    // financial amount is updated. Migrate both legacy and current daily data.
    await db.rawInsert('''
      INSERT OR IGNORE INTO measurement_units (scope, name, created_at)
      SELECT DISTINCT 'credit', trim(unit_name), ?
      FROM credit_purchase_items
      WHERE unit_name IS NOT NULL AND trim(unit_name) <> ''
    ''', [now]);
    await db.rawInsert('''
      INSERT OR IGNORE INTO measurement_units (scope, name, created_at)
      SELECT DISTINCT 'daily', trim(unit_name), ?
      FROM cash_purchase_items
      WHERE unit_name IS NOT NULL AND trim(unit_name) <> ''
    ''', [now]);
    await db.rawInsert('''
      INSERT OR IGNORE INTO measurement_units (scope, name, created_at)
      SELECT DISTINCT 'daily', trim(unit_name), ?
      FROM daily_purchase_items
      WHERE unit_name IS NOT NULL AND trim(unit_name) <> ''
    ''', [now]);
  }
}
