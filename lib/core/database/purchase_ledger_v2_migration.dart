import 'package:sqflite/sqflite.dart';

/// Schema migration from the first Purchase Ledger release to V2.
///
/// The original tables are retained so existing records are never discarded.
/// V2 introduces a canonical supplier movement ledger and daily purchase sheets.
class PurchaseLedgerV2Migration {
  PurchaseLedgerV2Migration._();

  static Future<void> apply(Database db) async {
    await _addColumnIfMissing(db, 'business_profiles', 'shop_number', 'TEXT');
    await _addColumnIfMissing(db, 'suppliers', 'activity_type', 'TEXT');
    await _addColumnIfMissing(db, 'supplier_opening_balances', 'balance_side',
        "TEXT NOT NULL DEFAULT 'due'");
    await _addColumnIfMissing(
        db, 'credit_purchase_invoices', 'received_at', 'TEXT');
    await _addColumnIfMissing(
        db, 'credit_purchase_invoices', 'attachment_id', 'INTEGER');
    await _addColumnIfMissing(
        db, 'credit_purchase_items', 'category_id', 'INTEGER');
    await _addColumnIfMissing(db, 'credit_purchase_items', 'notes', 'TEXT');
    await _addColumnIfMissing(
        db, 'supplier_payments', 'idempotency_key', 'TEXT');

    await db.execute('''
      CREATE TABLE supplier_account_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        currency TEXT NOT NULL,
        movement_type TEXT NOT NULL CHECK (movement_type IN (
          'opening_balance', 'credit_invoice', 'payment', 'purchase_return',
          'daily_purchase', 'adjustment', 'reversal'
        )),
        source_type TEXT NOT NULL,
        source_id INTEGER,
        entry_date TEXT NOT NULL,
        signed_amount_minor INTEGER NOT NULL,
        note TEXT,
        reverses_movement_id INTEGER,
        idempotency_key TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      INSERT INTO supplier_account_movements (
        supplier_id, currency, movement_type, source_type, source_id,
        entry_date, signed_amount_minor, note, created_at
      )
      SELECT supplier_id, currency, entry_type, entry_type, reference_id,
             entry_date, signed_amount_minor, note, created_at
      FROM supplier_ledger
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_supplier_movements_source
      ON supplier_account_movements(source_type, source_id, currency, movement_type)
      WHERE source_id IS NOT NULL
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_supplier_movements_idempotency
      ON supplier_account_movements(idempotency_key)
      WHERE idempotency_key IS NOT NULL
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_supplier_movements_reversal
      ON supplier_account_movements(reverses_movement_id)
      WHERE reverses_movement_id IS NOT NULL
    ''');
    await db.execute('''
      CREATE INDEX idx_supplier_movements_account_date
      ON supplier_account_movements(supplier_id, currency, entry_date, id)
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_supplier_payment_idempotency
      ON supplier_payments(idempotency_key)
      WHERE idempotency_key IS NOT NULL
    ''');

    await db.execute('''
      CREATE TABLE supplier_payment_reversals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL UNIQUE REFERENCES supplier_payments(id) ON DELETE RESTRICT,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        reversal_date TEXT NOT NULL,
        reason TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_purchase_sheets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sheet_number TEXT NOT NULL UNIQUE,
        purchase_date TEXT NOT NULL,
        branch_id INTEGER REFERENCES branches(id) ON DELETE SET NULL,
        employee_id INTEGER REFERENCES employees(id) ON DELETE SET NULL,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'DRAFT'
          CHECK (status IN ('DRAFT','READY_FOR_HANDOVER','HANDED_OVER','CLOSED')),
        header_snapshot_json TEXT,
        totals_snapshot_json TEXT,
        operations_snapshot_json TEXT,
        handed_over_at TEXT,
        closed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_daily_sheets_date_branch
      ON daily_purchase_sheets(purchase_date, branch_id, employee_id, status)
    ''');

    await db.execute('''
      CREATE TABLE daily_purchase_operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sheet_id INTEGER NOT NULL REFERENCES daily_purchase_sheets(id) ON DELETE RESTRICT,
        operation_number TEXT NOT NULL,
        legacy_cash_purchase_id INTEGER UNIQUE,
        supplier_id INTEGER REFERENCES suppliers(id) ON DELETE RESTRICT,
        accounting_mode TEXT NOT NULL CHECK (accounting_mode IN ('daily_outstanding','supplier_account')),
        seller_name TEXT,
        currency TEXT NOT NULL,
        subtotal_minor INTEGER NOT NULL CHECK (subtotal_minor >= 0),
        discount_minor INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
        tax_minor INTEGER NOT NULL DEFAULT 0 CHECK (tax_minor >= 0),
        total_minor INTEGER NOT NULL CHECK (total_minor >= 0),
        amount_paid_minor INTEGER NOT NULL DEFAULT 0 CHECK (amount_paid_minor >= 0),
        status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','void')),
        initial_supplier_payment_id INTEGER REFERENCES supplier_payments(id) ON DELETE RESTRICT,
        attachment_id INTEGER,
        due_date TEXT,
        notes TEXT,
        idempotency_key TEXT UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(sheet_id, operation_number),
        CHECK (amount_paid_minor <= total_minor),
        CHECK (accounting_mode <> 'supplier_account' OR supplier_id IS NOT NULL)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_daily_operations_sheet
      ON daily_purchase_operations(sheet_id, id)
    ''');
    await db.execute('''
      CREATE INDEX idx_daily_operations_supplier
      ON daily_purchase_operations(supplier_id, currency, created_at)
    ''');

    await db.execute('''
      CREATE TABLE daily_purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id INTEGER NOT NULL REFERENCES daily_purchase_operations(id) ON DELETE RESTRICT,
        product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
        category_id INTEGER REFERENCES purchase_categories(id) ON DELETE SET NULL,
        item_name TEXT NOT NULL,
        quantity_milli INTEGER NOT NULL CHECK (quantity_milli > 0),
        unit_name TEXT NOT NULL,
        unit_price_minor INTEGER NOT NULL CHECK (unit_price_minor >= 0),
        discount_minor INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
        tax_minor INTEGER NOT NULL DEFAULT 0 CHECK (tax_minor >= 0),
        line_total_minor INTEGER NOT NULL CHECK (line_total_minor >= 0),
        seller_name TEXT,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_daily_items_operation ON daily_purchase_items(operation_id, id)
    ''');

    await db.execute('''
      CREATE TABLE daily_purchase_outstandings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id INTEGER NOT NULL UNIQUE REFERENCES daily_purchase_operations(id) ON DELETE RESTRICT,
        original_minor INTEGER NOT NULL CHECK (original_minor > 0),
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','partial','paid','void')),
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_purchase_outstanding_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        outstanding_id INTEGER NOT NULL REFERENCES daily_purchase_outstandings(id) ON DELETE RESTRICT,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        payment_date TEXT NOT NULL,
        method TEXT NOT NULL,
        reference TEXT,
        notes TEXT,
        attachment_id INTEGER,
        idempotency_key TEXT UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_daily_outstanding_payments
      ON daily_purchase_outstanding_payments(outstanding_id, payment_date, id)
    ''');

    await db.execute('''
      CREATE TABLE daily_purchase_outstanding_adjustments (
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
      CREATE INDEX idx_daily_outstanding_adjustments
      ON daily_purchase_outstanding_adjustments(outstanding_id, adjustment_date, id)
    ''');

    await db.execute('''
      CREATE TABLE daily_purchase_sheet_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sheet_id INTEGER NOT NULL REFERENCES daily_purchase_sheets(id) ON DELETE RESTRICT,
        event_type TEXT NOT NULL,
        from_status TEXT,
        to_status TEXT,
        details_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_purchase_sheet_amendments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sheet_id INTEGER NOT NULL REFERENCES daily_purchase_sheets(id) ON DELETE RESTRICT,
        amendment_number TEXT NOT NULL,
        reason TEXT NOT NULL,
        details TEXT NOT NULL,
        currency TEXT,
        amount_delta_minor INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        UNIQUE(sheet_id, amendment_number)
      )
    ''');

    await db.execute('''
      CREATE TABLE supplier_statement_archives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        currency TEXT NOT NULL,
        period_from TEXT,
        period_to TEXT,
        statement_type TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TRIGGER trg_supplier_statement_archives_no_update
      BEFORE UPDATE ON supplier_statement_archives
      BEGIN SELECT RAISE(ABORT, 'Supplier statement archives are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_supplier_statement_archives_no_delete
      BEFORE DELETE ON supplier_statement_archives
      BEGIN SELECT RAISE(ABORT, 'Supplier statement archives are append-only'); END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_supplier_movements_no_update
      BEFORE UPDATE ON supplier_account_movements
      BEGIN
        SELECT RAISE(ABORT, 'Supplier account movements are append-only');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_supplier_movements_no_delete
      BEFORE DELETE ON supplier_account_movements
      BEGIN
        SELECT RAISE(ABORT, 'Supplier account movements are append-only');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_supplier_movement_reversal_validate
      BEFORE INSERT ON supplier_account_movements
      WHEN NEW.movement_type = 'reversal'
      BEGIN
        SELECT CASE WHEN NOT EXISTS (
          SELECT 1 FROM supplier_account_movements original
          WHERE original.id = NEW.reverses_movement_id
            AND original.supplier_id = NEW.supplier_id
            AND original.currency = NEW.currency
            AND NEW.signed_amount_minor = -original.signed_amount_minor
        ) THEN RAISE(ABORT, 'Invalid supplier movement reversal') END;
        SELECT CASE WHEN EXISTS (
          SELECT 1 FROM supplier_account_movements prior
          WHERE prior.reverses_movement_id = NEW.reverses_movement_id
        ) THEN RAISE(ABORT, 'Supplier movement already reversed') END;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_supplier_payment_reversals_no_update
      BEFORE UPDATE ON supplier_payment_reversals
      BEGIN SELECT RAISE(ABORT, 'Supplier payment reversals are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_supplier_payment_reversals_no_delete
      BEFORE DELETE ON supplier_payment_reversals
      BEGIN SELECT RAISE(ABORT, 'Supplier payment reversals are append-only'); END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_supplier_payment_reversal_validate
      BEFORE INSERT ON supplier_payment_reversals
      BEGIN
        SELECT CASE WHEN NEW.amount_minor <> (
          SELECT amount_minor FROM supplier_payments WHERE id = NEW.payment_id
        ) THEN RAISE(ABORT, 'Only full payment reversal is supported') END;
      END
    ''');

    await db.execute('DROP TRIGGER IF EXISTS trg_payment_allocation_validate');
    await db.execute('''
      CREATE TRIGGER trg_payment_allocation_validate
      BEFORE INSERT ON payment_allocations
      BEGIN
        SELECT CASE WHEN EXISTS (
          SELECT 1 FROM supplier_payment_reversals r WHERE r.payment_id = NEW.payment_id
        ) THEN RAISE(ABORT, 'Cannot allocate a reversed payment') END;
        SELECT CASE WHEN NEW.amount_minor > (
          SELECT amount_minor - COALESCE((
            SELECT SUM(amount_minor) FROM payment_allocations
            WHERE payment_id = NEW.payment_id
          ), 0)
          FROM supplier_payments WHERE id = NEW.payment_id
        ) THEN RAISE(ABORT, 'Allocation exceeds payment amount') END;
        SELECT CASE WHEN (
          SELECT supplier_id FROM supplier_payments WHERE id = NEW.payment_id
        ) <> (
          SELECT supplier_id FROM credit_purchase_invoices WHERE id = NEW.invoice_id
        ) THEN RAISE(ABORT, 'Payment and invoice suppliers differ') END;
        SELECT CASE WHEN (
          SELECT currency FROM supplier_payments WHERE id = NEW.payment_id
        ) <> (
          SELECT currency FROM credit_purchase_invoices WHERE id = NEW.invoice_id
        ) THEN RAISE(ABORT, 'Payment and invoice currencies differ') END;
        SELECT CASE WHEN NEW.amount_minor +
          COALESCE((
            SELECT SUM(a.amount_minor)
            FROM payment_allocations a
            JOIN supplier_payments p ON p.id = a.payment_id
            LEFT JOIN supplier_payment_reversals r ON r.payment_id = p.id
            WHERE a.invoice_id = NEW.invoice_id AND r.id IS NULL
          ), 0) +
          COALESCE((
            SELECT SUM(total_minor) FROM purchase_returns
            WHERE invoice_id = NEW.invoice_id
          ), 0) >
          (SELECT total_minor FROM credit_purchase_invoices WHERE id = NEW.invoice_id)
          THEN RAISE(ABORT, 'Allocation exceeds invoice outstanding') END;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_daily_operation_insert_draft_only
      BEFORE INSERT ON daily_purchase_operations
      WHEN (SELECT status FROM daily_purchase_sheets WHERE id = NEW.sheet_id) <> 'DRAFT'
      BEGIN
        SELECT RAISE(ABORT, 'Only draft daily sheets can be changed');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_daily_operation_update_draft_only
      BEFORE UPDATE ON daily_purchase_operations
      WHEN (SELECT status FROM daily_purchase_sheets WHERE id = OLD.sheet_id) <> 'DRAFT'
      BEGIN
        SELECT RAISE(ABORT, 'Handed-over daily sheets are immutable');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_daily_operation_delete_draft_only
      BEFORE DELETE ON daily_purchase_operations
      WHEN (SELECT status FROM daily_purchase_sheets WHERE id = OLD.sheet_id) <> 'DRAFT'
      BEGIN
        SELECT RAISE(ABORT, 'Handed-over daily sheets are immutable');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_daily_sheet_status_transition
      BEFORE UPDATE OF status ON daily_purchase_sheets
      WHEN NOT (
        OLD.status = NEW.status OR
        (OLD.status = 'DRAFT' AND NEW.status = 'READY_FOR_HANDOVER') OR
        (OLD.status = 'READY_FOR_HANDOVER' AND NEW.status = 'HANDED_OVER') OR
        (OLD.status = 'HANDED_OVER' AND NEW.status = 'CLOSED')
      )
      BEGIN
        SELECT RAISE(ABORT, 'Invalid daily sheet status transition');
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_daily_sheet_events_no_update
      BEFORE UPDATE ON daily_purchase_sheet_events
      BEGIN SELECT RAISE(ABORT, 'Daily sheet events are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_daily_sheet_events_no_delete
      BEFORE DELETE ON daily_purchase_sheet_events
      BEGIN SELECT RAISE(ABORT, 'Daily sheet events are append-only'); END
    ''');

    await db.execute('''
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

    await db.execute('''
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

    await db.execute('''
      CREATE TRIGGER trg_daily_outstanding_payments_no_update
      BEFORE UPDATE ON daily_purchase_outstanding_payments
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding payments are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_daily_outstanding_payments_no_delete
      BEFORE DELETE ON daily_purchase_outstanding_payments
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding payments are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_daily_outstanding_adjustments_no_update
      BEFORE UPDATE ON daily_purchase_outstanding_adjustments
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding adjustments are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_daily_outstanding_adjustments_no_delete
      BEFORE DELETE ON daily_purchase_outstanding_adjustments
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding adjustments are append-only'); END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_daily_sheet_amendments_no_update
      BEFORE UPDATE ON daily_purchase_sheet_amendments
      BEGIN SELECT RAISE(ABORT, 'Daily sheet amendments are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_daily_sheet_amendments_no_delete
      BEFORE DELETE ON daily_purchase_sheet_amendments
      BEGIN SELECT RAISE(ABORT, 'Daily sheet amendments are append-only'); END
    ''');

    await _migrateLegacyDailyPurchases(db);
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String declaration,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
    }
  }

  static Future<void> _migrateLegacyDailyPurchases(Database db) async {
    await db.execute('''
      INSERT INTO daily_purchase_sheets (
        sheet_number, purchase_date, notes, status, created_at, updated_at
      )
      SELECT
        'LEGACY-' || REPLACE(purchase_date, '-', ''),
        purchase_date,
        'Imported from the previous daily-purchase register',
        'DRAFT',
        MIN(created_at),
        MIN(created_at)
      FROM cash_purchases
      GROUP BY purchase_date
    ''');

    await db.execute('''
      INSERT INTO daily_purchase_operations (
        sheet_id, operation_number, legacy_cash_purchase_id, accounting_mode,
        seller_name, currency, subtotal_minor, discount_minor, tax_minor,
        total_minor, amount_paid_minor, due_date, notes, created_at, updated_at
      )
      SELECT
        s.id,
        'LEGACY-' || c.id,
        c.id,
        'daily_outstanding',
        c.seller_name,
        c.currency,
        c.total_minor,
        0,
        0,
        c.total_minor,
        COALESCE((
          SELECT SUM(p.amount_minor)
          FROM cash_purchase_payments p
          WHERE p.cash_purchase_id = c.id AND p.notes = 'Initial payment'
        ), 0),
        c.due_date,
        c.notes,
        c.created_at,
        c.created_at
      FROM cash_purchases c
      JOIN daily_purchase_sheets s
        ON s.purchase_date = c.purchase_date
    ''');

    await db.execute('''
      INSERT INTO daily_purchase_items (
        operation_id, item_name, quantity_milli, unit_name,
        unit_price_minor, line_total_minor
      )
      SELECT o.id, i.item_name, i.quantity_milli, i.unit_name,
             i.unit_price_minor, i.line_total_minor
      FROM cash_purchase_items i
      JOIN daily_purchase_operations o
        ON o.legacy_cash_purchase_id = i.cash_purchase_id
    ''');

    await db.execute('''
      INSERT INTO daily_purchase_outstandings (
        operation_id, original_minor, due_date, status, created_at
      )
      SELECT
        o.id,
        o.total_minor - o.amount_paid_minor,
        o.due_date,
        CASE
          WHEN COALESCE((
            SELECT SUM(p.amount_minor)
            FROM cash_purchase_payments p
            WHERE p.cash_purchase_id = o.legacy_cash_purchase_id
              AND COALESCE(p.notes, '') <> 'Initial payment'
          ), 0) >= o.total_minor - o.amount_paid_minor THEN 'paid'
          WHEN COALESCE((
            SELECT SUM(p.amount_minor)
            FROM cash_purchase_payments p
            WHERE p.cash_purchase_id = o.legacy_cash_purchase_id
              AND COALESCE(p.notes, '') <> 'Initial payment'
          ), 0) = 0 THEN 'open'
          ELSE 'partial'
        END,
        o.created_at
      FROM daily_purchase_operations o
      WHERE o.legacy_cash_purchase_id IS NOT NULL
        AND o.total_minor - o.amount_paid_minor > 0
    ''');

    await db.execute('''
      INSERT INTO daily_purchase_outstanding_payments (
        outstanding_id, amount_minor, payment_date, method, reference, notes, created_at
      )
      SELECT
        ob.id, p.amount_minor, p.payment_date, p.method, p.reference, p.notes, p.created_at
      FROM cash_purchase_payments p
      JOIN daily_purchase_operations o
        ON o.legacy_cash_purchase_id = p.cash_purchase_id
      JOIN daily_purchase_outstandings ob
        ON ob.operation_id = o.id
      WHERE COALESCE(p.notes, '') <> 'Initial payment'
    ''');
  }
}
