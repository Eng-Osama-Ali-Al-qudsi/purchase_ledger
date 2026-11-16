import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'purchase_ledger_v2_migration.dart';
import 'purchase_ledger_v3_migration.dart';
import 'purchase_ledger_v4_migration.dart';
import 'purchase_ledger_v5_migration.dart';
import 'purchase_ledger_v6_migration.dart';
import 'purchase_ledger_v7_migration.dart';
import 'purchase_ledger_v8_migration.dart';

/// SQLite database for the offline-first application.
/// Monetary values are stored as integer minor units (1/100 of a currency unit).
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    final current = _database;
    if (current != null && current.isOpen) return current;
    final pending = _opening;
    if (pending != null) return pending;

    final opening = _openDatabase();
    _opening = opening;
    try {
      return await opening;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _openDatabase() async {
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'purchase_ledger.db'),
      version: 8,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await database.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
      onUpgrade: _upgrade,
    );
    _database = db;
    return db;
  }

  Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE business_profiles (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        shop_name TEXT NOT NULL,
        commercial_number TEXT,
        logo_path TEXT,
        owner_name TEXT,
        manager_name TEXT,
        buyer_name TEXT,
        phone TEXT,
        address TEXT,
        city TEXT,
        default_currency TEXT NOT NULL DEFAULT 'YER',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        code TEXT,
        address TEXT,
        phone TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        branch_id INTEGER REFERENCES branches(id) ON DELETE SET NULL,
        name TEXT NOT NULL,
        phone TEXT,
        role TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE purchase_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_type TEXT NOT NULL CHECK (category_type IN ('credit','daily','both')),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
        UNIQUE(name, category_type)
      )
    ''');

    batch.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        company_name TEXT,
        notes TEXT,
        default_currency TEXT NOT NULL DEFAULT 'YER',
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sku TEXT,
        category_id INTEGER REFERENCES purchase_categories(id) ON DELETE SET NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
        created_at TEXT NOT NULL,
        UNIQUE(sku)
      )
    ''');

    batch.execute('''
      CREATE TABLE product_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        unit_name TEXT NOT NULL,
        conversion_factor_milli INTEGER NOT NULL DEFAULT 1000 CHECK (conversion_factor_milli > 0),
        UNIQUE(product_id, unit_name)
      )
    ''');

    batch.execute('''
      CREATE TABLE supplier_opening_balances (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        currency TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK (amount_minor >= 0),
        as_of_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(supplier_id, currency)
      )
    ''');

    batch.execute('''
      CREATE TABLE credit_purchase_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        branch_id INTEGER REFERENCES branches(id) ON DELETE SET NULL,
        employee_id INTEGER REFERENCES employees(id) ON DELETE SET NULL,
        invoice_number TEXT NOT NULL,
        invoice_date TEXT NOT NULL,
        due_date TEXT,
        currency TEXT NOT NULL,
        subtotal_minor INTEGER NOT NULL CHECK (subtotal_minor >= 0),
        discount_minor INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
        tax_minor INTEGER NOT NULL DEFAULT 0 CHECK (tax_minor >= 0),
        total_minor INTEGER NOT NULL CHECK (total_minor >= 0),
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('draft','posted','void')),
        created_at TEXT NOT NULL,
        UNIQUE(supplier_id, invoice_number)
      )
    ''');

    batch.execute('''
      CREATE TABLE credit_purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL REFERENCES credit_purchase_invoices(id) ON DELETE RESTRICT,
        product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
        description TEXT NOT NULL,
        quantity_milli INTEGER NOT NULL CHECK (quantity_milli > 0),
        unit_name TEXT NOT NULL,
        unit_price_minor INTEGER NOT NULL CHECK (unit_price_minor >= 0),
        discount_minor INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
        tax_minor INTEGER NOT NULL DEFAULT 0 CHECK (tax_minor >= 0),
        line_total_minor INTEGER NOT NULL CHECK (line_total_minor >= 0)
      )
    ''');

    batch.execute('''
      CREATE TABLE supplier_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        currency TEXT NOT NULL,
        payment_date TEXT NOT NULL,
        method TEXT NOT NULL,
        receipt_number TEXT,
        notes TEXT,
        attachment_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE payment_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL REFERENCES supplier_payments(id) ON DELETE RESTRICT,
        invoice_id INTEGER NOT NULL REFERENCES credit_purchase_invoices(id) ON DELETE RESTRICT,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        created_at TEXT NOT NULL,
        UNIQUE(payment_id, invoice_id)
      )
    ''');

    batch.execute('''
      CREATE TABLE supplier_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        currency TEXT NOT NULL,
        entry_type TEXT NOT NULL CHECK (entry_type IN ('opening_balance','credit_invoice','payment','purchase_return','adjustment')),
        reference_id INTEGER,
        entry_date TEXT NOT NULL,
        signed_amount_minor INTEGER NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE purchase_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE RESTRICT,
        invoice_id INTEGER NOT NULL REFERENCES credit_purchase_invoices(id) ON DELETE RESTRICT,
        return_number TEXT NOT NULL,
        return_date TEXT NOT NULL,
        currency TEXT NOT NULL,
        total_minor INTEGER NOT NULL CHECK (total_minor > 0),
        notes TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(supplier_id, return_number)
      )
    ''');

    batch.execute('''
      CREATE TABLE purchase_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL REFERENCES purchase_returns(id) ON DELETE RESTRICT,
        invoice_item_id INTEGER REFERENCES credit_purchase_items(id) ON DELETE SET NULL,
        description TEXT NOT NULL,
        quantity_milli INTEGER NOT NULL CHECK (quantity_milli > 0),
        unit_name TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0)
      )
    ''');

    batch.execute('''
      CREATE TABLE cash_purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_date TEXT NOT NULL,
        branch_id INTEGER REFERENCES branches(id) ON DELETE SET NULL,
        employee_id INTEGER REFERENCES employees(id) ON DELETE SET NULL,
        seller_name TEXT,
        category_id INTEGER REFERENCES purchase_categories(id) ON DELETE SET NULL,
        currency TEXT NOT NULL,
        total_minor INTEGER NOT NULL CHECK (total_minor >= 0),
        due_date TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE cash_purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cash_purchase_id INTEGER NOT NULL REFERENCES cash_purchases(id) ON DELETE RESTRICT,
        product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
        item_name TEXT NOT NULL,
        quantity_milli INTEGER NOT NULL CHECK (quantity_milli > 0),
        unit_name TEXT NOT NULL,
        unit_price_minor INTEGER NOT NULL CHECK (unit_price_minor >= 0),
        line_total_minor INTEGER NOT NULL CHECK (line_total_minor >= 0)
      )
    ''');

    batch.execute('''
      CREATE TABLE cash_purchase_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cash_purchase_id INTEGER NOT NULL REFERENCES cash_purchases(id) ON DELETE RESTRICT,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        payment_date TEXT NOT NULL,
        method TEXT NOT NULL,
        reference TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE cash_purchase_outstanding_balances (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cash_purchase_id INTEGER NOT NULL UNIQUE REFERENCES cash_purchases(id) ON DELETE RESTRICT,
        original_minor INTEGER NOT NULL CHECK (original_minor > 0),
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','partial','paid','void')),
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT,
        file_size INTEGER,
        sha256 TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notification_type TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        reference_type TEXT,
        reference_id INTEGER,
        scheduled_at TEXT,
        delivered_at TEXT,
        is_read INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0,1)),
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id INTEGER,
        details_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TRIGGER trg_payment_allocation_validate
      BEFORE INSERT ON payment_allocations
      BEGIN
        SELECT CASE WHEN NEW.amount_minor > (
          SELECT amount_minor - COALESCE((SELECT SUM(amount_minor) FROM payment_allocations WHERE payment_id = NEW.payment_id), 0)
          FROM supplier_payments WHERE id = NEW.payment_id
        ) THEN RAISE(ABORT, 'Allocation exceeds payment amount') END;
        SELECT CASE WHEN (
          SELECT supplier_id FROM supplier_payments WHERE id = NEW.payment_id
        ) <> (
          SELECT supplier_id FROM credit_purchase_invoices WHERE id = NEW.invoice_id
        ) THEN RAISE(ABORT, 'Payment and invoice suppliers differ') END;
        SELECT CASE WHEN (
          SELECT currency FROM supplier_payments WHERE id = NEW.payment_id
        ) <> (
          SELECT currency FROM credit_purchase_invoices WHERE id = NEW.invoice_id
        ) THEN RAISE(ABORT, 'Payment and invoice currencies differ') END;
        SELECT CASE WHEN NEW.amount_minor +
          COALESCE((SELECT SUM(amount_minor) FROM payment_allocations WHERE invoice_id = NEW.invoice_id), 0) +
          COALESCE((SELECT SUM(total_minor) FROM purchase_returns WHERE invoice_id = NEW.invoice_id), 0) >
          (SELECT total_minor FROM credit_purchase_invoices WHERE id = NEW.invoice_id)
          THEN RAISE(ABORT, 'Allocation exceeds invoice outstanding') END;
      END
    ''');

    batch.execute('''
      CREATE TRIGGER trg_purchase_return_validate
      BEFORE INSERT ON purchase_returns
      BEGIN
        SELECT CASE WHEN NEW.supplier_id <> (SELECT supplier_id FROM credit_purchase_invoices WHERE id = NEW.invoice_id)
          THEN RAISE(ABORT, 'Return supplier differs from invoice') END;
        SELECT CASE WHEN NEW.currency <> (SELECT currency FROM credit_purchase_invoices WHERE id = NEW.invoice_id)
          THEN RAISE(ABORT, 'Return currency differs from invoice') END;
        SELECT CASE WHEN NEW.total_minor +
          COALESCE((SELECT SUM(total_minor) FROM purchase_returns WHERE invoice_id = NEW.invoice_id), 0) >
          (SELECT total_minor FROM credit_purchase_invoices WHERE id = NEW.invoice_id)
          THEN RAISE(ABORT, 'Returns exceed original invoice total') END;
      END
    ''');

    batch.execute('''
      CREATE TRIGGER trg_cash_purchase_payment_validate
      BEFORE INSERT ON cash_purchase_payments
      BEGIN
        SELECT CASE WHEN NEW.amount_minor +
          COALESCE((SELECT SUM(amount_minor) FROM cash_purchase_payments WHERE cash_purchase_id = NEW.cash_purchase_id), 0) >
          (SELECT total_minor FROM cash_purchases WHERE id = NEW.cash_purchase_id)
          THEN RAISE(ABORT, 'Payment exceeds daily purchase total') END;
      END
    ''');

    batch.execute('''
      CREATE TRIGGER trg_supplier_ledger_no_update
      BEFORE UPDATE ON supplier_ledger
      BEGIN SELECT RAISE(ABORT, 'Supplier ledger is append-only'); END
    ''');
    batch.execute('''
      CREATE TRIGGER trg_supplier_ledger_no_delete
      BEFORE DELETE ON supplier_ledger
      BEGIN SELECT RAISE(ABORT, 'Supplier ledger is append-only'); END
    ''');
    batch.execute('''
      CREATE TRIGGER trg_audit_logs_no_update
      BEFORE UPDATE ON audit_logs
      BEGIN SELECT RAISE(ABORT, 'Audit log is append-only'); END
    ''');
    batch.execute('''
      CREATE TRIGGER trg_audit_logs_no_delete
      BEFORE DELETE ON audit_logs
      BEGIN SELECT RAISE(ABORT, 'Audit log is append-only'); END
    ''');

    batch.execute(
        'CREATE INDEX idx_credit_invoice_supplier_date ON credit_purchase_invoices(supplier_id, invoice_date)');
    batch.execute(
        'CREATE INDEX idx_credit_invoice_due_date ON credit_purchase_invoices(due_date)');
    batch.execute(
        'CREATE INDEX idx_supplier_ledger_supplier_date ON supplier_ledger(supplier_id, currency, entry_date, id)');
    batch.execute(
        'CREATE INDEX idx_supplier_payments_supplier_date ON supplier_payments(supplier_id, payment_date)');
    batch.execute(
        'CREATE INDEX idx_cash_purchase_date ON cash_purchases(purchase_date)');
    batch.execute(
        'CREATE INDEX idx_cash_payment_purchase ON cash_purchase_payments(cash_purchase_id, payment_date)');
    batch.execute(
        'CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id, created_at)');

    await batch.commit(noResult: true);
    await PurchaseLedgerV2Migration.apply(db);
    await PurchaseLedgerV3Migration.apply(db);
    await PurchaseLedgerV4Migration.apply(db);
    await PurchaseLedgerV5Migration.apply(db);
    await PurchaseLedgerV6Migration.apply(db);
    await PurchaseLedgerV7Migration.apply(db);
    await PurchaseLedgerV8Migration.apply(db);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await PurchaseLedgerV2Migration.apply(db);
    }
    if (oldVersion < 3) {
      await PurchaseLedgerV3Migration.apply(db);
    }
    if (oldVersion < 4) {
      await PurchaseLedgerV4Migration.apply(db);
    }
    if (oldVersion < 5) {
      await PurchaseLedgerV5Migration.apply(db);
    }
    if (oldVersion < 6) {
      await PurchaseLedgerV6Migration.apply(db);
    }
    if (oldVersion < 7) {
      await PurchaseLedgerV7Migration.apply(db);
    }
    if (oldVersion < 8) {
      await PurchaseLedgerV8Migration.apply(db);
    }
  }

  Future<void> close() async {
    final pending = _opening;
    if (pending != null) await pending;
    await _database?.close();
    _database = null;
  }
}
