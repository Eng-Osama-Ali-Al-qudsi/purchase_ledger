"""SQLite integration checks for the real V7 DDL and the V4 trigger it replaces.

Run with: python -m unittest discover -s test -p 'validate_*.py' -v
This does not replace Flutter/Dart tests or an Android build.
"""

import pathlib
import re
import sqlite3
import unittest


DATABASE_DIR = pathlib.Path(__file__).resolve().parents[1] / 'lib' / 'core' / 'database'


def quoted_sql_from_dart(filename):
    source = (DATABASE_DIR / filename).read_text(encoding='utf-8')
    return re.findall(r"await db\.execute\('''(.*?)'''\)", source, flags=re.S)


class RealV7MigrationSqlTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.execute('PRAGMA foreign_keys = ON')
        self.db.executescript('''
            CREATE TABLE credit_purchase_invoices (
                id INTEGER PRIMARY KEY, supplier_id INTEGER NOT NULL,
                branch_id INTEGER, employee_id INTEGER,
                invoice_number TEXT, invoice_date TEXT, due_date TEXT,
                currency TEXT, subtotal_minor INTEGER, discount_minor INTEGER,
                tax_minor INTEGER, total_minor INTEGER, notes TEXT,
                status TEXT, received_at TEXT, created_at TEXT
            );
            CREATE TABLE supplier_account_movements (
                id INTEGER PRIMARY KEY, supplier_id INTEGER, currency TEXT,
                movement_type TEXT, source_type TEXT, source_id INTEGER,
                reverses_movement_id INTEGER REFERENCES supplier_account_movements(id),
                signed_amount_minor INTEGER, entry_date TEXT, created_at TEXT
            );
            CREATE TABLE supplier_payments (id INTEGER PRIMARY KEY);
            CREATE TABLE payment_allocations (
                id INTEGER PRIMARY KEY, invoice_id INTEGER,
                payment_id INTEGER REFERENCES supplier_payments(id)
            );
            CREATE TABLE supplier_payment_reversals (
                id INTEGER PRIMARY KEY, payment_id INTEGER REFERENCES supplier_payments(id)
            );
            CREATE TABLE purchase_returns (id INTEGER PRIMARY KEY, invoice_id INTEGER);
            CREATE TABLE daily_purchase_operations (
                id INTEGER PRIMARY KEY, supplier_id INTEGER,
                accounting_mode TEXT, recording_category TEXT,
                responsible_person_name TEXT, total_minor INTEGER
            );
            INSERT INTO credit_purchase_invoices VALUES
                (1,7,NULL,NULL,'INV-1','2026-11-14',NULL,'YER',10000,0,0,
                 10000,NULL,'posted',NULL,'2026-11-14');
            INSERT INTO supplier_account_movements VALUES
                (1,7,'YER','credit_invoice','credit_invoice',1,NULL,
                 10000,'2026-11-14','2026-11-14');
            INSERT INTO daily_purchase_operations VALUES
                (1,NULL,'daily_outstanding','person','اسم تاريخي',3000);
        ''')
        v4_triggers = [sql for sql in quoted_sql_from_dart(
            'purchase_ledger_v4_migration.dart'
        ) if 'CREATE TRIGGER IF NOT EXISTS trg_credit_invoice_financial_fields_immutable' in sql]
        self.assertEqual(1, len(v4_triggers))
        self.db.execute(v4_triggers[0])

    def tearDown(self):
        self.db.close()

    def upgrade(self):
        ddl = quoted_sql_from_dart('purchase_ledger_v7_migration.dart')
        self.assertEqual(10, len(ddl), 'V7 schema/trigger DDL changed; update test')
        for statement in ddl:
            if 'CREATE TRIGGER trg_credit_invoice_financial_fields_immutable' in statement:
                self.db.execute('DROP TRIGGER IF EXISTS trg_credit_invoice_financial_fields_immutable')
            self.db.execute(statement)

    def reversal(self, invoice_id=1, amount=-10000):
        self.db.execute('''INSERT INTO supplier_account_movements VALUES
            (NULL,7,'YER','reversal','credit_invoice_void',?,?,?,
             '2026-11-14','2026-11-14')''', (invoice_id, 1, amount))

    def test_v4_previously_blocked_valid_void_then_v7_allows_exact_reversal(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE credit_purchase_invoices SET status='void' WHERE id=1")
        self.upgrade()
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE credit_purchase_invoices SET status='void' WHERE id=1")
        self.reversal()
        self.db.execute("UPDATE credit_purchase_invoices SET status='void' WHERE id=1")
        self.assertEqual('void', self.db.execute(
            'SELECT status FROM credit_purchase_invoices WHERE id=1'
        ).fetchone()[0])
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE credit_purchase_invoices SET total_minor=1 WHERE id=1")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE credit_purchase_invoices SET status='posted' WHERE id=1")

    def test_reversal_must_match_exact_invoice_and_amount(self):
        self.upgrade()
        self.reversal(amount=-9999)
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE credit_purchase_invoices SET status='void' WHERE id=1")

    def test_active_payment_blocks_void_even_with_reversal(self):
        self.upgrade()
        self.reversal()
        self.db.execute('INSERT INTO supplier_payments VALUES (5)')
        self.db.execute('INSERT INTO payment_allocations VALUES (4,1,5)')
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE credit_purchase_invoices SET status='void' WHERE id=1")
        self.db.execute('INSERT INTO supplier_payment_reversals VALUES (2,5)')
        self.db.execute("UPDATE credit_purchase_invoices SET status='void' WHERE id=1")

    def test_existing_return_blocks_void(self):
        self.upgrade()
        self.reversal()
        self.db.execute('INSERT INTO purchase_returns VALUES (1,1)')
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE credit_purchase_invoices SET status='void' WHERE id=1")

    def test_person_identity_and_legacy_rows_survive_upgrade(self):
        self.upgrade()
        old = self.db.execute('SELECT responsible_person_name, responsible_person_id '
                              'FROM daily_purchase_operations WHERE id=1').fetchone()
        self.assertEqual(('اسم تاريخي', None), old)
        self.db.execute("INSERT INTO responsible_people(name,created_at) VALUES ('أحمد','now')")
        person_id = self.db.execute('SELECT id FROM responsible_people').fetchone()[0]
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO responsible_people(name,created_at) VALUES ('أحمد','now')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute('''INSERT INTO daily_purchase_operations
                (supplier_id,accounting_mode,recording_category,total_minor)
                VALUES (NULL,'daily_outstanding','person',800)''')
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute('''INSERT INTO daily_purchase_operations
                (supplier_id,accounting_mode,recording_category,responsible_person_id,total_minor)
                VALUES (8,'daily_outstanding','person',?,800)''', (person_id,))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute('''INSERT INTO daily_purchase_operations
                (supplier_id,accounting_mode,recording_category,responsible_person_id,total_minor)
                VALUES (NULL,'daily_outstanding','independent',?,800)''', (person_id,))
        self.db.execute('''INSERT INTO daily_purchase_operations
            (supplier_id,accounting_mode,recording_category,responsible_person_id,total_minor)
            VALUES (NULL,'daily_outstanding','person',?,800)''', (person_id,))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute('UPDATE daily_purchase_operations '
                            'SET responsible_person_id=NULL WHERE responsible_person_id=?', (person_id,))
        self.assertEqual(800, self.db.execute('SELECT total_minor FROM daily_purchase_operations '
                                              'WHERE responsible_person_id=?', (person_id,)).fetchone()[0])
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute('DELETE FROM responsible_people WHERE id=?', (person_id,))

    def test_person_balances_follow_actual_repository_query_and_settlements(self):
        """Execute the repository's outstanding SELECT, not a copied formula."""
        self.upgrade()
        self.db.executescript('''
            ALTER TABLE daily_purchase_operations ADD COLUMN sheet_id INTEGER;
            ALTER TABLE daily_purchase_operations ADD COLUMN operation_number TEXT;
            ALTER TABLE daily_purchase_operations ADD COLUMN seller_name TEXT;
            ALTER TABLE daily_purchase_operations ADD COLUMN currency TEXT;
            ALTER TABLE daily_purchase_operations ADD COLUMN status TEXT;
            CREATE TABLE daily_purchase_sheets (
                id INTEGER PRIMARY KEY, sheet_number TEXT,
                purchase_date TEXT, branch_id INTEGER, employee_id INTEGER
            );
            CREATE TABLE branches(id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE employees(id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE suppliers(id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE daily_purchase_outstandings (
                id INTEGER PRIMARY KEY, operation_id INTEGER,
                original_minor INTEGER, due_date TEXT, status TEXT
            );
            CREATE TABLE daily_purchase_outstanding_payments (
                id INTEGER PRIMARY KEY, outstanding_id INTEGER, amount_minor INTEGER
            );
            CREATE TABLE daily_purchase_outstanding_adjustments (
                id INTEGER PRIMARY KEY, outstanding_id INTEGER,
                signed_delta_minor INTEGER
            );
            INSERT INTO daily_purchase_sheets VALUES (1,'DPS-1','2026-11-14',NULL,NULL);
            INSERT INTO responsible_people(name,created_at) VALUES ('سمير','now');
            INSERT INTO daily_purchase_operations
                (id,supplier_id,accounting_mode,recording_category,
                 responsible_person_id,total_minor,sheet_id,operation_number,currency,status)
                VALUES (2,NULL,'daily_outstanding','person',1,10000,1,'OP-2','YER','posted');
            INSERT INTO daily_purchase_outstandings
                VALUES (9,2,10000,NULL,'partial');
            INSERT INTO daily_purchase_outstanding_payments VALUES (1,9,3000);
            INSERT INTO daily_purchase_outstanding_adjustments VALUES (1,9,-2000);
        ''')
        source = (DATABASE_DIR.parent.parent / 'features' / 'purchases' /
                  'data' / 'daily_purchases_repository.dart').read_text(encoding='utf-8')
        method = source.split('Future<List<DailyOutstandingRecord>> getOutstandingRecords(', 1)[1]
        method = method.split('Future<List<DailyOutstandingHistoryEntry>>', 1)[0]
        match = re.search(r"final rows = await db\.rawQuery\('''(.*?)'''", method, re.S)
        self.assertIsNotNone(match)
        query = match.group(1).replace(
            "${where.join(' AND ')}",
            "o.status = 'posted' AND ob.status <> 'void' AND o.responsible_person_id = ?"
        ).replace('$outerWhere', '')
        rows = self.db.execute(query, (1,)).fetchall()
        column_names = [column[0] for column in self.db.execute(query, (1,)).description]
        result = dict(zip(column_names, rows[0]))
        self.assertEqual(1, len(rows))
        self.assertEqual(1, result['responsible_person_id'])
        self.assertEqual('سمير', result['seller_name'])
        self.assertEqual(10000, result['original_minor'])
        self.assertEqual(3000, result['paid_minor'])
        self.assertEqual(-2000, result['adjustment_delta_minor'])
        self.assertEqual(5000, result['remaining_minor'])
        self.db.execute('INSERT INTO daily_purchase_outstanding_payments VALUES (2,9,5000)')
        settled = self.db.execute(query, (1,)).fetchone()
        self.assertEqual(0, dict(zip(column_names, settled))['remaining_minor'])
        self.assertEqual([], self.db.execute('PRAGMA foreign_key_check').fetchall())

    def test_daily_supplier_edit_has_precise_atomic_reversal_for_each_movement(self):
        """V2 reversal trigger requires each inverse to match its own source."""
        self.upgrade()
        v2_triggers = [statement for statement in quoted_sql_from_dart(
            'purchase_ledger_v2_migration.dart'
        ) if 'CREATE TRIGGER trg_supplier_movement_reversal_validate' in statement]
        self.assertEqual(1, len(v2_triggers))
        self.db.execute(v2_triggers[0])
        self.db.execute('CREATE UNIQUE INDEX idx_reversed_once ON '
                        'supplier_account_movements(reverses_movement_id) '
                        'WHERE reverses_movement_id IS NOT NULL')
        self.db.execute('''INSERT INTO daily_purchase_operations
            (id,supplier_id,accounting_mode,recording_category,total_minor)
            VALUES (2,7,'supplier_account','supplier',12000)''')
        self.db.execute('''INSERT INTO supplier_account_movements
            (id,supplier_id,currency,movement_type,source_type,source_id,
             signed_amount_minor,entry_date,created_at)
            VALUES (20,7,'YER','daily_purchase','daily_purchase',2,
                    10000,'2026-11-14','now')''')
        self.db.execute('''INSERT INTO supplier_account_movements
            (id,supplier_id,currency,movement_type,source_type,
             signed_amount_minor,entry_date,created_at)
            VALUES (21,7,'YER','adjustment','daily_purchase_edit',
                    2000,'2026-11-14','now')''')
        self.db.execute('INSERT INTO daily_operation_adjustment_movements '
                        'VALUES (2,21,\'now\')')
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute('''INSERT INTO supplier_account_movements
                (supplier_id,currency,movement_type,source_type,source_id,
                 reverses_movement_id,signed_amount_minor,entry_date,created_at)
                VALUES (7,'YER','reversal','daily_purchase_void',2,
                        20,-12000,'2026-11-14','now')''')
        self.db.execute('''INSERT INTO supplier_account_movements
            (supplier_id,currency,movement_type,source_type,source_id,
             reverses_movement_id,signed_amount_minor,entry_date,created_at)
            VALUES (7,'YER','reversal','daily_purchase_void',2,
                    20,-10000,'2026-11-14','now')''')
        self.db.execute('''INSERT INTO supplier_account_movements
            (supplier_id,currency,movement_type,source_type,source_id,
             reverses_movement_id,signed_amount_minor,entry_date,created_at)
            VALUES (7,'YER','reversal','daily_purchase_edit_void',21,
                    21,-2000,'2026-11-14','now')''')
        amount = self.db.execute('''SELECT SUM(signed_amount_minor)
            FROM supplier_account_movements
            WHERE source_id IN (2,21) AND movement_type != 'credit_invoice'
                OR id = 21''').fetchone()[0]
        self.assertEqual(0, amount)
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute('''INSERT INTO supplier_account_movements
                (supplier_id,currency,movement_type,source_type,source_id,
                 reverses_movement_id,signed_amount_minor,entry_date,created_at)
                VALUES (7,'YER','reversal','daily_purchase_edit_void',21,
                        21,-2000,'2026-11-14','now')''')


if __name__ == '__main__':
    unittest.main()
