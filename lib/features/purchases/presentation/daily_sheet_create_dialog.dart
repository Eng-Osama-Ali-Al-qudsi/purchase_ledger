import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';

class DailySheetCreateDialog extends ConsumerStatefulWidget {
  const DailySheetCreateDialog({super.key});

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
    return AlertDialog(
      title: Text(tr(
          context, 'إنشاء ورقة مشتريات يومية', 'Create daily purchase sheet')),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width > 620
            ? 520
            : MediaQuery.sizeOf(context).width * .84,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _date,
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
                  initialValue: _branchId,
                  decoration: InputDecoration(
                      labelText: tr(context, 'الفرع', 'Branch')),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(tr(context, 'غير محدد', 'Not specified')),
                    ),
                    ...items.map((item) => DropdownMenuItem<int?>(
                          value: item['id'] as int,
                          child: Text(item['name'] as String),
                        )),
                  ],
                  onChanged: (value) => setState(() {
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
                  initialValue: _employeeId,
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
                          child: Text(item['name'] as String),
                        )),
                  ],
                  onChanged: (value) => setState(() => _employeeId = value),
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
          child: Text(tr(context, 'إنشاء الورقة', 'Create sheet')),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_date.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
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
      final id = await ref.read(dailyPurchasesRepositoryProvider).createSheet(
            purchaseDate: _date.text.trim(),
            branchId: _branchId,
            employeeId: _employeeId,
            notes: _notes.text,
          );
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
