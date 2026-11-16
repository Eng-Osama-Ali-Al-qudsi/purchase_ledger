"""Integration checks for the SQL used by the Android QA repairs.

These execute SELECT statements extracted from Dart source against an in-memory
SQLite fixture. They are NOT Flutter widget/device tests.
"""

import pathlib
import re
import sqlite3
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
DAILY = (ROOT / 'lib/features/purchases/data/daily_purchases_repository.dart').read_text(encoding='utf-8')
SUPPLIER = (ROOT / 'lib/features/suppliers/data/supplier_accounting_repository.dart').read_text(encoding='utf-8')
DETAIL = (ROOT / 'lib/features/suppliers/presentation/supplier_financial_details_screen.dart').read_text(encoding='utf-8')


def extract(source, start):
    match = re.search(re.escape(start) + r"(.*?)'''", source, re.S)
    if match is None:
        raise AssertionError('Source SQL fragment is missing: ' + start)
    return match.group(1)


class AndroidQaSqlTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.execute('PRAGMA foreign_keys = ON')
        self.db.executescript('''
          CREATE TABLE daily_purchase_sheets (
            id INTEGER PRIMARY KEY, sheet_number TEXT UNIQUE, purchase_date TEXT,
            status TEXT, branch_id INTEGER, employee_id INTEGER, notes TEXT
          );
          CREATE TABLE daily_purchase_sheet_events (
            id INTEGER PRIMARY KEY, sheet_id INTEGER REFERENCES daily_purchase_sheets(id),
            event_type TEXT, details_json TEXT
          );
          CREATE TABLE daily_purchase_operations (
            id INTEGER PRIMARY KEY, sheet_id INTEGER REFERENCES daily_purchase_sheets(id),
            supplier_id INTEGER, accounting_mode TEXT, status TEXT,
            currency TEXT, total_minor INTEGER
          );
          CREATE TABLE credit_purchase_invoices (
            id INTEGER PRIMARY KEY, supplier_id INTEGER, status TEXT,
            currency TEXT, total_minor INTEGER, invoice_number TEXT,
            invoice_date TEXT
          );
          CREATE TABLE supplier_payments (
            id INTEGER PRIMARY KEY, supplier_id INTEGER, amount_minor INTEGER,
            currency TEXT, payment_date TEXT
          );
          CREATE TABLE supplier_payment_reversals (
            id INTEGER PRIMARY KEY, payment_id INTEGER, amount_minor INTEGER
          );
          CREATE TABLE purchase_returns (
            id INTEGER PRIMARY KEY, supplier_id INTEGER, currency TEXT,
            return_date TEXT, total_minor INTEGER
          );
          CREATE TABLE payment_allocations (
            id INTEGER PRIMARY KEY, payment_id INTEGER, invoice_id INTEGER,
            amount_minor INTEGER, created_at TEXT
          );
          INSERT INTO daily_purchase_sheets VALUES
            (1,'DPS-01','2026-11-14','DRAFT',NULL,NULL,NULL),
            (2,'DPS-02','2026-11-14','DRAFT',NULL,NULL,NULL),
            (3,'DPS-03','2026-11-14','HANDED_OVER',NULL,NULL,NULL);
          INSERT INTO daily_purchase_sheet_events VALUES
            (1,1,'created','{}'), (2,2,'created','{}'),
            (3,2,'archived','{"reason":"created by mistake"}');
          INSERT INTO credit_purchase_invoices VALUES
            (1,9,'posted','YER',10000,'INV-1','2026-11-14'),
            (2,9,'void','YER',7000,'INV-2','2026-11-14'),
            (3,9,'posted','SAR',2000,'INV-3','2026-11-14');
          INSERT INTO daily_purchase_operations VALUES
            (1,3,9,'supplier_account','posted','YER',4000),
            (2,3,9,'supplier_account','void','YER',3000);
          INSERT INTO supplier_payments VALUES (5,9,4000,'YER','2026-11-14');
          INSERT INTO payment_allocations VALUES
            (6,5,1,3000,'2026-11-14');
        ''')

    def tearDown(self):
        self.db.close()

    def test_archive_event_excludes_list_without_deleting_original(self):
        # The production query adds this predicate only for ordinary lists.
        match = re.search(r"if \(!includeArchived\) \{\s*where.add\('''(.*?)'''\);", DAILY, re.S)
        self.assertIsNotNone(match)
        predicate = match.group(1)
        active = self.db.execute(
            'SELECT s.id FROM daily_purchase_sheets s WHERE ' + predicate +
            ' ORDER BY s.id').fetchall()
        self.assertEqual([(1,), (3,)], active)
        self.assertEqual(3, self.db.execute(
            'SELECT COUNT(*) FROM daily_purchase_sheets').fetchone()[0])
        self.assertEqual('archived', self.db.execute(
            'SELECT event_type FROM daily_purchase_sheet_events WHERE sheet_id = 2 AND id = 3'
        ).fetchone()[0])

    def test_active_supplier_purchases_exclude_voided_documents(self):
        sql = extract(SUPPLIER, "final postedPurchaseRows = await db.rawQuery('''")
        rows = self.db.execute(sql, [9, 9]).fetchall()
        self.assertEqual([('SAR', 2000), ('YER', 14000)], rows)

    def test_monthly_chart_does_not_mix_currencies(self):
        sql = extract(SUPPLIER, "final monthlyRows = await db.rawQuery('''")
        rows = self.db.execute(sql, [9, 9, 9, 9]).fetchall()
        self.assertEqual([('2026-11', 'SAR', 2000, 0, 0),
                          ('2026-11', 'YER', 14000, 4000, 0)], rows)

    def test_payment_detail_uses_real_invoice_join_and_amount(self):
        payment_branch = DETAIL.split("documentType == 'payment'", 1)[1]
        sql = extract(payment_branch, "data['lines'] = await db.rawQuery('''")
        allocations = self.db.execute(sql, [5]).fetchall()
        columns = [col[0] for col in self.db.execute(sql, [5]).description]
        record = dict(zip(columns, allocations[0]))
        self.assertEqual(record['invoice_number'], 'INV-1')
        self.assertEqual(record['amount_minor'], 3000)
        self.assertEqual(record['invoice_total_minor'], 10000)

    def test_soft_archive_guards_exist_in_write_paths(self):
        self.assertIn('Archived daily sheets cannot receive purchases', DAILY)
        self.assertIn('An archived daily sheet cannot be handed over', DAILY)
        self.assertIn('A sheet with purchase history cannot be archived', DAILY)
        self.assertIn("'event_type': 'metadata_edited'", DAILY)
        self.assertIn("'event_type': 'archived'", DAILY)


if __name__ == '__main__':
    unittest.main()
