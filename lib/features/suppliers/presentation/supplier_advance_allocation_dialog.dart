import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money.dart';
import '../domain/supplier.dart';
import '../domain/supplier_accounting_models.dart';

class SupplierAdvanceAllocationDialog extends ConsumerStatefulWidget {
  const SupplierAdvanceAllocationDialog({super.key, required this.supplier});
  final Supplier supplier;

  @override
  ConsumerState<SupplierAdvanceAllocationDialog> createState() =>
      _SupplierAdvanceAllocationDialogState();
}

class _SupplierAdvanceAllocationDialogState
    extends ConsumerState<SupplierAdvanceAllocationDialog> {
  final Map<int, TextEditingController> _controllers = {};
  final Set<int> _selected = {};
  int? _paymentId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final advancesAsync =
        ref.watch(supplierAdvancesProvider(widget.supplier.id));
    final invoicesAsync =
        ref.watch(supplierInvoicesProvider(widget.supplier.id));
    return AlertDialog(
      title:
          Text(tr(context, 'تخصيص الرصيد المقدم', 'Allocate supplier advance')),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width > 620
            ? 560
            : MediaQuery.sizeOf(context).width * .84,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.supplier.name,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              advancesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, stack) => Text(tr(context,
                    'تعذر تحميل الأرصدة المقدمة', 'Could not load advances')),
                data: (advances) {
                  if (advances.isEmpty) {
                    return Text(
                      tr(context, 'لا يوجد رصيد مقدم غير مخصص لهذا المورد.',
                          'There is no unallocated advance for this supplier.'),
                    );
                  }
                  if (_paymentId == null ||
                      !advances
                          .any((advance) => advance.paymentId == _paymentId)) {
                    _paymentId = advances.first.paymentId;
                  }
                  final current = advances.firstWhere(
                    (advance) => advance.paymentId == _paymentId,
                    orElse: () => advances.first,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _paymentId,
                        decoration: InputDecoration(
                          labelText: tr(
                              context, 'سند الدفعة المقدمة', 'Advance payment'),
                        ),
                        items: advances.map((advance) {
                          return DropdownMenuItem(
                            value: advance.paymentId,
                            child: Text(
                              '${advance.receiptNumber ?? 'PAY-${advance.paymentId}'} • ${Money.format(advance.remainingMinor, advance.currency)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) => setState(() {
                          _paymentId = value;
                          _selected.clear();
                          for (final controller in _controllers.values) {
                            controller.clear();
                          }
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${tr(context, 'المتاح للتخصيص', 'Available to allocate')}: ${Money.format(current.remainingMinor, current.currency)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      invoicesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stack) => Text(
                          tr(context, 'تعذر تحميل الفواتير',
                              'Could not load invoices'),
                        ),
                        data: (invoices) {
                          final open = invoices
                              .where((invoice) =>
                                  invoice.currency == current.currency &&
                                  invoice.outstandingMinor > 0)
                              .toList(growable: false);
                          if (open.isEmpty) {
                            return Text(
                              tr(
                                  context,
                                  'لا توجد فواتير مفتوحة بنفس عملة الرصيد المقدم.',
                                  'No open invoices in the advance currency.'),
                            );
                          }
                          return Column(
                            children: open.map(_invoiceRow).toList(),
                          );
                        },
                      ),
                    ],
                  );
                },
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
          child: Text(tr(context, 'إغلاق', 'Close')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(tr(context, 'تخصيص الرصيد', 'Allocate advance')),
        ),
      ],
    );
  }

  Widget _invoiceRow(SupplierInvoiceBalance invoice) {
    final controller = _controllers.putIfAbsent(
      invoice.id,
      () => TextEditingController(),
    );
    final selected = _selected.contains(invoice.id);
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
                  _selected.add(invoice.id);
                } else {
                  _selected.remove(invoice.id);
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
                  hintText: tr(context, 'المبلغ', 'Amount'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_paymentId == null) {
      setState(() => _error =
          tr(context, 'لا يوجد سند دفعة محدد.', 'Select an advance payment.'));
      return;
    }
    final allocations = <int, int>{};
    try {
      for (final invoiceId in _selected) {
        final text = _controllers[invoiceId]?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final amount = Money.parseMinor(text);
        if (amount <= 0) {
          throw StateError(tr(context, 'مبلغ التخصيص يجب أن يكون أكبر من صفر.',
              'Allocation must be greater than zero.'));
        }
        allocations[invoiceId] = amount;
      }
      if (allocations.isEmpty) {
        throw StateError(tr(context, 'حدد فاتورة وأدخل مبلغ التخصيص.',
            'Select an invoice and enter an allocation amount.'));
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      await ref.read(supplierAccountingRepositoryProvider).allocateAdvance(
            paymentId: _paymentId!,
            allocations: allocations,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
