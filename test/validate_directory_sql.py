"""SQLite compatibility checks for directory archiving on the original DDL.

Does not call Dart repository methods; validates the database constraints used
by their logical-delete strategy.
"""

from pathlib import Path
import re
import sqlite3
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "lib/core/database/app_database.dart"
)


class DirectoryArchiveSqlTest(unittest.TestCase):
    def test_archiving_preserves_historical_foreign_keys(self):
        content = SOURCE.read_text(encoding="utf-8")
        definitions = re.findall(
            r"batch\.execute\('''(.*?)'''\);", content, re.S
        )
        required = (
            "branches", "employees", "purchase_categories", "suppliers",
            "products", "credit_purchase_invoices", "credit_purchase_items",
        )
        connection = sqlite3.connect(":memory:")
        connection.execute("PRAGMA foreign_keys=ON")
        for name in required:
            sql = next(
                (stmt for stmt in definitions
                 if re.search(rf"\bCREATE TABLE {name}\s*\(", stmt)),
                None,
            )
            self.assertIsNotNone(sql, f"Missing original DDL for {name}")
            connection.execute(sql)
        connection.execute(
            "INSERT INTO branches (id,name,created_at) VALUES (1,'A','2026-11-14')"
        )
        connection.execute(
            "INSERT INTO employees (id,name,branch_id,created_at) "
            "VALUES (1,'B',1,'2026-11-14')"
        )
        connection.execute(
            "INSERT INTO purchase_categories (id,name,category_type) "
            "VALUES (1,'C','credit')"
        )
        connection.execute(
            "INSERT INTO products (id,name,category_id,created_at) "
            "VALUES (1,'P',1,'2026-11-14')"
        )
        connection.execute(
            "INSERT INTO suppliers (id,name,created_at,updated_at) "
            "VALUES (1,'S','2026-11-14','2026-11-14')"
        )
        connection.execute(
            "INSERT INTO credit_purchase_invoices "
            "(id,supplier_id,branch_id,employee_id,invoice_number,invoice_date,"
            "currency,subtotal_minor,total_minor,created_at) "
            "VALUES (1,1,1,1,'INV1','2026-11-14','YER',1000,1000,'2026-11-14')"
        )
        connection.execute(
            "INSERT INTO credit_purchase_items "
            "(id,invoice_id,product_id,description,quantity_milli,"
            "unit_name,unit_price_minor,line_total_minor) "
            "VALUES (1,1,1,'P',1000,'قطعة',1000,1000)"
        )
        for table in ("branches", "employees", "purchase_categories", "products"):
            connection.execute(
                f"UPDATE {table} SET is_active=0 WHERE id=1 AND is_active=1"
            )
        self.assertEqual(connection.execute("PRAGMA foreign_key_check").fetchall(), [])
        self.assertEqual(
            connection.execute(
                "SELECT branch_id,employee_id,total_minor FROM credit_purchase_invoices"
            ).fetchone(),
            (1, 1, 1000),
        )
        self.assertEqual(
            connection.execute(
                "SELECT product_id,description,unit_name,line_total_minor "
                "FROM credit_purchase_items"
            ).fetchone(),
            (1, "P", "قطعة", 1000),
        )


if __name__ == "__main__":
    unittest.main()
