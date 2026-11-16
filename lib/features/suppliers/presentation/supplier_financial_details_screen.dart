import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money.dart';
import '../../purchases/presentation/daily_purchase_sheet_screen.dart';
import 'supplier_return_dialog.dart';

/// Read-only drill-down into original documents. Financial history is never
/// synthesized from screen totals; every row comes from the source tables.
class SupplierPurchasesScreen extends ConsumerWidget {
  const SupplierPurchasesScreen({super.key, required this.supplierId});
  final int supplierId;

  Future<List<Map<String, Object?>>> _load(WidgetRef ref) async {
    final db = await ref.read(appDatabaseProvider).database;
    return db.rawQuery('''
      SELECT id, invoice_number AS document_number, invoice_date AS purchase_date,
        currency, total_minor, status, 'credit_invoice' AS source_type
      FROM credit_purchase_invoices
      WHERE supplier_id = ?
      UNION ALL
      SELECT o.id, o.operation_number, s.purchase_date, o.currency,
        o.total_minor, o.status, 'daily_purchase'
      FROM daily_purchase_operations o
      JOIN daily_purchase_sheets s ON s.id = o.sheet_id
      WHERE o.supplier_id = ?
      ORDER BY purchase_date DESC, id DESC
    ''', [supplierId, supplierId]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'سجل البضائع المستلمة', 'Goods received'))),
    body: SafeArea(top: false, child: FutureBuilder<List<Map<String, Object?>>>(
      future: _load(ref),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${tr(context, 'تعذر تحميل المشتريات', 'Could not load purchases')}: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return Center(child: Text(tr(context, 'لا توجد عمليات شراء مسجلة', 'No purchases recorded')));
        String? lastDate;
        final children = <Widget>[];
        for (final row in items) {
          final date = row['purchase_date'] as String? ?? tr(context, 'غير مؤرخ', 'Undated');
          if (date != lastDate) {
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(12, 15, 12, 5),
              child: Text(date, style: Theme.of(context).textTheme.titleSmall),
            ));
            lastDate = date;
          }
          final invoice = row['source_type'] == 'credit_invoice';
          final total = row['total_minor'] as int? ?? 0;
          final currency = row['currency'] as String? ?? 'YER';
          children.add(Card(child: ListTile(
            title: Text('${invoice ? tr(context, 'فاتورة آجلة', 'Credit invoice') : tr(context, 'شراء يومي', 'Daily purchase')} • ${row['document_number']}'),
            subtitle: Text('${_detailValue(context, 'status', row['status'])} • ${Money.format(total, currency, locale: Localizations.localeOf(context).languageCode)}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => SupplierDocumentDetailScreen(
                documentType: row['source_type'] as String,
                documentId: row['id'] as int,
              ),
            )),
          )));
        }
        return ListView(padding: const EdgeInsets.fromLTRB(10, 4, 10, 30), children: children);
      },
    )),
  );
}

class SupplierDocumentDetailScreen extends ConsumerWidget {
  const SupplierDocumentDetailScreen({
    super.key, required this.documentType, required this.documentId,
  });
  final String documentType;
  final int documentId;

  Future<Map<String, Object?>> _load(WidgetRef ref) async {
    final db = await ref.read(appDatabaseProvider).database;
    final data = <String, Object?>{};
    if (documentType == 'credit_invoice') {
      final rows = await db.rawQuery('''
        SELECT i.*, s.name AS supplier_name, b.name AS branch_name,
          e.name AS employee_name FROM credit_purchase_invoices i
        JOIN suppliers s ON s.id = i.supplier_id
        LEFT JOIN branches b ON b.id = i.branch_id
        LEFT JOIN employees e ON e.id = i.employee_id WHERE i.id = ?
      ''', [documentId]);
      if (rows.isEmpty) throw StateError('الفاتورة غير موجودة');
      data['header'] = rows.first;
      data['lines'] = await db.query('credit_purchase_items',
          where: 'invoice_id = ?', whereArgs: [documentId], orderBy: 'id');
      data['payments'] = await db.rawQuery('''
        SELECT p.receipt_number, p.payment_date, p.method, a.amount_minor,
          CASE WHEN r.id IS NULL THEN 0 ELSE 1 END AS reversed
        FROM payment_allocations a JOIN supplier_payments p ON p.id = a.payment_id
        LEFT JOIN supplier_payment_reversals r ON r.payment_id = p.id
        WHERE a.invoice_id = ? ORDER BY p.payment_date, p.id
      ''', [documentId]);
      data['returns'] = await db.rawQuery('''
        SELECT r.return_number, r.return_date, r.total_minor,
          r.notes, ri.description AS item_description,
          ri.quantity_milli, ri.unit_name, ri.amount_minor AS item_amount_minor
        FROM purchase_returns r
        LEFT JOIN purchase_return_items ri ON ri.return_id = r.id
        WHERE r.invoice_id = ?
        ORDER BY r.return_date, r.id, ri.id
      ''', [documentId]);
    } else if (documentType == 'daily_purchase') {
      final rows = await db.rawQuery('''
        SELECT o.*, s.purchase_date, s.sheet_number, p.name AS supplier_name
        FROM daily_purchase_operations o
        JOIN daily_purchase_sheets s ON s.id = o.sheet_id
        LEFT JOIN suppliers p ON p.id = o.supplier_id WHERE o.id = ?
      ''', [documentId]);
      if (rows.isEmpty) throw StateError('عملية الشراء غير موجودة');
      data['header'] = rows.first;
      data['lines'] = await db.query('daily_purchase_items',
          where: 'operation_id = ?', whereArgs: [documentId], orderBy: 'id');
      data['payments'] = <Map<String, Object?>>[];
      data['returns'] = <Map<String, Object?>>[];
    } else if (documentType == 'payment') {
      final rows = await db.rawQuery('''
        SELECT p.*, s.name AS supplier_name,
          CASE WHEN EXISTS(SELECT 1 FROM supplier_payment_reversals r
            WHERE r.payment_id = p.id) THEN 0
            ELSE COALESCE((SELECT SUM(a.amount_minor) FROM payment_allocations a
              WHERE a.payment_id = p.id), 0)
          END AS allocated_minor,
          COALESCE((SELECT SUM(a.amount_minor) FROM payment_allocations a
            WHERE a.payment_id = p.id), 0) AS historical_allocated_minor,
          CASE WHEN EXISTS(SELECT 1 FROM supplier_payment_reversals r
            WHERE r.payment_id = p.id) THEN 0
            ELSE p.amount_minor - COALESCE((SELECT SUM(a.amount_minor)
            FROM payment_allocations a WHERE a.payment_id = p.id), 0)
          END AS unallocated_minor
        FROM supplier_payments p
        JOIN suppliers s ON s.id = p.supplier_id WHERE p.id = ?
      ''', [documentId]);
      if (rows.isEmpty) throw StateError('الدفعة غير موجودة');
      data['header'] = rows.first;
      data['lines'] = await db.rawQuery('''
        SELECT a.*, i.invoice_number, i.invoice_date,
          i.total_minor AS invoice_total_minor
        FROM payment_allocations a
        JOIN credit_purchase_invoices i ON i.id = a.invoice_id
        WHERE a.payment_id = ? ORDER BY i.invoice_date, i.id
      ''', [documentId]);
      data['payments'] = await db.query('supplier_payment_reversals',
          where: 'payment_id = ?', whereArgs: [documentId]);
      data['returns'] = <Map<String, Object?>>[];
      data['audit'] = await db.query('audit_logs',
          where: 'entity_type IN (?, ?) AND entity_id = ?',
          whereArgs: ['supplier_payment', 'payment', documentId],
          orderBy: 'created_at, id');
    } else if (documentType == 'purchase_return') {
      final rows = await db.rawQuery('''
        SELECT r.*, s.name AS supplier_name FROM purchase_returns r
        JOIN suppliers s ON s.id = r.supplier_id WHERE r.id = ?
      ''', [documentId]);
      if (rows.isEmpty) throw StateError('المرتجع غير موجود');
      data['header'] = rows.first;
      data['lines'] = await db.query('purchase_return_items',
          where: 'return_id = ?', whereArgs: [documentId]);
      data['payments'] = <Map<String, Object?>>[];
      data['returns'] = <Map<String, Object?>>[];
    } else {
      throw StateError('نوع المستند غير معروف');
    }
    if (documentType != 'payment') {
      final entityType = switch (documentType) {
        'credit_invoice' => 'credit_purchase_invoice',
        'daily_purchase' => 'daily_purchase_operation',
        'purchase_return' => 'purchase_return',
        _ => documentType,
      };
      data['audit'] = await db.query('audit_logs',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: [entityType, documentId], orderBy: 'created_at, id');
    }
    return data;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(documentType == 'payment'
        ? tr(context, 'تفاصيل دفعة المورد', 'Supplier payment details')
        : tr(context, 'تفاصيل المستند', 'Document details'))),
    body: SafeArea(top: false, child: FutureBuilder<Map<String, Object?>>(
      future: _load(ref), builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${tr(context, 'تعذر عرض المستند', 'Could not display document')}: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final header = data['header'] as Map<String, Object?>;
        return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
          if (documentType == 'payment') ...[
            _detailGroup(context,
                tr(context, 'بيانات الدفعة', 'Payment information'), {
              for (final key in const [
                'receipt_number', 'supplier_name', 'payment_date', 'method',
                'amount_minor', 'currency', 'allocated_minor',
                'unallocated_minor', 'historical_allocated_minor', 'notes',
              ]) if (header.containsKey(key)) key: header[key],
              'reversed': (data['payments'] as List).isNotEmpty ? 1 : 0,
            }),
          ] else
            _detailGroup(context,
                tr(context, 'بيانات المستند', 'Document information'), header),
          if (documentType == 'credit_invoice' && header['status'] == 'posted')
            OutlinedButton.icon(
              icon: const Icon(Icons.undo_outlined),
              label: Text(tr(context, 'طلب إلغاء الفاتورة غير المسددة', 'Void unpaid invoice')),
              onPressed: () async {
                var text = '';
                final reason = await showDialog<String>(context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(tr(context, 'تأكيد إلغاء الفاتورة', 'Confirm invoice reversal')),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(tr(context,
                        'يُسمح بعكس الفاتورة التي لا تحمل دفعات أو مرتجعات مرتبطة فقط. يبقى الأصل محفوظاً ويُسجل قيد عكسي في حساب المورد.',
                        'Only invoices without linked payments or returns can be voided. The original remains preserved and a reversal entry is recorded.')),
                      TextField(onChanged: (v) => text = v,
                        decoration: InputDecoration(labelText: tr(context, 'سبب الإلغاء *', 'Reversal reason *'))),
                    ]),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext),
                        child: Text(tr(context, 'رجوع', 'Back'))),
                      FilledButton(onPressed: () {
                        if (text.trim().isNotEmpty) Navigator.pop(dialogContext, text.trim());
                      }, child: Text(tr(context, 'إلغاء وعكس القيد', 'Void and reverse entry'))),
                    ],
                  ),
                );
                if (reason == null || !context.mounted) return;
                try {
                  await ref.read(supplierAccountingRepositoryProvider)
                      .voidUnsettledInvoice(documentId, reason: reason);
                  ref.invalidate(supplierInvoicesProvider(header['supplier_id'] as int));
                  ref.invalidate(supplierDashboardProvider(header['supplier_id'] as int));
                  ref.invalidate(creditInvoicesProvider);
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${tr(context, 'تعذر الإلغاء', 'Could not void invoice')}: $error')));
                  }
                }
              },
            ),
          if (documentType == 'credit_invoice' &&
              header['status'] == 'posted')
            OutlinedButton.icon(
              icon: const Icon(Icons.assignment_return_outlined),
              label: Text(tr(context, 'تصحيح مالي عبر مرتجع مرتبط بالفاتورة', 'Correct with an invoice return')),
              onPressed: () async {
                final supplierId = header['supplier_id'] as int;
                final result = await showDialog<bool>(context: context,
                  builder: (_) => SupplierReturnDialog(
                    supplierId: supplierId, invoiceId: documentId,
                  ),
                );
                if (result == true) {
                  ref.invalidate(supplierDashboardProvider(supplierId));
                  ref.invalidate(supplierInvoicesProvider(supplierId));
                  ref.invalidate(creditInvoicesProvider);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          if (documentType == 'daily_purchase' &&
              header['sheet_id'] is int)
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_note_outlined),
              label: Text(tr(context, 'فتح ورقة اليومية للتصحيح أو الإلغاء المسموح', 'Open daily sheet for allowed correction')),
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => DailyPurchaseSheetScreen(
                    sheetId: header['sheet_id'] as int),
              )),
            ),
          _detailsList(context, documentType == 'payment'
              ? tr(context, 'تخصيصات الدفعة للفواتير', 'Invoice allocations')
              : tr(context, 'الأصناف وتفاصيل التخصيص', 'Items and allocations'),
              data['lines'] as List<Map<String, Object?>>,
              currency: header['currency'] as String?),
          _detailsList(context, tr(context, 'الدفعات والعكس المرتبط', 'Payments and reversals'),
              data['payments'] as List<Map<String, Object?>>,
              currency: header['currency'] as String?),
          _detailsList(context, tr(context, 'المرتجعات', 'Returns'),
              data['returns'] as List<Map<String, Object?>>,
              currency: header['currency'] as String?),
          _detailsList(context, tr(context, 'سجل التدقيق', 'Audit trail'),
              data['audit'] as List<Map<String, Object?>>,
              currency: header['currency'] as String?),
        ]);
      },
    )),
  );
}

class SupplierMovementDetailScreen extends ConsumerWidget {
  const SupplierMovementDetailScreen({super.key, required this.movementId});
  final int movementId;

  Future<Map<String, Object?>> _load(WidgetRef ref) async {
    final db = await ref.read(appDatabaseProvider).database;
    final rows = await db.rawQuery('''
      SELECT m.*, s.name AS supplier_name,
        original.movement_type AS original_movement_type,
        original.source_type AS original_source_type,
        original.source_id AS original_source_id
      FROM supplier_account_movements m
      JOIN suppliers s ON s.id = m.supplier_id
      LEFT JOIN supplier_account_movements original ON original.id = m.reverses_movement_id
      WHERE m.id = ?
    ''', [movementId]);
    if (rows.isEmpty) throw StateError('القيد غير موجود');
    final row = Map<String, Object?>.from(rows.first);
    final balances = await db.rawQuery('''
      SELECT COALESCE(SUM(signed_amount_minor),0) AS balance_minor
      FROM supplier_account_movements
      WHERE supplier_id = ? AND currency = ?
        AND (entry_date < ? OR (entry_date = ? AND id <= ?))
    ''', [row['supplier_id'], row['currency'], row['entry_date'],
      row['entry_date'], row['id']]);
    final after = balances.first['balance_minor'] as int? ?? 0;
    row['balance_after_minor'] = after;
    row['balance_before_minor'] = after - (row['signed_amount_minor'] as int);
    return row;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'تفاصيل حركة الحساب', 'Account entry details'))),
    body: SafeArea(top: false, child: FutureBuilder<Map<String, Object?>>(
      future: _load(ref), builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final movement = snapshot.data!;
        final type = movement['source_type'] as String? ?? '';
        final id = movement['source_id'] as int?;
        final originalType = movement['original_source_type'] as String?;
        final originalId = movement['original_source_id'] as int?;
        final sourceType = ['credit_invoice', 'daily_purchase', 'payment', 'purchase_return'].contains(type)
            ? type : originalType;
        final sourceId = sourceType == type ? id : originalId;
        return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 30), children: [
          _detailGroup(context, tr(context, 'بيانات القيد الأصلي', 'Original ledger entry'), movement),
          if (sourceType != null && sourceId != null &&
              ['credit_invoice', 'daily_purchase', 'payment', 'purchase_return'].contains(sourceType))
            Card(child: ListTile(
              title: Text(tr(context, 'فتح المستند المرتبط', 'Open linked document')),
              subtitle: Text('${_detailValue(context, 'source_type', sourceType)} #$sourceId'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => SupplierDocumentDetailScreen(
                  documentType: sourceType, documentId: sourceId,
                ),
              )),
            )),
        ]);
      },
    )),
  );
}

const _labels = <String, String>{
  'id':'الرقم', 'supplier_id':'رقم المورد', 'supplier_name':'المورد',
  'invoice_number':'رقم الفاتورة', 'invoice_date':'تاريخ الفاتورة',
  'purchase_date':'تاريخ الشراء', 'sheet_number':'رقم الورقة',
  'operation_number':'رقم العملية', 'receipt_number':'رقم الإيصال',
  'amount_minor':'المبلغ', 'total_minor':'الإجمالي',
  'subtotal_minor':'المجموع قبل الخصم والضريبة',
  'line_total_minor':'إجمالي الصنف', 'unit_price_minor':'سعر الوحدة',
  'quantity_milli':'الكمية', 'unit_name':'وحدة القياس',
  'item_name':'الصنف', 'description':'الوصف', 'status':'الحالة',
  'notes':'ملاحظات', 'note':'البيان', 'created_at':'وقت التسجيل',
  'entry_date':'تاريخ القيد', 'payment_date':'تاريخ الدفعة',
  'return_date':'تاريخ المرتجع', 'signed_amount_minor':'الأثر على الرصيد',
  'source_type':'نوع المستند', 'source_id':'رقم المستند',
  'movement_type':'نوع القيد', 'reverses_movement_id':'القيد المعكوس',
  'reason':'السبب', 'currency':'العملة', 'payment_method':'طريقة الدفع',
  'balance_before_minor':'الرصيد قبل القيد',
  'balance_after_minor':'الرصيد بعد القيد',
  'paid_minor':'المبلغ المسدد', 'amount_paid_minor':'المدفوع عند الشراء',
  'method':'وسيلة الدفع', 'branch_name':'الفرع', 'employee_name':'الموظف',
  'branch_id':'رقم الفرع', 'employee_id':'رقم الموظف',
  'payment_id':'رقم الدفعة', 'invoice_id':'رقم الفاتورة المرتبطة',
  'return_number':'رقم المرتجع', 'item_description':'وصف الصنف المرتجع',
  'item_amount_minor':'مبلغ الصنف المرتجع', 'reversed':'هل عُكست الدفعة؟',
  'sheet_id':'رقم اليومية', 'operation_id':'رقم عملية اليومية',
  'responsible_person_id':'رقم حساب الشخص',
  'responsible_person_name':'الشخص المسؤول', 'recording_category':'نوع التسجيل',
  'seller_name':'اسم البائع', 'accounting_mode':'طريقة القيد',
  'original_source_type':'نوع المستند المعكوس',
  'original_source_id':'رقم المستند المعكوس',
  'original_movement_type':'نوع القيد المعكوس',
  'attachment_id':'رقم المرفق', 'updated_at':'وقت التعديل',
  'received_at':'تاريخ الاستلام', 'due_date':'تاريخ الاستحقاق',
  'discount_minor':'الخصم', 'tax_minor':'الضريبة',
  'initial_supplier_payment_id':'رقم الدفعة الأولى',
  'allocated_minor':'المبلغ المخصص للفواتير',
  'historical_allocated_minor':'التخصيصات الأصلية المحفوظة للتدقيق',
  'reversal_date':'تاريخ العكس',
  'unallocated_minor':'الرصيد غير المخصص',
  'invoice_total_minor':'القيمة الأصلية للفاتورة',
  'details_json':'تفاصيل حدث التدقيق',
  'action':'الإجراء', 'entity_type':'نوع السجل', 'entity_id':'رقم السجل',
  'idempotency_key':'مرجع منع التكرار',
  'reference_id':'المرجع', 'adjustment_date':'تاريخ التسوية',
  'advance_minor':'الرصيد المقدم غير المخصص',
  'reversal_id':'رقم عملية العكس',
  'created_by':'منفذ العملية',
};

const _labelsEn = <String, String>{
  'id':'Record number', 'supplier_id':'Supplier number',
  'supplier_name':'Supplier', 'invoice_number':'Invoice number',
  'invoice_date':'Invoice date', 'purchase_date':'Purchase date',
  'sheet_number':'Sheet number', 'operation_number':'Operation number',
  'receipt_number':'Receipt number', 'amount_minor':'Amount',
  'total_minor':'Total', 'subtotal_minor':'Subtotal',
  'line_total_minor':'Line total', 'unit_price_minor':'Unit price',
  'quantity_milli':'Quantity', 'unit_name':'Unit', 'item_name':'Item',
  'description':'Description', 'status':'Status', 'notes':'Notes',
  'note':'Description', 'created_at':'Recorded at', 'updated_at':'Updated at',
  'entry_date':'Entry date', 'payment_date':'Payment date',
  'return_date':'Return date', 'signed_amount_minor':'Balance change',
  'source_type':'Document type', 'source_id':'Document number',
  'movement_type':'Entry type', 'reverses_movement_id':'Reversed entry',
  'reason':'Reason', 'currency':'Currency', 'payment_method':'Payment method',
  'balance_before_minor':'Balance before',
  'balance_after_minor':'Balance after', 'paid_minor':'Paid amount',
  'amount_paid_minor':'Paid at purchase', 'method':'Payment method',
  'branch_name':'Branch', 'employee_name':'Employee',
  'branch_id':'Branch number', 'employee_id':'Employee number',
  'payment_id':'Payment number', 'invoice_id':'Invoice number',
  'return_number':'Return number', 'item_description':'Returned item',
  'item_amount_minor':'Returned amount', 'reversed':'Reversed?',
  'sheet_id':'Daily sheet', 'operation_id':'Daily operation',
  'responsible_person_id':'Responsible person number',
  'responsible_person_name':'Responsible person',
  'recording_category':'Recording category', 'seller_name':'Seller',
  'accounting_mode':'Accounting method', 'original_source_type':'Original document',
  'original_source_id':'Original document number',
  'original_movement_type':'Original entry', 'attachment_id':'Attachment',
  'received_at':'Received at', 'due_date':'Due date',
  'discount_minor':'Discount', 'tax_minor':'Tax',
  'initial_supplier_payment_id':'Initial payment',
  'allocated_minor':'Allocated to invoices',
  'historical_allocated_minor':'Historical allocations (audit)',
  'reversal_date':'Reversal date', 'unallocated_minor':'Unallocated balance',
  'invoice_total_minor':'Original invoice total',
  'details_json':'Audit event details',
  'action':'Action', 'entity_type':'Record type', 'entity_id':'Record number',
  'reference_id':'Reference', 'adjustment_date':'Adjustment date',
  'advance_minor':'Unallocated advance', 'reversal_id':'Reversal number',
  'created_by':'Performed by',
};

String _detailValue(BuildContext context, String key, Object? raw) {
  final value = raw?.toString() ?? '—';
  const translationsAr = <String, String>{
    'posted':'مرحّلة', 'void':'ملغاة', 'draft':'مسودة',
    'open':'مفتوحة', 'partial':'مسددة جزئياً', 'paid':'مسددة',
    'credit_invoice':'فاتورة شراء آجلة', 'daily_purchase':'مشتريات يومية',
    'daily_purchase_edit':'تصحيح مشتريات يومية',
    'daily_purchase_void':'إلغاء مشتريات يومية',
    'credit_invoice_void':'إلغاء فاتورة آجلة',
    'payment':'دفعة', 'purchase_return':'مرتجع مشتريات',
    'supplier_payment_reversal':'عكس دفعة مورد',
    'supplier_payment':'دفعة مورد',
    'allocate_advance':'تخصيص رصيد مقدم',
    'credit_purchase_invoice':'فاتورة مشتريات آجلة',
    'daily_purchase_operation':'عملية مشتريات يومية',
    'daily_purchase_sheet':'ورقة مشتريات يومية',
    'create':'إنشاء', 'update':'تعديل', 'archive':'أرشفة',
    'reverse':'عكس',
    'reversal':'قيد عكسي', 'adjustment':'تسوية',
    'opening_balance':'رصيد افتتاحي',
    'cash':'نقداً', 'bank_transfer':'تحويل بنكي',
    'wallet':'محفظة', 'cheque':'شيك', 'other':'أخرى',
    'daily_outstanding':'مستحق يومي', 'supplier_account':'حساب مورد',
    'person':'حساب شخص', 'independent':'مستقل',
    'supplier':'مورد', 'unspecified':'غير محددة',
  };
  const translationsEn = <String, String>{
    'posted':'Posted', 'void':'Voided', 'draft':'Draft',
    'open':'Open', 'partial':'Partially paid', 'paid':'Paid',
    'credit_invoice':'Credit invoice', 'daily_purchase':'Daily purchase',
    'daily_purchase_edit':'Daily purchase correction',
    'daily_purchase_void':'Daily purchase reversal',
    'credit_invoice_void':'Credit invoice reversal',
    'payment':'Payment', 'purchase_return':'Purchase return',
    'supplier_payment_reversal':'Supplier payment reversal',
    'supplier_payment':'Supplier payment', 'allocate_advance':'Advance allocation',
    'credit_purchase_invoice':'Credit purchase invoice',
    'daily_purchase_operation':'Daily purchase operation',
    'daily_purchase_sheet':'Daily purchase sheet',
    'create':'Created', 'update':'Updated', 'archive':'Archived',
    'reverse':'Reversed', 'reversal':'Reversal',
    'adjustment':'Adjustment', 'opening_balance':'Opening balance',
    'cash':'Cash', 'bank_transfer':'Bank transfer', 'wallet':'Wallet',
    'cheque':'Cheque', 'other':'Other', 'daily_outstanding':'Daily outstanding',
    'supplier_account':'Supplier account', 'person':'Personal account',
    'independent':'Independent', 'supplier':'Supplier',
    'unspecified':'Unspecified',
  };
  final arabic = Localizations.localeOf(context).languageCode == 'ar';
  if (key == 'reversed') {
    return raw == 1 ? (arabic ? 'نعم' : 'Yes') : (arabic ? 'لا' : 'No');
  }
  return (arabic ? translationsAr : translationsEn)[value] ?? value;
}

String _readableDate(BuildContext context, String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final localizations = MaterialLocalizations.of(context);
  if (value.length <= 10) return localizations.formatFullDate(parsed);
  final local = parsed.toLocal();
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '${localizations.formatFullDate(local)} — $time';
}

String _displayAuditDetails(BuildContext context, String raw, String currency) {
  final locale = Localizations.localeOf(context).languageCode;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return raw;
    String formatMap(Map values, {String indent = ''}) {
      return values.entries.map((entry) {
        final key = entry.key.toString();
        final label = locale == 'ar'
            ? (_labels[key] ?? 'حقل غير معروف ($key)')
            : (_labelsEn[key] ?? 'Unknown field ($key)');
        final value = entry.value;
        if (value is Map) {
          return '$indent$label:\n${formatMap(value, indent: '$indent  ')}';
        }
        final rendered = value is int && key.endsWith('_minor')
            ? Money.format(value, currency, locale: locale)
            : (value == null ? '—' : _detailValue(context, key, value));
        return '$indent$label: $rendered';
      }).join('\n');
    }
    return formatMap(decoded);
  } catch (_) {
    return tr(context, 'تفاصيل إضافية محفوظة في سجل التدقيق.',
        'Additional details are preserved in the audit record.');
  }
}

String _formattedField(BuildContext context, String key, Object value,
    String currency) {
  final locale = Localizations.localeOf(context).languageCode;
  if (key == 'details_json' && value is String) {
    return _displayAuditDetails(context, value, currency);
  }
  if (key.endsWith('_minor') && value is int) {
    return Money.format(value, currency, locale: locale);
  }
  if (key == 'quantity_milli' && value is int) {
    return Money.formatQuantity(value);
  }
  if ((key.endsWith('_at') || key.endsWith('_date')) && value is String) {
    return _readableDate(context, value);
  }
  return _detailValue(context, key, value);
}

Widget _detailGroup(BuildContext context, String title,
    Map<String, Object?> row, {String? currency}) {
  final locale = Localizations.localeOf(context).languageCode;
  final effectiveCurrency = row['currency'] as String? ?? currency ?? 'YER';
  const diagnosticFields = {
    'idempotency_key', 'entity_id', 'reference_id', 'attachment_id',
    'source_id', 'original_source_id', 'reverses_movement_id',
  };
  final display = row.entries.where((entry) => entry.value != null &&
      (_labels.containsKey(entry.key) || _labelsEn.containsKey(entry.key)) &&
      !diagnosticFields.contains(entry.key));
  final diagnostics = row.entries.where((entry) => entry.value != null &&
      (diagnosticFields.contains(entry.key) ||
       (!_labels.containsKey(entry.key) && !_labelsEn.containsKey(entry.key))));
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Divider(),
          for (final entry in display)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(locale == 'ar'
                      ? (_labels[entry.key] ?? 'تفاصيل')
                      : (_labelsEn[entry.key] ?? 'Details'),
                    style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  SelectableText(_formattedField(context, entry.key,
                      entry.value!, effectiveCurrency),
                    style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          if (diagnostics.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr(context, 'المراجع التقنية (للتدقيق)',
                  'Technical references (audit)')),
              children: [
                for (final entry in diagnostics)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(locale == 'ar'
                            ? (_labels[entry.key] ?? 'مرجع إضافي')
                            : (_labelsEn[entry.key] ?? 'Additional reference')),
                        SelectableText('${entry.value}',
                            textDirection: TextDirection.ltr),
                      ],
                    ),
                  ),
              ],
            ),
          if (row['details_json'] is String)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr(context, 'البيانات الخام للتدقيق (للمختصين)',
                  'Raw audit record (advanced)')),
              children: [
                SelectableText(row['details_json'] as String,
                    textDirection: TextDirection.ltr),
              ],
            ),
        ],
      ),
    ),
  );
}

Widget _detailsList(BuildContext context, String title,
    List<Map<String, Object?>> rows, {String? currency}) {
  if (rows.isEmpty) return const SizedBox.shrink();
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
    for (final row in rows) _detailGroup(context, title, row,
        currency: currency),
  ]);
}
