import 'package:sqflite/sqflite.dart';

/// Additive metadata for the accounting route chosen by the operator.
/// Existing historical operations remain unchanged with NULL metadata.
class PurchaseLedgerV6Migration {
  PurchaseLedgerV6Migration._();

  static Future<void> apply(Database db) async {
    await db.execute('ALTER TABLE daily_purchase_operations '
      'ADD COLUMN recording_category TEXT');
    await db.execute('ALTER TABLE daily_purchase_operations '
      'ADD COLUMN responsible_person_name TEXT');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_daily_responsible_person '
      'ON daily_purchase_operations(responsible_person_name)');
  }
}
