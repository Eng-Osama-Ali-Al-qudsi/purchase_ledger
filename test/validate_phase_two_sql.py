"""SQLite-only acceptance probes for additive V6 metadata and append-only reversal.

These tests do not execute Flutter/Dart or sqflite repository code.
"""
from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PhaseTwoSql(unittest.TestCase):
    def test_v6_keeps_original_daily_accounting(self):
        code = (ROOT / 'lib/core/database/purchase_ledger_v6_migration.dart').read_text()
        statements = re.findall(r"db\.execute\('([^']*)'\s*'([^']*)'\)", code)
        self.assertEqual(len(statements), 3)
        db = sqlite3.connect(':memory:')
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('''CREATE TABLE daily_purchase_operations (
          id INTEGER PRIMARY KEY, account_mode TEXT,
          supplier_id INTEGER, total_minor INTEGER, paid_minor INTEGER)''')
        db.execute("INSERT INTO daily_purchase_operations VALUES(1,'daily_outstanding',NULL,2400000,0)")
        for halves in statements:
            db.execute(''.join(halves))
        self.assertEqual(db.execute('''SELECT account_mode, total_minor, paid_minor,
                   recording_category, responsible_person_name
                   FROM daily_purchase_operations WHERE id = 1''').fetchone(),
                         ('daily_outstanding', 2400000, 0, None, None))
        db.execute('''INSERT INTO daily_purchase_operations
          (id,account_mode,total_minor,paid_minor,recording_category,responsible_person_name)
          VALUES(2,'daily_outstanding',120000,0,'person','أحمد')''')
        db.execute('''INSERT INTO daily_purchase_operations
          (id,account_mode,total_minor,paid_minor,recording_category)
          VALUES(3,'daily_outstanding',120000,120000,'cash')''')
        self.assertEqual(db.execute('SELECT COUNT(*) FROM daily_purchase_operations WHERE supplier_id IS NOT NULL').fetchone()[0],0)
        self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(),[])

    def test_append_only_reversal_balances_and_duplicate_protection(self):
        db = sqlite3.connect(':memory:')
        db.executescript('''
           CREATE TABLE movements (
             id INTEGER PRIMARY KEY, signed_amount_minor INTEGER NOT NULL,
             reverses_movement_id INTEGER UNIQUE);
           CREATE TRIGGER validate_reversal BEFORE INSERT ON movements
             WHEN NEW.reverses_movement_id IS NOT NULL BEGIN
               SELECT CASE WHEN NOT EXISTS(
                 SELECT 1 FROM movements m WHERE m.id=NEW.reverses_movement_id
                 AND m.signed_amount_minor=-NEW.signed_amount_minor)
               THEN RAISE(ABORT,'incorrect reversal') END;
             END;
        ''')
        db.execute('INSERT INTO movements VALUES (1,2400000,NULL)')
        db.execute('INSERT INTO movements VALUES (2,-2400000,1)')
        self.assertEqual(db.execute('SELECT SUM(signed_amount_minor) FROM movements').fetchone()[0],0)
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute('INSERT INTO movements VALUES (3,-2400000,1)')
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute('INSERT INTO movements VALUES (4,-100,2)')
        self.assertEqual(db.execute('SELECT COUNT(*) FROM movements').fetchone()[0],2)


if __name__ == '__main__':
    unittest.main()
