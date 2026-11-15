import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../domain/daily_sheet_models.dart';
import 'daily_purchase_sheet_screen.dart';
import 'daily_outstanding_screen.dart';
import 'daily_sheet_create_dialog.dart';

class DailyPurchasesScreen extends ConsumerStatefulWidget {
  const DailyPurchasesScreen({super.key});

  @override
  ConsumerState<DailyPurchasesScreen> createState() =>
      _DailyPurchasesScreenState();
}

class _DailyPurchasesScreenState extends ConsumerState<DailyPurchasesScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  int? _branchId;
  int? _employeeId;
  late Future<List<DailySheetSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<List<DailySheetSummary>> _load() {
    return ref.read(dailyPurchasesRepositoryProvider).getSheets(
          dateFrom: _from.text.trim().isEmpty ? null : _from.text.trim(),
          dateTo: _to.text.trim().isEmpty ? null : _to.text.trim(),
          branchId: _branchId,
          employeeId: _employeeId,
        );
  }

  void _refresh() {
    ref.invalidate(dashboardProvider);
    ref.invalidate(dailySheetsProvider);
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);
    final employees = ref.watch(employeesProvider(_branchId));
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 5),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr(context, 'دفتر المشتريات اليومية',
                                'Daily purchases book'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(
                            builder: (_) => const DailyOutstandingScreen(),
                          )),
                          icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 17),
                          label: Text(tr(context, 'المستحقات اليومية',
                              'Outstanding ledger')),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: _dateFilter(
                                _from, tr(context, 'من تاريخ', 'From date'))),
                        const SizedBox(width: 7),
                        Expanded(
                            child: _dateFilter(
                                _to, tr(context, 'إلى تاريخ', 'To date'))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: branches.when(
                            loading: () => const LinearProgressIndicator(),
                            error: (error, stack) => Text(tr(
                                context,
                                'تعذر تحميل الفروع',
                                'Could not load branches')),
                            data: (items) => DropdownButtonFormField<int?>(
                              initialValue: _branchId,
                              decoration: InputDecoration(
                                labelText: tr(context, 'الفرع', 'Branch'),
                                isDense: true,
                              ),
                              items: [
                                DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text(
                                      tr(context, 'كل الفروع', 'All branches')),
                                ),
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
                            error: (error, stack) => Text(tr(
                                context,
                                'تعذر تحميل الموظفين',
                                'Could not load employees')),
                            data: (items) => DropdownButtonFormField<int?>(
                              initialValue: _employeeId,
                              decoration: InputDecoration(
                                labelText: tr(context, 'مسؤول المشتريات',
                                    'Purchasing officer'),
                                isDense: true,
                              ),
                              items: [
                                DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text(tr(
                                      context, 'كل الموظفين', 'All officers')),
                                ),
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
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            _from.clear();
                            _to.clear();
                            _branchId = null;
                            _employeeId = null;
                            _refresh();
                          },
                          child:
                              Text(tr(context, 'مسح الفلاتر', 'Clear filters')),
                        ),
                        const Spacer(),
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
            child: FutureBuilder<List<DailySheetSummary>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _error(snapshot.error.toString());
                }
                final sheets = snapshot.data ?? const <DailySheetSummary>[];
                if (sheets.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      children: [
                        const SizedBox(height: 80),
                        Icon(Icons.menu_book_outlined,
                            size: 54,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 10),
                        Text(
                          tr(context, 'لا توجد أوراق مشتريات يومية بعد.',
                              'No daily purchase sheets yet.'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(
                              context,
                              'أنشئ ورقة اليوم ثم أضف إليها عمليات الشراء المتعددة.',
                              'Create a daily sheet, then add multiple purchase operations.'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: sheets.length,
                    itemBuilder: (context, index) => _sheetCard(sheets[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSheet,
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'ورقة جديدة', 'New sheet')),
      ),
    );
  }

  Widget _dateFilter(TextEditingController controller, String label) {
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
        if (picked != null) {
          controller.text =
              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
    );
  }

  Widget _sheetCard(DailySheetSummary sheet) {
    final statusColor = switch (sheet.status) {
      'DRAFT' => AppTheme.teal,
      'READY_FOR_HANDOVER' => AppTheme.amber,
      'HANDED_OVER' => AppTheme.emerald,
      'CLOSED' => Theme.of(context).colorScheme.onSurfaceVariant,
      _ => AppTheme.teal,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(
          builder: (_) => DailyPurchaseSheetScreen(sheetId: sheet.id),
        ))
            .then((_) {
          if (mounted) _refresh();
        }),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(sheet.sheetNumber,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                  _statusChip(sheet.status, statusColor),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 14),
                  const SizedBox(width: 5),
                  Text(sheet.purchaseDate),
                  const Spacer(),
                  Text(
                      '${sheet.operationCount} ${tr(context, 'عملية', 'operations')} • ${sheet.itemCount} ${tr(context, 'صنف', 'items')}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              if (sheet.branchName != null || sheet.employeeName != null) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    if (sheet.branchName != null) sheet.branchName!,
                    if (sheet.employeeName != null) sheet.employeeName!,
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (sheet.totalsByCurrency.isNotEmpty) ...[
                const Divider(height: 17),
                ...sheet.totalsByCurrency.map((total) => Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${tr(context, 'الإجمالي', 'Total')} (${total.currency})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          Money.format(total.totalMinor, total.currency,
                              locale:
                                  Localizations.localeOf(context).languageCode),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    )),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  tr(context, 'فتح الورقة والتفاصيل ←', 'Open sheet details →'),
                  style: const TextStyle(
                      color: AppTheme.teal,
                      fontWeight: FontWeight.w700,
                      fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status, Color color) {
    final label = switch (status) {
      'DRAFT' => tr(context, 'مسودة', 'Draft'),
      'READY_FOR_HANDOVER' => tr(context, 'جاهزة للتسليم', 'Ready'),
      'HANDED_OVER' => tr(context, 'تم التسليم', 'Handed over'),
      'CLOSED' => tr(context, 'مغلقة', 'Closed'),
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _error(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
              Text(tr(context, 'تعذر تحميل أوراق المشتريات',
                  'Could not load daily sheets')),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: _refresh,
                  child: Text(tr(context, 'إعادة المحاولة', 'Retry'))),
            ],
          ),
        ),
      );

  Future<void> _createSheet() async {
    final id = await showDialog<int>(
      context: context,
      builder: (_) => const DailySheetCreateDialog(),
    );
    if (!mounted || id == null) return;
    // Newly created sheets may fall outside an old date/branch filter.
    // Reset filters to make the saved record visible immediately.
    _from.clear();
    _to.clear();
    _branchId = null;
    _employeeId = null;
    _refresh();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DailyPurchaseSheetScreen(sheetId: id),
    ));
    if (mounted) _refresh();
  }
}
