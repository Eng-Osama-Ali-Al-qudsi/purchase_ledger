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
  bool _showArchived = false;
  bool _creatingSheet = false;
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
          includeArchived: _showArchived,
        );
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(dashboardProvider);
    ref.invalidate(dailySheetsProvider);
    final next = _load();
    // Never return the Future from a setState callback: Flutter expects a
    // synchronous VoidCallback even though _load itself is asynchronous.
    setState(() {
      _future = next;
    });
  }

  Future<void> _refreshAndWait() async {
    _refresh();
    try {
      await _future;
    } catch (_) {
      // FutureBuilder presents the error and the Retry action.
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);
    final employees = ref.watch(employeesProvider(_branchId));
    return Scaffold(
      body: SafeArea(top: false, child: Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .46,
            ),
            child: SingleChildScrollView(child: Padding(
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
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(tr(context, 'إظهار الأوراق المؤرشفة',
                          'Show archived sheets')),
                      value: _showArchived,
                      onChanged: (value) {
                        _showArchived = value;
                        _refresh();
                      },
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
                              key: ValueKey('filter-branch-${_branchId ?? 'all'}'),
                              isExpanded: true,
                              initialValue: _branchId,
                              decoration: InputDecoration(
                                labelText: tr(context, 'الفرع', 'Branch'),
                                isDense: true,
                              ),
                              items: [
                                DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text(
                                      tr(context, 'كل الفروع', 'All branches'),
                                      overflow: TextOverflow.ellipsis),
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
                              key: ValueKey('filter-employee-${_employeeId ?? 'all'}'),
                              isExpanded: true,
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
                                      context, 'كل الموظفين', 'All officers'),
                                      overflow: TextOverflow.ellipsis),
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
          ))),
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
                    onRefresh: _refreshAndWait,
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
                  onRefresh: _refreshAndWait,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: sheets.length,
                    itemBuilder: (context, index) => _sheetCard(sheets[index]),
                  ),
                );
              },
            ),
          ),
        ],
      )),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: _creatingSheet ? null : _createSheet,
            icon: const Icon(Icons.add),
            label: Text(tr(context, 'ورقة جديدة', 'New sheet')),
          ),
        ),
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
        if (!mounted) return;
        if (picked != null) {
          controller.text =
              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
    );
  }

  Widget _sheetCard(DailySheetSummary sheet) {
    final statusColor = switch (sheet.status) {
      'ARCHIVED' => Theme.of(context).colorScheme.outline,
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
                  if (sheet.status == 'DRAFT')
                    PopupMenuButton<String>(
                      tooltip: tr(context, 'إدارة المسودة', 'Manage draft'),
                      onSelected: (action) {
                        if (action == 'edit') _editSheet(sheet);
                        if (action == 'archive') _archiveSheet(sheet);
                        if (action == 'delete') _deleteSheet(sheet);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit',
                            child: Text(tr(context, 'تعديل بيانات الورقة',
                                'Edit sheet details'))),
                        PopupMenuItem(value: 'archive',
                            child: Text(tr(context, 'أرشفة المسودة الفارغة',
                                'Archive empty draft'))),
                        PopupMenuItem(value: 'delete',
                            child: Text(tr(context, 'حذف المسودة الفارغة نهائياً',
                                'Permanently delete empty draft'))),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Wrap(spacing: 12, runSpacing: 5, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_today_outlined, size: 14),
                  const SizedBox(width: 5),
                  Text(sheet.purchaseDate),
                ]),
                Text(
                  '${sheet.operationCount} ${tr(context, 'عملية', 'operations')} • ${sheet.itemCount} ${tr(context, 'صنف', 'items')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
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
      'ARCHIVED' => tr(context, 'مؤرشفة', 'Archived'),
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

  Widget _error(String message) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppTheme.danger,
              size: 40,
            ),

            const SizedBox(height: 12),

            Text(
              tr(
                context,
                'تعذر تحميل أوراق المشتريات',
                'Could not load daily sheets',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              message,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            OutlinedButton(
              onPressed: _refresh,
              child: Text(
                tr(
                  context,
                  'إعادة المحاولة',
                  'Retry',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _createSheet() async {
    if (_creatingSheet) return;
    setState(() { _creatingSheet = true; });
    try {
      final id = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const DailySheetCreateDialog(),
      );
      if (!mounted || id == null) return;
      // The dialog returns an actual id ONLY after SQLite commits.
      _from.clear();
      _to.clear();
      _branchId = null;
      _employeeId = null;
      _showArchived = false;
      _refresh();
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DailyPurchaseSheetScreen(sheetId: id),
      ));
      if (mounted) _refresh();
    } finally {
      if (mounted) setState(() { _creatingSheet = false; });
    }
  }

  Future<void> _editSheet(DailySheetSummary sheet) async {
    try {
      final detail = await ref.read(dailyPurchasesRepositoryProvider)
          .getSheetDetail(sheet.id);
      if (!mounted) return;
      final result = await showDialog<int>(context: context,
          builder: (_) => DailySheetCreateDialog(existing: detail));
      if (!mounted || result == null) return;
      _from.clear();
      _to.clear();
      _branchId = null;
      _employeeId = null;
      _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteSheet(DailySheetSummary sheet) async {
    var reason = '';
    final confirmed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          scrollable: true,
          title: Text(tr(context, 'حذف المسودة نهائياً',
              'Permanently delete empty draft')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${tr(context, 'رقم الورقة', 'Sheet number')}: ${sheet.sheetNumber}'),
              Text('${tr(context, 'التاريخ', 'Date')}: ${sheet.purchaseDate}'),
              Text('${tr(context, 'الحالة', 'Status')}: ${tr(context, 'مسودة', 'Draft')}'),
              Text('${tr(context, 'العمليات النشطة', 'Active operations')}: ${sheet.operationCount}'),
              const SizedBox(height: 8),
              Text(tr(context,
                'لا يمكن التراجع من التطبيق. يُسمح فقط بمسودة لا تحتوي على أي عمليات سابقة أو قيود مالية. يُحفظ سجل الحذف ورقم الورقة للتدقيق.',
                'This cannot be undone in the app. Only a draft with no operation history or financial links can be deleted. An audit receipt and document number are retained.')),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => refreshDialog(() => reason = value),
                decoration: InputDecoration(labelText: tr(context,
                    'سبب الحذف *', 'Deletion reason *')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr(context, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: reason.trim().isEmpty ? null : () =>
                Navigator.pop(dialogContext, reason.trim()),
              child: Text(tr(context, 'حذف الورقة نهائياً',
                  'Permanently delete sheet')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed == null) return;
    try {
      await ref.read(dailyPurchasesRepositoryProvider)
          .deleteEmptyDraftSheet(sheet.id, reason: confirmed);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(
        context, 'حُذفت المسودة الفارغة، وبقي سجل الحذف للتدقيق.',
        'Empty draft deleted; deletion receipt is retained.'))));
    } catch (error) {
      if (mounted) {
        final raw = error.toString();
        final message = raw.contains('Purchase history exists')
            ? tr(context,
                'لا يمكن حذف الورقة نهائياً: لديها عمليات شراء سابقة أو ارتباطات مالية. استخدم إلغاء العملية أو الأرشفة وفق الحالة.',
                'Cannot permanently delete: operation history or financial links exist. Use voiding or archiving where appropriate.')
            : raw.contains('Only active draft sheets')
                ? tr(context,
                    'الحذف النهائي متاح للمسودات النشطة الفارغة فقط.',
                    'Permanent deletion is available only for active empty drafts.')
                : raw;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _archiveSheet(DailySheetSummary sheet) async {
    var reason = '';
    final confirmedReason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          scrollable: true,
          title: Text(tr(context, 'أرشفة ورقة فارغة', 'Archive empty sheet')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${tr(context, 'الورقة', 'Sheet')}: ${sheet.sheetNumber}  •  '
                  '${tr(context, 'الحالة', 'Status')}: ${tr(context, 'مسودة', 'Draft')}'),
              Text('${tr(context, 'العمليات النشطة', 'Active operations')}: '
                  '${sheet.operationCount}'),
              const SizedBox(height: 8),
              Text(tr(context,
                  'تُحفظ الورقة وسجل تدقيقها دون حذف. لا يمكن أرشفة ورقة تحتوي على أي عملية شراء، حتى لو أُلغيت.',
                  'The sheet and its audit trail are preserved. Sheets with any purchase history cannot be archived.')),
              TextField(
                maxLines: 2,
                onChanged: (value) => refreshDialog(() => reason = value),
                decoration: InputDecoration(
                  labelText: tr(context, 'سبب الأرشفة *', 'Archive reason *')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr(context, 'رجوع', 'Back'))),
            FilledButton(
              onPressed: reason.trim().isEmpty || sheet.operationCount > 0 ? null :
                  () => Navigator.pop(dialogContext, reason.trim()),
              child: Text(tr(context, 'أرشفة', 'Archive')),
            ),
          ],
        ),
      ),
    );
    if (confirmedReason == null || !mounted) return;
    try {
      await ref.read(dailyPurchasesRepositoryProvider)
          .archiveEmptyDraftSheet(sheet.id, reason: confirmedReason);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'أُرشفت الورقة مع حفظ سجلها.',
            'Sheet archived with its audit history.')),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())));
    }
  }
}
