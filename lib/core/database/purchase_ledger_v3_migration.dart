import 'package:sqflite/sqflite.dart';

/// Additive migration for databases that already ran the first V2 release.
/// All operations are idempotent so an interrupted upgrade can be retried.
class PurchaseLedgerV3Migration {
  PurchaseLedgerV3Migration._();

  static Future<void> apply(Database db) async {
    await _addColumnIfMissing(
      db,
      'supplier_opening_balances',
      'balance_side',
      "TEXT NOT NULL DEFAULT 'due'",
    );
    await _addColumnIfMissing(
        db, 'credit_purchase_items', 'category_id', 'INTEGER');
    await _addColumnIfMissing(db, 'credit_purchase_items', 'notes', 'TEXT');
    await _addColumnIfMissing(
        db, 'daily_purchase_sheets', 'operations_snapshot_json', 'TEXT');
    await _addColumnIfMissing(db, 'daily_purchase_operations', 'status',
        "TEXT NOT NULL DEFAULT 'posted'");
    await _addColumnIfMissing(
        db, 'daily_purchase_operations', 'attachment_id', 'INTEGER');
    await _addColumnIfMissing(
        db, 'daily_purchase_operations', 'idempotency_key', 'TEXT');
    await _addColumnIfMissing(
        db, 'daily_purchase_outstanding_payments', 'attachment_id', 'INTEGER');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_operation_idempotency
      ON daily_purchase_operations(idempotency_key)
      WHERE idempotency_key IS NOT NULL
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_purchase_outstanding_adjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        outstanding_id INTEGER NOT NULL REFERENCES daily_purchase_outstandings(id) ON DELETE RESTRICT,
        adjustment_type TEXT NOT NULL CHECK (adjustment_type IN ('return','adjustment')),
        signed_delta_minor INTEGER NOT NULL CHECK (signed_delta_minor <> 0),
        adjustment_date TEXT NOT NULL,
        reason TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_daily_outstanding_adjustments
      ON daily_purchase_outstanding_adjustments(outstanding_id, adjustment_date, id)
    ''');

    await _replaceTrigger(db, 'trg_daily_outstanding_payment_validate', '''
      CREATE TRIGGER trg_daily_outstanding_payment_validate
      BEFORE INSERT ON daily_purchase_outstanding_payments
      BEGIN
        SELECT CASE WHEN NEW.amount_minor > (
          SELECT o.original_minor
            - COALESCE((
              SELECT SUM(p.amount_minor)
              FROM daily_purchase_outstanding_payments p
              WHERE p.outstanding_id = NEW.outstanding_id
            ), 0)
            + COALESCE((
              SELECT SUM(a.signed_delta_minor)
              FROM daily_purchase_outstanding_adjustments a
              WHERE a.outstanding_id = NEW.outstanding_id
            ), 0)
          FROM daily_purchase_outstandings o WHERE o.id = NEW.outstanding_id
        ) THEN RAISE(ABORT, 'Payment exceeds daily outstanding') END;
      END
    ''');

    await _replaceTrigger(db, 'trg_daily_outstanding_adjustment_validate', '''
      CREATE TRIGGER trg_daily_outstanding_adjustment_validate
      BEFORE INSERT ON daily_purchase_outstanding_adjustments
      BEGIN
        SELECT CASE WHEN (
          SELECT original_minor
            - COALESCE((SELECT SUM(amount_minor)
              FROM daily_purchase_outstanding_payments
              WHERE outstanding_id = NEW.outstanding_id),0)
            + COALESCE((SELECT SUM(signed_delta_minor)
              FROM daily_purchase_outstanding_adjustments
              WHERE outstanding_id = NEW.outstanding_id),0)
            + NEW.signed_delta_minor
          FROM daily_purchase_outstandings
          WHERE id = NEW.outstanding_id
        ) < 0 THEN RAISE(ABORT, 'Adjustment cannot make daily outstanding negative') END;
      END
    ''');

    await _replaceTrigger(db, 'trg_daily_outstanding_payments_no_update', '''
      CREATE TRIGGER trg_daily_outstanding_payments_no_update
      BEFORE UPDATE ON daily_purchase_outstanding_payments
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding payments are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_daily_outstanding_payments_no_delete', '''
      CREATE TRIGGER trg_daily_outstanding_payments_no_delete
      BEFORE DELETE ON daily_purchase_outstanding_payments
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding payments are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_daily_outstanding_adjustments_no_update', '''
      CREATE TRIGGER trg_daily_outstanding_adjustments_no_update
      BEFORE UPDATE ON daily_purchase_outstanding_adjustments
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding adjustments are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_daily_outstanding_adjustments_no_delete', '''
      CREATE TRIGGER trg_daily_outstanding_adjustments_no_delete
      BEFORE DELETE ON daily_purchase_outstanding_adjustments
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding adjustments are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_daily_sheet_events_no_update', '''
      CREATE TRIGGER trg_daily_sheet_events_no_update
      BEFORE UPDATE ON daily_purchase_sheet_events
      BEGIN SELECT RAISE(ABORT, 'Daily sheet events are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_daily_sheet_events_no_delete', '''
      CREATE TRIGGER trg_daily_sheet_events_no_delete
      BEFORE DELETE ON daily_purchase_sheet_events
      BEGIN SELECT RAISE(ABORT, 'Daily sheet events are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_supplier_payment_reversals_no_update', '''
      CREATE TRIGGER trg_supplier_payment_reversals_no_update
      BEFORE UPDATE ON supplier_payment_reversals
      BEGIN SELECT RAISE(ABORT, 'Supplier payment reversals are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_supplier_payment_reversals_no_delete', '''
      CREATE TRIGGER trg_supplier_payment_reversals_no_delete
      BEFORE DELETE ON supplier_payment_reversals
      BEGIN SELECT RAISE(ABORT, 'Supplier payment reversals are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_supplier_statement_archives_no_update', '''
      CREATE TRIGGER trg_supplier_statement_archives_no_update
      BEFORE UPDATE ON supplier_statement_archives
      BEGIN SELECT RAISE(ABORT, 'Supplier statement archives are append-only'); END
    ''');
    await _replaceTrigger(db, 'trg_supplier_statement_archives_no_delete', '''
      CREATE TRIGGER trg_supplier_statement_archives_no_delete
      BEFORE DELETE ON supplier_statement_archives
      BEGIN SELECT RAISE(ABORT, 'Supplier statement archives are append-only'); END
    ''');
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String declaration,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
  }

  static Future<void> _replaceTrigger(
    Database db,
    String name,
    String sql,
  ) async {
    await db.execute('DROP TRIGGER IF EXISTS $name');
    await db.execute(sql);
  }
}
