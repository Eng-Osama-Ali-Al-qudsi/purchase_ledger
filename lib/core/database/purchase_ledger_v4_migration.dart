import 'package:sqflite/sqflite.dart';

/// Additive V4 migration: persist the payment method used at purchase time
/// for every daily operation. Older daily records are backfilled only where
/// a legacy or linked supplier-payment record provides reliable evidence.
class PurchaseLedgerV4Migration {
  PurchaseLedgerV4Migration._();

  static Future<void> apply(Database db) async {
    await _addColumnIfMissing(
      db,
      'daily_purchase_operations',
      'payment_method',
      "TEXT NOT NULL DEFAULT 'unspecified'",
    );

    // Give historical payments a stable visible receipt reference where the
    // original record did not contain one. The ID-derived value is unique.
    await db.execute('''
      UPDATE supplier_payments
      SET receipt_number = 'PAY-' || printf('%08d', id)
      WHERE receipt_number IS NULL OR TRIM(receipt_number) = ''
    ''');

    // V2 protects posted operations with a trigger that blocks every update
    // after handover. Temporarily replace only that trigger while performing
    // this schema-owned backfill; restore the exact guard immediately after.
    await db.execute(
        'DROP TRIGGER IF EXISTS trg_daily_operation_update_draft_only');
    try {
      // Recover the initial method from legacy cash-purchase payments.
      await db.execute('''
        UPDATE daily_purchase_operations
        SET payment_method = COALESCE((
          SELECT p.method
          FROM cash_purchase_payments p
          WHERE p.cash_purchase_id = daily_purchase_operations.legacy_cash_purchase_id
            AND p.notes = 'Initial payment'
          ORDER BY p.id
          LIMIT 1
        ), 'unspecified')
        WHERE legacy_cash_purchase_id IS NOT NULL
          AND amount_paid_minor > 0
          AND payment_method = 'unspecified'
      ''');

      // Recover the initial method for operations posted to supplier accounts.
      await db.execute('''
        UPDATE daily_purchase_operations
        SET payment_method = COALESCE((
          SELECT p.method
          FROM supplier_payments p
          WHERE p.id = daily_purchase_operations.initial_supplier_payment_id
        ), 'unspecified')
        WHERE initial_supplier_payment_id IS NOT NULL
          AND payment_method = 'unspecified'
      ''');
    } finally {
      // Restore the original V2 immutability rule even if backfill fails.
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_daily_operation_update_draft_only
        BEFORE UPDATE ON daily_purchase_operations
        WHEN (SELECT status FROM daily_purchase_sheets WHERE id = OLD.sheet_id) <> 'DRAFT'
        BEGIN SELECT RAISE(ABORT, 'Handed-over daily sheets are immutable'); END
      ''');
    }

    // Daily line items may only change while their parent sheet is a draft.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_item_insert_draft_only
      BEFORE INSERT ON daily_purchase_items
      WHEN COALESCE((
        SELECT s.status
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = NEW.operation_id
      ), '') <> 'DRAFT'
      BEGIN SELECT RAISE(ABORT, 'Daily items can only be added to draft sheets'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_item_update_draft_only
      BEFORE UPDATE ON daily_purchase_items
      WHEN COALESCE((
        SELECT s.status
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = OLD.operation_id
      ), '') <> 'DRAFT'
      OR COALESCE((
        SELECT s.status
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = NEW.operation_id
      ), '') <> 'DRAFT'
      BEGIN SELECT RAISE(ABORT, 'Daily items can only be changed on draft sheets'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_item_delete_draft_only
      BEFORE DELETE ON daily_purchase_items
      WHEN COALESCE((
        SELECT s.status
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = OLD.operation_id
      ), '') <> 'DRAFT'
      BEGIN SELECT RAISE(ABORT, 'Daily items can only be removed from draft sheets'); END
    ''');

    // Protect the identity of a sheet after it leaves DRAFT.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_sheet_identity_immutable
      BEFORE UPDATE OF sheet_number, purchase_date, branch_id, employee_id, notes
      ON daily_purchase_sheets
      WHEN OLD.status <> 'DRAFT'
      BEGIN SELECT RAISE(ABORT, 'Handed-over daily sheet identity is immutable'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_sheet_no_delete
      BEFORE DELETE ON daily_purchase_sheets
      BEGIN SELECT RAISE(ABORT, 'Daily purchase sheets cannot be deleted'); END
    ''');

    // Outstanding principal can be changed only before handover. Later
    // payments and adjustments remain append-only through their own ledgers.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_outstanding_insert_draft_only
      BEFORE INSERT ON daily_purchase_outstandings
      WHEN COALESCE((
        SELECT s.status
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = NEW.operation_id
      ), '') <> 'DRAFT'
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding can only be created on draft sheets'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_outstanding_principal_update_draft_only
      BEFORE UPDATE ON daily_purchase_outstandings
      WHEN (
        NEW.operation_id IS NOT OLD.operation_id OR
        NEW.original_minor IS NOT OLD.original_minor OR
        NEW.due_date IS NOT OLD.due_date
      )
      AND COALESCE((
        SELECT s.status
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = OLD.operation_id
      ), '') <> 'DRAFT'
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding principal is immutable after handover'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_outstanding_delete_draft_only
      BEFORE DELETE ON daily_purchase_outstandings
      WHEN COALESCE((
        SELECT s.status
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = OLD.operation_id
      ), '') <> 'DRAFT'
      BEGIN SELECT RAISE(ABORT, 'Daily outstanding cannot be deleted after handover'); END
    ''');

    // The first handover captures one immutable snapshot. The snapshot is
    // created atomically when READY_FOR_HANDOVER becomes HANDED_OVER; later
    // edits must be represented by append-only amendments instead.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_sheet_snapshot_write_once
      BEFORE UPDATE OF header_snapshot_json, totals_snapshot_json, operations_snapshot_json
      ON daily_purchase_sheets
      WHEN NOT (
        OLD.status = 'READY_FOR_HANDOVER'
        AND NEW.status = 'HANDED_OVER'
        AND OLD.header_snapshot_json IS NULL
        AND OLD.totals_snapshot_json IS NULL
        AND OLD.operations_snapshot_json IS NULL
        AND NEW.header_snapshot_json IS NOT NULL
        AND NEW.totals_snapshot_json IS NOT NULL
        AND NEW.operations_snapshot_json IS NOT NULL
      )
      BEGIN SELECT RAISE(ABORT, 'Daily handover snapshots can only be captured once'); END
    ''');

    // Posted invoice identity and financial values are immutable. Attachment
    // metadata is the only field that may be added after invoice creation.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_credit_invoice_financial_fields_immutable
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
        OR NEW.status IS NOT OLD.status
        OR NEW.received_at IS NOT OLD.received_at
        OR NEW.created_at IS NOT OLD.created_at
      BEGIN SELECT RAISE(ABORT, 'Posted invoice financial fields are immutable'); END
    ''');

    // Payments and allocations are never deleted. Financial identity fields
    // on supplier payments are immutable; only a draft-linked initial payment
    // may have its payment method corrected and that change is audited.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_supplier_payment_financial_fields_immutable
      BEFORE UPDATE ON supplier_payments
      WHEN NEW.id IS NOT OLD.id
        OR NEW.supplier_id IS NOT OLD.supplier_id
        OR NEW.amount_minor IS NOT OLD.amount_minor
        OR NEW.currency IS NOT OLD.currency
        OR NEW.payment_date IS NOT OLD.payment_date
        OR NEW.receipt_number IS NOT OLD.receipt_number
        OR NEW.notes IS NOT OLD.notes
        OR NEW.idempotency_key IS NOT OLD.idempotency_key
        OR NEW.created_at IS NOT OLD.created_at
        OR (
          NEW.method IS NOT OLD.method
          AND NOT EXISTS (
            SELECT 1
            FROM daily_purchase_operations o
            JOIN daily_purchase_sheets s ON s.id = o.sheet_id
            WHERE o.initial_supplier_payment_id = OLD.id
              AND s.status = 'DRAFT'
          )
        )
      BEGIN SELECT RAISE(ABORT, 'Supplier payment financial fields are immutable'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_supplier_payment_no_delete
      BEFORE DELETE ON supplier_payments
      BEGIN SELECT RAISE(ABORT, 'Supplier payments cannot be deleted; reverse them instead'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_payment_allocation_no_update
      BEFORE UPDATE ON payment_allocations
      BEGIN SELECT RAISE(ABORT, 'Payment allocations are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_payment_allocation_no_delete
      BEFORE DELETE ON payment_allocations
      BEGIN SELECT RAISE(ABORT, 'Payment allocations are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_purchase_return_no_update
      BEFORE UPDATE ON purchase_returns
      BEGIN SELECT RAISE(ABORT, 'Purchase returns are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_purchase_return_no_delete
      BEFORE DELETE ON purchase_returns
      BEGIN SELECT RAISE(ABORT, 'Purchase returns are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_purchase_return_item_no_update
      BEFORE UPDATE ON purchase_return_items
      BEGIN SELECT RAISE(ABORT, 'Purchase return items are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_purchase_return_item_no_delete
      BEFORE DELETE ON purchase_return_items
      BEGIN SELECT RAISE(ABORT, 'Purchase return items are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_supplier_opening_balance_no_update
      BEFORE UPDATE ON supplier_opening_balances
      BEGIN SELECT RAISE(ABORT, 'Supplier opening balances are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_supplier_opening_balance_no_delete
      BEFORE DELETE ON supplier_opening_balances
      BEGIN SELECT RAISE(ABORT, 'Supplier opening balances are append-only'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_credit_invoice_no_delete
      BEFORE DELETE ON credit_purchase_invoices
      BEGIN SELECT RAISE(ABORT, 'Credit invoices cannot be deleted; use a reversal or adjustment'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_credit_invoice_item_no_update
      BEFORE UPDATE ON credit_purchase_items
      BEGIN SELECT RAISE(ABORT, 'Posted invoice items are immutable'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_credit_invoice_item_no_delete
      BEFORE DELETE ON credit_purchase_items
      BEGIN SELECT RAISE(ABORT, 'Posted invoice items are immutable'); END
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
}
