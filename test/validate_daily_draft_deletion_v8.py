"""SQLite V8 migration regression tests extracted from the real Dart migration.

This does not substitute for Flutter or Android testing. It executes the
actual migration's CREATE TABLE / CREATE TRIGGER statements in sqlite3.
"""
import json
import re
import sqlite3
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = (ROOT / 'lib/core/database/purchase_ledger_v8_migration.dart').read_text(encoding='utf-8')
REPOSITORY = (ROOT / 'lib/features/purchases/data/daily_purchases_repository.dart').read_text(encoding='utf-8')
LIST = (ROOT / 'lib/features/purchases/presentation/daily_purchases_screen.dart').read_text(encoding='utf-8')
OUTSTANDING = (ROOT / 'lib/features/purchases/presentation/daily_outstanding_screen.dart').read_text(encoding='utf-8')
STATEMENT = (ROOT / 'lib/features/suppliers/presentation/supplier_statement_screen.dart').read_text(encoding='utf-8')
PDF = (ROOT / 'lib/core/reports/report_pdf_service.dart').read_text(encoding='utf-8')


def migrate_v8(db):
    # The Dart migration calls execute('''...''') for table and trigger SQL.
    statements = re.findall(r"await db.execute\(\s*(?:'''(.*?)'''|'([^']+)')\s*\);", MIGRATION, re.S)
    assert len(statements) >= 7
    for triple_quoted, single_quoted in statements:
        db.execute(triple_quoted or single_quoted)
    for trigger in ['trg_daily_sheet_events_no_delete', 'trg_daily_sheet_no_delete']:
        assert db.execute('SELECT sql FROM sqlite_master WHERE type=? AND name=?',
                          ('trigger', trigger)).fetchone()


class DailyDraftDeletionMigration(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''
          CREATE TABLE daily_purchase_sheets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sheet_number TEXT UNIQUE, purchase_date TEXT,
            branch_id INTEGER, employee_id INTEGER,
            status TEXT, created_at TEXT,
            header_snapshot_json TEXT, totals_snapshot_json TEXT,
            operations_snapshot_json TEXT,
            handed_over_at TEXT, closed_at TEXT
          );
          CREATE TABLE daily_purchase_operations (
            id INTEGER PRIMARY KEY, sheet_id INTEGER NOT NULL
              REFERENCES daily_purchase_sheets(id) ON DELETE RESTRICT,
            status TEXT, recording_category TEXT,
            accounting_mode TEXT, supplier_id INTEGER,
            total_minor INTEGER, amount_paid_minor INTEGER
          );
          CREATE TABLE daily_purchase_sheet_amendments (
            id INTEGER PRIMARY KEY, sheet_id INTEGER NOT NULL
              REFERENCES daily_purchase_sheets(id) ON DELETE RESTRICT
          );
          CREATE TABLE daily_purchase_sheet_events (
            id INTEGER PRIMARY KEY, sheet_id INTEGER NOT NULL
              REFERENCES daily_purchase_sheets(id) ON DELETE RESTRICT,
            event_type TEXT, details_json TEXT
          );
          CREATE TRIGGER trg_daily_sheet_events_no_delete BEFORE DELETE
            ON daily_purchase_sheet_events
            BEGIN SELECT RAISE(ABORT, 'Append only'); END;
          CREATE TRIGGER trg_daily_sheet_no_delete BEFORE DELETE
            ON daily_purchase_sheets
            BEGIN SELECT RAISE(ABORT, 'No delete'); END;
        ''')
        migrate_v8(self.db)

    def tearDown(self):
        self.db.close()

    def sheet(self, number='DPS-20261117-001', status='DRAFT'):
        row = self.db.execute('''INSERT INTO daily_purchase_sheets
          (sheet_number,purchase_date,status,created_at) VALUES
          (?, '2026-11-17',?,'2026-11-17T07:00:00')''', (number, status))
        self.db.execute('INSERT INTO daily_purchase_sheet_events '
                        '(sheet_id,event_type,details_json) VALUES (?,?,?)',
                        (row.lastrowid, 'created', '{"test":true}'))
        return row.lastrowid

    def record(self, id, *, event_snapshot=True):
        events = self.db.execute('SELECT * FROM daily_purchase_sheet_events WHERE sheet_id=?', (id,)).fetchall()
        info = self.db.execute('SELECT sheet_number,purchase_date,created_at FROM daily_purchase_sheets WHERE id=?', (id,)).fetchone()
        if event_snapshot:
            self.db.execute('''INSERT INTO daily_sheet_deleted_drafts
              (sheet_id,sheet_number,purchase_date,deleted_at,deletion_reason,
               events_json,original_created_at) VALUES (?,?,?,'2026-11-17T08:00:00',?,?,?)''',
               (id, info[0], info[1], 'Duplicate blank draft', json.dumps(events), info[2]))
        self.db.execute('DELETE FROM daily_purchase_sheet_events WHERE sheet_id=?', (id,))
        self.db.execute('DELETE FROM daily_purchase_sheets WHERE id=?', (id,))

    def test_safe_empty_draft_deletes_and_retains_audit_and_number(self):
        id = self.sheet()
        with self.db:
            self.record(id)
        self.assertEqual(0, self.db.execute('SELECT COUNT(*) FROM daily_purchase_sheets').fetchone()[0])
        data = self.db.execute('SELECT sheet_number,events_json FROM daily_sheet_deleted_drafts').fetchone()
        self.assertEqual('DPS-20261117-001', data[0])
        self.assertEqual(1, len(json.loads(data[1])))
        self.assertIn('daily_sheet_deleted_drafts WHERE sheet_number LIKE ?', REPOSITORY)

    def test_no_event_can_be_deleted_without_tombstone(self):
        id = self.sheet()
        with self.assertRaises(sqlite3.DatabaseError):
            self.db.execute('DELETE FROM daily_purchase_sheet_events WHERE sheet_id=?',(id,))

    def test_draft_with_even_void_history_cannot_delete(self):
        id = self.sheet()
        self.db.execute('INSERT INTO daily_purchase_operations VALUES (1,?,?,?,?,?,?,?)',
                        (id, 'void', 'cash', 'daily_outstanding', None, 100, 100))
        with self.assertRaises(sqlite3.DatabaseError):
            self.record(id)
        self.assertEqual(1, self.db.execute('SELECT COUNT(*) FROM daily_purchase_sheets').fetchone()[0])

    def test_draft_with_supplier_credit_cannot_delete(self):
        id = self.sheet()
        self.db.execute('INSERT INTO daily_purchase_operations VALUES (1,?,?,?,?,?,?,?)',
                        (id,'posted','supplier','supplier_account',5,100,0))
        with self.assertRaises(sqlite3.DatabaseError):
            self.record(id)

    def test_handed_over_sheet_cannot_delete(self):
        id = self.sheet(status='HANDED_OVER')
        with self.assertRaises(sqlite3.DatabaseError):
            self.record(id)

    def test_archived_draft_cannot_delete(self):
        id = self.sheet()
        self.db.execute("INSERT INTO daily_purchase_sheet_events (sheet_id,event_type) VALUES (?, 'archived')", (id,))
        with self.assertRaises(sqlite3.DatabaseError):
            self.record(id)

    def test_no_delete_without_tombstone_even_after_events_removed(self):
        id = self.sheet()
        self.db.execute('INSERT INTO daily_sheet_deleted_drafts '
            '(sheet_id,sheet_number,purchase_date,deleted_at,deletion_reason,events_json,original_created_at) '
            'VALUES (?,?,?,?,?,?,?)',
            (id,'DPS-20261117-001','2026-11-17','now','why','[]','created'))
        # Once permitted, direct sheet removal is still blocked until original
        # event rows have been moved to the tombstone.
        with self.assertRaises(sqlite3.DatabaseError):
            self.db.execute('DELETE FROM daily_purchase_sheets WHERE id=?',(id,))

    def test_deleted_draft_receipt_immutable(self):
        id = self.sheet()
        with self.db:
            self.record(id)
        with self.assertRaises(sqlite3.DatabaseError):
            self.db.execute('UPDATE daily_sheet_deleted_drafts SET deletion_reason=?', ('changed',))
        with self.assertRaises(sqlite3.DatabaseError):
            self.db.execute('DELETE FROM daily_sheet_deleted_drafts')

    def test_tombstone_reserved_number_prevents_reuse(self):
        id = self.sheet()
        with self.db:
            self.record(id)
        prefix = 'DPS-20261117-'
        ids = self.db.execute('''SELECT sheet_number FROM daily_purchase_sheets WHERE sheet_number LIKE ?
           UNION ALL SELECT sheet_number FROM daily_sheet_deleted_drafts WHERE sheet_number LIKE ?''',
           (prefix+'%', prefix+'%')).fetchall()
        self.assertEqual([('DPS-20261117-001',)], ids)
        self.assertEqual('DPS-20261117-002', f'{prefix}{len(ids)+1:03d}')

    def test_state_refresh_never_returns_future_to_setstate(self):
        self.assertNotRegex(LIST, r'setState\(\(\) => _future = _load\(\)\)')
        self.assertNotRegex(OUTSTANDING, r'setState\(\(\) => _future = _load\(\)\)')
        self.assertNotRegex(STATEMENT, r'setState\(\(\) => _statementFuture = _loadStatement\(\)\)')
        self.assertIn('DailyPurchaseSheetScreen(sheetId: id)', LIST)

    def test_report_table_has_matching_ten_columns(self):
        start = PDF.index('static Future<Uint8List> buildDailyHandoverReport')
        part = PDF[start:PDF.index('static Future<void> shareDailyHandoverReport', start)]
        header = part[part.index('final tableRows'):part.index('header: true,')]
        names = re.findall(r"^\s*'([^']+)',\s*$", header, flags=re.M)
        self.assertEqual(10, len(names))
        widths = re.findall(r'^\s*\d+: pw.FlexColumnWidth\(', part, flags=re.M)
        self.assertEqual(10, len(widths))
        self.assertIn('fontSize: header ? 10 : 8.8', PDF)


if __name__ == '__main__':
    unittest.main()
