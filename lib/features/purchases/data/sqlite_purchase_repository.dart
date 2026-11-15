import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/attachments/attachment_service.dart';
import '../domain/purchase_line.dart';
import '../domain/purchase_models.dart';
import '../domain/purchase_repository.dart';

class SqlitePurchaseRepository implements PurchaseRepository {
  SqlitePurchaseRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<InvoiceSummary>> getCreditInvoices() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT i.id, i.supplier_id, i.invoice_number, s.name AS supplier_name, i.invoice_date,
        i.currency, i.total_minor, i.due_date,
        COALESCE((SELECT SUM(a.amount_minor)
          FROM payment_allocations a
          JOIN supplier_payments p ON p.id = a.payment_id
          LEFT JOIN supplier_payment_reversals pr ON pr.payment_id = p.id
          WHERE a.invoice_id = i.id AND pr.id IS NULL), 0) AS paid_minor,
        COALESCE((SELECT SUM(r.total_minor)
          FROM purchase_returns r WHERE r.invoice_id = i.id), 0) AS returned_minor
      FROM credit_purchase_invoices i
      JOIN suppliers s ON s.id = i.supplier_id
      WHERE i.status = 'posted'
      ORDER BY i.invoice_date DESC, i.id DESC
    ''');
    return rows
        .map((row) => InvoiceSummary(
              id: row['id'] as int,
              supplierId: row['supplier_id'] as int,
              invoiceNumber: row['invoice_number'] as String,
              supplierName: row['supplier_name'] as String,
              invoiceDate: row['invoice_date'] as String,
              currency: row['currency'] as String,
              totalMinor: row['total_minor'] as int,
              paidMinor: row['paid_minor'] as int,
              returnedMinor: row['returned_minor'] as int,
              dueDate: row['due_date'] as String?,
            ))
        .toList(growable: false);
  }

  @override
  Future<List<DailyPurchaseSummary>> getDailyPurchases() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT o.id, s.purchase_date, COALESCE(o.seller_name, sp.name) AS seller_name,
        o.currency, o.total_minor,
        o.amount_paid_minor + CASE WHEN o.accounting_mode = 'daily_outstanding'
          THEN COALESCE((
            SELECT SUM(p.amount_minor)
            FROM daily_purchase_outstanding_payments p
            JOIN daily_purchase_outstandings ob ON ob.id = p.outstanding_id
            WHERE ob.operation_id = o.id
          ),0) ELSE 0 END AS paid_minor,
        o.due_date
      FROM daily_purchase_operations o
      JOIN daily_purchase_sheets s ON s.id = o.sheet_id
      LEFT JOIN suppliers sp ON sp.id = o.supplier_id
      WHERE o.status = 'posted'
      ORDER BY s.purchase_date DESC, o.id DESC
    ''');
    return rows
        .map((row) => DailyPurchaseSummary(
              id: row['id'] as int,
              purchaseDate: row['purchase_date'] as String,
              sellerName: row['seller_name'] as String?,
              currency: row['currency'] as String,
              totalMinor: row['total_minor'] as int,
              paidMinor: row['paid_minor'] as int,
              dueDate: row['due_date'] as String?,
            ))
        .toList(growable: false);
  }

  @override
  Future<int> createCreditInvoice({
    required int supplierId,
    required String invoiceNumber,
    required String invoiceDate,
    String? dueDate,
    required String currency,
    required List<PurchaseLine> lines,
    int paidMinor = 0,
    String initialPaymentMethod = 'cash',
    String? notes,
    int? branchId,
    int? employeeId,
    String? receivedAt,
    AttachmentDraft? attachment,
  }) async {
    final cleanNumber = invoiceNumber.trim();
    if (cleanNumber.isEmpty) throw ArgumentError('Invoice number is required');
    if (lines.isEmpty)
      throw ArgumentError('At least one invoice item is required');
    if (paidMinor < 0) throw ArgumentError('Paid amount cannot be negative');
    final totals = _calculateTotals(lines);
    if (totals.totalMinor <= 0)
      throw ArgumentError('Invoice total must be greater than zero');
    final now = DateTime.now().toIso8601String();
    final db = await _database.database;

    return db.transaction((txn) async {
      final supplierRows = await txn.query(
        'suppliers',
        columns: ['id'],
        where: 'id = ? AND is_archived = 0',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (supplierRows.isEmpty)
        throw StateError('Supplier does not exist or is archived');

      final invoiceId = await txn.insert('credit_purchase_invoices', {
        'supplier_id': supplierId,
        'invoice_number': cleanNumber,
        'invoice_date': invoiceDate,
        'received_at': receivedAt ?? now,
        'branch_id': branchId,
        'employee_id': employeeId,
        'due_date': _clean(dueDate),
        'currency': currency,
        'subtotal_minor': totals.subtotalMinor,
        'discount_minor': totals.discountMinor,
        'tax_minor': totals.taxMinor,
        'total_minor': totals.totalMinor,
        'notes': _clean(notes),
        'status': 'posted',
        'created_at': now,
      });
      if (attachment != null) {
        final attachmentId = await AttachmentService.save(
          txn,
          draft: attachment,
          entityType: 'credit_purchase_invoice',
          entityId: invoiceId,
        );
        await txn.update(
          'credit_purchase_invoices',
          {'attachment_id': attachmentId},
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
      }

      for (final line in lines) {
        await txn.insert('credit_purchase_items', {
          'invoice_id': invoiceId,
          'product_id': line.productId,
          'category_id': line.categoryId,
          'description': line.description.trim(),
          'quantity_milli': line.quantityMilli,
          'unit_name': line.unitName.trim(),
          'unit_price_minor': line.unitPriceMinor,
          'discount_minor': line.discountMinor,
          'tax_minor': line.taxMinor,
          'line_total_minor': line.totalMinor,
          'notes': _clean(line.notes),
        });
      }

      await txn.insert('supplier_ledger', {
        'supplier_id': supplierId,
        'currency': currency,
        'entry_type': 'credit_invoice',
        'reference_id': invoiceId,
        'entry_date': invoiceDate,
        'signed_amount_minor': totals.totalMinor,
        'note': 'Credit purchase invoice $cleanNumber',
        'created_at': now,
      });
      await txn.insert('supplier_account_movements', {
        'supplier_id': supplierId,
        'currency': currency,
        'movement_type': 'credit_invoice',
        'source_type': 'credit_invoice',
        'source_id': invoiceId,
        'entry_date': invoiceDate,
        'signed_amount_minor': totals.totalMinor,
        'note': 'Credit purchase invoice $cleanNumber',
        'created_at': now,
      });

      if (paidMinor > 0) {
        final paymentId = await txn.insert('supplier_payments', {
          'supplier_id': supplierId,
          'amount_minor': paidMinor,
          'currency': currency,
          'payment_date': invoiceDate,
          'method': initialPaymentMethod,
          'receipt_number':
              'PAY-$supplierId-${DateTime.now().microsecondsSinceEpoch}',
          'notes': 'Initial payment on invoice $cleanNumber',
          'idempotency_key': 'credit-invoice-$invoiceId-initial-payment',
          'created_at': now,
        });
        final allocation =
            paidMinor < totals.totalMinor ? paidMinor : totals.totalMinor;
        if (allocation > 0) {
          await txn.insert('payment_allocations', {
            'payment_id': paymentId,
            'invoice_id': invoiceId,
            'amount_minor': allocation,
            'created_at': now,
          });
        }
        await txn.insert('supplier_ledger', {
          'supplier_id': supplierId,
          'currency': currency,
          'entry_type': 'payment',
          'reference_id': paymentId,
          'entry_date': invoiceDate,
          'signed_amount_minor': -paidMinor,
          'note': 'Payment recorded with invoice $cleanNumber',
          'created_at': now,
        });
        await txn.insert('supplier_account_movements', {
          'supplier_id': supplierId,
          'currency': currency,
          'movement_type': 'payment',
          'source_type': 'payment',
          'source_id': paymentId,
          'entry_date': invoiceDate,
          'signed_amount_minor': -paidMinor,
          'note': 'Payment recorded with invoice $cleanNumber',
          'idempotency_key': 'credit-invoice-$invoiceId-initial-payment',
          'created_at': now,
        });
      }

      await txn.insert('audit_logs', {
        'action': 'create',
        'entity_type': 'credit_invoice',
        'entity_id': invoiceId,
        'details_json':
            '{"invoice_number":"${_jsonEscape(cleanNumber)}","total_minor":${totals.totalMinor}}',
        'created_at': now,
      });
      return invoiceId;
    });
  }

  @override
  Future<int> recordPurchaseReturn({
    required int supplierId,
    required int invoiceId,
    required String returnNumber,
    required String returnDate,
    required String currency,
    required List<PurchaseLine> lines,
    String? notes,
  }) async {
    final cleanNumber = returnNumber.trim();
    if (cleanNumber.isEmpty) throw ArgumentError('Return number is required');
    if (lines.isEmpty)
      throw ArgumentError('At least one return item is required');
    final totals = _calculateTotals(lines);
    if (totals.totalMinor <= 0)
      throw ArgumentError('Return total must be greater than zero');
    final now = DateTime.now().toIso8601String();
    final db = await _database.database;
    return db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'credit_purchase_invoices',
        columns: ['supplier_id', 'currency', 'total_minor'],
        where: 'id = ? AND status = ?',
        whereArgs: [invoiceId, 'posted'],
        limit: 1,
      );
      if (invoiceRows.isEmpty) throw StateError('Invoice not found');
      final invoice = invoiceRows.first;
      if (invoice['supplier_id'] != supplierId ||
          invoice['currency'] != currency) {
        throw StateError(
            'Return supplier or currency does not match the invoice');
      }
      final priorReturns = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(SUM(total_minor),0) FROM purchase_returns WHERE invoice_id = ?',
            [invoiceId],
          )) ??
          0;
      final invoiceTotal = invoice['total_minor'] as int;
      if (priorReturns + totals.totalMinor > invoiceTotal) {
        throw StateError(
            'Total returns cannot exceed the original invoice total');
      }

      final unlinkedReturnCount = Sqflite.firstIntValue(await txn.rawQuery('''
        SELECT COUNT(*)
        FROM purchase_return_items ri
        JOIN purchase_returns r ON r.id = ri.return_id
        WHERE r.invoice_id = ? AND ri.invoice_item_id IS NULL
      ''', [invoiceId])) ?? 0;
      if (unlinkedReturnCount > 0) {
        throw StateError(
            'This invoice has older returns without item-level links; reconcile them before adding another return');
      }
      for (final line in lines) {
        final invoiceItemId = line.sourceInvoiceItemId;
        if (invoiceItemId == null) {
          throw StateError(
              'Every return line must reference an original invoice item');
        }
        final originalRows = await txn.query(
          'credit_purchase_items',
          columns: [
            'quantity_milli',
            'unit_name',
            'line_total_minor',
            'description'
          ],
          where: 'id = ? AND invoice_id = ?',
          whereArgs: [invoiceItemId, invoiceId],
          limit: 1,
        );
        if (originalRows.isEmpty) {
          throw StateError(
              'Return item does not belong to the selected invoice');
        }
        final original = originalRows.first;
        final previousRows = await txn.rawQuery('''
          SELECT COALESCE(SUM(quantity_milli),0) AS returned_quantity,
            COALESCE(SUM(amount_minor),0) AS returned_amount
          FROM purchase_return_items
          WHERE invoice_item_id = ?
        ''', [invoiceItemId]);
        final previousQuantity = previousRows.first['returned_quantity'] as int;
        final previousAmount = previousRows.first['returned_amount'] as int;
        final originalQuantity = original['quantity_milli'] as int;
        final originalAmount = original['line_total_minor'] as int;
        if (previousQuantity + line.quantityMilli > originalQuantity) {
          throw StateError(
              'Return quantity exceeds the remaining original item quantity');
        }
        if (previousAmount + line.totalMinor > originalAmount) {
          throw StateError(
              'Return amount exceeds the remaining original item amount');
        }
        if (line.unitName.trim() != original['unit_name']) {
          throw StateError(
              'Return unit does not match the original invoice item');
        }
      }

      final returnId = await txn.insert('purchase_returns', {
        'supplier_id': supplierId,
        'invoice_id': invoiceId,
        'return_number': cleanNumber,
        'return_date': returnDate,
        'currency': currency,
        'total_minor': totals.totalMinor,
        'notes': _clean(notes),
        'created_at': now,
      });
      for (final line in lines) {
        await txn.insert('purchase_return_items', {
          'return_id': returnId,
          'invoice_item_id': line.sourceInvoiceItemId,
          'description': line.description.trim(),
          'quantity_milli': line.quantityMilli,
          'unit_name': line.unitName.trim(),
          'amount_minor': line.totalMinor,
        });
      }
      await txn.insert('supplier_ledger', {
        'supplier_id': supplierId,
        'currency': currency,
        'entry_type': 'purchase_return',
        'reference_id': returnId,
        'entry_date': returnDate,
        'signed_amount_minor': -totals.totalMinor,
        'note': 'Purchase return $cleanNumber',
        'created_at': now,
      });
      await txn.insert('supplier_account_movements', {
        'supplier_id': supplierId,
        'currency': currency,
        'movement_type': 'purchase_return',
        'source_type': 'purchase_return',
        'source_id': returnId,
        'entry_date': returnDate,
        'signed_amount_minor': -totals.totalMinor,
        'note': 'Purchase return $cleanNumber',
        'created_at': now,
      });
      await txn.insert('audit_logs', {
        'action': 'create',
        'entity_type': 'purchase_return',
        'entity_id': returnId,
        'details_json':
            '{"return_number":"${_jsonEscape(cleanNumber)}","total_minor":${totals.totalMinor}}',
        'created_at': now,
      });
      return returnId;
    });
  }

  @override
  Future<int> recordSupplierPayment({
    required int supplierId,
    required int amountMinor,
    required String currency,
    required String paymentDate,
    required String method,
    int? invoiceId,
    String? receiptNumber,
    String? notes,
    AttachmentDraft? attachment,
    String? idempotencyKey,
    bool allowAdvance = false,
    int? expectedDueMinor,
  }) async {
    if (amountMinor <= 0)
      throw ArgumentError('Payment must be greater than zero');
    final now = DateTime.now().toIso8601String();
    final db = await _database.database;
    return db.transaction((txn) async {
      final supplier = await txn.query('suppliers',
          columns: ['id'],
          where: 'id = ? AND is_archived = 0',
          whereArgs: [supplierId],
          limit: 1);
      if (supplier.isEmpty) throw StateError('Supplier not found');

      final cleanReceipt = _clean(receiptNumber);
      final cleanKey = _clean(idempotencyKey);
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
            columns: ['invoice_id'],
            where: 'payment_id = ?',
            whereArgs: [existing['id']],
          );
          if (invoiceId == null && existingAllocations.isNotEmpty) {
            throw StateError(
                'Idempotency key was already used for a different invoice allocation');
          }
          if (invoiceId != null &&
              existingAllocations
                  .any((row) => row['invoice_id'] != invoiceId)) {
            throw StateError(
                'Idempotency key was already used for a different invoice allocation');
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
      final storedReceipt = cleanReceipt ??
          'PAY-$supplierId-${DateTime.now().microsecondsSinceEpoch}';
      final liveBalance = Sqflite.firstIntValue(await txn.rawQuery('''
        SELECT COALESCE(SUM(signed_amount_minor),0)
        FROM supplier_account_movements WHERE supplier_id = ? AND currency = ?
      ''', [supplierId, currency])) ?? 0;
      final liveDue = liveBalance > 0 ? liveBalance : 0;
      if (expectedDueMinor != null && expectedDueMinor != liveDue) {
        throw StateError('Supplier balance changed; review and reconfirm the payment');
      }
      if (amountMinor > liveDue && !allowAdvance) {
        throw StateError('Excess payment requires explicit advance confirmation');
      }
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
        await txn.update('supplier_payments', {'attachment_id': attachmentId},
            where: 'id = ?', whereArgs: [paymentId]);
      }

      if (invoiceId != null) {
        final invoiceRows = await txn.query(
          'credit_purchase_invoices',
          columns: ['supplier_id', 'currency', 'total_minor'],
          where: 'id = ? AND status = ?',
          whereArgs: [invoiceId, 'posted'],
          limit: 1,
        );
        if (invoiceRows.isEmpty) throw StateError('Invoice not found');
        final invoice = invoiceRows.first;
        if (invoice['supplier_id'] != supplierId ||
            invoice['currency'] != currency) {
          throw StateError(
              'Payment supplier or currency does not match the invoice');
        }
        final paid = Sqflite.firstIntValue(await txn.rawQuery(
              '''SELECT COALESCE(SUM(a.amount_minor),0)
                 FROM payment_allocations a
                 JOIN supplier_payments p ON p.id = a.payment_id
                 LEFT JOIN supplier_payment_reversals r ON r.payment_id = p.id
                 WHERE a.invoice_id = ? AND r.id IS NULL''',
              [invoiceId],
            )) ??
            0;
        final returned = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COALESCE(SUM(total_minor),0) FROM purchase_returns WHERE invoice_id = ?',
              [invoiceId],
            )) ??
            0;
        final total = invoice['total_minor'] as int;
        final remaining = total - paid - returned;
        if (remaining > 0) {
          final allocation = amountMinor < remaining ? amountMinor : remaining;
          if (allocation > 0) {
            await txn.insert('payment_allocations', {
              'payment_id': paymentId,
              'invoice_id': invoiceId,
              'amount_minor': allocation,
              'created_at': now,
            });
          }
        }
      }

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
      await txn.insert('supplier_account_movements', {
        'supplier_id': supplierId,
        'currency': currency,
        'movement_type': 'payment',
        'source_type': 'payment',
        'source_id': paymentId,
        'entry_date': paymentDate,
        'signed_amount_minor': -amountMinor,
        'note': _clean(notes) ?? 'Supplier payment',
        'idempotency_key': cleanKey,
        'created_at': now,
      });
      await txn.insert('audit_logs', {
        'action': 'create',
        'entity_type': 'supplier_payment',
        'entity_id': paymentId,
        'details_json':
            '{"amount_minor":$amountMinor,"currency":"${_jsonEscape(currency)}"}',
        'created_at': now,
      });
      return paymentId;
    });
  }

  @override
  Future<int> createDailyPurchase({
    required String purchaseDate,
    String? sellerName,
    required String currency,
    required List<PurchaseLine> lines,
    int paidMinor = 0,
    String paymentMethod = 'cash',
    String? dueDate,
    String? notes,
  }) async {
    if (lines.isEmpty)
      throw ArgumentError('At least one purchase item is required');
    final totals = _calculateTotals(lines);
    if (totals.totalMinor <= 0)
      throw ArgumentError('Daily purchase total must be greater than zero');
    if (paidMinor < 0 || paidMinor > totals.totalMinor) {
      throw ArgumentError(
          'Paid amount must be between zero and the purchase total');
    }
    final now = DateTime.now().toIso8601String();
    final db = await _database.database;
    return db.transaction((txn) async {
      final purchaseId = await txn.insert('cash_purchases', {
        'purchase_date': purchaseDate,
        'seller_name': _clean(sellerName),
        'currency': currency,
        'total_minor': totals.totalMinor,
        'due_date': _clean(dueDate),
        'notes': _clean(notes),
        'created_at': now,
      });
      for (final line in lines) {
        await txn.insert('cash_purchase_items', {
          'cash_purchase_id': purchaseId,
          'item_name': line.description.trim(),
          'quantity_milli': line.quantityMilli,
          'unit_name': line.unitName.trim(),
          'unit_price_minor': line.unitPriceMinor,
          'line_total_minor': line.totalMinor,
        });
      }
      if (paidMinor > 0) {
        await txn.insert('cash_purchase_payments', {
          'cash_purchase_id': purchaseId,
          'amount_minor': paidMinor,
          'payment_date': purchaseDate,
          'method': paymentMethod,
          'notes': 'Initial payment',
          'created_at': now,
        });
      }
      final remaining = totals.totalMinor - paidMinor;
      if (remaining > 0) {
        await txn.insert('cash_purchase_outstanding_balances', {
          'cash_purchase_id': purchaseId,
          'original_minor': remaining,
          'due_date': _clean(dueDate),
          'status': paidMinor > 0 ? 'partial' : 'open',
          'created_at': now,
        });
      }
      await txn.insert('audit_logs', {
        'action': 'create',
        'entity_type': 'daily_purchase',
        'entity_id': purchaseId,
        'details_json':
            '{"total_minor":${totals.totalMinor},"paid_minor":$paidMinor}',
        'created_at': now,
      });
      return purchaseId;
    });
  }

  @override
  Future<void> recordDailyPurchasePayment({
    required int purchaseId,
    required int amountMinor,
    required String paymentDate,
    required String method,
    String? notes,
  }) async {
    if (amountMinor <= 0)
      throw ArgumentError('Payment must be greater than zero');
    final now = DateTime.now().toIso8601String();
    final db = await _database.database;
    await db.transaction((txn) async {
      final purchaseRows = await txn.query(
        'cash_purchases',
        columns: ['total_minor'],
        where: 'id = ?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (purchaseRows.isEmpty) throw StateError('Daily purchase not found');
      final paid = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(SUM(amount_minor),0) FROM cash_purchase_payments WHERE cash_purchase_id = ?',
            [purchaseId],
          )) ??
          0;
      final total = purchaseRows.first['total_minor'] as int;
      final remaining = total - paid;
      if (amountMinor > remaining)
        throw StateError('Payment exceeds outstanding amount');

      await txn.insert('cash_purchase_payments', {
        'cash_purchase_id': purchaseId,
        'amount_minor': amountMinor,
        'payment_date': paymentDate,
        'method': method,
        'notes': _clean(notes),
        'created_at': now,
      });
      final newRemaining = remaining - amountMinor;
      await txn.update(
        'cash_purchase_outstanding_balances',
        {'status': newRemaining == 0 ? 'paid' : 'partial'},
        where: 'cash_purchase_id = ?',
        whereArgs: [purchaseId],
      );
      await txn.insert('audit_logs', {
        'action': 'payment',
        'entity_type': 'daily_purchase',
        'entity_id': purchaseId,
        'details_json': '{"amount_minor":$amountMinor}',
        'created_at': now,
      });
    });
  }

  @override
  Future<DashboardSummary> getDashboardSummary() async {
    final db = await _database.database;
    final supplierCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM suppliers WHERE is_archived = 0',
        )) ??
        0;
    final invoiceCount = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM credit_purchase_invoices WHERE status = 'posted'",
        )) ??
        0;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final overdueCount = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM credit_purchase_invoices i
      WHERE i.status = 'posted' AND i.due_date IS NOT NULL AND i.due_date < ?
        AND (i.total_minor
          - COALESCE((
            SELECT SUM(a.amount_minor)
            FROM payment_allocations a
            JOIN supplier_payments p ON p.id = a.payment_id
            LEFT JOIN supplier_payment_reversals pr ON pr.payment_id = p.id
            WHERE a.invoice_id = i.id AND pr.id IS NULL
          ),0)
          - COALESCE((SELECT SUM(r.total_minor) FROM purchase_returns r WHERE r.invoice_id=i.id),0)) > 0
    ''', [today])) ?? 0;
    final dailyCount = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM daily_purchase_operations WHERE status = 'posted'",
        )) ??
        0;

    final supplierRows = await db.rawQuery('''
      SELECT currency,
        SUM(CASE WHEN movement_type = 'credit_invoice'
          THEN signed_amount_minor ELSE 0 END) AS credit_minor,
        SUM(signed_amount_minor) AS supplier_due_minor
      FROM supplier_account_movements
      GROUP BY currency
    ''');
    final dailyRows = await db.rawQuery('''
      SELECT o.currency,
        SUM(o.total_minor) AS daily_minor,
        SUM(CASE WHEN o.accounting_mode = 'daily_outstanding'
          THEN COALESCE(ob.original_minor,0)
            - COALESCE((
              SELECT SUM(p.amount_minor)
              FROM daily_purchase_outstanding_payments p
              WHERE p.outstanding_id = ob.id
            ),0)
            + COALESCE((
              SELECT SUM(a.signed_delta_minor)
              FROM daily_purchase_outstanding_adjustments a
              WHERE a.outstanding_id = ob.id
            ),0)
          ELSE 0 END) AS daily_due_minor
      FROM daily_purchase_operations o
      LEFT JOIN daily_purchase_outstandings ob ON ob.operation_id = o.id
      WHERE o.status = 'posted'
      GROUP BY o.currency
    ''');

    final totals = <String, Map<String, int>>{};
    for (final row in supplierRows) {
      final currency = row['currency'] as String;
      totals.putIfAbsent(currency, () => <String, int>{});
      totals[currency]!['credit'] = (row['credit_minor'] as int?) ?? 0;
      totals[currency]!['supplierDue'] =
          (row['supplier_due_minor'] as int?) ?? 0;
    }
    for (final row in dailyRows) {
      final currency = row['currency'] as String;
      totals.putIfAbsent(currency, () => <String, int>{});
      totals[currency]!['daily'] = (row['daily_minor'] as int?) ?? 0;
      totals[currency]!['dailyDue'] = (row['daily_due_minor'] as int?) ?? 0;
    }

    final currencyTotals = totals.entries
        .map((entry) => CurrencyTotal(
              currency: entry.key,
              creditPurchasesMinor: entry.value['credit'] ?? 0,
              dailyPurchasesMinor: entry.value['daily'] ?? 0,
              supplierDueMinor: entry.value['supplierDue'] ?? 0,
              dailyDueMinor: entry.value['dailyDue'] ?? 0,
            ))
        .toList(growable: false)
      ..sort((a, b) => a.currency.compareTo(b.currency));

    return DashboardSummary(
      supplierCount: supplierCount,
      invoiceCount: invoiceCount,
      overdueInvoiceCount: overdueCount,
      dailyPurchaseCount: dailyCount,
      totalsByCurrency: currencyTotals,
    );
  }

  _PurchaseTotals _calculateTotals(List<PurchaseLine> lines) {
    var subtotal = 0;
    var discount = 0;
    var tax = 0;
    var total = 0;
    for (final line in lines) {
      if (line.description.trim().isEmpty)
        throw ArgumentError('Item name is required');
      if (line.unitName.trim().isEmpty) throw ArgumentError('Unit is required');
      final gross = (line.quantityMilli * line.unitPriceMinor + 500) ~/ 1000;
      subtotal += gross;
      discount += line.discountMinor;
      tax += line.taxMinor;
      total += line.totalMinor;
    }
    return _PurchaseTotals(
      subtotalMinor: subtotal,
      discountMinor: discount,
      taxMinor: tax,
      totalMinor: total,
    );
  }

  String? _clean(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }

  String _jsonEscape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', ' ');
}

class _PurchaseTotals {
  const _PurchaseTotals({
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
  });

  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int totalMinor;
}
