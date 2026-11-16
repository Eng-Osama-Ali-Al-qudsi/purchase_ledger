"""Regression checks against the current SQL literals in the Flutter project.

These SQLite checks are real queries, not substitutes for Flutter or device QA.
"""

import pathlib
import re
import sqlite3
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
REPOSITORY = (ROOT / 'lib/features/suppliers/data/supplier_accounting_repository.dart').read_text(encoding='utf-8')
DAILY = (ROOT / 'lib/features/purchases/data/daily_purchases_repository.dart').read_text(encoding='utf-8')
DETAILS = (ROOT / 'lib/features/suppliers/presentation/supplier_financial_details_screen.dart').read_text(encoding='utf-8')


def embedded_query(after, text=REPOSITORY):
    start = text.index(after) + len(after)
    return text[start:text.index("'''", start)]


class SupplierOverviewFollowupTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.executescript('''
          CREATE TABLE credit_purchase_invoices (
            id INTEGER PRIMARY KEY, supplier_id INTEGER, invoice_number TEXT,
            invoice_date TEXT, currency TEXT, total_minor INTEGER,
            due_date TEXT, status TEXT
          );
          CREATE TABLE payment_allocations (
            id INTEGER PRIMARY KEY, invoice_id INTEGER, payment_id INTEGER,
            amount_minor INTEGER
          );
          CREATE TABLE supplier_payments (
            id INTEGER PRIMARY KEY, supplier_id INTEGER,
            currency TEXT, payment_date TEXT, amount_minor INTEGER
          );
          CREATE TABLE supplier_payment_reversals (
            id INTEGER PRIMARY KEY, payment_id INTEGER, amount_minor INTEGER
          );
          CREATE TABLE purchase_returns (
            id INTEGER PRIMARY KEY, supplier_id INTEGER, invoice_id INTEGER,
            return_date TEXT, currency TEXT, total_minor INTEGER
          );
          CREATE TABLE daily_purchase_sheets (
            id INTEGER PRIMARY KEY, sheet_number TEXT UNIQUE, purchase_date TEXT
          );
          CREATE TABLE daily_sheet_deleted_drafts (
            sheet_number TEXT NOT NULL UNIQUE
          );
          CREATE TABLE daily_purchase_operations (
            id INTEGER PRIMARY KEY, sheet_id INTEGER, supplier_id INTEGER,
            accounting_mode TEXT, currency TEXT, status TEXT, total_minor INTEGER
          );
          INSERT INTO credit_purchase_invoices VALUES
            (1,7,'INV-1','2026-10-10','YER',10000,NULL,'posted'),
            (2,7,'INV-2','2026-10-12','YER',12000,NULL,'posted'),
            (3,7,'INV-3','2026-11-05','YER',5000,NULL,'posted'),
            (4,7,'INV-4','2026-11-10','YER',8000,NULL,'posted'),
            (5,7,'INV-5','2026-11-09','SAR',2000,NULL,'posted'),
            (6,8,'OTHER','2026-11-09','SAR',5500,NULL,'posted'),
            (7,7,'VOID','2026-11-11','YER',3000,NULL,'void');
          INSERT INTO supplier_payments VALUES
            (10,7,'YER','2026-10-13',3000),
            (11,7,'YER','2026-11-06',5000),
            (12,7,'YER','2026-11-12',8000),
            (13,7,'YER','2026-11-13',1000);
          INSERT INTO payment_allocations VALUES
            (1,2,10,3000),(2,3,11,5000),(3,1,13,1000);
          INSERT INTO supplier_payment_reversals VALUES (1,13,1000);
          INSERT INTO purchase_returns VALUES
            (1,7,5,'2026-11-11','SAR',2000);
          INSERT INTO daily_purchase_sheets VALUES
            (1,'DPS-20261115-001','2026-11-14'),
            (2,'DPS-20261115-002','2026-11-15');
          INSERT INTO daily_purchase_operations VALUES
            (1,1,7,'supplier_account','YER','posted',4000),
            (2,1,7,'supplier_account','YER','void',9000);
        ''')

    def tearDown(self):
        self.db.close()

    def test_invoice_status_counts_match_drilldown_and_exclude_advances(self):
        counts_sql = embedded_query("final invoiceRows = await db.rawQuery('''")
        drilldown = REPOSITORY.split('Future<List<SupplierInvoiceBalance>> getInvoices', 1)[1]
        list_sql = embedded_query("final rows = await db.rawQuery('''", drilldown)
        summary = self.db.execute(counts_sql, [7]).fetchall()
        listed = self.db.execute(list_sql, [7]).fetchall()
        states = lambda rows: [
            'paid' if max(0, row[0] - row[1] - row[2]) == 0
            else 'partial' if row[1] > 0 or row[2] > 0 else 'unpaid'
            for row in rows
        ]
        # List order: id, number, date, currency, total, due, allocated, returned.
        list_states = states([(r[4], r[6], r[7]) for r in listed])
        self.assertEqual({'unpaid': 2, 'partial': 1, 'paid': 2},
                         {status: states(summary).count(status)
                          for status in ('unpaid', 'partial', 'paid')})
        self.assertEqual(sorted(states(summary)), sorted(list_states))
        self.assertEqual('unpaid', list_states[next(i for i, r in enumerate(listed) if r[1] == 'INV-4')])
        self.assertEqual('unpaid', list_states[next(i for i, r in enumerate(listed) if r[1] == 'INV-1')])

    def test_monthly_activity_keeps_currency_and_discards_reversed_payment(self):
        monthly_sql = embedded_query("final monthlyRows = await db.rawQuery('''")
        rows = self.db.execute(monthly_sql, [7, 7, 7, 7]).fetchall()
        table = {(r[0], r[1]): r[2:] for r in rows}
        self.assertEqual((22000, 3000, 0), table['2026-10', 'YER'])
        self.assertEqual((17000, 13000, 0), table['2026-11', 'YER'])
        self.assertEqual((2000, 0, 2000), table['2026-11', 'SAR'])

    def test_latest_active_payment_excludes_reversed_and_voided_purchases(self):
        purchases = embedded_query("final lastPurchaseRows = await db.rawQuery('''")
        payments = embedded_query("final lastPaymentRows = await db.rawQuery('''")
        self.assertEqual('2026-11-14', self.db.execute(purchases, [7, 7]).fetchone()[0])
        self.assertEqual('2026-11-12', self.db.execute(payments, [7]).fetchone()[0])

    def test_numbering_query_uses_highest_stored_id_not_record_count(self):
        sql = re.search(r"[\x27]{3}(SELECT sheet_number FROM daily_purchase_sheets WHERE sheet_number LIKE \?\s+UNION ALL\s+SELECT sheet_number FROM daily_sheet_deleted_drafts WHERE sheet_number LIKE \?)[\x27]{3}", DAILY)
        self.assertIsNotNone(sql)
        prefix = 'DPS-20261115-'
        existing = [row[0] for row in self.db.execute(
            sql.group(1), [prefix + '%', prefix + '%'])]
        self.assertEqual('DPS-20261115-003',
                         prefix + str(max(int(v[len(prefix):]) for v in existing) + 1).zfill(3))
        self.assertNotEqual(len(self.db.execute('SELECT 1 FROM daily_purchase_sheets WHERE purchase_date=?',
                                                ['2026-11-15']).fetchall()) + 1, 3)

    def test_audit_translation_constants_have_unique_keys(self):
        for map_name in ('_labels', '_labelsEn', 'translationsAr', 'translationsEn'):
            match = re.search(r'(?:const |  const )' + re.escape(map_name) +
                              r' = <String, String>\{(.*?)\};', DETAILS, re.S)
            self.assertIsNotNone(match, map_name)
            keys = re.findall(r"'([^']+)'\s*:", match.group(1))
            self.assertEqual(len(keys), len(set(keys)), map_name)


if __name__ == '__main__':
    unittest.main()
