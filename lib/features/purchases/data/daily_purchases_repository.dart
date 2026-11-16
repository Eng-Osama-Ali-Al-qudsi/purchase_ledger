import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/attachments/attachment_service.dart';
import '../domain/daily_sheet_models.dart';
import '../domain/purchase_line.dart';

class DailyPurchasesRepository {
  DailyPurchasesRepository(this._database);

  final AppDatabase _database;

  Future<List<DailySheetSummary>> getSheets({
    String? dateFrom,
    String? dateTo,
    int? branchId,
    int? employeeId,
    bool includeArchived = false,
  }) async {
    final db = await _database.database;
    final where = <String>[];
    final args = <Object?>[];
    if (dateFrom != null) {
      where.add('s.purchase_date >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null) {
      where.add('s.purchase_date <= ?');
      args.add(dateTo);
    }
    if (branchId != null) {
      where.add('s.branch_id = ?');
      args.add(branchId);
    }
    if (employeeId != null) {
      where.add('s.employee_id = ?');
      args.add(employeeId);
    }
    if (!includeArchived) {
      where.add('''NOT EXISTS (
        SELECT 1 FROM daily_purchase_sheet_events archived
        WHERE archived.sheet_id = s.id AND archived.event_type = 'archived'
      )''');
    }
    final rows = await db.rawQuery('''
      SELECT s.id, s.sheet_number, s.purchase_date,
        CASE WHEN EXISTS (SELECT 1 FROM daily_purchase_sheet_events archived
          WHERE archived.sheet_id = s.id AND archived.event_type = 'archived')
          THEN 'ARCHIVED' ELSE s.status END AS status,
        b.name AS branch_name, e.name AS employee_name,
        COUNT(DISTINCT CASE WHEN o.status = 'posted' THEN o.id END) AS operation_count,
        COUNT(DISTINCT CASE WHEN o.status = 'posted' THEN i.id END) AS item_count
      FROM daily_purchase_sheets s
      LEFT JOIN branches b ON b.id = s.branch_id
      LEFT JOIN employees e ON e.id = s.employee_id
      LEFT JOIN daily_purchase_operations o ON o.sheet_id = s.id
      LEFT JOIN daily_purchase_items i ON i.operation_id = o.id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      GROUP BY s.id
      ORDER BY s.purchase_date DESC, s.id DESC
    ''', args);

    final ids = rows.map((row) => row['id'] as int).toList(growable: false);
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final totalRows = await db.rawQuery('''
      SELECT o.sheet_id, o.currency,
        SUM(o.total_minor) AS total_minor,
        SUM(o.amount_paid_minor) AS cash_minor,
        SUM(o.amount_paid_minor + CASE WHEN o.accounting_mode = 'daily_outstanding'
          THEN COALESCE((
            SELECT SUM(dp.amount_minor)
            FROM daily_purchase_outstanding_payments dp
            WHERE dp.outstanding_id = ob.id
          ),0) ELSE 0 END) AS paid_minor,
        SUM(CASE WHEN o.accounting_mode = 'daily_outstanding'
          THEN COALESCE(ob.original_minor,0)
            - COALESCE((
              SELECT SUM(dp.amount_minor)
              FROM daily_purchase_outstanding_payments dp
              WHERE dp.outstanding_id = ob.id
            ),0)
            + COALESCE((
              SELECT SUM(da.signed_delta_minor)
              FROM daily_purchase_outstanding_adjustments da
              WHERE da.outstanding_id = ob.id
            ),0)
          ELSE 0 END) AS daily_outstanding_minor,
        SUM(CASE WHEN o.accounting_mode = 'supplier_account'
          THEN o.total_minor - o.amount_paid_minor ELSE 0 END) AS supplier_account_credit_minor
      FROM daily_purchase_operations o
      LEFT JOIN daily_purchase_outstandings ob ON ob.operation_id = o.id
      WHERE o.status = 'posted' AND o.sheet_id IN ($placeholders)
      GROUP BY o.sheet_id, o.currency
    ''', ids);

    final totalsBySheet = <int, List<DailySheetCurrencyTotal>>{};
    for (final row in totalRows) {
      final sheetId = row['sheet_id'] as int;
      final total = (row['total_minor'] as int?) ?? 0;
      final paidAtPurchase = (row['cash_minor'] as int?) ?? 0;
      final paidByNow = (row['paid_minor'] as int?) ?? 0;
      final outstanding =
          math.max(0, (row['daily_outstanding_minor'] as int?) ?? 0);
      final supplierCredit =
          (row['supplier_account_credit_minor'] as int?) ?? 0;
      totalsBySheet.putIfAbsent(sheetId, () => []).add(DailySheetCurrencyTotal(
            currency: row['currency'] as String,
            totalMinor: total,
            cashMinor: paidAtPurchase,
            creditMinor: math.max(0, total - paidAtPurchase),
            paidMinor: paidByNow,
            outstandingMinor: outstanding,
            supplierAccountCreditMinor: supplierCredit,
          ));
    }

    return rows.map((row) {
      final id = row['id'] as int;
      return DailySheetSummary(
        id: id,
        sheetNumber: row['sheet_number'] as String,
        purchaseDate: row['purchase_date'] as String,
        branchName: row['branch_name'] as String?,
        employeeName: row['employee_name'] as String?,
        status: row['status'] as String,
        operationCount: (row['operation_count'] as int?) ?? 0,
        itemCount: (row['item_count'] as int?) ?? 0,
        totalsByCurrency: totalsBySheet[id] ?? const [],
      );
    }).toList(growable: false);
  }

  Future<int> createSheet({
    required String purchaseDate,
    int? branchId,
    int? employeeId,
    String? notes,
  }) async {
    _validateDate(purchaseDate);
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    return db.transaction((txn) async {
      if (branchId != null) {
        final branches = await txn.query('branches',
            columns: ['id'], where: 'id = ? AND is_active = 1',
            whereArgs: [branchId], limit: 1);
        if (branches.isEmpty) throw StateError('Selected branch is not active');
      }
      if (employeeId != null) {
        final employees = await txn.query('employees',
            columns: ['branch_id'], where: 'id = ? AND is_active = 1',
            whereArgs: [employeeId], limit: 1);
        if (employees.isEmpty ||
            (branchId != null && employees.first['branch_id'] != branchId)) {
          throw StateError('Purchasing officer must belong to the selected branch');
        }
      }
      // A draft's date can change without rewriting its permanent document
      // number. COUNT(*)+1 may then reuse a number already issued for a day.
      // Choose a monotonically increasing suffix from existing *identifiers*.
      final prefix = 'DPS-${purchaseDate.replaceAll('-', '')}-';
      final existing = await txn.rawQuery(
        '''SELECT sheet_number FROM daily_purchase_sheets WHERE sheet_number LIKE ?
           UNION ALL
           SELECT sheet_number FROM daily_sheet_deleted_drafts WHERE sheet_number LIKE ?''',
        ['$prefix%', '$prefix%'],
      );
      var lastSequence = 0;
      for (final row in existing) {
        final value = row['sheet_number'] as String;
        if (!value.startsWith(prefix)) continue;
        final suffix = int.tryParse(value.substring(prefix.length));
        if (suffix != null && suffix > lastSequence) lastSequence = suffix;
      }
      final sheetNumber =
          '$prefix${(lastSequence + 1).toString().padLeft(3, '0')}';
      final id = await txn.insert('daily_purchase_sheets', {
        'sheet_number': sheetNumber,
        'purchase_date': purchaseDate,
        'branch_id': branchId,
        'employee_id': employeeId,
        'notes': _clean(notes),
        'status': 'DRAFT',
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': id,
        'event_type': 'created',
        'to_status': 'DRAFT',
        'details_json': jsonEncode({'sheet_number': sheetNumber}),
        'created_at': now,
      });
      await _audit(
          txn,
          'create',
          'daily_purchase_sheet',
          id,
          {
            'sheet_number': sheetNumber,
            'purchase_date': purchaseDate,
          },
          now);
      return id;
    });
  }

  /// Edits metadata only; never rewrites posted financial history.
  /// If operations ever existed on this draft, only the notes may change.
  Future<void> updateDraftSheet({
    required int sheetId,
    required String purchaseDate,
    int? branchId,
    int? employeeId,
    String? notes,
  }) async {
    _validateDate(purchaseDate);
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('daily_purchase_sheets',
          where: 'id = ?', whereArgs: [sheetId], limit: 1);
      if (rows.isEmpty) throw StateError('Daily sheet not found');
      final before = rows.first;
      if (before['status'] != 'DRAFT' || await _isArchived(txn, sheetId)) {
        throw StateError('Only active draft sheets can be edited');
      }
      final count = Sqflite.firstIntValue(await txn.rawQuery(
          'SELECT COUNT(*) FROM daily_purchase_operations WHERE sheet_id = ?',
          [sheetId])) ?? 0;
      if (count > 0 &&
          (purchaseDate != before['purchase_date'] ||
           branchId != before['branch_id'] ||
           employeeId != before['employee_id'])) {
        final financialRows = Sqflite.firstIntValue(await txn.rawQuery('''
          SELECT COUNT(*) FROM daily_purchase_operations o
          WHERE o.sheet_id = ? AND (
            o.status <> 'posted' OR o.recording_category IS NOT 'cash'
            OR o.accounting_mode <> 'daily_outstanding'
            OR o.supplier_id IS NOT NULL
            OR o.legacy_cash_purchase_id IS NOT NULL
            OR o.initial_supplier_payment_id IS NOT NULL
            OR o.total_minor <> o.amount_paid_minor
            OR EXISTS (SELECT 1 FROM daily_purchase_outstandings ob
              WHERE ob.operation_id = o.id)
          )
        ''', [sheetId])) ?? 0;
        if (financialRows != 0) {
          throw StateError('Only notes can change when supplier, outstanding, or void operation history exists');
        }
      }
      if (branchId != null) {
        final branches = await txn.query('branches', where: 'id = ?',
            whereArgs: [branchId], limit: 1);
        if (branches.isEmpty) throw StateError('Branch not found');
      }
      if (employeeId != null) {
        final employees = await txn.query('employees', where: 'id = ?',
            whereArgs: [employeeId], limit: 1);
        if (employees.isEmpty ||
            (branchId != null && employees.first['branch_id'] != branchId)) {
          throw StateError('Employee must belong to the selected branch');
        }
      }
      final after = <String, Object?>{
        'purchase_date': purchaseDate,
        'branch_id': branchId,
        'employee_id': employeeId,
        'notes': _clean(notes),
      };
      if (after.entries.every((field) => before[field.key] == field.value)) {
        return;
      }
      await txn.update('daily_purchase_sheets', {...after, 'updated_at': now},
          where: 'id = ?', whereArgs: [sheetId]);
      final changes = <String, Object?>{
        'before': {
          for (final key in after.keys) key: before[key],
        },
        'after': after,
      };
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': sheetId,
        'event_type': 'metadata_edited',
        'details_json': jsonEncode(changes),
        'created_at': now,
      });
      await _audit(txn, 'update', 'daily_purchase_sheet', sheetId,
          changes, now);
    });
  }

  /// Permanently remove ONLY a draft with no purchase operation history or
  /// downstream financial links. All original events and its document number
  /// survive in an append-only deletion receipt (SQLite schema V8).
  Future<void> deleteEmptyDraftSheet(int sheetId, {required String reason}) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('A deletion reason is required');
    }
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('daily_purchase_sheets',
          where: 'id = ?', whereArgs: [sheetId], limit: 1);
      if (rows.isEmpty) throw StateError('Daily sheet not found');
      final sheet = rows.first;
      if (sheet['status'] != 'DRAFT' || await _isArchived(txn, sheetId)) {
        throw StateError('Only active draft sheets can be deleted');
      }
      if (sheet['header_snapshot_json'] != null ||
          sheet['totals_snapshot_json'] != null ||
          sheet['operations_snapshot_json'] != null ||
          sheet['handed_over_at'] != null || sheet['closed_at'] != null) {
        throw StateError('A handed-over sheet cannot be deleted');
      }
      final operationCount = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM daily_purchase_operations WHERE sheet_id = ?',
        [sheetId],
      )) ?? 0;
      final amendmentCount = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM daily_purchase_sheet_amendments WHERE sheet_id = ?',
        [sheetId],
      )) ?? 0;
      // A void operation still has permanent history; do not mistake the
      // summary's active-operation count for proof that deletion is safe.
      if (operationCount != 0 || amendmentCount != 0) {
        throw StateError('Purchase history exists. Void/archive instead; permanent deletion is blocked');
      }
      final events = await txn.query('daily_purchase_sheet_events',
          where: 'sheet_id = ?', whereArgs: [sheetId], orderBy: 'id');
      final deletionReceipt = <String, Object?>{
        'sheet_id': sheetId,
        'sheet_number': sheet['sheet_number'],
        'purchase_date': sheet['purchase_date'],
        'branch_id': sheet['branch_id'],
        'employee_id': sheet['employee_id'],
        'deleted_at': now,
        'deletion_reason': cleanReason,
        'events_json': jsonEncode(events),
        'original_created_at': sheet['created_at'],
      };
      // The insert is checked by the V8 database trigger, and remains in the
      // same transaction as event deletion, sheet deletion, and audit logging.
      await txn.insert('daily_sheet_deleted_drafts', deletionReceipt);
      await txn.delete('daily_purchase_sheet_events',
          where: 'sheet_id = ?', whereArgs: [sheetId]);
      final removed = await txn.delete('daily_purchase_sheets',
          where: 'id = ?', whereArgs: [sheetId]);
      if (removed != 1) throw StateError('Sheet deletion did not complete');
      await _audit(txn, 'delete_empty_draft', 'daily_purchase_sheet',
          sheetId, {
            'sheet_number': sheet['sheet_number'],
            'purchase_date': sheet['purchase_date'],
            'reason': cleanReason,
            'events_retained': events.length,
          }, now);
    });
  }

  /// Soft archive: preserve the original record and an immutable audit trail.
  Future<void> archiveEmptyDraftSheet(int sheetId, {required String reason}) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw ArgumentError('Archiving reason is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('daily_purchase_sheets',
          where: 'id = ?', whereArgs: [sheetId], limit: 1);
      if (rows.isEmpty) throw StateError('Daily sheet not found');
      if (rows.first['status'] != 'DRAFT' ||
          await _isArchived(txn, sheetId)) {
        throw StateError('Only active draft sheets can be archived');
      }
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM daily_purchase_operations WHERE sheet_id = ?',
        [sheetId],
      )) ?? 0;
      if (count != 0) {
        throw StateError('A sheet with purchase history cannot be archived');
      }
      final details = {'reason': cleanReason, 'sheet_number': rows.first['sheet_number']};
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': sheetId,
        'event_type': 'archived',
        'details_json': jsonEncode(details),
        'created_at': now,
      });
      await _audit(txn, 'archive', 'daily_purchase_sheet', sheetId, details, now);
    });
  }

  Future<bool> _isArchived(Transaction txn, int sheetId) async =>
      (Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT COUNT(*) FROM daily_purchase_sheet_events WHERE sheet_id = ? AND event_type = 'archived'",
        [sheetId],
      )) ?? 0) > 0;

  /// Stable person directory. Balances are not duplicated here: the canonical
  /// obligation, settlement and adjustment rows are the daily outstanding
  /// records linked to each operation's responsible_person_id.
  Future<List<Map<String, Object?>>> getResponsiblePeople() async {
    final db = await _database.database;
    return db.query('responsible_people',
        where: 'is_active = 1', orderBy: 'name COLLATE NOCASE');
  }

  Future<int> createResponsiblePerson(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Person name is required');
    final db = await _database.database;
    return db.transaction((txn) async {
      final previous = await txn.query('responsible_people',
          columns: ['id', 'is_active'],
          where: 'name = ? COLLATE NOCASE', whereArgs: [cleanName], limit: 1);
      if (previous.isNotEmpty) {
        final id = previous.first['id'] as int;
        if (previous.first['is_active'] == 0) {
          await txn.update('responsible_people', {'is_active': 1},
              where: 'id = ?', whereArgs: [id]);
        }
        return id;
      }
      return txn.insert('responsible_people', {
        'name': cleanName,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<int> createOperation({
    required int sheetId,
    required String currency,
    required List<PurchaseLine> lines,
    String? sellerName,
    int? supplierId,
    String accountingMode = 'daily_outstanding',
    int paidMinor = 0,
    String paymentMethod = 'cash',
    String? dueDate,
    String? notes,
    AttachmentDraft? attachment,
    String? idempotencyKey,
    String? recordingCategory,
    String? responsiblePersonName,
    int? responsiblePersonId,
  }) async {
    if (lines.isEmpty) throw ArgumentError('At least one item is required');
    if (!['daily_outstanding', 'supplier_account'].contains(accountingMode)) {
      throw ArgumentError('Invalid daily purchase accounting mode');
    }
    if (recordingCategory != null &&
        !['cash', 'supplier', 'independent', 'person'].contains(recordingCategory)) {
      throw ArgumentError('Invalid daily purchase recording category');
    }
    if (recordingCategory == 'person' && responsiblePersonId == null) {
      throw ArgumentError('A registered responsible person is required');
    }
    if (recordingCategory == 'person' &&
        (supplierId != null || accountingMode != 'daily_outstanding')) {
      throw ArgumentError('A personal liability cannot also be a supplier debt');
    }
    if (recordingCategory != 'person' && responsiblePersonId != null) {
      throw ArgumentError('Responsible person is only valid for person accounts');
    }
    if (recordingCategory == 'cash' && paidMinor != _calculateTotals(lines).total) {
      throw ArgumentError('A cash purchase must be fully paid');
    }
    if (!['cash', 'bank_transfer', 'wallet', 'cheque', 'other', 'unspecified']
        .contains(paymentMethod)) {
      throw ArgumentError('Invalid daily purchase payment method');
    }
    if (accountingMode == 'supplier_account' && supplierId == null) {
      throw ArgumentError(
          'Select a supplier when posting to the supplier account');
    }
    final totals = _calculateTotals(lines);
    if (totals.total <= 0)
      throw ArgumentError('Purchase total must be greater than zero');
    if (paidMinor < 0 || paidMinor > totals.total) {
      throw ArgumentError('Paid amount must be between zero and the total');
    }
    _validateOptionalDate(dueDate);

    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    final cleanIdempotencyKey = _clean(idempotencyKey);
    final requestedSeller = _clean(sellerName);
    return db.transaction((txn) async {
      if (cleanIdempotencyKey != null) {
        final duplicateRows = await txn.query(
          'daily_purchase_operations',
          where: 'idempotency_key = ?',
          whereArgs: [cleanIdempotencyKey],
          limit: 1,
        );
        if (duplicateRows.isNotEmpty) {
          final existing = duplicateRows.first;
          if (existing['sheet_id'] != sheetId ||
              existing['currency'] != currency ||
              existing['total_minor'] != totals.total ||
              existing['accounting_mode'] != accountingMode ||
              existing['supplier_id'] != supplierId ||
              (requestedSeller != null &&
                  existing['seller_name'] != requestedSeller) ||
              existing['recording_category'] != recordingCategory ||
              existing['responsible_person_id'] != responsiblePersonId ||
              existing['amount_paid_minor'] != paidMinor ||
              existing['payment_method'] != paymentMethod ||
              existing['due_date'] != _clean(dueDate) ||
              existing['notes'] != _clean(notes)) {
            throw StateError(
                'Idempotency key was already used for a different daily purchase');
          }
          final existingItems = await txn.query(
            'daily_purchase_items',
            where: 'operation_id = ?',
            whereArgs: [existing['id']],
            orderBy: 'id',
          );
          if (existingItems.length != lines.length) {
            throw StateError(
                'Idempotency key was already used with different purchase items');
          }
          for (var index = 0; index < lines.length; index++) {
            final saved = existingItems[index];
            final requested = lines[index];
            final same = saved['product_id'] == requested.productId &&
                saved['category_id'] == requested.categoryId &&
                saved['item_name'] == requested.description.trim() &&
                saved['quantity_milli'] == requested.quantityMilli &&
                saved['unit_name'] == requested.unitName.trim() &&
                saved['unit_price_minor'] == requested.unitPriceMinor &&
                saved['discount_minor'] == requested.discountMinor &&
                saved['tax_minor'] == requested.taxMinor &&
                saved['line_total_minor'] == requested.totalMinor &&
                saved['seller_name'] == _clean(requested.sellerName) &&
                saved['notes'] == _clean(requested.notes);
            if (!same) {
              throw StateError(
                  'Idempotency key was already used with different purchase items');
            }
          }
          return existing['id'] as int;
        }
      }
      final sheetRows = await txn.query(
        'daily_purchase_sheets',
        columns: ['purchase_date', 'status'],
        where: 'id = ?',
        whereArgs: [sheetId],
        limit: 1,
      );
      if (sheetRows.isEmpty) throw StateError('Daily sheet not found');
      if (sheetRows.first['status'] != 'DRAFT') {
        throw StateError('Only draft daily sheets can be edited');
      }
      if (await _isArchived(txn, sheetId)) {
        throw StateError('Archived daily sheets cannot receive purchases');
      }

      String? resolvedSeller = _clean(sellerName);
      String? resolvedPersonName;
      if (responsiblePersonId != null) {
        final people = await txn.query('responsible_people',
            columns: ['name'],
            where: 'id = ? AND is_active = 1',
            whereArgs: [responsiblePersonId], limit: 1);
        if (people.isEmpty) {
          throw StateError('Responsible person was removed or archived');
        }
        resolvedPersonName = people.first['name'] as String;
        if (responsiblePersonName != null &&
            _clean(responsiblePersonName)?.toLowerCase() !=
                resolvedPersonName.toLowerCase()) {
          throw ArgumentError('Selected responsible person name does not match');
        }
      }
      if (accountingMode == 'supplier_account') {
        final supplierRows = await txn.query(
          'suppliers',
          columns: ['name', 'is_archived'],
          where: 'id = ?',
          whereArgs: [supplierId],
          limit: 1,
        );
        if (supplierRows.isEmpty || supplierRows.first['is_archived'] == 1) {
          throw StateError('Supplier not found or archived');
        }
        resolvedSeller ??= supplierRows.first['name'] as String;
      }

      final operationCount = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM daily_purchase_operations WHERE sheet_id = ?',
            [sheetId],
          )) ??
          0;
      final operationNumber =
          'OP-${(operationCount + 1).toString().padLeft(3, '0')}';
      final operationId = await txn.insert('daily_purchase_operations', {
        'sheet_id': sheetId,
        'operation_number': operationNumber,
        'supplier_id': supplierId,
        'accounting_mode': accountingMode,
        'seller_name': resolvedSeller,
        'recording_category': recordingCategory,
        'responsible_person_name': resolvedPersonName,
        'responsible_person_id': responsiblePersonId,
        'currency': currency,
        'payment_method': paymentMethod,
        'subtotal_minor': totals.subtotal,
        'discount_minor': totals.discount,
        'tax_minor': totals.tax,
        'total_minor': totals.total,
        'amount_paid_minor': paidMinor,
        'due_date': _clean(dueDate),
        'notes': _clean(notes),
        'idempotency_key': cleanIdempotencyKey,
        'status': 'posted',
        'created_at': now,
        'updated_at': now,
      });
      if (attachment != null) {
        final attachmentId = await AttachmentService.save(
          txn,
          draft: attachment,
          entityType: 'daily_purchase_operation',
          entityId: operationId,
        );
        await txn.update(
            'daily_purchase_operations', {'attachment_id': attachmentId},
            where: 'id = ?', whereArgs: [operationId]);
      }

      for (final line in lines) {
        await _insertItem(txn, operationId, line);
      }

      if (accountingMode == 'supplier_account') {
        await txn.insert('supplier_account_movements', {
          'supplier_id': supplierId,
          'currency': currency,
          'movement_type': 'daily_purchase',
          'source_type': 'daily_purchase',
          'source_id': operationId,
          'entry_date': sheetRows.first['purchase_date'],
          'signed_amount_minor': totals.total,
          'note': 'Daily purchase $operationNumber on sheet $sheetId',
          'created_at': now,
        });
        if (paidMinor > 0) {
          final paymentId = await txn.insert('supplier_payments', {
            'supplier_id': supplierId,
            'amount_minor': paidMinor,
            'currency': currency,
            'payment_date': sheetRows.first['purchase_date'],
            'method': paymentMethod,
            'receipt_number':
                'PAY-$supplierId-${DateTime.now().microsecondsSinceEpoch}',
            'notes': 'Initial payment for daily purchase $operationNumber',
            'idempotency_key': 'daily-operation-$operationId-initial-payment',
            'created_at': now,
          });
          await txn.update(
            'daily_purchase_operations',
            {'initial_supplier_payment_id': paymentId},
            where: 'id = ?',
            whereArgs: [operationId],
          );
          await txn.insert('supplier_account_movements', {
            'supplier_id': supplierId,
            'currency': currency,
            'movement_type': 'payment',
            'source_type': 'payment',
            'source_id': paymentId,
            'entry_date': sheetRows.first['purchase_date'],
            'signed_amount_minor': -paidMinor,
            'note': 'Initial payment for daily purchase $operationNumber',
            'idempotency_key': 'daily-operation-$operationId-initial-payment',
            'created_at': now,
          });
        }
      } else {
        final remaining = totals.total - paidMinor;
        if (remaining > 0) {
          await txn.insert('daily_purchase_outstandings', {
            'operation_id': operationId,
            'original_minor': remaining,
            'due_date': _clean(dueDate),
            'status': 'open',
            'created_at': now,
          });
        }
      }

      await txn.update(
        'daily_purchase_sheets',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [sheetId],
      );
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': sheetId,
        'event_type': 'operation_created',
        'details_json': jsonEncode({
          'operation_id': operationId,
          'operation_number': operationNumber,
          'accounting_mode': accountingMode,
          'recording_category': recordingCategory,
          'responsible_person_name': resolvedPersonName,
          'responsible_person_id': responsiblePersonId,
          'total_minor': totals.total,
          'paid_minor': paidMinor,
        }),
        'created_at': now,
      });
      await _audit(
          txn,
          'create',
          'daily_purchase_operation',
          operationId,
          {
            'sheet_id': sheetId,
            'operation_number': operationNumber,
            'total_minor': totals.total,
            'accounting_mode': accountingMode,
          },
          now);
      return operationId;
    });
  }

  Future<void> updateOperationItems({
    required int operationId,
    required List<PurchaseLine> lines,
    required String paymentMethod,
    String? notes,
  }) async {
    if (lines.isEmpty) throw ArgumentError('At least one item is required');
    if (!['cash', 'bank_transfer', 'wallet', 'cheque', 'other', 'unspecified']
        .contains(paymentMethod)) {
      throw ArgumentError('Invalid daily purchase payment method');
    }
    final totals = _calculateTotals(lines);
    if (totals.total <= 0)
      throw ArgumentError('Purchase total must be greater than zero');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT o.*, s.status AS sheet_status, s.purchase_date
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = ? AND o.status = 'posted'
      ''', [operationId]);
      if (rows.isEmpty) throw StateError('Daily purchase operation not found');
      final operation = rows.first;
      if (operation['sheet_status'] != 'DRAFT') {
        throw StateError('Only draft daily sheets can be edited');
      }
      final oldTotal = operation['total_minor'] as int;
      final initialPaid = operation['amount_paid_minor'] as int;
      final mode = operation['accounting_mode'] as String;
      // A fully paid cash purchase has no receivable. When correcting the
      // draft's line items, its paid-at-purchase figure must follow the new
      // total atomically; otherwise a price increase silently creates debt.
      final isCashPurchase = mode == 'daily_outstanding' &&
          (operation['recording_category'] == 'cash' ||
            (operation['recording_category'] == null && initialPaid == oldTotal));
      if (!isCashPurchase && initialPaid > totals.total) {
        throw StateError(
            'New total cannot be lower than the amount already paid');
      }
      if (mode == 'daily_outstanding') {
        final outstandingRows = await txn.query(
          'daily_purchase_outstandings',
          columns: ['id'],
          where: 'operation_id = ?',
          whereArgs: [operationId],
          limit: 1,
        );
        if (isCashPurchase && outstandingRows.isNotEmpty) {
          throw StateError('A fully paid cash purchase has an unexpected outstanding; correction blocked');
        }
        if (isCashPurchase) {
          // No separate liability or second payment may be created here.
        } else if (outstandingRows.isNotEmpty) {
          final outstandingId = outstandingRows.first['id'] as int;
          final laterPaid = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COALESCE(SUM(amount_minor),0) FROM daily_purchase_outstanding_payments WHERE outstanding_id = ?',
                [outstandingId],
              )) ??
              0;
          final adjustmentDelta = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COALESCE(SUM(signed_delta_minor),0) FROM daily_purchase_outstanding_adjustments WHERE outstanding_id = ?',
                [outstandingId],
              )) ??
              0;
          final newOriginal = totals.total - initialPaid;
          final newRemaining = newOriginal - laterPaid + adjustmentDelta;
          if (newRemaining < 0) {
            throw StateError(
                'New total would be lower than payments and adjustments already recorded');
          }
          if (newOriginal == 0 && laterPaid == 0 && adjustmentDelta == 0) {
            await txn.delete('daily_purchase_outstandings',
                where: 'id = ?', whereArgs: [outstandingId]);
          } else {
            await txn.update(
                'daily_purchase_outstandings',
                {
                  'original_minor': newOriginal,
                  'status': newRemaining == 0
                      ? 'paid'
                      : (laterPaid > 0 || adjustmentDelta != 0)
                          ? 'partial'
                          : 'open',
                },
                where: 'id = ?',
                whereArgs: [outstandingId]);
          }
        } else if (totals.total - initialPaid > 0) {
          await txn.insert('daily_purchase_outstandings', {
            'operation_id': operationId,
            'original_minor': totals.total - initialPaid,
            'due_date': operation['due_date'],
            'status': 'open',
            'created_at': now,
          });
        }
      } else {
        final delta = totals.total - oldTotal;
        if (delta != 0) {
          final adjustmentMovementId = await txn.insert('supplier_account_movements', {
            'supplier_id': operation['supplier_id'],
            'currency': operation['currency'],
            'movement_type': 'adjustment',
            'source_type': 'daily_purchase_edit',
            'source_id': null,
            'entry_date': operation['purchase_date'],
            'signed_amount_minor': delta,
            'note':
                'Draft daily purchase correction for operation ${operation['operation_number']}',
            'created_at': now,
          });
          await txn.insert('daily_operation_adjustment_movements', {
            'operation_id': operationId,
            'movement_id': adjustmentMovementId,
            'created_at': now,
          });
        }
      }

      // Preserve the exact before/after item data in append-only audit logs.
      // A draft correction may replace live line rows, but must never silently
      // destroy the explanation of the previous financial amount.
      final previousItems = await txn.query('daily_purchase_items',
          where: 'operation_id = ?', whereArgs: [operationId], orderBy: 'id');
      final newItemsAudit = lines.map((line) => {
        'description': line.description.trim(),
        'category_id': line.categoryId,
        'unit_name': line.unitName.trim(),
        'quantity_milli': line.quantityMilli,
        'unit_price_minor': line.unitPriceMinor,
        'discount_minor': line.discountMinor,
        'tax_minor': line.taxMinor,
        'line_total_minor': line.totalMinor,
        'seller_name': line.sellerName,
        'notes': line.notes,
      }).toList(growable: false);
      await txn.delete('daily_purchase_items',
          where: 'operation_id = ?', whereArgs: [operationId]);
      for (final line in lines) {
        await _insertItem(txn, operationId, line);
      }
      await txn.update(
          'daily_purchase_operations',
          {
            'subtotal_minor': totals.subtotal,
            'discount_minor': totals.discount,
            'tax_minor': totals.tax,
            'total_minor': totals.total,
            'amount_paid_minor': isCashPurchase ? totals.total : initialPaid,
            'payment_method': paymentMethod,
            'notes': _clean(notes),
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [operationId]);
      final initialSupplierPaymentId =
          operation['initial_supplier_payment_id'] as int?;
      if (initialSupplierPaymentId != null) {
        await txn.update(
          'supplier_payments',
          {'method': paymentMethod},
          where: 'id = ?',
          whereArgs: [initialSupplierPaymentId],
        );
      }
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': operation['sheet_id'],
        'event_type': 'operation_items_updated',
        'details_json': jsonEncode({
          'operation_id': operationId,
          'old_total_minor': oldTotal,
          'new_total_minor': totals.total,
          'old_paid_minor': initialPaid,
          'new_paid_minor': isCashPurchase ? totals.total : initialPaid,
          'old_payment_method': operation['payment_method'],
          'new_payment_method': paymentMethod,
        }),
        'created_at': now,
      });
      await _audit(
          txn,
          'update_items',
          'daily_purchase_operation',
          operationId,
          {
            'old_total_minor': oldTotal,
            'new_total_minor': totals.total,
            'old_paid_minor': initialPaid,
            'new_paid_minor': isCashPurchase ? totals.total : initialPaid,
            'old_payment_method': operation['payment_method'],
            'new_payment_method': paymentMethod,
            'previous_items': previousItems,
            'updated_items': newItemsAudit,
          },
          now);
    });
  }

  Future<void> voidOperation(int operationId, {required String reason}) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw ArgumentError('A reason is required');
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT o.*, s.status AS sheet_status, s.purchase_date
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        WHERE o.id = ? AND o.status = 'posted'
      ''', [operationId]);
      if (rows.isEmpty) throw StateError('Operation not found or already void');
      final op = rows.first;
      if (op['sheet_status'] != 'DRAFT') {
        throw StateError('Only draft daily sheets can be changed');
      }

      if (op['accounting_mode'] == 'supplier_account') {
        final original = await txn.query(
          'supplier_account_movements',
          columns: ['id', 'signed_amount_minor'],
          where: "source_type = 'daily_purchase' AND source_id = ?",
          whereArgs: [operationId],
          limit: 1,
        );
        if (original.isEmpty) {
          throw StateError('Original supplier movement is missing; cancellation was not applied');
        }
        final linkedCorrections = await txn.rawQuery('''
          SELECT m.id, m.signed_amount_minor
          FROM daily_operation_adjustment_movements link
          JOIN supplier_account_movements m ON m.id = link.movement_id
          WHERE link.operation_id = ? AND m.source_type = 'daily_purchase_edit'
            AND m.movement_type = 'adjustment'
          ORDER BY m.id
        ''', [operationId]);
        final postedTotal = (original.first['signed_amount_minor'] as int) +
            linkedCorrections.fold<int>(0, (sum, entry) =>
              sum + (entry['signed_amount_minor'] as int));
        if (postedTotal != op['total_minor']) {
          throw StateError('Cannot safely identify all historical corrections for this purchase; balance was not changed');
        }
        await txn.insert('supplier_account_movements', {
          'supplier_id': op['supplier_id'],
          'currency': op['currency'],
          'movement_type': 'reversal',
          'source_type': 'daily_purchase_void',
          'source_id': operationId,
          'entry_date': op['purchase_date'],
          'signed_amount_minor': -(original.first['signed_amount_minor'] as int),
          'note': 'إلغاء عملية شراء يومية: $cleanReason',
          'reverses_movement_id': original.first['id'],
          'created_at': now,
        });
        for (final edit in linkedCorrections) {
          await txn.insert('supplier_account_movements', {
            'supplier_id': op['supplier_id'],
            'currency': op['currency'],
            'movement_type': 'reversal',
            'source_type': 'daily_purchase_edit_void',
            'source_id': edit['id'],
            'entry_date': op['purchase_date'],
            'signed_amount_minor': -(edit['signed_amount_minor'] as int),
            'note': 'عكس تصحيح عملية شراء يومية #$operationId: $cleanReason',
            'reverses_movement_id': edit['id'],
            'created_at': now,
          });
        }
        final paymentId = op['initial_supplier_payment_id'] as int?;
        if (paymentId != null) {
          await _reverseSupplierPaymentInTransaction(
            txn,
            paymentId: paymentId,
            reversalDate: op['purchase_date'] as String,
            reason: 'Voided daily purchase: $cleanReason',
            createdAt: now,
          );
        }
      } else {
        final outstandingRows = await txn.query(
          'daily_purchase_outstandings',
          columns: ['id'],
          where: 'operation_id = ?',
          whereArgs: [operationId],
          limit: 1,
        );
        if (outstandingRows.isNotEmpty) {
          final outstandingId = outstandingRows.first['id'] as int;
          final laterPayments = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM daily_purchase_outstanding_payments WHERE outstanding_id = ?',
                [outstandingId],
              )) ??
              0;
          final priorAdjustments = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM daily_purchase_outstanding_adjustments WHERE outstanding_id = ?',
                [outstandingId],
              )) ??
              0;
          if (laterPayments > 0 || priorAdjustments > 0) {
            throw StateError(
                'Cannot void a daily purchase after payments or adjustments; record a correcting adjustment instead');
          }
          await txn.update('daily_purchase_outstandings', {'status': 'void'},
              where: 'id = ?', whereArgs: [outstandingId]);
        }
      }

      await txn.update(
          'daily_purchase_operations',
          {
            'status': 'void',
            'updated_at': now,
            'notes': [
              _clean(op['notes'] as String?),
              'إلغاء: $cleanReason',
            ].whereType<String>().join('\n'),
          },
          where: 'id = ?',
          whereArgs: [operationId]);
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': op['sheet_id'],
        'event_type': 'operation_voided',
        'details_json':
            jsonEncode({'operation_id': operationId, 'reason': cleanReason}),
        'created_at': now,
      });
      await _audit(
          txn,
          'void',
          'daily_purchase_operation',
          operationId,
          {
            'reason': cleanReason,
          },
          now);
    });
  }

  Future<List<DailyOutstandingRecord>> getOutstandingRecords({
    String? dateFrom,
    String? dateTo,
    int? branchId,
    int? employeeId,
    int? responsiblePersonId,
    bool includeSettled = false,
  }) async {
    final db = await _database.database;
    final where = <String>["o.status = 'posted'", "ob.status <> 'void'"];
    final args = <Object?>[];
    if (dateFrom != null) {
      where.add('s.purchase_date >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null) {
      where.add('s.purchase_date <= ?');
      args.add(dateTo);
    }
    if (branchId != null) {
      where.add('s.branch_id = ?');
      args.add(branchId);
    }
    if (employeeId != null) {
      where.add('s.employee_id = ?');
      args.add(employeeId);
    }
    if (responsiblePersonId != null) {
      where.add('o.responsible_person_id = ?');
      args.add(responsiblePersonId);
    }
    final outerWhere = includeSettled ? '' : 'WHERE remaining_minor > 0';
    final rows = await db.rawQuery('''
      SELECT * FROM (
        SELECT ob.id, o.id AS operation_id, o.operation_number,
          s.id AS sheet_id, s.sheet_number, s.purchase_date, ob.due_date,
          b.name AS branch_name, e.name AS employee_name,
          COALESCE(rp.name, o.responsible_person_name,
              o.seller_name, sp.name) AS seller_name,
          o.responsible_person_id,
          o.currency, ob.original_minor,
          COALESCE((
            SELECT SUM(p.amount_minor)
            FROM daily_purchase_outstanding_payments p
            WHERE p.outstanding_id = ob.id
          ),0) AS paid_minor,
          COALESCE((
            SELECT SUM(a.signed_delta_minor)
            FROM daily_purchase_outstanding_adjustments a
            WHERE a.outstanding_id = ob.id
          ),0) AS adjustment_delta_minor,
          ob.original_minor
            - COALESCE((
              SELECT SUM(p.amount_minor)
              FROM daily_purchase_outstanding_payments p
              WHERE p.outstanding_id = ob.id
            ),0)
            + COALESCE((
              SELECT SUM(a.signed_delta_minor)
              FROM daily_purchase_outstanding_adjustments a
              WHERE a.outstanding_id = ob.id
            ),0) AS remaining_minor,
          ob.status
        FROM daily_purchase_outstandings ob
        JOIN daily_purchase_operations o ON o.id = ob.operation_id
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        LEFT JOIN branches b ON b.id = s.branch_id
        LEFT JOIN employees e ON e.id = s.employee_id
        LEFT JOIN suppliers sp ON sp.id = o.supplier_id
        LEFT JOIN responsible_people rp ON rp.id = o.responsible_person_id
        WHERE ${where.join(' AND ')}
      )
      $outerWhere
      ORDER BY purchase_date DESC, id DESC
    ''', args);
    return rows
        .map((row) => DailyOutstandingRecord(
              id: row['id'] as int,
              operationId: row['operation_id'] as int,
              operationNumber: row['operation_number'] as String,
              sheetId: row['sheet_id'] as int,
              sheetNumber: row['sheet_number'] as String,
              purchaseDate: row['purchase_date'] as String,
              dueDate: row['due_date'] as String?,
              branchName: row['branch_name'] as String?,
              employeeName: row['employee_name'] as String?,
              sellerName: row['seller_name'] as String?,
              responsiblePersonId: row['responsible_person_id'] as int?,
              currency: row['currency'] as String,
              originalMinor: row['original_minor'] as int,
              paidMinor: row['paid_minor'] as int,
              adjustmentDeltaMinor: row['adjustment_delta_minor'] as int,
              remainingMinor: row['remaining_minor'] as int,
              status: (row['remaining_minor'] as int) == 0
                  ? 'paid'
                  : (row['paid_minor'] as int) > 0 ||
                          (row['adjustment_delta_minor'] as int) != 0
                      ? 'partial'
                      : 'open',
            ))
        .toList(growable: false);
  }

  Future<List<DailyOutstandingHistoryEntry>> getOutstandingHistory(
    int outstandingId,
  ) async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT id, payment_date AS entry_date, 'payment' AS entry_type,
        amount_minor, method, reference, notes AS reason
      FROM daily_purchase_outstanding_payments
      WHERE outstanding_id = ?
      UNION ALL
      SELECT id, adjustment_date AS entry_date, adjustment_type AS entry_type,
        signed_delta_minor AS amount_minor, NULL AS method, NULL AS reference,
        reason
      FROM daily_purchase_outstanding_adjustments
      WHERE outstanding_id = ?
      ORDER BY entry_date, id
    ''', [outstandingId, outstandingId]);
    return rows
        .map((row) => DailyOutstandingHistoryEntry(
              id: row['id'] as int,
              entryDate: row['entry_date'] as String,
              entryType: row['entry_type'] as String,
              amountMinor: row['amount_minor'] as int,
              method: row['method'] as String?,
              reference: row['reference'] as String?,
              reason: row['reason'] as String?,
            ))
        .toList(growable: false);
  }

  Future<void> recordOutstandingPayment({
    required int outstandingId,
    required int amountMinor,
    required String paymentDate,
    required String method,
    String? reference,
    String? notes,
    String? idempotencyKey,
    AttachmentDraft? attachment,
  }) async {
    if (amountMinor <= 0)
      throw ArgumentError('Payment must be greater than zero');
    _validateDate(paymentDate);
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final outstandingRows = await txn.rawQuery('''
        SELECT ob.*, o.status AS operation_status, o.sheet_id, o.operation_number
        FROM daily_purchase_outstandings ob
        JOIN daily_purchase_operations o ON o.id = ob.operation_id
        WHERE ob.id = ?
      ''', [outstandingId]);
      if (outstandingRows.isEmpty)
        throw StateError('Daily outstanding not found');
      final outstanding = outstandingRows.first;
      if (outstanding['status'] == 'void' ||
          outstanding['operation_status'] == 'void') {
        throw StateError('Cannot pay a void daily purchase');
      }
      final key = _clean(idempotencyKey);
      if (key != null) {
        final duplicate = await txn.query(
          'daily_purchase_outstanding_payments',
          columns: ['id'],
          where: 'idempotency_key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          final existingRows = await txn.query(
            'daily_purchase_outstanding_payments',
            where: 'id = ?',
            whereArgs: [duplicate.first['id']],
            limit: 1,
          );
          final existing = existingRows.first;
          if (existing['outstanding_id'] != outstandingId ||
              existing['amount_minor'] != amountMinor ||
              existing['payment_date'] != paymentDate ||
              existing['method'] != method ||
              existing['reference'] != _clean(reference) ||
              existing['notes'] != _clean(notes)) {
            throw StateError(
                'Idempotency key was already used for a different daily payment');
          }
          return;
        }
      }
      final paid = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(SUM(amount_minor),0) FROM daily_purchase_outstanding_payments WHERE outstanding_id = ?',
            [outstandingId],
          )) ??
          0;
      final adjustments = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(SUM(signed_delta_minor),0) FROM daily_purchase_outstanding_adjustments WHERE outstanding_id = ?',
            [outstandingId],
          )) ??
          0;
      final remaining =
          (outstanding['original_minor'] as int) - paid + adjustments;
      if (amountMinor > remaining)
        throw StateError('Payment exceeds daily outstanding');

      final paymentId =
          await txn.insert('daily_purchase_outstanding_payments', {
        'outstanding_id': outstandingId,
        'amount_minor': amountMinor,
        'payment_date': paymentDate,
        'method': method,
        'reference': _clean(reference),
        'notes': _clean(notes),
        'idempotency_key': key,
        'created_at': now,
      });
      if (attachment != null) {
        final attachmentId = await AttachmentService.save(
          txn,
          draft: attachment,
          entityType: 'daily_purchase_outstanding_payment',
          entityId: paymentId,
        );
        await txn.update(
          'daily_purchase_outstanding_payments',
          {'attachment_id': attachmentId},
          where: 'id = ?',
          whereArgs: [paymentId],
        );
      }
      final newRemaining = remaining - amountMinor;
      await txn.update(
          'daily_purchase_outstandings',
          {
            'status': newRemaining == 0 ? 'paid' : 'partial',
          },
          where: 'id = ?',
          whereArgs: [outstandingId]);
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': outstanding['sheet_id'],
        'event_type': 'outstanding_payment_recorded',
        'details_json': jsonEncode({
          'outstanding_id': outstandingId,
          'operation_number': outstanding['operation_number'],
          'amount_minor': amountMinor,
          'payment_date': paymentDate,
        }),
        'created_at': now,
      });
      await _audit(
          txn,
          'payment',
          'daily_purchase_outstanding',
          outstandingId,
          {
            'amount_minor': amountMinor,
            'payment_date': paymentDate,
          },
          now);
    });
  }

  Future<int> recordOutstandingAdjustment({
    required int outstandingId,
    required String adjustmentType,
    required int signedDeltaMinor,
    required String adjustmentDate,
    required String reason,
  }) async {
    if (!['return', 'adjustment'].contains(adjustmentType)) {
      throw ArgumentError('Invalid daily outstanding adjustment type');
    }
    if (signedDeltaMinor == 0) throw ArgumentError('Adjustment cannot be zero');
    if (adjustmentType == 'return' && signedDeltaMinor >= 0) {
      throw ArgumentError('A return must reduce the outstanding balance');
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty)
      throw ArgumentError('Adjustment reason is required');
    _validateDate(adjustmentDate);
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    return db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT ob.*, o.sheet_id, o.operation_number
        FROM daily_purchase_outstandings ob
        JOIN daily_purchase_operations o ON o.id = ob.operation_id
        WHERE ob.id = ?
      ''', [outstandingId]);
      if (rows.isEmpty || rows.first['status'] == 'void') {
        throw StateError('Daily outstanding not found or void');
      }
      final paid = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(SUM(amount_minor),0) FROM daily_purchase_outstanding_payments WHERE outstanding_id = ?',
            [outstandingId],
          )) ??
          0;
      final priorAdjustments = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(SUM(signed_delta_minor),0) FROM daily_purchase_outstanding_adjustments WHERE outstanding_id = ?',
            [outstandingId],
          )) ??
          0;
      final current =
          (rows.first['original_minor'] as int) - paid + priorAdjustments;
      if (current + signedDeltaMinor < 0) {
        throw StateError(
            'Adjustment cannot make the outstanding balance negative');
      }
      final id = await txn.insert('daily_purchase_outstanding_adjustments', {
        'outstanding_id': outstandingId,
        'adjustment_type': adjustmentType,
        'signed_delta_minor': signedDeltaMinor,
        'adjustment_date': adjustmentDate,
        'reason': cleanReason,
        'created_at': now,
      });
      final remaining = current + signedDeltaMinor;
      await txn.update(
          'daily_purchase_outstandings',
          {
            'status': remaining == 0 ? 'paid' : 'partial',
          },
          where: 'id = ?',
          whereArgs: [outstandingId]);
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': rows.first['sheet_id'],
        'event_type': 'outstanding_adjustment_recorded',
        'details_json': jsonEncode({
          'outstanding_id': outstandingId,
          'operation_number': rows.first['operation_number'],
          'adjustment_id': id,
          'adjustment_type': adjustmentType,
          'signed_delta_minor': signedDeltaMinor,
          'reason': cleanReason,
        }),
        'created_at': now,
      });
      await _audit(
          txn,
          adjustmentType,
          'daily_purchase_outstanding',
          outstandingId,
          {
            'adjustment_id': id,
            'signed_delta_minor': signedDeltaMinor,
            'reason': cleanReason,
          },
          now);
      return id;
    });
  }

  Future<void> transitionSheetStatus(int sheetId, String targetStatus) async {
    const transitions = {
      'DRAFT': 'READY_FOR_HANDOVER',
      'READY_FOR_HANDOVER': 'HANDED_OVER',
      'HANDED_OVER': 'CLOSED',
    };
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'daily_purchase_sheets',
        where: 'id = ?',
        whereArgs: [sheetId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Daily sheet not found');
      final sheet = rows.first;
      if (await _isArchived(txn, sheetId)) {
        throw StateError('An archived daily sheet cannot be handed over');
      }
      final current = sheet['status'] as String;
      if (transitions[current] != targetStatus) {
        throw StateError(
            'Invalid status transition: $current -> $targetStatus');
      }
      if (targetStatus == 'READY_FOR_HANDOVER') {
        final operationCount = Sqflite.firstIntValue(await txn.rawQuery(
              "SELECT COUNT(*) FROM daily_purchase_operations WHERE sheet_id = ? AND status = 'posted'",
              [sheetId],
            )) ??
            0;
        if (operationCount == 0)
          throw StateError(
              'Add at least one purchase before preparing handover');
      }

      final update = <String, Object?>{
        'status': targetStatus,
        'updated_at': now,
      };
      if (targetStatus == 'HANDED_OVER') {
        final profileRows = await txn.query('business_profiles', limit: 1);
        final branchRows = sheet['branch_id'] == null
            ? const <Map<String, Object?>>[]
            : await txn.query('branches',
                where: 'id = ?', whereArgs: [sheet['branch_id']], limit: 1);
        final employeeRows = sheet['employee_id'] == null
            ? const <Map<String, Object?>>[]
            : await txn.query('employees',
                where: 'id = ?', whereArgs: [sheet['employee_id']], limit: 1);
        final totals = await _totalsForSheet(txn, sheetId);
        update['header_snapshot_json'] = jsonEncode({
          'business': profileRows.isEmpty ? {} : profileRows.first,
          'branch': branchRows.isEmpty ? null : branchRows.first,
          'employee': employeeRows.isEmpty ? null : employeeRows.first,
          'captured_at': now,
        });
        update['totals_snapshot_json'] = jsonEncode({
          for (final total in totals)
            total.currency: {
              'total_minor': total.totalMinor,
              'cash_minor': total.cashMinor,
              'credit_minor': total.creditMinor,
              'paid_minor': total.paidMinor,
              'daily_outstanding_minor': total.outstandingMinor,
              'supplier_account_credit_minor': total.supplierAccountCreditMinor,
            }
        });
        update['operations_snapshot_json'] =
            jsonEncode(await _snapshotOperations(txn, sheetId));
        update['handed_over_at'] = now;
      } else if (targetStatus == 'CLOSED') {
        update['closed_at'] = now;
      }

      await txn.update('daily_purchase_sheets', update,
          where: 'id = ?', whereArgs: [sheetId]);
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': sheetId,
        'event_type': 'status_changed',
        'from_status': current,
        'to_status': targetStatus,
        'details_json': jsonEncode({'changed_at': now}),
        'created_at': now,
      });
      await _audit(
          txn,
          'status_change',
          'daily_purchase_sheet',
          sheetId,
          {
            'from': current,
            'to': targetStatus,
          },
          now);
    });
  }

  Future<int> addAmendment({
    required int sheetId,
    required String reason,
    required String details,
    String? currency,
    int amountDeltaMinor = 0,
  }) async {
    final cleanReason = reason.trim();
    final cleanDetails = details.trim();
    if (cleanReason.isEmpty || cleanDetails.isEmpty) {
      throw ArgumentError('Amendment reason and details are required');
    }
    if (amountDeltaMinor != 0 && _clean(currency) == null) {
      throw ArgumentError(
          'Currency is required when an amendment has a financial amount');
    }
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();
    return db.transaction((txn) async {
      final sheetRows = await txn.query(
        'daily_purchase_sheets',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [sheetId],
        limit: 1,
      );
      if (sheetRows.isEmpty) throw StateError('Daily sheet not found');
      final status = sheetRows.first['status'] as String;
      if (status != 'HANDED_OVER' && status != 'CLOSED') {
        throw StateError('Amendments are available after handover');
      }
      final count = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM daily_purchase_sheet_amendments WHERE sheet_id = ?',
            [sheetId],
          )) ??
          0;
      final number = 'ADD-${(count + 1).toString().padLeft(3, '0')}';
      final id = await txn.insert('daily_purchase_sheet_amendments', {
        'sheet_id': sheetId,
        'amendment_number': number,
        'reason': cleanReason,
        'details': cleanDetails,
        'currency': _clean(currency),
        'amount_delta_minor': amountDeltaMinor,
        'created_at': now,
      });
      await txn.insert('daily_purchase_sheet_events', {
        'sheet_id': sheetId,
        'event_type': 'amendment_created',
        'details_json': jsonEncode({
          'amendment_id': id,
          'amendment_number': number,
          'reason': cleanReason,
          'amount_delta_minor': amountDeltaMinor,
          'currency': currency,
        }),
        'created_at': now,
      });
      await _audit(
          txn,
          'amendment',
          'daily_purchase_sheet',
          sheetId,
          {
            'amendment_id': id,
            'amendment_number': number,
            'reason': cleanReason,
          },
          now);
      return id;
    });
  }

  Future<List<DailySheetEvent>> getEvents(int sheetId) async {
    final db = await _database.database;
    final rows = await db.query(
      'daily_purchase_sheet_events',
      where: 'sheet_id = ?',
      whereArgs: [sheetId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows
        .map((row) => DailySheetEvent(
              id: row['id'] as int,
              eventType: row['event_type'] as String,
              fromStatus: row['from_status'] as String?,
              toStatus: row['to_status'] as String?,
              detailsJson: row['details_json'] as String?,
              createdAt: row['created_at'] as String,
            ))
        .toList(growable: false);
  }

  Future<List<DailySheetAmendment>> getAmendments(int sheetId) async {
    final db = await _database.database;
    final rows = await db.query(
      'daily_purchase_sheet_amendments',
      where: 'sheet_id = ?',
      whereArgs: [sheetId],
      orderBy: 'created_at, id',
    );
    return rows
        .map((row) => DailySheetAmendment(
              id: row['id'] as int,
              amendmentNumber: row['amendment_number'] as String,
              reason: row['reason'] as String,
              details: row['details'] as String,
              currency: row['currency'] as String?,
              amountDeltaMinor: row['amount_delta_minor'] as int,
              createdAt: row['created_at'] as String,
            ))
        .toList(growable: false);
  }

  Future<DailySheetDetail> getSheetDetail(int sheetId) async {
    final db = await _database.database;
    final hasOperationHistory = (Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM daily_purchase_operations WHERE sheet_id = ?',
      [sheetId],
    )) ?? 0) > 0;
    final archived = (Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM daily_purchase_sheet_events WHERE sheet_id = ? AND event_type = 'archived'",
      [sheetId],
    )) ?? 0) > 0;
    final rows = await db.rawQuery('''
      SELECT s.*, b.name AS branch_name, e.name AS employee_name
      FROM daily_purchase_sheets s
      LEFT JOIN branches b ON b.id = s.branch_id
      LEFT JOIN employees e ON e.id = s.employee_id
      WHERE s.id = ?
    ''', [sheetId]);
    if (rows.isEmpty) throw StateError('Daily sheet not found');
    final sheet = rows.first;
    final operationRows = await db.rawQuery('''
      SELECT o.*, s.purchase_date, sp.name AS supplier_name,
        ob.id AS outstanding_id, ob.original_minor AS outstanding_original_minor,
        ob.status AS outstanding_status,
        COALESCE((
          SELECT SUM(dp.amount_minor)
          FROM daily_purchase_outstanding_payments dp
          WHERE dp.outstanding_id = ob.id
        ),0) AS later_paid_minor
      FROM daily_purchase_operations o
      JOIN daily_purchase_sheets s ON s.id = o.sheet_id
      LEFT JOIN suppliers sp ON sp.id = o.supplier_id
      LEFT JOIN daily_purchase_outstandings ob ON ob.operation_id = o.id
      WHERE o.sheet_id = ? AND o.status = 'posted'
      ORDER BY o.id
    ''', [sheetId]);

    final operations = <DailyPurchaseOperation>[];
    for (final row in operationRows) {
      final operationId = row['id'] as int;
      final itemRows = await db.rawQuery('''
        SELECT i.*, c.name AS category_name
        FROM daily_purchase_items i
        LEFT JOIN purchase_categories c ON c.id = i.category_id
        WHERE i.operation_id = ?
        ORDER BY i.id
      ''', [operationId]);
      final items = itemRows
          .map((item) => DailyPurchaseItem(
                id: item['id'] as int,
                productId: item['product_id'] as int?,
                categoryId: item['category_id'] as int?,
                categoryName: item['category_name'] as String?,
                itemName: item['item_name'] as String,
                quantityMilli: item['quantity_milli'] as int,
                unitName: item['unit_name'] as String,
                unitPriceMinor: item['unit_price_minor'] as int,
                discountMinor: item['discount_minor'] as int,
                taxMinor: item['tax_minor'] as int,
                lineTotalMinor: item['line_total_minor'] as int,
                sellerName: item['seller_name'] as String?,
                notes: item['notes'] as String?,
              ))
          .toList(growable: false);
      final laterPaid = row['later_paid_minor'] as int;
      final original = (row['outstanding_original_minor'] as int?) ?? 0;
      final adjustmentDelta = row['outstanding_id'] == null
          ? 0
          : (Sqflite.firstIntValue(await db.rawQuery(
                'SELECT COALESCE(SUM(signed_delta_minor),0) FROM daily_purchase_outstanding_adjustments WHERE outstanding_id = ?',
                [row['outstanding_id']],
              )) ??
              0);
      final dailyRemaining =
          math.max(0, original - laterPaid + adjustmentDelta);
      final mode = row['accounting_mode'] as String;
      operations.add(DailyPurchaseOperation(
        id: operationId,
        operationNumber: row['operation_number'] as String,
        supplierId: row['supplier_id'] as int?,
        supplierName: row['supplier_name'] as String?,
        accountingMode: mode,
        outstandingId: row['outstanding_id'] as int?,
        sellerName: row['seller_name'] as String?,
        recordingCategory: row['recording_category'] as String?,
        responsiblePersonName: row['responsible_person_name'] as String?,
        responsiblePersonId: row['responsible_person_id'] as int?,
        currency: row['currency'] as String,
        paymentMethod: row['payment_method'] as String? ?? 'unspecified',
        subtotalMinor: row['subtotal_minor'] as int,
        discountMinor: row['discount_minor'] as int,
        taxMinor: row['tax_minor'] as int,
        totalMinor: row['total_minor'] as int,
        amountPaidMinor: row['amount_paid_minor'] as int,
        laterPaidMinor: laterPaid,
        outstandingMinor: mode == 'daily_outstanding' ? dailyRemaining : 0,
        supplierAccountCreditMinor: mode == 'supplier_account'
            ? math.max(0,
                (row['total_minor'] as int) - (row['amount_paid_minor'] as int))
            : 0,
        dueDate: row['due_date'] as String?,
        status: row['status'] as String,
        notes: row['notes'] as String?,
        items: items,
      ));
    }

    final amendmentCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM daily_purchase_sheet_amendments WHERE sheet_id = ?',
          [sheetId],
        )) ??
        0;

    final restrictedOperationCount = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM daily_purchase_operations o
      WHERE o.sheet_id = ? AND (
        o.status <> 'posted' OR o.recording_category IS NOT 'cash'
        OR o.accounting_mode <> 'daily_outstanding'
        OR o.supplier_id IS NOT NULL
        OR o.legacy_cash_purchase_id IS NOT NULL
        OR o.initial_supplier_payment_id IS NOT NULL
        OR o.total_minor <> o.amount_paid_minor
        OR EXISTS (SELECT 1 FROM daily_purchase_outstandings ob
          WHERE ob.operation_id = o.id)
      )
    ''', [sheetId])) ?? 0;
    return DailySheetDetail(
      id: sheetId,
      sheetNumber: sheet['sheet_number'] as String,
      purchaseDate: sheet['purchase_date'] as String,
      branchId: sheet['branch_id'] as int?,
      branchName: sheet['branch_name'] as String?,
      employeeId: sheet['employee_id'] as int?,
      employeeName: sheet['employee_name'] as String?,
      notes: sheet['notes'] as String?,
      status: archived ? 'ARCHIVED' : sheet['status'] as String,
      handedOverAt: sheet['handed_over_at'] as String?,
      closedAt: sheet['closed_at'] as String?,
      headerSnapshotJson: sheet['header_snapshot_json'] as String?,
      totalsSnapshotJson: sheet['totals_snapshot_json'] as String?,
      operationsSnapshotJson: sheet['operations_snapshot_json'] as String?,
      operations: operations,
      hasOperationHistory: hasOperationHistory,
      canEditIdentity: !archived && sheet['status'] == 'DRAFT' &&
          restrictedOperationCount == 0 && amendmentCount == 0,
      amendmentCount: amendmentCount,
    );
  }

  Future<DailyHandoverReport> getHandoverReport(int sheetId) async {
    final db = await _database.database;
    final detail = await getSheetDetail(sheetId);
    Map<String, Object?> snapshot = {};
    if (detail.headerSnapshotJson != null) {
      final decoded = jsonDecode(detail.headerSnapshotJson!);
      if (decoded is Map) snapshot = Map<String, Object?>.from(decoded);
    }
    Map<String, Object?> business = {};
    Map<String, Object?>? branch;
    Map<String, Object?>? employee;
    if (snapshot['business'] is Map) {
      business = Map<String, Object?>.from(snapshot['business'] as Map);
    } else {
      final profileRows = await db.query('business_profiles', limit: 1);
      if (profileRows.isNotEmpty) business = profileRows.first;
    }
    if (snapshot['branch'] is Map) {
      branch = Map<String, Object?>.from(snapshot['branch'] as Map);
    } else if (detail.branchId != null) {
      final rows = await db.query('branches',
          where: 'id = ?', whereArgs: [detail.branchId], limit: 1);
      if (rows.isNotEmpty) branch = rows.first;
    }
    if (snapshot['employee'] is Map) {
      employee = Map<String, Object?>.from(snapshot['employee'] as Map);
    } else if (detail.employeeId != null) {
      final rows = await db.query('employees',
          where: 'id = ?', whereArgs: [detail.employeeId], limit: 1);
      if (rows.isNotEmpty) employee = rows.first;
    }
    final amendments = await getAmendments(sheetId);
    var reportSheet = detail;
    if (detail.operationsSnapshotJson != null) {
      final decodedOperations = jsonDecode(detail.operationsSnapshotJson!);
      if (decodedOperations is List) {
        final snapshotOperations = decodedOperations
            .whereType<Map>()
            .map(_operationFromSnapshot)
            .toList(growable: false);
        reportSheet = DailySheetDetail(
          id: detail.id,
          sheetNumber: detail.sheetNumber,
          purchaseDate: detail.purchaseDate,
          branchId: detail.branchId,
          branchName: detail.branchName,
          employeeId: detail.employeeId,
          employeeName: detail.employeeName,
          notes: detail.notes,
          status: detail.status,
          handedOverAt: detail.handedOverAt,
          closedAt: detail.closedAt,
          headerSnapshotJson: detail.headerSnapshotJson,
          totalsSnapshotJson: detail.totalsSnapshotJson,
          operationsSnapshotJson: detail.operationsSnapshotJson,
          operations: snapshotOperations,
          hasOperationHistory: detail.hasOperationHistory,
          amendmentCount: detail.amendmentCount,
        );
      }
    }
    List<DailySheetCurrencyTotal> totals;
    if (detail.totalsSnapshotJson != null) {
      final decodedTotals = jsonDecode(detail.totalsSnapshotJson!);
      final map =
          decodedTotals is Map ? decodedTotals : const <Object?, Object?>{};
      totals = map.entries.map((entry) {
        final values = Map<String, Object?>.from(entry.value as Map);
        return DailySheetCurrencyTotal(
          currency: entry.key.toString(),
          totalMinor: values['total_minor'] as int? ?? 0,
          cashMinor: values['cash_minor'] as int? ?? 0,
          creditMinor: values['credit_minor'] as int? ?? 0,
          paidMinor: values['paid_minor'] as int? ?? 0,
          outstandingMinor: values['daily_outstanding_minor'] as int? ?? 0,
          supplierAccountCreditMinor:
              values['supplier_account_credit_minor'] as int? ?? 0,
        );
      }).toList(growable: false);
    } else {
      totals = await _totalsForSheet(db, sheetId);
    }
    return DailyHandoverReport(
      sheet: reportSheet,
      shopName: (business['shop_name'] as String?) ?? 'Purchase Ledger',
      shopLogoPath: business['logo_path'] as String?,
      shopNumber: business['shop_number'] as String?,
      shopAddress: business['address'] as String?,
      shopPhone: business['phone'] as String?,
      managerName: business['manager_name'] as String?,
      buyerName: (employee?['name'] as String?) ?? detail.employeeName ??
          business['buyer_name'] as String?,
      branchName: (branch?['name'] as String?) ?? detail.branchName,
      branchCode: branch?['code'] as String?,
      totalsByCurrency: totals,
      amendments: amendments,
    );
  }

  Future<List<Map<String, Object?>>> _snapshotOperations(
    DatabaseExecutor executor,
    int sheetId,
  ) async {
    final rows = await executor.rawQuery('''
      SELECT o.*, sp.name AS supplier_name, ob.id AS outstanding_id,
        ob.original_minor AS outstanding_original_minor,
        COALESCE((
          SELECT SUM(dp.amount_minor)
          FROM daily_purchase_outstanding_payments dp
          WHERE dp.outstanding_id = ob.id
        ),0) AS later_paid_minor,
        COALESCE((
          SELECT SUM(da.signed_delta_minor)
          FROM daily_purchase_outstanding_adjustments da
          WHERE da.outstanding_id = ob.id
        ),0) AS adjustment_delta_minor
      FROM daily_purchase_operations o
      LEFT JOIN suppliers sp ON sp.id = o.supplier_id
      LEFT JOIN daily_purchase_outstandings ob ON ob.operation_id = o.id
      WHERE o.sheet_id = ? AND o.status = 'posted'
      ORDER BY o.id
    ''', [sheetId]);
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final items = await executor.rawQuery('''
        SELECT i.*, c.name AS category_name
        FROM daily_purchase_items i
        LEFT JOIN purchase_categories c ON c.id = i.category_id
        WHERE i.operation_id = ?
        ORDER BY i.id
      ''', [row['id']]);
      final mode = row['accounting_mode'] as String;
      final total = row['total_minor'] as int;
      final paidAtPurchase = row['amount_paid_minor'] as int;
      final laterPaid = row['later_paid_minor'] as int;
      final original = (row['outstanding_original_minor'] as int?) ?? 0;
      final adjustment = (row['adjustment_delta_minor'] as int?) ?? 0;
      result.add({
        'id': row['id'],
        'operation_number': row['operation_number'],
        'supplier_id': row['supplier_id'],
        'supplier_name': row['supplier_name'],
        'accounting_mode': mode,
        'outstanding_id': row['outstanding_id'],
        'seller_name': row['seller_name'],
        'currency': row['currency'],
        'payment_method': row['payment_method'],
        'subtotal_minor': row['subtotal_minor'],
        'discount_minor': row['discount_minor'],
        'tax_minor': row['tax_minor'],
        'total_minor': total,
        'amount_paid_minor': paidAtPurchase,
        'later_paid_minor': laterPaid,
        'outstanding_minor': mode == 'daily_outstanding'
            ? math.max(0, original - laterPaid + adjustment)
            : 0,
        'supplier_account_credit_minor': mode == 'supplier_account'
            ? math.max(0, total - paidAtPurchase)
            : 0,
        'due_date': row['due_date'],
        'status': row['status'],
        'notes': row['notes'],
        'items': items,
      });
    }
    return result;
  }

  DailyPurchaseOperation _operationFromSnapshot(Map<dynamic, dynamic> row) {
    final rawItems = row['items'] as List? ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map((item) => DailyPurchaseItem(
              id: item['id'] as int,
              productId: item['product_id'] as int?,
              categoryId: item['category_id'] as int?,
              categoryName: item['category_name'] as String?,
              itemName: item['item_name'] as String,
              quantityMilli: item['quantity_milli'] as int,
              unitName: item['unit_name'] as String,
              unitPriceMinor: item['unit_price_minor'] as int,
              discountMinor: item['discount_minor'] as int,
              taxMinor: item['tax_minor'] as int,
              lineTotalMinor: item['line_total_minor'] as int,
              sellerName: item['seller_name'] as String?,
              notes: item['notes'] as String?,
            ))
        .toList(growable: false);
    return DailyPurchaseOperation(
      id: row['id'] as int,
      operationNumber: row['operation_number'] as String,
      supplierId: row['supplier_id'] as int?,
      supplierName: row['supplier_name'] as String?,
      accountingMode: row['accounting_mode'] as String,
      outstandingId: row['outstanding_id'] as int?,
      sellerName: row['seller_name'] as String?,
      currency: row['currency'] as String,
      paymentMethod: row['payment_method'] as String? ?? 'unspecified',
      subtotalMinor: row['subtotal_minor'] as int,
      discountMinor: row['discount_minor'] as int,
      taxMinor: row['tax_minor'] as int,
      totalMinor: row['total_minor'] as int,
      amountPaidMinor: row['amount_paid_minor'] as int,
      laterPaidMinor: row['later_paid_minor'] as int,
      outstandingMinor: row['outstanding_minor'] as int,
      supplierAccountCreditMinor: row['supplier_account_credit_minor'] as int,
      dueDate: row['due_date'] as String?,
      status: row['status'] as String,
      notes: row['notes'] as String?,
      items: items,
    );
  }

  Future<List<DailySheetCurrencyTotal>> _totalsForSheet(
    DatabaseExecutor executor,
    int sheetId,
  ) async {
    final rows = await executor.rawQuery('''
      SELECT o.currency,
        SUM(o.total_minor) AS total_minor,
        SUM(o.amount_paid_minor) AS cash_minor,
        SUM(o.amount_paid_minor + CASE WHEN o.accounting_mode = 'daily_outstanding'
          THEN COALESCE((
            SELECT SUM(dp.amount_minor)
            FROM daily_purchase_outstanding_payments dp
            WHERE dp.outstanding_id = ob.id
          ),0) ELSE 0 END) AS paid_minor,
        SUM(CASE WHEN o.accounting_mode = 'daily_outstanding'
          THEN COALESCE(ob.original_minor,0)
            - COALESCE((
              SELECT SUM(dp.amount_minor)
              FROM daily_purchase_outstanding_payments dp
              WHERE dp.outstanding_id = ob.id
            ),0)
            + COALESCE((
              SELECT SUM(da.signed_delta_minor)
              FROM daily_purchase_outstanding_adjustments da
              WHERE da.outstanding_id = ob.id
            ),0)
          ELSE 0 END) AS outstanding_minor,
        SUM(CASE WHEN o.accounting_mode = 'supplier_account'
          THEN o.total_minor - o.amount_paid_minor ELSE 0 END) AS supplier_credit_minor
      FROM daily_purchase_operations o
      LEFT JOIN daily_purchase_outstandings ob ON ob.operation_id = o.id
      WHERE o.sheet_id = ? AND o.status = 'posted'
      GROUP BY o.currency
      ORDER BY o.currency
    ''', [sheetId]);
    return rows.map((row) {
      final total = (row['total_minor'] as int?) ?? 0;
      final paid = (row['paid_minor'] as int?) ?? 0;
      return DailySheetCurrencyTotal(
        currency: row['currency'] as String,
        totalMinor: total,
        cashMinor: (row['cash_minor'] as int?) ?? 0,
        creditMinor: math.max(0, total - ((row['cash_minor'] as int?) ?? 0)),
        paidMinor: paid,
        outstandingMinor: math.max(0, (row['outstanding_minor'] as int?) ?? 0),
        supplierAccountCreditMinor: (row['supplier_credit_minor'] as int?) ?? 0,
      );
    }).toList(growable: false);
  }

  Future<void> _insertItem(
    DatabaseExecutor executor,
    int operationId,
    PurchaseLine line,
  ) async {
    if (line.description.trim().isEmpty || line.unitName.trim().isEmpty) {
      throw ArgumentError('Item name and unit are required');
    }
    await executor.insert('daily_purchase_items', {
      'operation_id': operationId,
      'product_id': line.productId,
      'category_id': line.categoryId,
      'item_name': line.description.trim(),
      'quantity_milli': line.quantityMilli,
      'unit_name': line.unitName.trim(),
      'unit_price_minor': line.unitPriceMinor,
      'discount_minor': line.discountMinor,
      'tax_minor': line.taxMinor,
      'line_total_minor': line.totalMinor,
      'seller_name': _clean(line.sellerName),
      'notes': _clean(line.notes),
    });
  }

  Future<void> _reverseSupplierPaymentInTransaction(
    Transaction txn, {
    required int paymentId,
    required String reversalDate,
    required String reason,
    required String createdAt,
  }) async {
    final paymentRows = await txn.query(
      'supplier_payments',
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (paymentRows.isEmpty) {
      throw StateError('Linked supplier payment is missing; cancellation was not applied');
    }
    final payment = paymentRows.first;
    final reversed = await txn.query(
      'supplier_payment_reversals',
      columns: ['id'],
      where: 'payment_id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (reversed.isNotEmpty) return;
    final allocations = Sqflite.firstIntValue(await txn.rawQuery(
      'SELECT COUNT(*) FROM payment_allocations WHERE payment_id = ?',
      [paymentId],
    )) ?? 0;
    if (allocations > 0) {
      throw StateError('Linked payment has invoice allocations; reverse those dependencies before cancelling the daily purchase');
    }
    final movementRows = await txn.query(
      'supplier_account_movements',
      columns: ['id'],
      where:
          "source_type = 'payment' AND source_id = ? AND movement_type = 'payment'",
      whereArgs: [paymentId],
      limit: 1,
    );
    if (movementRows.isEmpty) {
      throw StateError('Linked supplier payment movement is missing; cancellation was not applied');
    }
    final amount = payment['amount_minor'] as int;
    final reversalId = await txn.insert('supplier_payment_reversals', {
      'payment_id': paymentId,
      'amount_minor': amount,
      'reversal_date': reversalDate,
      'reason': reason,
      'created_at': createdAt,
    });
    await txn.insert('supplier_account_movements', {
      'supplier_id': payment['supplier_id'],
      'currency': payment['currency'],
      'movement_type': 'reversal',
      'source_type': 'supplier_payment_reversal',
      'source_id': reversalId,
      'entry_date': reversalDate,
      'signed_amount_minor': amount,
      'note': 'Payment reversal: $reason',
      'reverses_movement_id': movementRows.first['id'],
      'created_at': createdAt,
    });
  }

  _DailyTotals _calculateTotals(List<PurchaseLine> lines) {
    var subtotal = 0;
    var discount = 0;
    var tax = 0;
    var total = 0;
    for (final line in lines) {
      final gross = (line.quantityMilli * line.unitPriceMinor + 500) ~/ 1000;
      subtotal += gross;
      discount += line.discountMinor;
      tax += line.taxMinor;
      total += line.totalMinor;
    }
    return _DailyTotals(subtotal, discount, tax, total);
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
      'details_json': jsonEncode(details),
      'created_at': createdAt,
    });
  }

  void _validateDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw ArgumentError('Date must be a real date in YYYY-MM-DD form');
    }
  }

  void _validateOptionalDate(String? value) {
    if (value != null && value.trim().isNotEmpty) _validateDate(value.trim());
  }

  String? _clean(String? value) {
    final result = value?.trim();
    return result == null || result.isEmpty ? null : result;
  }
}

class _DailyTotals {
  const _DailyTotals(this.subtotal, this.discount, this.tax, this.total);
  final int subtotal;
  final int discount;
  final int tax;
  final int total;
}
