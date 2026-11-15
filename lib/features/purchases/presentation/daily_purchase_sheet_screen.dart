import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/reports/csv_export_service.dart';
import '../../../core/reports/report_pdf_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../suppliers/presentation/supplier_dashboard_screen.dart';
import '../domain/daily_sheet_models.dart';
import 'daily_operation_dialog.dart';
import 'daily_sheet_action_dialogs.dart';

class DailyPurchaseSheetScreen extends ConsumerWidget {
  const DailyPurchaseSheetScreen({super.key, required this.sheetId});
  final int sheetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(dailySheetDetailProvider(sheetId));
    return detail.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(error.toString())),
      ),
      data: (sheet) => _DailySheetContent(sheet: sheet),
    );
  }
}

class _DailySheetContent extends ConsumerWidget {
  const _DailySheetContent({required this.sheet});
  final DailySheetDetail sheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = _totals(sheet.operations);
    return Scaffold(
      appBar: AppBar(
        title: Text(sheet.sheetNumber,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr(context, 'مشاركة تقرير PDF', 'Share handover PDF'),
            onPressed: () => _shareReport(context, ref),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: tr(context, 'طباعة التقرير', 'Print report'),
            onPressed: () => _printReport(context, ref),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: tr(context, 'تصدير CSV', 'Export CSV'),
            onPressed: () => _shareCsv(context, ref),
            icon: const Icon(Icons.table_view_outlined),
          ),
        ],
      ),
      floatingActionButton: sheet.isEditable
          ? FloatingActionButton.extended(
              onPressed: () => _addOperation(context, ref),
              icon: const Icon(Icons.add),
              label: Text(tr(context, 'إضافة عملية', 'Add operation')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: ListView(
          padding: EdgeInsets.fromLTRB(13, 10, 13, 150 + MediaQuery.paddingOf(context).bottom),
          children: [
            _sheetHeader(context),
            const SizedBox(height: 10),
            _workflowCard(context, ref),
            const SizedBox(height: 12),
            Text(
              tr(context, 'ملخص الورقة حسب العملة',
                  'Sheet summary by currency'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            if (totals.isEmpty)
              _empty(
                  context,
                  tr(context, 'لم تتم إضافة عمليات شراء بعد.',
                      'No purchase operations have been added.'))
            else
              ...totals.entries
                  .map((entry) => _totalCard(context, entry.key, entry.value)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(context, 'عمليات الشراء', 'Purchase operations'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                Text('${sheet.operations.length}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, color: AppTheme.teal)),
              ],
            ),
            const SizedBox(height: 6),
            if (sheet.operations.isEmpty)
              _empty(
                  context,
                  tr(context, 'ابدأ بإضافة أول عملية شراء إلى هذه الورقة.',
                      'Add the first purchase operation to this sheet.'))
            else
              ...sheet.operations
                  .map((operation) => _operationCard(context, ref, operation)),
            if (sheet.amendmentCount > 0) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history_edu_outlined,
                      color: AppTheme.amber),
                  title: Text(tr(context, 'الملاحق والتصحيحات',
                      'Addenda and corrections')),
                  subtitle: Text('${sheet.amendmentCount}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAmendments(context, ref),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sheetHeader(BuildContext context) {
    final statusColor = _statusColor(context, sheet.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(sheet.sheetNumber,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                ),
                _statusChip(context, sheet.status, statusColor),
              ],
            ),
            const SizedBox(height: 8),
            _headerLine(
                context, Icons.calendar_today_outlined, sheet.purchaseDate),
            if (sheet.branchName != null)
              _headerLine(context, Icons.store_outlined, sheet.branchName!),
            if (sheet.employeeName != null)
              _headerLine(context, Icons.person_outline, sheet.employeeName!),
            if (sheet.notes?.isNotEmpty == true) ...[
              const Divider(height: 17),
              Text(sheet.notes!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (sheet.handedOverAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  '${tr(context, 'وقت التسليم', 'Handed over at')}: ${sheet.handedOverAt}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _workflowCard(BuildContext context, WidgetRef ref) {
    final nextAction = switch (sheet.status) {
      'DRAFT' => (
          tr(context, 'تجهيز تقرير تسليم الحسابات', 'Prepare handover report'),
          'READY_FOR_HANDOVER',
          Icons.fact_check_outlined,
        ),
      'READY_FOR_HANDOVER' => (
          tr(context, 'تأكيد تسليم التقرير للحسابات',
              'Confirm handover to accounting'),
          'HANDED_OVER',
          Icons.outbox_outlined,
        ),
      'HANDED_OVER' => (
          tr(context, 'إغلاق ورقة اليوم', 'Close daily sheet'),
          'CLOSED',
          Icons.lock_outline,
        ),
      _ => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(context, 'حالة سير العمل', 'Workflow status'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Row(
              children: [
                _workflowStep(context, 'DRAFT', tr(context, 'مسودة', 'Draft')),
                _stepLine(context),
                _workflowStep(context, 'READY_FOR_HANDOVER',
                    tr(context, 'جاهزة', 'Ready')),
                _stepLine(context),
                _workflowStep(context, 'HANDED_OVER',
                    tr(context, 'تم التسليم', 'Handed over')),
                _stepLine(context),
                _workflowStep(
                    context, 'CLOSED', tr(context, 'مغلقة', 'Closed')),
              ],
            ),
            if (nextAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _changeStatus(context, ref, nextAction.$2),
                icon: Icon(nextAction.$3),
                label: Text(nextAction.$1),
              ),
            ],
            if (sheet.status == 'HANDED_OVER' || sheet.status == 'CLOSED') ...[
              const SizedBox(height: 7),
              OutlinedButton.icon(
                onPressed: () => _addAmendment(context, ref),
                icon: const Icon(Icons.note_add_outlined),
                label: Text(tr(context, 'إضافة ملحق تصحيحي دون تعديل الأصل',
                    'Add correction addendum without changing original')),
              ),
            ],
            if (sheet.status == 'READY_FOR_HANDOVER')
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  tr(
                      context,
                      'تم تجميد الورقة. راجع التقرير قبل تأكيد التسليم.',
                      'The sheet is locked. Review the report before confirming handover.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _showEvents(context, ref),
              icon: const Icon(Icons.history, size: 17),
              label: Text(tr(context, 'عرض سجل التغييرات', 'View change log')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workflowStep(BuildContext context, String status, String label) {
    final order = const [
      'DRAFT',
      'READY_FOR_HANDOVER',
      'HANDED_OVER',
      'CLOSED'
    ];
    final activeIndex = order.indexOf(sheet.status);
    final index = order.indexOf(status);
    final active = index <= activeIndex;
    final color =
        active ? AppTheme.teal : Theme.of(context).colorScheme.outline;
    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: .16),
            child: Icon(
              active ? Icons.check : Icons.circle_outlined,
              size: 13,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: active ? FontWeight.w800 : FontWeight.normal,
              )),
        ],
      ),
    );
  }

  Widget _stepLine(BuildContext context) => Container(
        width: 13,
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
        margin: const EdgeInsets.only(bottom: 17),
      );

  Widget _totalCard(
      BuildContext context, String currency, _CurrencyTotals total) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(currency, style: const TextStyle(fontWeight: FontWeight.w900)),
            _moneyLine(
                context,
                tr(context, 'إجمالي المشتريات', 'Total purchases'),
                total.total,
                currency),
            _moneyLine(
                context,
                tr(context, 'المدفوع عند الشراء', 'Paid at purchase'),
                total.cash,
                currency),
            _moneyLine(
                context,
                tr(context, 'المشتريات الآجلة', 'Credit portion'),
                total.credit,
                currency),
            _moneyLine(context, tr(context, 'المدفوع لاحقاً', 'Paid later'),
                total.laterPaid, currency),
            _moneyLine(
                context,
                tr(context, 'المستحق اليومي المتبقي',
                    'Daily outstanding remaining'),
                total.outstanding,
                currency,
                color: AppTheme.amber,
                strong: true),
            _moneyLine(
                context,
                tr(context, 'المسجل بحساب المورد',
                    'Posted to supplier account'),
                total.supplierAccount,
                currency),
          ],
        ),
      ),
    );
  }

  Widget _operationCard(
    BuildContext context,
    WidgetRef ref,
    DailyPurchaseOperation operation,
  ) {
    final dailyOutstanding = operation.outstandingMinor;
    final supplierCredit = operation.supplierAccountCreditMinor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(operation.operationNumber,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15)),
                ),
                _statusChip(
                  context,
                  operation.recordingCategory == 'cash' ? 'cash' :
                  operation.recordingCategory == 'person' ? 'person' :
                  operation.isSupplierAccount ? 'supplier_account' : 'daily_outstanding',
                  operation.recordingCategory == 'cash' ? AppTheme.emerald :
                  operation.isSupplierAccount ? AppTheme.teal : AppTheme.amber,
                ),
                if (sheet.isEditable)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit')
                        _editOperation(context, ref, operation);
                      if (value == 'void')
                        _voidOperation(context, ref, operation);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'edit',
                          child:
                              Text(tr(context, 'تعديل الأصناف', 'Edit items'))),
                      PopupMenuItem(
                          value: 'void',
                          child: Text(
                              tr(context, 'إلغاء العملية', 'Void operation'))),
                    ],
                  ),
              ],
            ),
            if (operation.responsiblePersonName != null)
              Text('على حساب: ${operation.responsiblePersonName}',
                style: Theme.of(context).textTheme.bodySmall),
            if (operation.supplierName != null || operation.sellerName != null)
              Text(
                operation.supplierName ?? operation.sellerName!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const Divider(height: 16),
            ...operation.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.itemName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text(
                              '${Money.formatQuantity(item.quantityMilli)} ${item.unitName} × ${Money.format(item.unitPriceMinor, operation.currency, locale: Localizations.localeOf(context).languageCode)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (item.sellerName?.isNotEmpty == true)
                              Text(
                                  '${tr(context, 'البائع', 'Seller')}: ${item.sellerName}',
                                  style:
                                      Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      ),
                      Text(
                        Money.format(item.lineTotalMinor, operation.currency,
                            locale:
                                Localizations.localeOf(context).languageCode),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                )),
            const Divider(height: 16),
            _moneyLine(
                context,
                tr(context, 'إجمالي العملية', 'Operation total'),
                operation.totalMinor,
                operation.currency,
                strong: true),
            _moneyLine(
                context,
                tr(context, 'المدفوع عند الشراء', 'Paid at purchase'),
                operation.amountPaidMinor,
                operation.currency),
            if (operation.laterPaidMinor > 0)
              _moneyLine(
                  context,
                  tr(context, 'الدفعات اللاحقة', 'Later payments'),
                  operation.laterPaidMinor,
                  operation.currency),
            if (dailyOutstanding > 0)
              _moneyLine(
                  context,
                  tr(context, 'المتبقي في المستحقات اليومية',
                      'Daily outstanding remaining'),
                  dailyOutstanding,
                  operation.currency,
                  color: AppTheme.amber,
                  strong: true),
            if (supplierCredit > 0)
              _moneyLine(
                  context,
                  tr(context, 'المتبقي ضمن حساب المورد',
                      'Remaining in supplier account'),
                  supplierCredit,
                  operation.currency,
                  color: AppTheme.teal,
                  strong: true),
            if (operation.dueDate != null)
              _moneyLine(context, tr(context, 'تاريخ الاستحقاق', 'Due date'),
                  null, operation.dueDate!),
            if (operation.isSupplierAccount && operation.supplierId != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SupplierDashboardScreen(
                        supplierId: operation.supplierId!),
                  )),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                      tr(context, 'فتح حساب المورد', 'Open supplier account')),
                ),
              ),
            if (!operation.isSupplierAccount && operation.outstandingId != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () =>
                      _showOutstandingHistory(context, ref, operation),
                  icon: const Icon(Icons.history, size: 16),
                  label: Text(tr(context, 'سجل الدفعات والتسويات',
                      'Payment/adjustment history')),
                ),
              ),
            if (!operation.isSupplierAccount &&
                operation.outstandingId != null &&
                dailyOutstanding > 0)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        _recordDailyPayment(context, ref, operation),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: Text(tr(context, 'تسجيل دفعة', 'Record payment')),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _adjustDailyOutstanding(context, ref, operation),
                    icon: const Icon(Icons.tune, size: 16),
                    label: Text(
                        tr(context, 'مرتجع / تسوية', 'Return / adjustment')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _moneyLine(
    BuildContext context,
    String label,
    int? amount,
    String currency, {
    bool strong = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: strong
                    ? const TextStyle(fontWeight: FontWeight.w800)
                    : Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            amount == null
                ? currency
                : Money.format(amount, currency,
                    locale: Localizations.localeOf(context).languageCode),
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerLine(BuildContext context, IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.teal),
          const SizedBox(width: 6),
          Expanded(
              child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status, Color color) {
    final label = switch (status) {
      'supplier_account' => tr(context, 'حساب مورد', 'Supplier account'),
      'cash' => tr(context, 'نقدي', 'Cash'),
      'person' => tr(context, 'على حساب شخص', 'Personal liability'),
      'daily_outstanding' => tr(context, 'مستحق يومي', 'Daily outstanding'),
      'DRAFT' => tr(context, 'مسودة', 'Draft'),
      'READY_FOR_HANDOVER' => tr(context, 'جاهزة للتسليم', 'Ready'),
      'HANDED_OVER' => tr(context, 'تم التسليم', 'Handed over'),
      'CLOSED' => tr(context, 'مغلقة', 'Closed'),
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _empty(BuildContext context, String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  Map<String, _CurrencyTotals> _totals(
      List<DailyPurchaseOperation> operations) {
    final result = <String, _CurrencyTotals>{};
    for (final operation in operations) {
      final current =
          result.putIfAbsent(operation.currency, _CurrencyTotals.new);
      current.total += operation.totalMinor;
      current.cash += operation.amountPaidMinor;
      current.credit +=
          math.max(0, operation.totalMinor - operation.amountPaidMinor);
      current.laterPaid += operation.laterPaidMinor;
      current.outstanding += operation.outstandingMinor;
      current.supplierAccount += operation.supplierAccountCreditMinor;
    }
    return result;
  }

  Color _statusColor(BuildContext context, String status) => switch (status) {
        'DRAFT' => AppTheme.teal,
        'READY_FOR_HANDOVER' => AppTheme.amber,
        'HANDED_OVER' => AppTheme.emerald,
        'CLOSED' => Theme.of(context).colorScheme.onSurfaceVariant,
        _ => AppTheme.teal,
      };

  Future<void> _addOperation(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DailyOperationDialog(sheetId: sheet.id),
    );
    if (result == true) _refresh(ref);
  }

  Future<void> _editOperation(
    BuildContext context,
    WidgetRef ref,
    DailyPurchaseOperation operation,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) =>
          DailyOperationDialog(sheetId: sheet.id, operation: operation),
    );
    if (result == true) _refresh(ref);
  }

  Future<void> _voidOperation(
    BuildContext context,
    WidgetRef ref,
    DailyPurchaseOperation operation,
  ) async {
    var reasonInput = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('إلغاء عملية شراء'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('سيتم عكس أثر العملية على حساب المورد إن كانت آجلة، '
            'مع الاحتفاظ بأصل المستند وأثر الإلغاء. قيمة العملية: '
            '${Money.format(operation.totalMinor, operation.currency)}'),
          const SizedBox(height: 8),
          TextField(
            maxLines: 2,
            onChanged: (value) => reasonInput = value,
            decoration: const InputDecoration(labelText: 'سبب الإلغاء *'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonInput.trim().isEmpty) return;
              Navigator.pop(dialogContext, reasonInput.trim());
            },
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(dailyPurchasesRepositoryProvider).voidOperation(
            operation.id, reason: reason);
      _refresh(ref);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _showOutstandingHistory(
    BuildContext context,
    WidgetRef ref,
    DailyPurchaseOperation operation,
  ) async {
    final entries = await ref
        .read(dailyPurchasesRepositoryProvider)
        .getOutstandingHistory(operation.outstandingId!);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            tr(context, 'سجل المستحق اليومي', 'Daily outstanding history')),
        content: SizedBox(
          width: 520,
          child: entries.isEmpty
              ? Text(tr(context, 'لا توجد دفعات أو تسويات.',
                  'No payments or adjustments.'))
              : ListView(
                  shrinkWrap: true,
                  children: entries
                      .map((entry) => ListTile(
                            leading: Icon(
                              entry.entryType == 'payment'
                                  ? Icons.payments_outlined
                                  : Icons.tune,
                              color: entry.entryType == 'payment'
                                  ? AppTheme.emerald
                                  : AppTheme.amber,
                            ),
                            title: Text(switch (entry.entryType) {
                              'payment' => tr(context, 'دفعة', 'Payment'),
                              'return' => tr(context, 'مرتجع', 'Return'),
                              'adjustment' =>
                                tr(context, 'تسوية', 'Adjustment'),
                              _ => entry.entryType,
                            }),
                            subtitle: Text([
                              entry.entryDate,
                              if (entry.method != null) entry.method!,
                              if (entry.reference != null) entry.reference!,
                              if (entry.reason != null) entry.reason!,
                            ].join(' • ')),
                            trailing: Text(
                              Money.format(
                                  entry.amountMinor.abs(), operation.currency),
                              style: TextStyle(
                                color: entry.amountMinor < 0
                                    ? AppTheme.amber
                                    : AppTheme.emerald,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr(context, 'إغلاق', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _recordDailyPayment(
    BuildContext context,
    WidgetRef ref,
    DailyPurchaseOperation operation,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DailyOutstandingPaymentDialog(
        outstandingId: operation.outstandingId!,
        currency: operation.currency,
      ),
    );
    if (result == true) _refresh(ref);
  }

  Future<void> _adjustDailyOutstanding(
    BuildContext context,
    WidgetRef ref,
    DailyPurchaseOperation operation,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DailyOutstandingAdjustmentDialog(
        outstandingId: operation.outstandingId!,
        currency: operation.currency,
      ),
    );
    if (result == true) _refresh(ref);
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    String targetStatus,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            tr(context, 'تأكيد تغيير حالة الورقة', 'Confirm sheet status')),
        content: Text(_statusConfirmation(context, targetStatus)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr(context, 'إلغاء', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr(context, 'تأكيد', 'Confirm'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref
          .read(dailyPurchasesRepositoryProvider)
          .transitionSheetStatus(sheet.id, targetStatus);
      _refresh(ref);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  String _statusConfirmation(BuildContext context, String target) {
    switch (target) {
      case 'READY_FOR_HANDOVER':
        return tr(
            context,
            'سيتم تجميد الورقة ومنع تعديل عملياتها. هل تريد تجهيزها للتسليم؟',
            'The sheet will be locked against edits. Prepare it for handover?');
      case 'HANDED_OVER':
        return tr(
            context,
            'سيتم حفظ لقطة ثابتة للبيانات والتقرير كما تم تسليمه للحسابات. هل تؤكد التسليم؟',
            'A fixed snapshot of the report will be saved. Confirm handover?');
      case 'CLOSED':
        return tr(context, 'سيتم إغلاق الورقة نهائياً. هل تريد المتابعة؟',
            'The sheet will be closed. Continue?');
      default:
        return '';
    }
  }

  Future<void> _addAmendment(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DailySheetAmendmentDialog(sheetId: sheet.id),
    );
    if (result == true) _refresh(ref);
  }

  Future<void> _showEvents(BuildContext context, WidgetRef ref) async {
    final events =
        await ref.read(dailyPurchasesRepositoryProvider).getEvents(sheet.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'سجل تغييرات الورقة', 'Sheet change log')),
        content: SizedBox(
          width: 560,
          child: events.isEmpty
              ? Text(
                  tr(context, 'لا توجد تغييرات مسجلة.', 'No events recorded.'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return ExpansionTile(
                      leading: const Icon(Icons.history, color: AppTheme.teal),
                      title: Text(_eventLabel(context, event.eventType),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text([
                        _friendlyDate(event.createdAt),
                        if (event.fromStatus != null || event.toStatus != null)
                          '${_friendlyStatus(event.fromStatus)} → ${_friendlyStatus(event.toStatus)}',
                      ].join(' • ')),
                      children: [
                        if (event.detailsJson != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: SelectableText(
                                _friendlyEventDetails(event.detailsJson!),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr(context, 'إغلاق', 'Close')),
          ),
        ],
      ),
    );
  }

  String _friendlyDate(String original) {
    final value = DateTime.tryParse(original);
    if (value == null) return original;
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  }

  String _friendlyStatus(String? status) => switch (status) {
    'DRAFT' => 'مسودة',
    'READY_FOR_HANDOVER' => 'جاهزة للتسليم',
    'HANDED_OVER' => 'تم التسليم',
    'CLOSED' => 'مغلقة',
    'posted' => 'مرحّلة',
    'void' => 'ملغاة',
    'paid' => 'مسددة',
    'partial' => 'مسددة جزئياً',
    'open' => 'مفتوحة',
    null => '—',
    _ => status,
  };

  String _friendlyEventDetails(String raw) {
    const labels = <String, String>{
      'sheet_number': 'رقم الورقة', 'operation_id': 'رقم العملية',
      'operation_number': 'مرجع العملية', 'accounting_mode': 'طريقة المحاسبة',
      'recording_category': 'نوع الشراء', 'responsible_person_name': 'صاحب الحساب',
      'total_minor': 'إجمالي العملية', 'paid_minor': 'المبلغ المدفوع',
      'old_total_minor': 'الإجمالي السابق', 'new_total_minor': 'الإجمالي الجديد',
      'old_payment_method': 'وسيلة الدفع السابقة',
      'new_payment_method': 'وسيلة الدفع الجديدة',
      'reason': 'السبب', 'amount_minor': 'المبلغ', 'amount_delta_minor': 'الفرق',
      'outstanding_id': 'رقم المستحق', 'status': 'الحالة',
      'from_status': 'الحالة السابقة', 'to_status': 'الحالة الجديدة',
      'responsible_person_id': 'معرّف حساب الشخص',
      'payment_date': 'تاريخ الدفع', 'changed_at': 'وقت التغيير',
      'adjustment_id': 'رقم التسوية', 'adjustment_type': 'نوع التسوية',
      'signed_delta_minor': 'التغير في المستحق',
      'amendment_id': 'رقم الملحق', 'amendment_number': 'مرجع الملحق',
      'currency': 'العملة', 'payment_method': 'وسيلة الدفع',
    };
    const values = <String, String>{
      'daily_outstanding':'مستحق يومي', 'supplier_account':'حساب مورد',
      'cash':'نقدي', 'supplier':'مورد', 'independent':'مستقل',
      'person':'حساب شخص', 'bank_transfer':'تحويل بنكي',
      'wallet':'محفظة', 'cheque':'شيك', 'unspecified':'غير محدد',
      'return':'مرتجع', 'adjustment':'تسوية', 'write_off':'شطب معتمد',
      'correction':'تصحيح', 'other':'أخرى',
    };
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return 'تفاصيل الحدث محفوظة في السجل الأصلي.';
      var extraIndex = 0;
      return decoded.entries.map((entry) {
        final key = entry.key.toString();
        final value = entry.value;
        if (!labels.containsKey(key)) extraIndex++;
        final readable = values['$value'] ??
            (key.endsWith('_status') || key == 'status'
                ? _friendlyStatus('$value') : '$value');
        final display = key.endsWith('_minor') && value is int
            ? Money.format(value, '', locale: 'ar').trim() : readable;
        return '${labels[key] ?? 'بيان إضافي $extraIndex'}: $display';
      }).join('\n');
    } catch (_) {
      return 'تعذر تنسيق تفاصيل هذا الحدث، ويبقى سجله الأصلي محفوظاً.';
    }
  }

  String _eventLabel(BuildContext context, String type) {
    switch (type) {
      case 'created':
        return tr(context, 'إنشاء الورقة', 'Sheet created');
      case 'operation_created':
        return tr(context, 'إضافة عملية شراء', 'Purchase operation added');
      case 'operation_items_updated':
        return tr(context, 'تعديل أصناف العملية', 'Operation items updated');
      case 'operation_voided':
        return tr(context, 'إلغاء عملية', 'Operation voided');
      case 'outstanding_payment_recorded':
        return tr(
            context, 'تسجيل دفعة مستحق يومي', 'Daily outstanding payment');
      case 'outstanding_adjustment_recorded':
        return tr(context, 'مرتجع أو تسوية مستحق يومي',
            'Daily outstanding return/adjustment');
      case 'status_changed':
        return tr(context, 'تغيير حالة الورقة', 'Sheet status changed');
      case 'amendment_created':
        return tr(context, 'إضافة ملحق تصحيحي', 'Correction addendum added');
      default:
        return tr(context, 'تغيير آخر في الورقة', 'Other sheet event');
    }
  }

  Future<void> _showAmendments(BuildContext context, WidgetRef ref) async {
    final amendments = await ref
        .read(dailyPurchasesRepositoryProvider)
        .getAmendments(sheet.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(tr(context, 'الملاحق والتصحيحات', 'Addenda and corrections')),
        content: SizedBox(
          width: 520,
          child: amendments.isEmpty
              ? Text(tr(context, 'لا توجد ملاحق.', 'No addenda.'))
              : ListView(
                  shrinkWrap: true,
                  children: amendments
                      .map((item) => ListTile(
                            title: Text(
                                '${item.amendmentNumber} • ${item.reason}'),
                            subtitle:
                                Text('${item.details}\n${item.createdAt}'),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr(context, 'إغلاق', 'Close'))),
        ],
      ),
    );
  }

  Future<void> _shareCsv(BuildContext context, WidgetRef ref) async {
    try {
      final report = await ref
          .read(dailyPurchasesRepositoryProvider)
          .getHandoverReport(sheet.id);
      if (!context.mounted) return;
      await CsvExportService.shareDailyHandover(report);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _shareReport(BuildContext context, WidgetRef ref) async {
    try {
      final report = await ref
          .read(dailyPurchasesRepositoryProvider)
          .getHandoverReport(sheet.id);
      if (!context.mounted) return;
      await ReportPdfService.shareDailyHandoverReport(report);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _printReport(BuildContext context, WidgetRef ref) async {
    try {
      final report = await ref
          .read(dailyPurchasesRepositoryProvider)
          .getHandoverReport(sheet.id);
      if (!context.mounted) return;
      await ReportPdfService.printDailyHandoverReport(report);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '${tr(context, 'تعذر تنفيذ العملية', 'Operation failed')}: $error')),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(dailySheetDetailProvider(sheet.id));
    ref.invalidate(dailySheetsProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(suppliersProvider);
    ref.invalidate(supplierDashboardProvider);
  }
}

class _CurrencyTotals {
  int total = 0;
  int cash = 0;
  int credit = 0;
  int laterPaid = 0;
  int outstanding = 0;
  int supplierAccount = 0;
}
