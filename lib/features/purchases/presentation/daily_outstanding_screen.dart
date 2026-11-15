import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../domain/daily_sheet_models.dart';
import 'daily_purchase_sheet_screen.dart';
import 'daily_sheet_action_dialogs.dart';

class DailyOutstandingScreen extends ConsumerStatefulWidget {
  const DailyOutstandingScreen({super.key, this.initialPersonId});

  final int? initialPersonId;

  @override
  ConsumerState<DailyOutstandingScreen> createState() =>
      _DailyOutstandingScreenState();
}

class _DailyOutstandingScreenState
    extends ConsumerState<DailyOutstandingScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  int? _branchId;
  int? _employeeId;
  int? _personId;
  bool _includeSettled = false;
  late Future<List<DailyOutstandingRecord>> _future;
  late Future<List<Map<String, Object?>>> _peopleFuture;

  @override
  void initState() {
    super.initState();
    _personId = widget.initialPersonId;
    _includeSettled = _personId != null;
    _peopleFuture = ref.read(dailyPurchasesRepositoryProvider)
        .getResponsiblePeople();
    _future = _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<List<DailyOutstandingRecord>> _load() {
    return ref.read(dailyPurchasesRepositoryProvider).getOutstandingRecords(
          dateFrom: _from.text.trim().isEmpty ? null : _from.text.trim(),
          dateTo: _to.text.trim().isEmpty ? null : _to.text.trim(),
          branchId: _branchId,
          employeeId: _employeeId,
          responsiblePersonId: _personId,
          includeSettled: _includeSettled,
        );
  }

  void _refresh() {
    setState(() => _future = _load());
    ref.invalidate(dailyOutstandingRecordsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);
    final employees = ref.watch(employeesProvider(_branchId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
            tr(context, 'سجل المستحقات اليومية', 'Daily outstanding ledger')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: _dateField(
                                _from, tr(context, 'من تاريخ', 'From date'))),
                        const SizedBox(width: 7),
                        Expanded(
                            child: _dateField(
                                _to, tr(context, 'إلى تاريخ', 'To date'))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: branches.when(
                            loading: () => const LinearProgressIndicator(),
                            error: (error, stack) => const SizedBox.shrink(),
                            data: (items) => DropdownButtonFormField<int?>(
                              initialValue: _branchId,
                              decoration: InputDecoration(
                                  labelText: tr(context, 'الفرع', 'Branch'),
                                  isDense: true),
                              items: [
                                DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(tr(
                                        context, 'كل الفروع', 'All branches'))),
                                ...items.map((item) => DropdownMenuItem<int?>(
                                      value: item['id'] as int,
                                      child: Text(item['name'] as String,
                                          overflow: TextOverflow.ellipsis),
                                    )),
                              ],
                              onChanged: (value) => setState(() {
                                _branchId = value;
                                _employeeId = null;
                                _future = _load();
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: employees.when(
                            loading: () => const LinearProgressIndicator(),
                            error: (error, stack) => const SizedBox.shrink(),
                            data: (items) => DropdownButtonFormField<int?>(
                              initialValue: _employeeId,
                              decoration: InputDecoration(
                                  labelText: tr(context, 'المسؤول', 'Officer'),
                                  isDense: true),
                              items: [
                                DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(tr(context, 'الكل', 'All'))),
                                ...items.map((item) => DropdownMenuItem<int?>(
                                      value: item['id'] as int,
                                      child: Text(item['name'] as String,
                                          overflow: TextOverflow.ellipsis),
                                    )),
                              ],
                              onChanged: (value) => setState(() {
                                _employeeId = value;
                                _future = _load();
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: _peopleFuture,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return snapshot.hasError
                              ? Text('تعذر تحميل حسابات الأشخاص: ${snapshot.error}')
                              : const LinearProgressIndicator();
                        }
                        return DropdownButtonFormField<int?>(
                          key: ValueKey('outstanding-person-$_personId'),
                          initialValue: _personId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'تصفية حسب حساب شخص'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('جميع الحسابات والمستحقات'),
                            ),
                            ...snapshot.data!.map((person) =>
                              DropdownMenuItem<int?>(
                                value: person['id'] as int,
                                child: Text('${person['name']}',
                                    overflow: TextOverflow.ellipsis),
                              )),
                          ],
                          onChanged: (value) => setState(() {
                            _personId = value;
                            if (value != null) _includeSettled = true;
                            _future = _load();
                          }),
                        );
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(tr(context, 'إظهار المسدد أيضاً',
                          'Include settled')),
                      value: _includeSettled,
                      onChanged: (value) => setState(() {
                        _includeSettled = value;
                        _future = _load();
                      }),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () {
                            _from.clear();
                            _to.clear();
                            _branchId = null;
                            _employeeId = null;
                            _personId = null;
                            _includeSettled = false;
                            _refresh();
                          },
                          child: Text(tr(context, 'مسح', 'Clear')),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.filter_alt_outlined, size: 17),
                          label: Text(tr(context, 'تطبيق', 'Apply')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<DailyOutstandingRecord>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }
                final records =
                    snapshot.data ?? const <DailyOutstandingRecord>[];
                if (records.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      children: [
                        const SizedBox(height: 90),
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 50),
                        const SizedBox(height: 8),
                        Text(
                          tr(context, 'لا توجد مستحقات يومية مطابقة للفلاتر.',
                              'No daily outstanding records match these filters.'),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
                    itemCount: records.length + (_personId == null ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (_personId != null && index == 0) {
                        return _personBalanceSummary(records);
                      }
                      return _recordCard(records[index -
                          (_personId == null ? 0 : 1)]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: const Icon(Icons.calendar_month_outlined, size: 18),
      ),
      onTap: () async {
        final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null && mounted) {
          controller.text =
              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
    );
  }

  Widget _personBalanceSummary(List<DailyOutstandingRecord> records) {
    final totals = <String, List<int>>{};
    for (final record in records) {
      final sum = totals.putIfAbsent(record.currency, () => [0, 0, 0, 0]);
      sum[0] += record.originalMinor;
      sum[1] += record.paidMinor;
      sum[2] += record.adjustmentDeltaMinor;
      sum[3] += record.remainingMinor;
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('ملخص حساب الشخص حسب العملة',
            style: TextStyle(fontWeight: FontWeight.w900)),
        if (!_includeSettled)
          const Text('الملخص الحالي يقتصر على المستحقات غير المسددة.'),
        for (final entry in totals.entries) ...[
          const Divider(),
          Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w800)),
          _moneyLine('أصل المستحقات', entry.value[0], entry.key),
          _moneyLine('إجمالي الدفعات', entry.value[1], entry.key),
          _moneyLine('التسويات والمرتجعات', entry.value[2], entry.key),
          _moneyLine('الرصيد المتبقي', entry.value[3], entry.key,
              strong: true),
        ],
      ]),
    ));
  }

  Widget _recordCard(DailyOutstandingRecord record) {
    final color =
        record.remainingMinor == 0 ? AppTheme.emerald : AppTheme.amber;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(record.operationNumber,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                Text(
                  record.remainingMinor == 0
                      ? tr(context, 'مسدد', 'Settled')
                      : record.paidMinor > 0
                          ? tr(context, 'مسدد جزئياً', 'Partially paid')
                          : tr(context, 'غير مسدد', 'Unpaid'),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${record.sheetNumber} • ${record.purchaseDate}',
                style: Theme.of(context).textTheme.bodySmall),
            if (record.sellerName != null)
              Text('${tr(context, 'الطرف المسؤول', 'Responsible party')}: ${record.sellerName}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (record.branchName != null || record.employeeName != null)
              Text(
                  [
                    if (record.branchName != null) record.branchName!,
                    if (record.employeeName != null) record.employeeName!,
                  ].join(' • '),
                  style: Theme.of(context).textTheme.labelSmall),
            if (record.dueDate != null)
              Text('${tr(context, 'الاستحقاق', 'Due date')}: ${record.dueDate}',
                  style: Theme.of(context).textTheme.labelSmall),
            const Divider(height: 16),
            _moneyLine(tr(context, 'المبلغ الأصلي', 'Original amount'),
                record.originalMinor, record.currency),
            _moneyLine(tr(context, 'الدفعات', 'Payments'), record.paidMinor,
                record.currency),
            if (record.adjustmentDeltaMinor != 0)
              _moneyLine(
                  tr(context, 'صافي المرتجعات والتسويات',
                      'Net returns/adjustments'),
                  record.adjustmentDeltaMinor,
                  record.currency),
            _moneyLine(tr(context, 'المتبقي', 'Remaining'),
                record.remainingMinor, record.currency,
                strong: true, color: color),
            const SizedBox(height: 5),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 5,
              children: [
                TextButton.icon(
                  onPressed: () => _showHistory(record),
                  icon: const Icon(Icons.history, size: 16),
                  label: Text(tr(context, 'السجل', 'History')),
                ),
                if (record.remainingMinor > 0)
                  TextButton.icon(
                    onPressed: () => _recordPayment(record),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: Text(tr(context, 'تسديد', 'Pay')),
                  ),
                if (record.remainingMinor > 0)
                  TextButton.icon(
                    onPressed: () => _adjust(record),
                    icon: const Icon(Icons.tune, size: 16),
                    label:
                        Text(tr(context, 'مرتجع / تسوية', 'Return / adjust')),
                  ),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) =>
                        DailyPurchaseSheetScreen(sheetId: record.sheetId),
                  )),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(tr(context, 'فتح الورقة', 'Open sheet')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _moneyLine(String label, int amount, String currency,
      {bool strong = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: strong
                      ? const TextStyle(fontWeight: FontWeight.w900)
                      : Theme.of(context).textTheme.bodySmall)),
          Text(
              Money.format(amount, currency,
                  locale: Localizations.localeOf(context).languageCode),
              style: TextStyle(
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  Future<void> _recordPayment(DailyOutstandingRecord record) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DailyOutstandingPaymentDialog(
        outstandingId: record.id,
        currency: record.currency,
      ),
    );
    if (result == true && mounted) _refresh();
  }

  Future<void> _adjust(DailyOutstandingRecord record) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DailyOutstandingAdjustmentDialog(
        outstandingId: record.id,
        currency: record.currency,
      ),
    );
    if (result == true && mounted) _refresh();
  }

  Future<void> _showHistory(DailyOutstandingRecord record) async {
    final entries = await ref
        .read(dailyPurchasesRepositoryProvider)
        .getOutstandingHistory(record.id);
    if (!mounted) return;
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
                            title: Text(_historyLabel(entry.entryType)),
                            subtitle: Text([
                              entry.entryDate,
                              if (entry.method != null) entry.method!,
                              if (entry.reference != null) entry.reference!,
                              if (entry.reason != null) entry.reason!,
                            ].join(' • ')),
                            trailing: Text(
                                Money.format(
                                    entry.amountMinor.abs(), record.currency),
                                style: TextStyle(
                                  color: entry.amountMinor < 0
                                      ? AppTheme.amber
                                      : AppTheme.emerald,
                                  fontWeight: FontWeight.w800,
                                )),
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

  String _historyLabel(String type) => switch (type) {
        'payment' => tr(context, 'دفعة', 'Payment'),
        'return' => tr(context, 'مرتجع', 'Return'),
        'adjustment' => tr(context, 'تسوية', 'Adjustment'),
        _ => type,
      };
}
