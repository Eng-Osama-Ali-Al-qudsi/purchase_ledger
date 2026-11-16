import 'package:sqflite/sqflite.dart';

/// V8: permits permanent removal ONLY of truly empty, unhanded-over drafts.
/// All original draft events are copied to a durable append-only tombstone.
/// Tombstones also reserve document numbers so deleted identifiers never recur.
class PurchaseLedgerV8Migration {
  PurchaseLedgerV8Migration._();

  static Future<void> apply(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_sheet_deleted_drafts (
        sheet_id INTEGER PRIMARY KEY,
        sheet_number TEXT NOT NULL UNIQUE,
        purchase_date TEXT NOT NULL,
        branch_id INTEGER,
        employee_id INTEGER,
        deleted_at TEXT NOT NULL,
        deletion_reason TEXT NOT NULL CHECK(length(trim(deletion_reason)) > 0),
        events_json TEXT NOT NULL,
        original_created_at TEXT NOT NULL
      )
    ''');
    // The tombstone must be inserted while the original sheet still exists.
    // This prevents outside code from authorizing removal of financial rows.
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_deleted_draft_validate
      BEFORE INSERT ON daily_sheet_deleted_drafts
      WHEN NOT EXISTS (
        SELECT 1 FROM daily_purchase_sheets s
        WHERE s.id = NEW.sheet_id AND s.sheet_number = NEW.sheet_number
          AND s.status = 'DRAFT'
          AND s.header_snapshot_json IS NULL
          AND s.totals_snapshot_json IS NULL
          AND s.operations_snapshot_json IS NULL
          AND s.handed_over_at IS NULL AND s.closed_at IS NULL
          AND NOT EXISTS (SELECT 1 FROM daily_purchase_operations o
            WHERE o.sheet_id = s.id)
          AND NOT EXISTS (SELECT 1 FROM daily_purchase_sheet_amendments a
            WHERE a.sheet_id = s.id)
          AND NOT EXISTS (SELECT 1 FROM daily_purchase_sheet_events e
            WHERE e.sheet_id = s.id AND e.event_type = 'archived')
      )
      BEGIN SELECT RAISE(ABORT, 'Only untouched financial drafts can be deleted'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_deleted_draft_no_update
      BEFORE UPDATE ON daily_sheet_deleted_drafts
      BEGIN SELECT RAISE(ABORT, 'Draft deletion evidence is immutable'); END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_daily_deleted_draft_no_delete
      BEFORE DELETE ON daily_sheet_deleted_drafts
      BEGIN SELECT RAISE(ABORT, 'Draft deletion evidence is immutable'); END
    ''');
    // Previously ALL event deletions were forbidden. Permit removing only
    // events that have already been snapshotted in a durable tombstone.
    await db.execute('DROP TRIGGER IF EXISTS trg_daily_sheet_events_no_delete');
    await db.execute('''
      CREATE TRIGGER trg_daily_sheet_events_no_delete
      BEFORE DELETE ON daily_purchase_sheet_events
      WHEN NOT EXISTS (SELECT 1 FROM daily_sheet_deleted_drafts d
        WHERE d.sheet_id = OLD.sheet_id)
      BEGIN SELECT RAISE(ABORT, 'Daily sheet events are append-only'); END
    ''');
    await db.execute('DROP TRIGGER IF EXISTS trg_daily_sheet_no_delete');
    await db.execute('''
      CREATE TRIGGER trg_daily_sheet_no_delete
      BEFORE DELETE ON daily_purchase_sheets
      WHEN OLD.status <> 'DRAFT'
        OR NOT EXISTS (SELECT 1 FROM daily_sheet_deleted_drafts d
          WHERE d.sheet_id = OLD.id AND d.sheet_number = OLD.sheet_number)
        OR EXISTS (SELECT 1 FROM daily_purchase_operations o
          WHERE o.sheet_id = OLD.id)
        OR EXISTS (SELECT 1 FROM daily_purchase_sheet_amendments a
          WHERE a.sheet_id = OLD.id)
        OR EXISTS (SELECT 1 FROM daily_purchase_sheet_events e
          WHERE e.sheet_id = OLD.id)
      BEGIN SELECT RAISE(ABORT, 'Cannot delete a daily sheet with financial history'); END
    ''');
  }
}
