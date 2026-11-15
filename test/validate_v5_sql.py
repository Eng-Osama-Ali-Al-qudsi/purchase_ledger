"""Run the V5 SQL statements on SQLite without needing a Flutter emulator.

This checks schema compatibility and the historical-unit backfill. It cannot
replace running Flutter's actual sqflite onUpgrade path on Android.
"""

from pathlib import Path
import re
import sqlite3
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "lib/core/database/purchase_ledger_v5_migration.dart"
)


class UnitMigrationSqlTest(unittest.TestCase):
    def test_additive_migration_preserves_old_items_and_splits_scopes(self):
        source = SOURCE.read_text(encoding="utf-8")
        statements = re.findall(
            r"(?:db\.execute|db\.rawInsert)\('''(.*?)'''", source, re.S
        )
        self.assertEqual(len(statements), 4, "Expected CREATE and three INSERT statements")
        connection = sqlite3.connect(":memory:")
        connection.execute("PRAGMA foreign_keys=ON")
        for table in ("credit_purchase_items", "cash_purchase_items", "daily_purchase_items"):
            connection.execute(
                f"CREATE TABLE {table} (id INTEGER PRIMARY KEY, unit_name TEXT NOT NULL)"
            )
        connection.execute(
            "INSERT INTO credit_purchase_items VALUES (1, 'صندوق')"
        )
        connection.execute(
            "INSERT INTO cash_purchase_items VALUES (1, 'حبة')"
        )
        connection.execute(
            "INSERT INTO daily_purchase_items VALUES (1, 'كيلو')"
        )
        original = {
            table: connection.execute(f"SELECT * FROM {table}").fetchall()
            for table in ("credit_purchase_items", "cash_purchase_items", "daily_purchase_items")
        }
        connection.execute(statements[0])
        for scope in ("credit", "daily"):
            for name in ("قطعة", "كرتون", "سلة", "دبة", "كيلو"):
                connection.execute(
                    "INSERT OR IGNORE INTO measurement_units (scope, name, created_at) "
                    "VALUES (?, ?, ?)",
                    (scope, name, "2026-11-14"),
                )
        for sql in statements[1:]:
            connection.execute(sql, ("2026-11-14",))
        self.assertEqual(
            connection.execute(
                "SELECT scope FROM measurement_units WHERE name='صندوق'"
            ).fetchall(),
            [("credit",)],
        )
        self.assertEqual(
            connection.execute(
                "SELECT scope FROM measurement_units WHERE name='حبة'"
            ).fetchall(),
            [("daily",)],
        )
        for table, rows in original.items():
            self.assertEqual(
                rows, connection.execute(f"SELECT * FROM {table}").fetchall()
            )
        # Unit names stored on historical line items survive catalogue archive.
        connection.execute(
            "UPDATE measurement_units SET is_active=0 "
            "WHERE scope='credit' AND name='صندوق'"
        )
        self.assertEqual(
            connection.execute(
                "SELECT unit_name FROM credit_purchase_items WHERE id=1"
            ).fetchone(),
            ("صندوق",),
        )
        with self.assertRaises(sqlite3.IntegrityError):
            connection.execute(
                "INSERT INTO measurement_units (scope,name,created_at) "
                "VALUES ('invalid','item','2026-11-14')"
            )


if __name__ == "__main__":
    unittest.main()
