"""SQLite and source-contract regressions for the daily purchasing workflow.

The aggregate is extracted from the production repository. Source-contract
checks cannot prove Flutter runtime behavior; device tests remain necessary.
"""

from pathlib import Path
import re
import sqlite3
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPO = (ROOT / 'lib/features/purchases/data/daily_purchases_repository.dart').read_text(encoding='utf-8')
LIST = (ROOT / 'lib/features/purchases/presentation/daily_purchases_screen.dart').read_text(encoding='utf-8')
FORM = (ROOT / 'lib/features/purchases/presentation/daily_operation_dialog.dart').read_text(encoding='utf-8')
PDF = (ROOT / 'lib/core/reports/report_pdf_service.dart').read_text(encoding='utf-8')


class DailyWorkflowSqlChecks(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.executescript('''
          CREATE TABLE daily_purchase_operations (
            id INTEGER PRIMARY KEY, sheet_id INTEGER, currency TEXT,
            status TEXT, accounting_mode TEXT, recording_category TEXT,
            supplier_id INTEGER, total_minor INTEGER, amount_paid_minor INTEGER
          );
          CREATE TABLE daily_purchase_outstandings (
            id INTEGER PRIMARY KEY, operation_id INTEGER,
            original_minor INTEGER
          );
          CREATE TABLE daily_purchase_outstanding_payments (
            id INTEGER PRIMARY KEY, outstanding_id INTEGER, amount_minor INTEGER
          );
          CREATE TABLE daily_purchase_outstanding_adjustments (
            id INTEGER PRIMARY KEY, outstanding_id INTEGER, signed_delta_minor INTEGER
          );
          INSERT INTO daily_purchase_operations VALUES
            (1,1,'YER','posted','daily_outstanding','cash',NULL,1000000,1000000),
            (2,1,'YER','posted','daily_outstanding','cash',NULL,2000000,2000000),
            (3,1,'YER','posted','supplier_account','supplier',9,1500000,0),
            (4,1,'SAR','posted','supplier_account','supplier',10,500000,0),
            (5,1,'YER','void','supplier_account','supplier',9,900000,0);
        ''')

    def tearDown(self):
        self.db.close()

    def _active_sheet_totals(self):
        match = re.search(r"final totalRows = await db.rawQuery\('''(.*?)'''", REPO, re.S)
        self.assertIsNotNone(match)
        return self.db.execute(match.group(1).replace('($placeholders)', '(?)'), [1]).fetchall()

    def test_cash_and_supplier_credit_are_distinct_and_currency_separated(self):
        rows = {row[1]: row for row in self._active_sheet_totals()}
        # id, currency, total, cash, paid, independent due, supplier due
        self.assertEqual((4500000, 3000000, 3000000, 0, 1500000), rows['YER'][2:])
        self.assertEqual((500000, 0, 0, 0, 500000), rows['SAR'][2:])

    def test_corrected_cash_total_stays_fully_paid_without_a_due_record(self):
        self.db.execute('UPDATE daily_purchase_operations '
                        'SET total_minor=1200000, amount_paid_minor=1200000 WHERE id=1')
        rows = {row[1]: row for row in self._active_sheet_totals()}
        self.assertEqual(3200000, rows['YER'][3])
        self.assertEqual(0, rows['YER'][5])
        self.assertIn("'amount_paid_minor': isCashPurchase ? totals.total : initialPaid", REPO)
        self.assertIn('if (isCashPurchase && outstandingRows.isNotEmpty)', REPO)
        self.assertIn("'previous_items': previousItems", REPO)

    def test_creation_opens_persisted_sheet_by_returned_id(self):
        method = LIST.split('Future<void> _createSheet()', 1)[1].split('Future<void> _editSheet', 1)[0]
        self.assertIn('if (!mounted || id == null) return;', method)
        self.assertIn('DailyPurchaseSheetScreen(sheetId: id)', method)
        self.assertLess(method.index('_refresh();'), method.index('DailyPurchaseSheetScreen(sheetId: id)'))

    def test_default_cash_and_credit_are_direct_choices(self):
        self.assertIn("String _mode = 'cash';", FORM)
        self.assertIn("value: 'supplier_account'", FORM)
        self.assertIn("'supplier_account' : 'daily_outstanding'", FORM)
        self.assertIn("'cash' ? 'cash' : 'independent'", FORM)

    def test_no_empty_sheet_handover_and_supplier_names_on_pdf(self):
        self.assertIn("if (targetStatus == 'READY_FOR_HANDOVER')", REPO)
        self.assertIn('if (operationCount == 0)', REPO)
        self.assertIn('المورد (للآجل)', PDF)
        self.assertIn('operation.supplierName ?? operation.sellerName', PDF)


if __name__ == '__main__':
    unittest.main()
