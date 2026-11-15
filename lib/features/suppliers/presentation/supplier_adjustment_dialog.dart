import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money.dart';
import '../domain/supplier.dart';

class SupplierAdjustmentDialog extends ConsumerStatefulWidget {
  const SupplierAdjustmentDialog({super.key, required this.supplier});
  final Supplier supplier;

  @override
  ConsumerState<SupplierAdjustmentDialog> createState() =>
      _SupplierAdjustmentDialogState();
}

class _SupplierAdjustmentDialogState
    extends ConsumerState<SupplierAdjustmentDialog> {
  final _amount = TextEditingController();
  final _date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  final _reason = TextEditingController();
  String _currency = 'YER';
  String _direction = 'increase';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currency = widget.supplier.defaultCurrency;
  }

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(tr(context, 'تسوية حساب المورد', 'Supplier account adjustment')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.supplier.name,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: InputDecoration(
                    labelText: tr(context, 'العملة', 'Currency')),
                items: const [
                  DropdownMenuItem(value: 'YER', child: Text('YER')),
                  DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                ],
                onChanged: (value) =>
                    setState(() => _currency = value ?? _currency),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _direction,
                decoration: InputDecoration(
                    labelText:
                        tr(context, 'اتجاه التسوية', 'Adjustment direction')),
                items: [
                  DropdownMenuItem(
                      value: 'increase',
                      child: Text(tr(context, 'زيادة المستحق للمورد',
                          'Increase amount due to supplier'))),
                  DropdownMenuItem(
                      value: 'decrease',
                      child: Text(tr(
                          context,
                          'تخفيض المستحق / زيادة الرصيد المقدم',
                          'Reduce due / increase advance'))),
                ],
                onChanged: (value) =>
                    setState(() => _direction = value ?? 'increase'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText:
                        '${tr(context, 'المبلغ', 'Amount')} ($_currency)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _date,
                readOnly: true,
                decoration: InputDecoration(
                    labelText: tr(context, 'تاريخ التسوية', 'Adjustment date'),
                    suffixIcon: const Icon(Icons.calendar_month_outlined)),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reason,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText:
                        tr(context, 'سبب التسوية *', 'Adjustment reason *')),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(tr(context, 'إلغاء', 'Cancel'))),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(tr(context, 'حفظ التسوية', 'Save adjustment'))),
      ],
    );
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_date.text) ?? DateTime.now();
    final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (picked != null) {
      _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    try {
      final amount = Money.parseMinor(_amount.text);
      if (amount <= 0)
        throw StateError(tr(context, 'أدخل مبلغاً أكبر من صفر.',
            'Enter an amount greater than zero.'));
      if (_reason.text.trim().isEmpty)
        throw StateError(tr(
            context, 'سبب التسوية مطلوب.', 'Adjustment reason is required.'));
      final signed = _direction == 'increase' ? amount : -amount;
      setState(() {
        _saving = true;
        _error = null;
      });
      await ref.read(supplierAccountingRepositoryProvider).createAdjustment(
            supplierId: widget.supplier.id,
            currency: _currency,
            signedAmountMinor: signed,
            entryDate: _date.text.trim(),
            reason: _reason.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
