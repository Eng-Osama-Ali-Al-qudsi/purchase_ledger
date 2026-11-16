import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../domain/daily_sheet_models.dart';

class DailySheetCreateDialog extends ConsumerStatefulWidget {
  const DailySheetCreateDialog({super.key, this.existing});

  final DailySheetDetail? existing;

  @override
  ConsumerState<DailySheetCreateDialog> createState() =>
      _DailySheetCreateDialogState();
}

class _DailySheetCreateDialogState
    extends ConsumerState<DailySheetCreateDialog> {
  final _date = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final _notes = TextEditingController();
  int? _branchId;
  int? _employeeId;
  bool _saving = false;
  String? _error;
  bool get _lockIdentity => widget.existing != null &&
      !widget.existing!.canEditIdentity;

  @override
  void initState() {
    super.initState();
    final sheet = widget.existing;
    if (sheet != null) {
      _date.text = sheet.purchaseDate;
      _notes.text = sheet.notes ?? '';
      _branchId = sheet.branchId;
      _employeeId = sheet.employeeId;
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);
    final employees = ref.watch(employeesProvider(_branchId));
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(widget.existing == null
          ? tr(context, 'إنشاء ورقة مشتريات يومية', 'Create daily purchase sheet')
          : tr(context, 'تعديل بيانات المسودة', 'Edit draft sheet')),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width > 620
            ? 520
            : MediaQuery.sizeOf(context).width - 80,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_lockIdentity) ...[
                Text(tr(context,
                    'تحتوي الورقة على عمليات؛ يمكن تغيير الملاحظات فقط حفاظاً على سلامة القيود المالية.',
                    'This sheet has purchase history; only notes can be edited to protect accounting records.')),
                const SizedBox(height: 10),
              ],
              TextFormField(
                controller: _date,
                enabled: !_lockIdentity,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'تاريخ الورقة', 'Sheet date'),
                  suffixIcon: const Icon(Icons.calendar_month_outlined),
                ),
                onTap: _pickDate,
              ),
              const SizedBox(height: 9),
              branches.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, stack) => Text(tr(
                    context, 'تعذر تحميل الفروع', 'Could not load branches')),
                data: (items) => DropdownButtonFormField<int?>(
                  key: ValueKey('branch-${_branchId ?? 'none'}'),
                  initialValue: _branchId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: tr(context, 'الفرع', 'Branch')),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(tr(context, 'غير محدد', 'Not specified')),
                    ),
                    ...items.map((item) => DropdownMenuItem<int?>(
                          value: item['id'] as int,
                          child: Text(item['name'] as String,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _lockIdentity ? null : (value) => setState(() {
                    _branchId = value;
                    _employeeId = null;
                  }),
                ),
              ),
              const SizedBox(height: 9),
              employees.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, stack) => Text(tr(context, 'تعذر تحميل الموظفين',
                    'Could not load employees')),
                data: (items) => DropdownButtonFormField<int?>(
                  key: ValueKey('employee-${_employeeId ?? 'none'}'),
                  initialValue: _employeeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText:
                          tr(context, 'مسؤول المشتريات', 'Purchasing officer')),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(tr(context, 'غير محدد', 'Not specified')),
                    ),
                    ...items.map((item) => DropdownMenuItem<int?>(
                          value: item['id'] as int,
                          child: Text(item['name'] as String,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _lockIdentity ? null :
                      (value) => setState(() => _employeeId = value),
                ),
              ),
              const SizedBox(height: 9),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText: tr(context, 'ملاحظات عامة', 'General notes')),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(tr(context, 'إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(widget.existing == null
              ? tr(context, 'إنشاء الورقة', 'Create sheet')
              : tr(context, 'حفظ التعديلات', 'Save changes')),
        ),
      ],
    ));
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_date.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked != null) {
      _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date.text.trim()) ||
        DateTime.tryParse(_date.text.trim()) == null) {
      setState(
          () => _error = tr(context, 'التاريخ غير صحيح.', 'Invalid date.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(dailyPurchasesRepositoryProvider);
      final sheet = widget.existing;
      final int id;
      if (sheet == null) {
        id = await repository.createSheet(
          purchaseDate: _date.text.trim(),
          branchId: _branchId,
          employeeId: _employeeId,
          notes: _notes.text,
        );
      } else {
        await repository.updateDraftSheet(
          sheetId: sheet.id,
          purchaseDate: _date.text.trim(),
          branchId: _branchId,
          employeeId: _employeeId,
          notes: _notes.text,
        );
        id = sheet.id;
        ref.invalidate(dailySheetDetailProvider(sheet.id));
      }
      // Notify any other sheet list before closing this route.
      ref.invalidate(dailySheetsProvider);
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
