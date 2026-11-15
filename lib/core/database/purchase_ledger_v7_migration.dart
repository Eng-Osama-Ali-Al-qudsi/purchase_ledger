import 'package:sqflite/sqflite.dart';

/// V7 is additive: person accounts receive a stable foreign key and invoices
/// may transition from posted to void only after a matching audited reversal.
/// Financial columns and historical item rows stay immutable.
class PurchaseLedgerV7Migration {
  PurchaseLedgerV7Migration._();

  static Future<void> apply(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS responsible_people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE
          CHECK (length(trim(name)) > 0),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        created_at TEXT NOT NULL
      )
    ''');
    final fields = (await db.rawQuery(
      'PRAGMA table_info(daily_purchase_operations)',
    )).map((row) => row['name'] as String).toSet();
    if (!fields.contains('responsible_person_id')) {
      await db.execute('''
        ALTER TABLE daily_purchase_operations
        ADD COLUMN responsible_person_id INTEGER
          REFERENCES responsible_people(id) ON DELETE RESTRICT
      ''');
    }
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_daily_responsible_person_id
      ON daily_purchase_operations(responsible_person_id)
    ''');
    // New draft corrections are explicitly linked to their source operation.
    // Older V2-V6 adjustments lacked an operation_id and cannot be associated
    // safely just by their human-readable OP-001 label.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_operation_adjustment_movements (
        operation_id INTEGER NOT NULL
          REFERENCES daily_purchase_operations(id) ON DELETE RESTRICT,
        movement_id INTEGER NOT NULL UNIQUE
          REFERENCES supplier_account_movements(id) ON DELETE RESTRICT,
        created_at TEXT NOT NULL,
        PRIMARY KEY (operation_id, movement_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_daily_operation_adjustment_source
      ON daily_operation_adjustment_movements(operation_id)
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_adjustment_link_no_update
      BEFORE UPDATE ON daily_operation_adjustment_movements
      BEGIN SELECT RAISE(ABORT, 'Daily adjustment links are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_adjustment_link_no_delete
      BEFORE DELETE ON daily_operation_adjustment_movements
      BEGIN SELECT RAISE(ABORT, 'Daily adjustment links are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_person_account_insert
      BEFORE INSERT ON daily_purchase_operations
      WHEN (NEW.recording_category = 'person' AND (
            NEW.responsible_person_id IS NULL OR
            NEW.accounting_mode <> 'daily_outstanding' OR
            NEW.supplier_id IS NOT NULL))
        OR (NEW.responsible_person_id IS NOT NULL AND
            NEW.recording_category IS NOT 'person')
      BEGIN
        SELECT RAISE(ABORT, 'Invalid person account responsibility');
      END
    ''');
    // A draft operation can be edited, but its person/supplier classification
    // must never be converted into a contradictory dual liability.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_person_account_update
      BEFORE UPDATE OF responsible_person_id, recording_category,
        accounting_mode, supplier_id ON daily_purchase_operations
      WHEN (NEW.recording_category = 'person' AND (
            NEW.responsible_person_id IS NULL OR
            NEW.accounting_mode <> 'daily_outstanding' OR
            NEW.supplier_id IS NOT NULL))
        OR (NEW.responsible_person_id IS NOT NULL AND
            NEW.recording_category IS NOT 'person')
      BEGIN
        SELECT RAISE(ABORT, 'Invalid person account responsibility');
      END
    ''');

    // V4 rejected ALL status transitions, including a correctly compensated
    // cancellation. Preserve every V4 immutable field rule; narrowly allow
    // posted -> void only after an exact reversal and no active dependencies.
    await db.execute('DROP TRIGGER IF EXISTS trg_credit_invoice_financial_fields_immutable');
    await db.execute('''
      CREATE TRIGGER trg_credit_invoice_financial_fields_immutable
      BEFORE UPDATE ON credit_purchase_invoices
      WHEN NEW.id IS NOT OLD.id
        OR NEW.supplier_id IS NOT OLD.supplier_id
        OR NEW.branch_id IS NOT OLD.branch_id
        OR NEW.employee_id IS NOT OLD.employee_id
        OR NEW.invoice_number IS NOT OLD.invoice_number
        OR NEW.invoice_date IS NOT OLD.invoice_date
        OR NEW.due_date IS NOT OLD.due_date
        OR NEW.currency IS NOT OLD.currency
        OR NEW.subtotal_minor IS NOT OLD.subtotal_minor
        OR NEW.discount_minor IS NOT OLD.discount_minor
        OR NEW.tax_minor IS NOT OLD.tax_minor
        OR NEW.total_minor IS NOT OLD.total_minor
        OR NEW.notes IS NOT OLD.notes
        OR NEW.received_at IS NOT OLD.received_at
        OR NEW.created_at IS NOT OLD.created_at
        OR (NEW.status IS NOT OLD.status AND NOT (
          OLD.status = 'posted' AND NEW.status = 'void'
          AND EXISTS (
            SELECT 1 FROM supplier_account_movements reversal
            JOIN supplier_account_movements original
              ON original.id = reversal.reverses_movement_id
            WHERE original.source_type = 'credit_invoice'
              AND original.source_id = OLD.id
              AND original.movement_type = 'credit_invoice'
              AND original.supplier_id = OLD.supplier_id
              AND original.currency = OLD.currency
              AND original.signed_amount_minor = OLD.total_minor
              AND reversal.source_type = 'credit_invoice_void'
              AND reversal.source_id = OLD.id
              AND reversal.movement_type = 'reversal'
              AND reversal.supplier_id = original.supplier_id
              AND reversal.currency = original.currency
              AND reversal.signed_amount_minor = -original.signed_amount_minor
          )
          AND NOT EXISTS (
            SELECT 1 FROM payment_allocations allocation
            JOIN supplier_payments payment ON payment.id = allocation.payment_id
            LEFT JOIN supplier_payment_reversals refund
              ON refund.payment_id = payment.id
            WHERE allocation.invoice_id = OLD.id AND refund.id IS NULL
          )
          AND NOT EXISTS (
            SELECT 1 FROM purchase_returns pr WHERE pr.invoice_id = OLD.id
          )
        ))
      BEGIN
        SELECT RAISE(ABORT, 'Posted invoice financial fields are immutable');
      END
    ''');
  }
}
