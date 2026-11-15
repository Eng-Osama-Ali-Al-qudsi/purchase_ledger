import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/attachments/attachment_service.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money.dart';
import '../domain/supplier.dart';
import '../domain/supplier_accounting_models.dart';
import 'confirm_excess_payment.dart';

class SupplierPaymentDialog extends ConsumerStatefulWidget {
  const SupplierPaymentDialog({super.key, required this.supplier});

  final Supplier supplier;

  @override
  ConsumerState<SupplierPaymentDialog> createState() =>
      _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends ConsumerState<SupplierPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _date = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final _receipt = TextEditingController();
  final _notes = TextEditingController();
  final Map<int, TextEditingController> _allocationControllers = {};
  final Set<int> _selectedInvoices = {};
  String _currency = 'YER';
  String _method = 'cash';
  bool _saving = false;
  AttachmentDraft? _attachment;
  String? _error;
  late final String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _currency = widget.supplier.defaultCurrency;
    _idempotencyKey =
        'supplier-payment-${widget.supplier.id}-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _receipt.dispose();
    _notes.dispose();
    for (final controller in _allocationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync =
        ref.watch(supplierInvoicesProvider(widget.supplier.id));
    return AlertDialog(
      scrollable: true,
      title: Text(tr(context, 'تسجيل دفعة للمورد', 'Record supplier payment')),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width > 620
            ? 560
            : MediaQuery.sizeOf(context).width * .84,
        child: Form(
          key: _formKey,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.supplier.name,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: InputDecoration(
                          labelText: tr(context, 'العملة', 'Currency'),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'YER', child: Text('YER')),
                          DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                        ],
                        onChanged: (value) => setState(() {
                          _currency = value ?? _currency;
                          _selectedInvoices.clear();
                          for (final controller
                              in _allocationControllers.values) {
                            controller.clear();
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _date,
                        decoration: InputDecoration(
                          labelText: tr(context, 'تاريخ الدفع', 'Payment date'),
                        ),
                        validator: _dateValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText:
                        '${tr(context, 'إجمالي مبلغ الدفعة', 'Payment amount')} ($_currency)',
                  ),
                  validator: (value) {
                    try {
                      if (Money.parseMinor(value ?? '0') <= 0) {
                        return tr(context, 'أدخل مبلغاً أكبر من صفر',
                            'Enter an amount greater than zero');
                      }
                      return null;
                    } catch (_) {
                      return tr(context, 'أدخل مبلغاً صحيحاً',
                          'Enter a valid amount');
                    }
                  },
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: InputDecoration(
                    labelText: tr(context, 'طريقة الدفع', 'Payment method'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'cash',
                      child: Text(tr(context, 'نقداً', 'Cash')),
                    ),
                    DropdownMenuItem(
                      value: 'bank_transfer',
                      child: Text(tr(context, 'تحويل بنكي', 'Bank transfer')),
                    ),
                    DropdownMenuItem(
                      value: 'wallet',
                      child: Text(tr(context, 'محفظة إلكترونية', 'E-wallet')),
                    ),
                    DropdownMenuItem(
                      value: 'cheque',
                      child: Text(tr(context, 'شيك', 'Cheque')),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(tr(context, 'أخرى', 'Other')),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _method = value ?? 'cash'),
                ),
                const SizedBox(height: 9),
                TextFormField(
                  controller: _receipt,
                  decoration: InputDecoration(
                    labelText: tr(context, 'رقم سند الدفع', 'Receipt number'),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr(context, 'تخصيص الدفعة على الفواتير (اختياري)',
                      'Allocate payment to invoices (optional)'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  tr(
                      context,
                      'يمكن توزيع الدفعة على عدة فواتير. أي مبلغ غير مخصص سيبقى رصيداً مقدماً للمحل لدى المورد.',
                      'A payment can cover multiple invoices. Any unallocated amount remains as an advance with the supplier.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                invoicesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stack) => Text(
                    tr(context, 'تعذر تحميل الفواتير المفتوحة',
                        'Could not load open invoices'),
                  ),
                  data: (invoices) {
                    final open = invoices
                        .where((invoice) =>
                            invoice.currency == _currency &&
                            invoice.outstandingMinor > 0)
                        .toList(growable: false);
                    if (open.isEmpty) {
                      return Text(
                        tr(
                            context,
                            'لا توجد فواتير مفتوحة بهذه العملة؛ ستُسجل الدفعة كرصيد مقدم.',
                            'No open invoices in this currency; the payment will be recorded as an advance.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    }
                    return Column(
                      children: open.map(_invoiceAllocationRow).toList(),
                    );
                  },
                ),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickAttachment,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_attachment == null
                      ? tr(context, 'إرفاق صورة سند الدفع (اختياري)',
                          'Attach payment receipt (optional)')
                      : tr(context, 'تم إرفاق صورة السند',
                          'Receipt image attached')),
                ),
                if (_attachment != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(_attachment!.filePath),
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: tr(context, 'ملاحظات', 'Notes'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 9),
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
          child: Text(tr(context, 'حفظ الدفعة', 'Save payment')),
        ),
      ],
    );
  }

  Widget _invoiceAllocationRow(SupplierInvoiceBalance invoice) {
    final controller = _allocationControllers.putIfAbsent(
      invoice.id,
      () => TextEditingController(),
    );
    final selected = _selectedInvoices.contains(invoice.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: (value) => setState(() {
                if (value == true) {
                  _selectedInvoices.add(invoice.id);
                } else {
                  _selectedInvoices.remove(invoice.id);
                  controller.clear();
                }
              }),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${invoice.invoiceNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '${invoice.invoiceDate} • ${tr(context, 'المتبقي', 'Remaining')}: ${Money.format(invoice.outstandingMinor, invoice.currency)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 118,
              child: TextField(
                controller: controller,
                enabled: selected,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr(context, 'التخصيص', 'Allocate'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _dateValidator(String? value) {
    final date = value?.trim() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date) == null) {
      return tr(context, 'استخدم YYYY-MM-DD', 'Use YYYY-MM-DD');
    }
    return null;
  }

  Future<void> _pickAttachment() async {
    try {
      final draft = await AttachmentService.pickImage();
      if (mounted && draft != null) setState(() => _attachment = draft);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final amount = Money.parseMinor(_amount.text);
      final allocations = <int, int>{};
      for (final invoiceId in _selectedInvoices) {
        final text = _allocationControllers[invoiceId]?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final value = Money.parseMinor(text);
        if (value <= 0) {
          throw StateError(tr(context, 'مبلغ التخصيص يجب أن يكون أكبر من صفر.',
              'Allocation must be greater than zero.'));
        }
        allocations[invoiceId] = value;
      }
      final accounting = ref.read(supplierAccountingRepositoryProvider);
      final due = await accounting.getCurrentDueMinor(widget.supplier.id, _currency);
      if (!mounted) return;
      final accepted = await confirmExcessSupplierPayment(context,
          dueMinor: due, amountMinor: amount, currency: _currency);
      if (!accepted || !mounted) return;
      await accounting.recordPayment(
            allowAdvance: amount > due,
            expectedDueMinor: due,
            supplierId: widget.supplier.id,
            amountMinor: amount,
            currency: _currency,
            paymentDate: _date.text.trim(),
            method: _method,
            receiptNumber: _receipt.text,
            notes: _notes.text,
            allocations: allocations,
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
