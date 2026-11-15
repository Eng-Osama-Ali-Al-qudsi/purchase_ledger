import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
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
    appBar: AppBar(title: const Text('سجل البضائع المستلمة')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _load(ref),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل المشتريات: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty) return const Center(child: Text('لا توجد عمليات شراء مسجلة'));
        String? lastDate;
        final children = <Widget>[];
        for (final row in items) {
          final date = row['purchase_date'] as String? ?? 'غير مؤرخ';
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
            title: Text('${invoice ? 'فاتورة آجلة' : 'شراء يومي'} • ${row['document_number']}'),
            subtitle: Text('${_detailValue('status', row['status'])} • ${Money.format(total, currency, locale: 'ar')}'),
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
    ),
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
        SELECT p.*, s.name AS supplier_name FROM supplier_payments p
        JOIN suppliers s ON s.id = p.supplier_id WHERE p.id = ?
      ''', [documentId]);
      if (rows.isEmpty) throw StateError('الدفعة غير موجودة');
      data['header'] = rows.first;
      data['lines'] = await db.query('payment_allocations',
          where: 'payment_id = ?', whereArgs: [documentId]);
      data['payments'] = await db.query('supplier_payment_reversals',
          where: 'payment_id = ?', whereArgs: [documentId]);
      data['returns'] = <Map<String, Object?>>[];
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
    return data;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('تفاصيل المستند الأصلي')),
    body: FutureBuilder<Map<String, Object?>>(
      future: _load(ref), builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('تعذر عرض المستند: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final header = data['header'] as Map<String, Object?>;
        return ListView(padding: const EdgeInsets.all(12), children: [
          _detailGroup(context, 'بيانات المستند', header),
          if (documentType == 'credit_invoice' && header['status'] == 'posted')
            OutlinedButton.icon(
              icon: const Icon(Icons.undo_outlined),
              label: const Text('طلب إلغاء الفاتورة غير المسددة'),
              onPressed: () async {
                var text = '';
                final reason = await showDialog<String>(context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('تأكيد إلغاء الفاتورة'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('يُسمح بعكس الفاتورة التي لا تحمل دفعات أو مرتجعات مرتبطة فقط. '
                        'يبقى الأصل محفوظاً ويُسجل قيد عكسي في حساب المورد.'),
                      TextField(onChanged: (v) => text = v,
                        decoration: const InputDecoration(labelText: 'سبب الإلغاء *')),
                    ]),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('رجوع')),
                      FilledButton(onPressed: () {
                        if (text.trim().isNotEmpty) Navigator.pop(dialogContext, text.trim());
                      }, child: const Text('إلغاء وعكس القيد')),
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
                      SnackBar(content: Text('تعذر الإلغاء: $error')));
                  }
                }
              },
            ),
          if (documentType == 'credit_invoice' &&
              header['status'] == 'posted')
            OutlinedButton.icon(
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('تصحيح مالي عبر مرتجع مرتبط بالفاتورة'),
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
              label: const Text('فتح ورقة اليومية للتصحيح أو الإلغاء المسموح'),
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => DailyPurchaseSheetScreen(
                    sheetId: header['sheet_id'] as int),
              )),
            ),
          _detailsList(context, 'الأصناف أو تفاصيل التخصيص', data['lines'] as List<Map<String, Object?>>),
          _detailsList(context, 'الدفعات والعكس المرتبط', data['payments'] as List<Map<String, Object?>>),
          _detailsList(context, 'المرتجعات', data['returns'] as List<Map<String, Object?>>),
        ]);
      },
    ),
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
    appBar: AppBar(title: const Text('تفاصيل حركة الحساب')),
    body: FutureBuilder<Map<String, Object?>>(
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
        return ListView(padding: const EdgeInsets.all(12), children: [
          _detailGroup(context, 'بيانات القيد الأصلي', movement),
          if (sourceType != null && sourceId != null &&
              ['credit_invoice', 'daily_purchase', 'payment', 'purchase_return'].contains(sourceType))
            Card(child: ListTile(
              title: const Text('فتح المستند المرتبط'),
              subtitle: Text('${_detailValue('source_type', sourceType)} #$sourceId'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(
                builder: (_) => SupplierDocumentDetailScreen(
                  documentType: sourceType, documentId: sourceId,
                ),
              )),
            )),
        ]);
      },
    ),
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
  'idempotency_key':'مرجع منع التكرار',
  'reference_id':'المرجع', 'adjustment_date':'تاريخ التسوية',
};

String _detailValue(String key, Object? raw) {
  final value = raw?.toString() ?? '—';
  const translations = <String, String>{
    'posted':'مرحّلة', 'void':'ملغاة', 'draft':'مسودة',
    'open':'مفتوحة', 'partial':'مسددة جزئياً', 'paid':'مسددة',
    'credit_invoice':'فاتورة شراء آجلة', 'daily_purchase':'مشتريات يومية',
    'daily_purchase_edit':'تصحيح مشتريات يومية',
    'daily_purchase_void':'إلغاء مشتريات يومية',
    'credit_invoice_void':'إلغاء فاتورة آجلة',
    'payment':'دفعة', 'purchase_return':'مرتجع مشتريات',
    'supplier_payment_reversal':'عكس دفعة مورد',
    'reversal':'قيد عكسي', 'adjustment':'تسوية',
    'opening_balance':'رصيد افتتاحي',
    'cash':'نقداً', 'bank_transfer':'تحويل بنكي',
    'wallet':'محفظة', 'cheque':'شيك', 'other':'أخرى',
    'daily_outstanding':'مستحق يومي', 'supplier_account':'حساب مورد',
    'person':'حساب شخص', 'independent':'مستقل',
    'supplier':'مورد', 'unspecified':'غير محددة',
  };
  if (key == 'reversed') return raw == 1 ? 'نعم' : 'لا';
  return translations[value] ?? value;
}

Widget _detailGroup(BuildContext context, String title, Map<String, Object?> row) =>
    Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Divider(),
        ...row.entries.where((e) => e.value != null).map((e) {
          final key = e.key;
          var value = '${e.value}';
          if (key.endsWith('_minor') && e.value is int) {
            value = Money.format(e.value as int, row['currency'] as String? ?? 'YER', locale:'ar');
          } else if (key == 'quantity_milli' && e.value is int) {
            value = Money.formatQuantity(e.value as int);
          } else {
            value = _detailValue(key, e.value);
          }
          return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: Text(_labels[key] ?? 'بيان إضافي',
                  style: Theme.of(context).textTheme.bodySmall)),
              Expanded(flex: 3, child: SelectableText(value)),
            ]),
          );
        }),
      ],
    )));

Widget _detailsList(BuildContext context, String title, List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return const SizedBox.shrink();
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: const EdgeInsets.fromLTRB(8,12,8,4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
    for (final row in rows) _detailGroup(context, title, row),
  ]);
}
