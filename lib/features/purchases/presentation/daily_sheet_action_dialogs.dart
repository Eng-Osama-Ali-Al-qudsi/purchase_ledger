import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/attachments/attachment_service.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money.dart';

class DailyOutstandingPaymentDialog extends ConsumerStatefulWidget {
  const DailyOutstandingPaymentDialog(
      {super.key, required this.outstandingId, required this.currency});
  final int outstandingId;
  final String currency;

  @override
  ConsumerState<DailyOutstandingPaymentDialog> createState() =>
      _DailyOutstandingPaymentDialogState();
}

class _DailyOutstandingPaymentDialogState
    extends ConsumerState<DailyOutstandingPaymentDialog> {
  final _amount = TextEditingController();
  final _date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'cash';
  AttachmentDraft? _attachment;
  bool _saving = false;
  String? _error;
  late final String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'daily-outstanding-${widget.outstandingId}-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'تسديد مستحق يومي', 'Settle daily outstanding')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText:
                      '${tr(context, 'المبلغ', 'Amount')} (${widget.currency})',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _date,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'تاريخ الدفع', 'Payment date'),
                  suffixIcon: const Icon(Icons.calendar_month_outlined),
                ),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: InputDecoration(
                    labelText: tr(context, 'طريقة الدفع', 'Payment method')),
                items: [
                  DropdownMenuItem(
                      value: 'cash', child: Text(tr(context, 'نقداً', 'Cash'))),
                  DropdownMenuItem(
                      value: 'bank_transfer',
                      child: Text(tr(context, 'تحويل بنكي', 'Bank transfer'))),
                  DropdownMenuItem(
                      value: 'wallet',
                      child: Text(tr(context, 'محفظة إلكترونية', 'E-wallet'))),
                  DropdownMenuItem(
                      value: 'cheque',
                      child: Text(tr(context, 'شيك', 'Cheque'))),
                  DropdownMenuItem(
                      value: 'other',
                      child: Text(tr(context, 'أخرى', 'Other'))),
                ],
                onChanged: (value) => setState(() => _method = value ?? 'cash'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reference,
                decoration: InputDecoration(
                    labelText: tr(
                        context, 'رقم السند أو المرجع', 'Receipt/reference')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickAttachment,
                icon: const Icon(Icons.attach_file),
                label: Text(_attachment == null
                    ? tr(context, 'إرفاق صورة سند الدفع',
                        'Attach payment receipt')
                    : tr(context, 'الصورة مرفقة', 'Image attached')),
              ),
              if (_attachment != null)
                Image.file(File(_attachment!.filePath),
                    height: 80, fit: BoxFit.cover),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration:
                    InputDecoration(labelText: tr(context, 'ملاحظات', 'Notes')),
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
            child: Text(tr(context, 'حفظ الدفعة', 'Save payment'))),
      ],
    );
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_date.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final draft = await AttachmentService.pickImage();
      if (mounted && draft != null) setState(() => _attachment = draft);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    try {
      final amount = Money.parseMinor(_amount.text);
      if (amount <= 0)
        throw StateError(tr(context, 'أدخل مبلغاً أكبر من صفر.',
            'Enter an amount greater than zero.'));
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date.text.trim())) {
        throw StateError(tr(context, 'التاريخ غير صحيح.', 'Invalid date.'));
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      await ref.read(dailyPurchasesRepositoryProvider).recordOutstandingPayment(
            outstandingId: widget.outstandingId,
            amountMinor: amount,
            paymentDate: _date.text.trim(),
            method: _method,
            reference: _reference.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
            attachment: _attachment,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class DailyOutstandingAdjustmentDialog extends ConsumerStatefulWidget {
  const DailyOutstandingAdjustmentDialog({
    super.key,
    required this.outstandingId,
    required this.currency,
  });
  final int outstandingId;
  final String currency;

  @override
  ConsumerState<DailyOutstandingAdjustmentDialog> createState() =>
      _DailyOutstandingAdjustmentDialogState();
}

class _DailyOutstandingAdjustmentDialogState
    extends ConsumerState<DailyOutstandingAdjustmentDialog> {
  final _amount = TextEditingController();
  final _date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  final _reason = TextEditingController();
  String _type = 'return';
  String _direction = 'decrease';
  bool _saving = false;
  String? _error;

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
      title: Text(tr(context, 'مرتجع أو تسوية مستحق يومي',
          'Return or adjust daily outstanding')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(
                    labelText: tr(context, 'نوع الحركة', 'Adjustment type')),
                items: [
                  DropdownMenuItem(
                      value: 'return',
                      child: Text(tr(context, 'مرتجع', 'Return'))),
                  DropdownMenuItem(
                      value: 'adjustment',
                      child: Text(tr(context, 'تسوية', 'Adjustment'))),
                ],
                onChanged: (value) => setState(() => _type = value ?? 'return'),
              ),
              if (_type == 'adjustment') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _direction,
                  decoration: InputDecoration(
                      labelText:
                          tr(context, 'اتجاه التسوية', 'Adjustment direction')),
                  items: [
                    DropdownMenuItem(
                        value: 'decrease',
                        child: Text(tr(
                            context, 'تخفيض المستحق', 'Reduce outstanding'))),
                    DropdownMenuItem(
                        value: 'increase',
                        child: Text(tr(
                            context, 'زيادة المستحق', 'Increase outstanding'))),
                  ],
                  onChanged: (value) =>
                      setState(() => _direction = value ?? 'decrease'),
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText:
                        '${tr(context, 'المبلغ', 'Amount')} (${widget.currency})'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _date,
                readOnly: true,
                decoration: InputDecoration(
                    labelText: tr(context, 'التاريخ', 'Date'),
                    suffixIcon: const Icon(Icons.calendar_month_outlined)),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reason,
                maxLines: 2,
                decoration: InputDecoration(
                    labelText:
                        tr(context, 'سبب المرتجع أو التسوية *', 'Reason *')),
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
            child: Text(tr(context, 'حفظ', 'Save'))),
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
        throw StateError(
            tr(context, 'سبب الحركة مطلوب.', 'A reason is required.'));
      final signed =
          _type == 'return' || _direction == 'decrease' ? -amount : amount;
      setState(() {
        _saving = true;
        _error = null;
      });
      await ref
          .read(dailyPurchasesRepositoryProvider)
          .recordOutstandingAdjustment(
            outstandingId: widget.outstandingId,
            adjustmentType: _type,
            signedDeltaMinor: signed,
            adjustmentDate: _date.text.trim(),
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

class DailySheetAmendmentDialog extends ConsumerStatefulWidget {
  const DailySheetAmendmentDialog({super.key, required this.sheetId});
  final int sheetId;

  @override
  ConsumerState<DailySheetAmendmentDialog> createState() =>
      _DailySheetAmendmentDialogState();
}

class _DailySheetAmendmentDialogState
    extends ConsumerState<DailySheetAmendmentDialog> {
  final _reason = TextEditingController();
  final _details = TextEditingController();
  final _amountDelta = TextEditingController(text: '0');
  String? _currency;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _details.dispose();
    _amountDelta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'إضافة ملحق تصحيحي', 'Add correction addendum')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _reason,
                decoration: InputDecoration(
                    labelText:
                        tr(context, 'سبب التصحيح *', 'Correction reason *')),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _details,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText:
                        tr(context, 'تفاصيل الملحق *', 'Addendum details *')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _currency,
                decoration: InputDecoration(
                    labelText:
                        tr(context, 'العملة (اختياري)', 'Currency (optional)')),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('—')),
                  DropdownMenuItem<String?>(value: 'YER', child: Text('YER')),
                  DropdownMenuItem<String?>(value: 'SAR', child: Text('SAR')),
                  DropdownMenuItem<String?>(value: 'USD', child: Text('USD')),
                ],
                onChanged: (value) => setState(() => _currency = value),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountDelta,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: InputDecoration(
                    labelText: tr(context, 'فرق مالي موثق (اختياري)',
                        'Documented amount difference (optional)')),
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
            child: Text(tr(context, 'إضافة الملحق', 'Add addendum'))),
      ],
    );
  }

  Future<void> _save() async {
    try {
      if (_reason.text.trim().isEmpty || _details.text.trim().isEmpty) {
        throw StateError(tr(context, 'السبب والتفاصيل مطلوبان.',
            'Reason and details are required.'));
      }
      final delta = Money.parseMinor(_amountDelta.text);
      setState(() {
        _saving = true;
        _error = null;
      });
      await ref.read(dailyPurchasesRepositoryProvider).addAmendment(
            sheetId: widget.sheetId,
            reason: _reason.text,
            details: _details.text,
            currency: _currency,
            amountDeltaMinor: delta,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
