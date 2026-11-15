import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../../core/accounting/accounting_engine.dart';
import '../../../core/attachments/attachment_service.dart';
import '../../../core/database/app_database.dart';
import '../domain/supplier_accounting_models.dart';

class SupplierAccountingRepository {
  SupplierAccountingRepository(this._database);

  final AppDatabase _database;

  Future<SupplierDashboard> getDashboard(int supplierId) async {
    final db = await _database.database;
    final supplierRows = await db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [supplierId],
      limit: 1,
    );
    if (supplierRows.isEmpty) throw StateError('Supplier not found');
    final supplier = supplierRows.first;

    final movementRows = await db.rawQuery('''
      SELECT currency,
        SUM(CASE WHEN movement_type IN ('credit_invoice','daily_purchase')
                  AND signed_amount_minor > 0
                 THEN signed_amount_minor ELSE 0 END) AS purchases_minor,
        SUM(CASE WHEN signed_amount_minor < 0
                  AND movement_type IN ('payment','adjustment')
                 THEN -signed_amount_minor ELSE 0 END) AS credits_minor,
        SUM(CASE WHEN movement_type = 'purchase_return'
                 THEN -signed_amount_minor ELSE 0 END) AS returns_minor,
        SUM(signed_amount_minor) AS net_minor
      FROM supplier_account_movements
      WHERE supplier_id = ?
      GROUP BY currency
      ORDER BY currency
    ''', [supplierId]);

    final paymentRows = await db.rawQuery('''
      SELECT p.currency,
        COALESCE(SUM(p.amount_minor), 0) -
        COALESCE(SUM(r.amount_minor), 0) AS net_paid_minor
      FROM supplier_payments p
      LEFT JOIN supplier_payment_reversals r ON r.payment_id = p.id
      WHERE p.supplier_id = ?
      GROUP BY p.currency
    ''', [supplierId]);
    final netPayments = <String, int>{
      for (final row in paymentRows)
        row['currency'] as String: (row['net_paid_minor'] as int?) ?? 0,
    };

    final summaries = movementRows.map((row) {
      final currency = row['currency'] as String;
      final net = (row['net_minor'] as int?) ?? 0;
      return SupplierCurrencySummary(
        currency: currency,
        totalPurchasesMinor: (row['purchases_minor'] as int?) ?? 0,
        totalPaymentsMinor: netPayments[currency] ?? 0,
        totalReturnsMinor: (row['returns_minor'] as int?) ?? 0,
        netBalanceMinor: net,
        dueToSupplierMinor: net > 0 ? net : 0,
        advanceAtSupplierMinor: net < 0 ? -net : 0,
      );
    }).toList(growable: false);

    final invoiceRows = await db.rawQuery('''
      SELECT i.total_minor,
        COALESCE((
          SELECT SUM(a.amount_minor)
          FROM payment_allocations a
          JOIN supplier_payments p ON p.id = a.payment_id
          LEFT JOIN supplier_payment_reversals pr ON pr.payment_id = p.id
          WHERE a.invoice_id = i.id AND pr.id IS NULL
        ), 0) AS allocated_minor,
        COALESCE((
          SELECT SUM(r.total_minor)
          FROM purchase_returns r WHERE r.invoice_id = i.id
        ), 0) AS returned_minor
      FROM credit_purchase_invoices i
      WHERE i.supplier_id = ? AND i.status = 'posted'
    ''', [supplierId]);

    var unpaid = 0;
    var partial = 0;
    var paid = 0;
    for (final row in invoiceRows) {
      final total = row['total_minor'] as int;
      final allocated = row['allocated_minor'] as int;
      final returned = row['returned_minor'] as int;
      final outstanding = math.max(0, total - allocated - returned);
      if (outstanding == 0) {
        paid++;
      } else if (allocated > 0 || returned > 0) {
        partial++;
      } else {
        unpaid++;
      }
    }

    final receivedRows = await db.rawQuery('''
      SELECT unit_name, SUM(quantity_milli) AS quantity_milli, COUNT(*) AS line_count
      FROM (
        SELECT ci.unit_name, ci.quantity_milli
        FROM credit_purchase_items ci
        JOIN credit_purchase_invoices i ON i.id = ci.invoice_id
        WHERE i.supplier_id = ? AND i.status = 'posted'
        UNION ALL
        SELECT di.unit_name, di.quantity_milli
        FROM daily_purchase_items di
        JOIN daily_purchase_operations o ON o.id = di.operation_id
        WHERE o.supplier_id = ? AND o.accounting_mode = 'supplier_account' AND o.status = 'posted'
      )
      GROUP BY unit_name
    ''', [supplierId, supplierId]);
    final quantitiesByUnit = <String, int>{
      for (final row in receivedRows)
        row['unit_name'] as String: (row['quantity_milli'] as int?) ?? 0,
    };
    final receivedLineCount = receivedRows.fold<int>(
      0,
      (sum, row) => sum + ((row['line_count'] as int?) ?? 0),
    );

    final lastPurchaseRows = await db.rawQuery('''
      SELECT MAX(purchase_date) AS last_date FROM (
        SELECT invoice_date AS purchase_date
        FROM credit_purchase_invoices
        WHERE supplier_id = ? AND status = 'posted'
        UNION ALL
        SELECT s.purchase_date AS purchase_date
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.supplier_id = ? AND o.accounting_mode = 'supplier_account' AND o.status = 'posted'
      )
    ''', [supplierId, supplierId]);
    final lastPaymentRows = await db.rawQuery('''
      SELECT MAX(p.payment_date) AS last_date
      FROM supplier_payments p
      LEFT JOIN supplier_payment_reversals r ON r.payment_id = p.id
      WHERE p.supplier_id = ? AND r.id IS NULL
    ''', [supplierId]);

    final monthlyRows = await db.rawQuery('''
      SELECT month,
        SUM(purchases_minor) AS purchases_minor,
        SUM(payments_minor) AS payments_minor,
        SUM(returns_minor) AS returns_minor
      FROM (
        SELECT substr(invoice_date,1,7) AS month,
               SUM(total_minor) AS purchases_minor, 0 AS payments_minor, 0 AS returns_minor
        FROM credit_purchase_invoices
        WHERE supplier_id = ? AND status = 'posted'
        GROUP BY substr(invoice_date,1,7)
        UNION ALL
        SELECT substr(s.purchase_date,1,7) AS month,
               SUM(o.total_minor) AS purchases_minor, 0 AS payments_minor, 0 AS returns_minor
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.supplier_id = ? AND o.accounting_mode = 'supplier_account' AND o.status = 'posted'
        GROUP BY substr(s.purchase_date,1,7)
        UNION ALL
        SELECT substr(payment_date,1,7), 0,
               SUM(p.amount_minor - COALESCE(r.amount_minor,0)), 0
        FROM supplier_payments p
        LEFT JOIN supplier_payment_reversals r ON r.payment_id = p.id
        WHERE p.supplier_id = ?
        GROUP BY substr(payment_date,1,7)
        UNION ALL
        SELECT substr(return_date,1,7), 0, 0, SUM(total_minor)
        FROM purchase_returns
        WHERE supplier_id = ?
        GROUP BY substr(return_date,1,7)
      )
      GROUP BY month
      ORDER BY month
    ''', [supplierId, supplierId, supplierId, supplierId]);

    return SupplierDashboard(
      supplierId: supplierId,
      name: supplier['name'] as String,
      phone: supplier['phone'] as String?,
      address: supplier['address'] as String?,
      companyName: supplier['company_name'] as String?,
      activityType: supplier['activity_type'] as String?,
      notes: supplier['notes'] as String?,
      defaultCurrency: supplier['default_currency'] as String,
      currencySummaries: summaries,
      invoiceCount: invoiceRows.length,
      receivedLineCount: receivedLineCount,
      receivedQuantitiesByUnit: quantitiesByUnit,
      unpaidInvoiceCount: unpaid,
      partiallyPaidInvoiceCount: partial,
      paidInvoiceCount: paid,
      lastPurchaseDate: lastPurchaseRows.first['last_date'] as String?,
      lastPaymentDate: lastPaymentRows.first['last_date'] as String?,
      monthlyActivity: monthlyRows
          .map((row) => SupplierMonthlyActivity(
                month: row['month'] as String,
                purchasesMinor: (row['purchases_minor'] as int?) ?? 0,
                paymentsMinor: (row['payments_minor'] as int?) ?? 0,
                returnsMinor: (row['returns_minor'] as int?) ?? 0,
              ))
          .toList(growable: false),
    );
  }

  /// An invoice may be voided only when no effective payment allocation or
  /// return remains. Previously reversed payments preserve their audit trail.
  /// Historical lines are retained. The account entry is reversed atomically.
  Future<void> voidUnsettledInvoice(int invoiceId, {required String reason}) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw ArgumentError('Cancellation reason is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final invoices = await txn.query('credit_purchase_invoices',
        where: "id = ? AND status = 'posted'", whereArgs: [invoiceId], limit: 1);
      if (invoices.isEmpty) throw StateError('Invoice is already void or missing');
      final invoice = invoices.first;
      final allocations = Sqflite.firstIntValue(await txn.rawQuery('''
        SELECT COUNT(*) FROM payment_allocations allocation
        JOIN supplier_payments payment ON payment.id = allocation.payment_id
        LEFT JOIN supplier_payment_reversals refund
          ON refund.payment_id = payment.id
        WHERE allocation.invoice_id = ? AND refund.id IS NULL
      ''', [invoiceId])) ?? 0;
      final returns = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM purchase_returns WHERE invoice_id = ?', [invoiceId])) ?? 0;
      if (allocations != 0 || returns != 0) {
        throw StateError('Cannot directly cancel a settled or returned invoice; '
          'reverse its linked payments/returns first using an approved correction');
      }
      final originals = await txn.query('supplier_account_movements',
        where: "source_type = 'credit_invoice' AND source_id = ? AND movement_type = 'credit_invoice'",
        whereArgs: [invoiceId], limit: 1);
      if (originals.isEmpty) throw StateError('Original supplier movement is missing');
      final original = originals.first;
      final prior = await txn.query('supplier_account_movements',
        where: 'reverses_movement_id = ?', whereArgs: [original['id']], limit: 1);
      if (prior.isNotEmpty) throw StateError('Invoice movement already reversed');
      final reversalId = await txn.insert('supplier_account_movements', {
        'supplier_id': invoice['supplier_id'],
        'currency': invoice['currency'],
        'movement_type': 'reversal',
        'source_type': 'credit_invoice_void',
        'source_id': invoiceId,
        'entry_date': now.substring(0, 10),
        'signed_amount_minor': -(original['signed_amount_minor'] as int),
        'note': 'إلغاء فاتورة #${invoice['invoice_number']}: $cleanReason',
        'reverses_movement_id': original['id'],
        'created_at': now,
      });
      // The V2 supplier movements are canonical. Keep the original V1 ledger
      // mirror coherent for legacy exports without posting a second balance.
      await txn.insert('supplier_ledger', {
        'supplier_id': invoice['supplier_id'],
        'currency': invoice['currency'],
        'entry_type': 'adjustment',
        'reference_id': reversalId,
        'entry_date': now.substring(0, 10),
        'signed_amount_minor': -(original['signed_amount_minor'] as int),
        'note': 'عكس فاتورة ${invoice['invoice_number']}: $cleanReason',
        'created_at': now,
      });
      await txn.update('credit_purchase_invoices', {'status':'void'},
        where: "id = ? AND status = 'posted'", whereArgs: [invoiceId]);
      await _audit(txn, 'void', 'credit_purchase_invoice', invoiceId,
        {'reason': cleanReason, 'reversed_movement_id': original['id'],
        'original_total_minor': invoice['total_minor']}, now);
    });
  }

  Future<SupplierInvoiceDetail> getInvoiceDetail(int invoiceId) async {
    final db = await _database.database;
    final invoiceRows = await db.query(
      'credit_purchase_invoices',
      where: "id = ? AND status = 'posted'",
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (invoiceRows.isEmpty) throw StateError('Invoice not found');
    final invoice = invoiceRows.first;
    final itemRows = await db.rawQuery('''
      SELECT ci.*,
        COALESCE((
          SELECT SUM(ri.quantity_milli)
          FROM purchase_return_items ri
          JOIN purchase_returns r ON r.id = ri.return_id
          WHERE ri.invoice_item_id = ci.id
        ),0) AS returned_quantity_milli,
        COALESCE((
          SELECT SUM(ri.amount_minor)
          FROM purchase_return_items ri
          JOIN purchase_returns r ON r.id = ri.return_id
          WHERE ri.invoice_item_id = ci.id
        ),0) AS returned_amount_minor
      FROM credit_purchase_items ci
      WHERE ci.invoice_id = ?
      ORDER BY ci.id
    ''', [invoiceId]);
    final unlinkedReturnAmount = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COALESCE(SUM(ri.amount_minor),0)
      FROM purchase_return_items ri
      JOIN purchase_returns r ON r.id = ri.return_id
      WHERE r.invoice_id = ? AND ri.invoice_item_id IS NULL
    ''', [invoiceId])) ?? 0;
    return SupplierInvoiceDetail(
      id: invoiceId,
      supplierId: invoice['supplier_id'] as int,
      invoiceNumber: invoice['invoice_number'] as String,
      invoiceDate: invoice['invoice_date'] as String,
      currency: invoice['currency'] as String,
      totalMinor: invoice['total_minor'] as int,
      unlinkedReturnAmountMinor: unlinkedReturnAmount,
      items: itemRows
          .map((row) => SupplierInvoiceItemDetail(
                id: row['id'] as int,
                description: row['description'] as String,
                quantityMilli: row['quantity_milli'] as int,
                unitName: row['unit_name'] as String,
                unitPriceMinor: row['unit_price_minor'] as int,
                discountMinor: row['discount_minor'] as int,
                taxMinor: row['tax_minor'] as int,
                lineTotalMinor: row['line_total_minor'] as int,
                returnedQuantityMilli: row['returned_quantity_milli'] as int,
                returnedAmountMinor: row['returned_amount_minor'] as int,
              ))
          .toList(growable: false),
    );
  }

  Future<List<SupplierInvoiceBalance>> getInvoices(int supplierId) async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT i.id, i.invoice_number, i.invoice_date, i.currency, i.total_minor, i.due_date,
        COALESCE((
          SELECT SUM(a.amount_minor)
          FROM payment_allocations a
          JOIN supplier_payments p ON p.id = a.payment_id
          LEFT JOIN supplier_payment_reversals pr ON pr.payment_id = p.id
          WHERE a.invoice_id = i.id AND pr.id IS NULL
        ), 0) AS allocated_minor,
        COALESCE((
          SELECT SUM(r.total_minor) FROM purchase_returns r WHERE r.invoice_id = i.id
        ), 0) AS returned_minor
      FROM credit_purchase_invoices i
      WHERE i.supplier_id = ? AND i.status = 'posted'
      ORDER BY i.invoice_date DESC, i.id DESC
    ''', [supplierId]);
    return rows.map((row) {
      final total = row['total_minor'] as int;
      final allocated = row['allocated_minor'] as int;
      final returned = row['returned_minor'] as int;
      return SupplierInvoiceBalance(
        id: row['id'] as int,
        invoiceNumber: row['invoice_number'] as String,
        invoiceDate: row['invoice_date'] as String,
        currency: row['currency'] as String,
        totalMinor: total,
        allocatedMinor: allocated,
        returnedMinor: returned,
        outstandingMinor: math.max(0, total - allocated - returned),
        dueDate: row['due_date'] as String?,
      );
    }).toList(growable: false);
  }

  Future<List<SupplierPaymentRecord>> getPayments(int supplierId) async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT p.*,
        COALESCE((
          SELECT SUM(a.amount_minor) FROM payment_allocations a
          WHERE a.payment_id = p.id
        ),0) AS allocated_minor,
        CASE WHEN r.id IS NULL THEN 0 ELSE 1 END AS is_reversed
      FROM supplier_payments p
      LEFT JOIN supplier_payment_reversals r ON r.payment_id = p.id
      WHERE p.supplier_id = ?
      ORDER BY p.payment_date DESC, p.id DESC
    ''', [supplierId]);
    return rows
        .map((row) => SupplierPaymentRecord(
              id: row['id'] as int,
              receiptNumber: row['receipt_number'] as String?,
              paymentDate: row['payment_date'] as String,
              amountMinor: row['amount_minor'] as int,
              currency: row['currency'] as String,
              method: row['method'] as String,
              allocatedMinor: row['allocated_minor'] as int,
              isReversed: (row['is_reversed'] as int) == 1,
              notes: row['notes'] as String?,
            ))
        .toList(growable: false);
  }

  Future<List<SupplierAdvance>> getUnallocatedAdvances(int supplierId) async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.receipt_number, p.payment_date, p.currency, p.amount_minor,
        COALESCE(SUM(a.amount_minor),0) AS allocated_minor
      FROM supplier_payments p
      LEFT JOIN payment_allocations a ON a.payment_id = p.id
      LEFT JOIN supplier_payment_reversals r ON r.payment_id = p.id
      WHERE p.supplier_id = ? AND r.id IS NULL
      GROUP BY p.id
      HAVING p.amount_minor - COALESCE(SUM(a.amount_minor),0) > 0
      ORDER BY p.payment_date, p.id
    ''', [supplierId]);
    return rows.map((row) {
      final amount = row['amount_minor'] as int;
      final allocated = row['allocated_minor'] as int;
      return SupplierAdvance(
        paymentId: row['id'] as int,
        receiptNumber: row['receipt_number'] as String?,
        paymentDate: row['payment_date'] as String,
        currency: row['currency'] as String,
        amountMinor: amount,
        allocatedMinor: allocated,
        remainingMinor: amount - allocated,
      );
    }).toList(growable: false);
  }

  Future<SupplierStatement> getStatement({
    required int supplierId,
    required String currency,
    String? periodFrom,
    String? periodTo,
  }) async {
    if (periodFrom != null &&
        periodTo != null &&
        periodFrom.compareTo(periodTo) > 0) {
      throw ArgumentError('Statement start date must not be after end date');
    }
    final db = await _database.database;
    final supplierRows = await db.query(
      'suppliers',
      columns: ['name', 'phone', 'address'],
      where: 'id = ?',
      whereArgs: [supplierId],
      limit: 1,
    );
    if (supplierRows.isEmpty) throw StateError('Supplier not found');

    final where = <String>['supplier_id = ?', 'currency = ?'];
    final args = <Object?>[supplierId, currency];
    if (periodFrom != null) {
      where.add('entry_date >= ?');
      args.add(periodFrom);
    }
    if (periodTo != null) {
      where.add('entry_date <= ?');
      args.add(periodTo);
    }
    final movementRows = await db.rawQuery('''
      SELECT m.*,
        CASE
          WHEN m.source_type = 'credit_invoice' THEN (
            SELECT invoice_number FROM credit_purchase_invoices WHERE id = m.source_id
          )
          WHEN m.source_type = 'payment' THEN (
            SELECT COALESCE(receipt_number, 'PAY-' || id)
            FROM supplier_payments WHERE id = m.source_id
          )
          WHEN m.source_type = 'purchase_return' THEN (
            SELECT return_number FROM purchase_returns WHERE id = m.source_id
          )
          WHEN m.source_type = 'daily_purchase' THEN (
            SELECT operation_number FROM daily_purchase_operations WHERE id = m.source_id
          )
          ELSE NULL
        END AS document_number
      FROM supplier_account_movements m
      WHERE ${where.join(' AND ')}
      ORDER BY entry_date, id
    ''', args);

    var opening = 0;
    if (periodFrom != null) {
      opening = Sqflite.firstIntValue(await db.rawQuery('''
        SELECT COALESCE(SUM(signed_amount_minor),0)
        FROM supplier_account_movements
        WHERE supplier_id = ? AND currency = ? AND entry_date < ?
      ''', [supplierId, currency, periodFrom])) ?? 0;
    }

    var running = opening;
    var purchases = 0;
    var payments = 0;
    var returns = 0;
    var adjustments = 0;
    final movements = <SupplierStatementMovement>[];
    for (final row in movementRows) {
      final type = row['movement_type'] as String;
      final signed = row['signed_amount_minor'] as int;
      running += signed;
      if (type == 'credit_invoice' || type == 'daily_purchase') {
        purchases += signed;
      } else if (type == 'payment') {
        payments += -signed;
      } else if (type == 'purchase_return') {
        returns += -signed;
      } else if (type == 'adjustment') {
        adjustments += signed;
      } else if (type == 'reversal') {
        if (row['source_type'] == 'supplier_payment_reversal') {
          payments -= signed;
        } else {
          adjustments += signed;
        }
      }
      final doc = row['document_number'] as String?;
      movements.add(SupplierStatementMovement(
        id: row['id'] as int,
        entryDate: row['entry_date'] as String,
        documentNumber: doc ?? '${type.toUpperCase()}-${row['id']}',
        movementType: type,
        details: (row['note'] as String?) ?? _movementLabel(type),
        signedAmountMinor: signed,
        runningBalanceMinor: running,
      ));
    }

    return SupplierStatement(
      supplierId: supplierId,
      supplierName: supplierRows.first['name'] as String,
      supplierPhone: supplierRows.first['phone'] as String?,
      supplierAddress: supplierRows.first['address'] as String?,
      currency: currency,
      periodFrom: periodFrom,
      periodTo: periodTo,
      openingBalanceMinor: opening,
      movements: movements,
      closingBalanceMinor: running,
      totalPurchasesMinor: purchases,
      totalPaymentsMinor: payments,
      totalReturnsMinor: returns,
      totalAdjustmentsMinor: adjustments,
    );
  }

  Future<int> archiveStatement(
    SupplierStatement statement, {
    String statementType = 'detailed',
    Map<String, Object?> businessProfile = const {},
  }) async {
    final db = await _database.database;
    final snapshot = {
      'supplier_id': statement.supplierId,
      'supplier_name': statement.supplierName,
      'supplier_phone': statement.supplierPhone,
      'supplier_address': statement.supplierAddress,
      'currency': statement.currency,
      'period_from': statement.periodFrom,
      'period_to': statement.periodTo,
      'opening_balance_minor': statement.openingBalanceMinor,
      'closing_balance_minor': statement.closingBalanceMinor,
      'total_purchases_minor': statement.totalPurchasesMinor,
      'total_payments_minor': statement.totalPaymentsMinor,
      'total_returns_minor': statement.totalReturnsMinor,
      'total_adjustments_minor': statement.totalAdjustmentsMinor,
      'business_profile': businessProfile,
      'movements': statement.movements
          .map((movement) => {
                'id': movement.id,
                'entry_date': movement.entryDate,
                'document_number': movement.documentNumber,
                'movement_type': movement.movementType,
                'details': movement.details,
                'signed_amount_minor': movement.signedAmountMinor,
                'running_balance_minor': movement.runningBalanceMinor,
              })
          .toList(),
    };
    return db.insert('supplier_statement_archives', {
      'supplier_id': statement.supplierId,
      'currency': statement.currency,
      'period_from': statement.periodFrom,
      'period_to': statement.periodTo,
      'statement_type': statementType,
      'snapshot_json': jsonEncode(snapshot),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// The canonical balance includes advances and prior reversals; never use
  /// only unpaid invoice totals as the supplier's due amount.
  Future<int> getCurrentDueMinor(int supplierId, String currency) async {
    final db = await _database.database;
    final balance = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COALESCE(SUM(signed_amount_minor), 0)
      FROM supplier_account_movements WHERE supplier_id = ? AND currency = ?
    ''', [supplierId, currency])) ?? 0;
    return math.max(0, balance);
  }

  Future<int> recordPayment({
    required int supplierId,
    required int amountMinor,
    required String currency,
    required String paymentDate,
    required String method,
    String? receiptNumber,
    String? notes,
    Map<int, int> allocations = const {},
    String? idempotencyKey,
    AttachmentDraft? attachment,
    bool allowAdvance = false,
    int? expectedDueMinor,
  }) async {
    if (amountMinor <= 0)
      throw ArgumentError('Payment must be greater than zero');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    final cleanReceipt = _clean(receiptNumber);
    final storedReceipt = cleanReceipt ??
        'PAY-$supplierId-${DateTime.now().microsecondsSinceEpoch}';
    final cleanKey = _clean(idempotencyKey);

    return db.transaction((txn) async {
      final supplierRows = await txn.query(
        'suppliers',
        columns: ['id'],
        where: 'id = ? AND is_archived = 0',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (supplierRows.isEmpty)
        throw StateError('Supplier not found or archived');

      if (cleanKey != null) {
        final duplicate = await txn.query(
          'supplier_payments',
          columns: ['id'],
          where: 'idempotency_key = ?',
          whereArgs: [cleanKey],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          final existingRows = await txn.query(
            'supplier_payments',
            where: 'id = ?',
            whereArgs: [duplicate.first['id']],
            limit: 1,
          );
          final existing = existingRows.first;
          if (existing['supplier_id'] != supplierId ||
              existing['amount_minor'] != amountMinor ||
              existing['currency'] != currency ||
              existing['payment_date'] != paymentDate ||
              existing['method'] != method ||
              (cleanReceipt != null &&
                  existing['receipt_number'] != cleanReceipt) ||
              existing['notes'] != _clean(notes)) {
            throw StateError(
                'Idempotency key was already used for a different payment');
          }
          final existingAllocations = await txn.query(
            'payment_allocations',
            columns: ['invoice_id', 'amount_minor'],
            where: 'payment_id = ?',
            whereArgs: [existing['id']],
          );
          final existingMap = <int, int>{
            for (final row in existingAllocations)
              row['invoice_id'] as int: row['amount_minor'] as int,
          };
          final requestedMap = <int, int>{
            for (final entry in allocations.entries)
              if (entry.value > 0) entry.key: entry.value,
          };
          if (existingMap.length != requestedMap.length ||
              requestedMap.entries
                  .any((entry) => existingMap[entry.key] != entry.value)) {
            throw StateError(
                'Idempotency key was already used with different invoice allocations');
          }
          return duplicate.first['id'] as int;
        }
      }
      if (cleanReceipt != null) {
        final duplicate = await txn.query(
          'supplier_payments',
          columns: ['id'],
          where: 'supplier_id = ? AND currency = ? AND receipt_number = ?',
          whereArgs: [supplierId, currency, cleanReceipt],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw StateError(
              'A payment with this receipt number is already registered');
        }
      }

      final liveBalance = Sqflite.firstIntValue(await txn.rawQuery('''
        SELECT COALESCE(SUM(signed_amount_minor),0)
        FROM supplier_account_movements WHERE supplier_id = ? AND currency = ?
      ''', [supplierId, currency])) ?? 0;
      final liveDue = math.max(0, liveBalance);
      if (expectedDueMinor != null && expectedDueMinor != liveDue) {
        throw StateError('Supplier balance changed; review and reconfirm the payment');
      }
      if (amountMinor > liveDue && !allowAdvance) {
        throw StateError('Excess payment requires explicit advance confirmation');
      }
      final openInvoices = await _getOpenInvoiceBalances(
        txn,
        supplierId: supplierId,
        currency: currency,
      );
      final plan = AccountingEngine.planPaymentAllocations(
        paymentAmountMinor: amountMinor,
        supplierId: supplierId,
        currency: currency,
        invoices: openInvoices,
        requested: allocations.entries
            .map((entry) => RequestedInvoiceAllocation(
                  invoiceId: entry.key,
                  amountMinor: entry.value,
                ))
            .toList(growable: false),
      );

      final paymentId = await txn.insert('supplier_payments', {
        'supplier_id': supplierId,
        'amount_minor': amountMinor,
        'currency': currency,
        'payment_date': paymentDate,
        'method': method,
        'receipt_number': storedReceipt,
        'notes': _clean(notes),
        'idempotency_key': cleanKey,
        'created_at': now,
      });
      if (attachment != null) {
        final attachmentId = await AttachmentService.save(
          txn,
          draft: attachment,
          entityType: 'supplier_payment',
          entityId: paymentId,
        );
        await txn.update(
          'supplier_payments',
          {'attachment_id': attachmentId},
          where: 'id = ?',
          whereArgs: [paymentId],
        );
      }

      for (final allocation in plan.allocations.entries) {
        await txn.insert('payment_allocations', {
          'payment_id': paymentId,
          'invoice_id': allocation.key,
          'amount_minor': allocation.value,
          'created_at': now,
        });
      }

      await _insertSupplierMovement(
        txn,
        supplierId: supplierId,
        currency: currency,
        movementType: 'payment',
        sourceType: 'payment',
        sourceId: paymentId,
        entryDate: paymentDate,
        signedAmountMinor: -amountMinor,
        note: _clean(notes) ?? 'Supplier payment',
        createdAt: now,
        idempotencyKey: cleanKey,
      );
      await txn.insert('supplier_ledger', {
        'supplier_id': supplierId,
        'currency': currency,
        'entry_type': 'payment',
        'reference_id': paymentId,
        'entry_date': paymentDate,
        'signed_amount_minor': -amountMinor,
        'note': _clean(notes) ?? 'Supplier payment',
        'created_at': now,
      });
      await _audit(
          txn,
          'create',
          'supplier_payment',
          paymentId,
          {
            'amount_minor': amountMinor,
            'currency': currency,
            'allocated_minor': plan.allocatedMinor,
            'advance_minor': plan.unallocatedAdvanceMinor,
          },
          now);
      return paymentId;
    });
  }

  Future<void> allocateAdvance({
    required int paymentId,
    required Map<int, int> allocations,
  }) async {
    if (allocations.isEmpty) throw ArgumentError('Select at least one invoice');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final paymentRows = await txn.query(
        'supplier_payments',
        columns: ['supplier_id', 'amount_minor', 'currency'],
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (paymentRows.isEmpty) throw StateError('Advance payment not found');
      final payment = paymentRows.first;
      final supplierId = payment['supplier_id'] as int;
      final currency = payment['currency'] as String;
      final reversed = await txn.query(
        'supplier_payment_reversals',
        columns: ['id'],
        where: 'payment_id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (reversed.isNotEmpty)
        throw StateError('Cannot allocate a reversed payment');

      final allocated = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(SUM(amount_minor),0) FROM payment_allocations WHERE payment_id = ?',
            [paymentId],
          )) ??
          0;
      final paymentAmount = payment['amount_minor'] as int;
      final available = paymentAmount - allocated;
      final openInvoices = await _getOpenInvoiceBalances(
        txn,
        supplierId: supplierId,
        currency: currency,
      );
      final plan = AccountingEngine.planPaymentAllocations(
        paymentAmountMinor: available,
        supplierId: supplierId,
        currency: currency,
        invoices: openInvoices,
        requested: allocations.entries
            .map((entry) => RequestedInvoiceAllocation(
                  invoiceId: entry.key,
                  amountMinor: entry.value,
                ))
            .toList(growable: false),
      );
      for (final allocation in plan.allocations.entries) {
        await txn.insert('payment_allocations', {
          'payment_id': paymentId,
          'invoice_id': allocation.key,
          'amount_minor': allocation.value,
          'created_at': now,
        });
      }
      await _audit(
          txn,
          'allocate_advance',
          'supplier_payment',
          paymentId,
          {
            'allocated_minor': plan.allocatedMinor,
            'allocations': allocations,
          },
          now);
    });
  }

  Future<void> reversePayment({
    required int paymentId,
    required String reversalDate,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty)
      throw ArgumentError('A reversal reason is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final paymentRows = await txn.query(
        'supplier_payments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (paymentRows.isEmpty) throw StateError('Payment not found');
      final payment = paymentRows.first;
      final alreadyReversed = await txn.query(
        'supplier_payment_reversals',
        columns: ['id'],
        where: 'payment_id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (alreadyReversed.isNotEmpty)
        throw StateError('Payment has already been reversed');

      final originalMovementRows = await txn.query(
        'supplier_account_movements',
        columns: ['id'],
        where:
            "source_type = 'payment' AND source_id = ? AND movement_type = 'payment'",
        whereArgs: [paymentId],
        limit: 1,
      );
      if (originalMovementRows.isEmpty)
        throw StateError('Original account movement not found');
      final originalMovementId = originalMovementRows.first['id'] as int;
      final amount = payment['amount_minor'] as int;
      final reversalId = await txn.insert('supplier_payment_reversals', {
        'payment_id': paymentId,
        'amount_minor': amount,
        'reversal_date': reversalDate,
        'reason': cleanReason,
        'created_at': now,
      });
      await _insertSupplierMovement(
        txn,
        supplierId: payment['supplier_id'] as int,
        currency: payment['currency'] as String,
        movementType: 'reversal',
        sourceType: 'supplier_payment_reversal',
        sourceId: reversalId,
        entryDate: reversalDate,
        signedAmountMinor: amount,
        note: 'Payment reversal: $cleanReason',
        createdAt: now,
        reversesMovementId: originalMovementId,
      );
      await txn.insert('supplier_ledger', {
        'supplier_id': payment['supplier_id'],
        'currency': payment['currency'],
        'entry_type': 'adjustment',
        'reference_id': reversalId,
        'entry_date': reversalDate,
        'signed_amount_minor': amount,
        'note': 'Payment reversal: $cleanReason',
        'created_at': now,
      });
      await _audit(
          txn,
          'reverse',
          'supplier_payment',
          paymentId,
          {
            'reversal_id': reversalId,
            'amount_minor': amount,
            'reason': cleanReason,
          },
          now);
    });
  }

  Future<int> createAdjustment({
    required int supplierId,
    required String currency,
    required int signedAmountMinor,
    required String entryDate,
    required String reason,
  }) async {
    if (signedAmountMinor == 0)
      throw ArgumentError('Adjustment cannot be zero');
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty)
      throw ArgumentError('Adjustment reason is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    return db.transaction((txn) async {
      final supplier = await txn.query(
        'suppliers',
        columns: ['id'],
        where: 'id = ? AND is_archived = 0',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (supplier.isEmpty) throw StateError('Supplier not found');
      final movementId = await txn.insert('supplier_account_movements', {
        'supplier_id': supplierId,
        'currency': currency,
        'movement_type': 'adjustment',
        'source_type': 'adjustment',
        'entry_date': entryDate,
        'signed_amount_minor': signedAmountMinor,
        'note': cleanReason,
        'created_at': now,
      });
      await txn.insert('supplier_ledger', {
        'supplier_id': supplierId,
        'currency': currency,
        'entry_type': 'adjustment',
        'reference_id': movementId,
        'entry_date': entryDate,
        'signed_amount_minor': signedAmountMinor,
        'note': cleanReason,
        'created_at': now,
      });
      await _audit(
          txn,
          'adjust',
          'supplier_account',
          supplierId,
          {
            'movement_id': movementId,
            'currency': currency,
            'signed_amount_minor': signedAmountMinor,
            'reason': cleanReason,
          },
          now);
      return movementId;
    });
  }

  Future<List<InvoiceOpenBalance>> _getOpenInvoiceBalances(
    DatabaseExecutor executor, {
    required int supplierId,
    required String currency,
  }) async {
    final rows = await executor.rawQuery('''
      SELECT i.id, i.supplier_id, i.currency, i.total_minor,
        COALESCE((
          SELECT SUM(a.amount_minor)
          FROM payment_allocations a
          JOIN supplier_payments p ON p.id = a.payment_id
          LEFT JOIN supplier_payment_reversals pr ON pr.payment_id = p.id
          WHERE a.invoice_id = i.id AND pr.id IS NULL
        ), 0) AS allocated_minor,
        COALESCE((
          SELECT SUM(r.total_minor) FROM purchase_returns r WHERE r.invoice_id = i.id
        ), 0) AS returned_minor
      FROM credit_purchase_invoices i
      WHERE i.supplier_id = ? AND i.currency = ? AND i.status = 'posted'
      ORDER BY i.invoice_date, i.id
    ''', [supplierId, currency]);
    return rows
        .map((row) {
          final total = row['total_minor'] as int;
          final allocated = row['allocated_minor'] as int;
          final returned = row['returned_minor'] as int;
          return InvoiceOpenBalance(
            invoiceId: row['id'] as int,
            supplierId: row['supplier_id'] as int,
            currency: row['currency'] as String,
            outstandingMinor: math.max(0, total - allocated - returned),
          );
        })
        .where((invoice) => invoice.outstandingMinor > 0)
        .toList(growable: false);
  }

  Future<int> _insertSupplierMovement(
    DatabaseExecutor executor, {
    required int supplierId,
    required String currency,
    required String movementType,
    required String sourceType,
    required int? sourceId,
    required String entryDate,
    required int signedAmountMinor,
    required String? note,
    required String createdAt,
    String? idempotencyKey,
    int? reversesMovementId,
  }) {
    return executor.insert('supplier_account_movements', {
      'supplier_id': supplierId,
      'currency': currency,
      'movement_type': movementType,
      'source_type': sourceType,
      'source_id': sourceId,
      'entry_date': entryDate,
      'signed_amount_minor': signedAmountMinor,
      'note': note,
      'reverses_movement_id': reversesMovementId,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt,
    });
  }

  Future<void> _audit(
    DatabaseExecutor executor,
    String action,
    String entityType,
    int entityId,
    Map<String, Object?> details,
    String createdAt,
  ) async {
    await executor.insert('audit_logs', {
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'details_json': _encodeDetails(details),
      'created_at': createdAt,
    });
  }

  String _movementLabel(String type) {
    switch (type) {
      case 'opening_balance':
        return 'Opening balance';
      case 'credit_invoice':
        return 'Credit purchase invoice';
      case 'payment':
        return 'Supplier payment';
      case 'purchase_return':
        return 'Purchase return';
      case 'daily_purchase':
        return 'Daily purchase linked to supplier account';
      case 'adjustment':
        return 'Account adjustment';
      case 'reversal':
        return 'Reversal';
      default:
        return type;
    }
  }

  String? _clean(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }

  String _encodeDetails(Map<String, Object?> values) {
    final entries = values.entries.map((entry) {
      final value = entry.value;
      final encoded = value is String
          ? '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"'
          : value is Map
              ? '{${value.entries.map((e) => '"${e.key}":${e.value}').join(',')}}'
              : value.toString();
      return '"${entry.key}":$encoded';
    });
    return '{${entries.join(',')}}';
  }
}
