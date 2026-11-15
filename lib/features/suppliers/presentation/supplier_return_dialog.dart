import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money.dart';
import '../../purchases/domain/purchase_line.dart';
import '../domain/supplier_accounting_models.dart';

class SupplierReturnDialog extends ConsumerStatefulWidget {
  const SupplierReturnDialog({
    super.key,
    required this.supplierId,
    required this.invoiceId,
  });

  final int supplierId;
  final int invoiceId;

  @override
  ConsumerState<SupplierReturnDialog> createState() =>
      _SupplierReturnDialogState();
}

class _SupplierReturnDialogState extends ConsumerState<SupplierReturnDialog> {
  final _returnNumber = TextEditingController();
  final _returnDate = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final _notes = TextEditingController();
  final Map<int, TextEditingController> _quantities = {};
  bool _saving = false;
  String? _error;
  Future<SupplierInvoiceDetail>? _detailFuture;

  @override
  void initState() {
    super.initState();
    _returnNumber.text = 'RET-${DateTime.now().microsecondsSinceEpoch}';
    _detailFuture = ref
        .read(supplierAccountingRepositoryProvider)
        .getInvoiceDetail(widget.invoiceId);
  }

  @override
  void dispose() {
    _returnNumber.dispose();
    _returnDate.dispose();
    _notes.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'تسجيل مرتجع مشتريات', 'Record purchase return')),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width > 720
            ? 660
            : MediaQuery.sizeOf(context).width * .86,
        child: FutureBuilder<SupplierInvoiceDetail>(
          future: _detailFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 180,
                child: Center(child: Text(snapshot.error.toString())),
              );
            }
            final detail = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${detail.invoiceNumber} • ${detail.invoiceDate} • ${detail.currency}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (detail.unlinkedReturnAmountMinor > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        tr(
                            context,
                            'توجد مرتجعات قديمة غير مرتبطة بأصناف الفاتورة بقيمة ${Money.format(detail.unlinkedReturnAmountMinor, detail.currency)}. يجب مراجعتها قبل تسجيل مرتجع جديد لضمان عدم تجاوز كميات الأصناف.',
                            'Older returns worth ${Money.format(detail.unlinkedReturnAmountMinor, detail.currency)} are not linked to invoice items. Reconcile them before recording another item-level return.'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  TextFormField(
                    controller: _returnNumber,
                    decoration: InputDecoration(
                        labelText:
                            tr(context, 'رقم المرتجع *', 'Return number *')),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _returnDate,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: tr(context, 'تاريخ المرتجع', 'Return date'),
                      suffixIcon: const Icon(Icons.calendar_month_outlined),
                    ),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(context, 'حدد الكميات المرتجعة من الأصناف الأصلية',
                        'Select return quantities from the original invoice items'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  ...detail.items
                      .map((item) => _itemRow(item, detail.currency)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: InputDecoration(
                        labelText:
                            tr(context, 'ملاحظات المرتجع', 'Return notes')),
                  ),
                  const SizedBox(height: 8),
                  _totalPreview(detail),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(tr(context, 'إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(tr(context, 'حفظ المرتجع', 'Save return')),
        ),
      ],
    );
  }

  Widget _itemRow(SupplierInvoiceItemDetail item, String currency) {
    final controller = _quantities.putIfAbsent(
      item.id,
      () => TextEditingController(text: '0'),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.description,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    '${tr(context, 'الأصل', 'Original')}: ${Money.formatQuantity(item.quantityMilli)} ${item.unitName} • ${Money.format(item.lineTotalMinor, currency)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${tr(context, 'المتبقي للمرتجع', 'Returnable')}: ${Money.formatQuantity(item.remainingQuantityMilli)} ${item.unitName} • ${Money.format(item.remainingAmountMinor, currency)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 105,
              child: TextField(
                controller: controller,
                enabled: item.remainingQuantityMilli > 0,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr(context, 'الكمية', 'Qty'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalPreview(SupplierInvoiceDetail detail) {
    var total = 0;
    for (final item in detail.items) {
      final quantity = _tryQuantity(_quantities[item.id]?.text ?? '0');
      if (quantity <= 0 || item.remainingQuantityMilli <= 0) continue;
      total += _amountForQuantity(item, quantity);
    }
    return Card(
      color:
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .25),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
                child: Text(tr(context, 'إجمالي قيمة المرتجع', 'Return total'),
                    style: const TextStyle(fontWeight: FontWeight.w900))),
            Text(Money.format(total, detail.currency),
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
      ),
    );
  }

  int _tryQuantity(String value) {
    try {
      return _parseQuantity(value);
    } catch (_) {
      return 0;
    }
  }

  int _parseQuantity(String value) {
    var normalized = value.trim().replaceAll('٫', '.');
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(arabic[i], '$i');
      normalized = normalized.replaceAll(persian[i], '$i');
    }
    final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(normalized);
    if (match == null) throw const FormatException('Invalid quantity');
    final fraction = (match.group(2) ?? '').padRight(3, '0');
    return int.parse(match.group(1)!) * 1000 +
        (fraction.isEmpty ? 0 : int.parse(fraction));
  }

  int _amountForQuantity(SupplierInvoiceItemDetail item, int quantityMilli) {
    if (quantityMilli <= 0 || item.remainingQuantityMilli <= 0) return 0;
    return (item.remainingAmountMinor * quantityMilli +
            (item.remainingQuantityMilli ~/ 2)) ~/
        item.remainingQuantityMilli;
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_returnDate.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _returnDate.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    final detail = await _detailFuture;
    if (!mounted || detail == null) return;
    try {
      if (detail.unlinkedReturnAmountMinor > 0) {
        throw StateError(tr(
            context,
            'يجب مراجعة المرتجعات القديمة غير المرتبطة بالأصناف أولاً.',
            'Reconcile older unlinked returns first.'));
      }
      if (_returnNumber.text.trim().isEmpty) {
        throw StateError(
            tr(context, 'رقم المرتجع مطلوب.', 'Return number is required.'));
      }
      final lines = <PurchaseLine>[];
      for (final item in detail.items) {
        final quantity = _tryQuantity(_quantities[item.id]?.text ?? '0');
        if (quantity == 0) continue;
        if (quantity < 0 || quantity > item.remainingQuantityMilli) {
          throw StateError(
              '${item.description}: ${tr(context, 'الكمية تتجاوز المتاح للمرتجع.', 'Return quantity exceeds the remaining quantity.')}');
        }
        final amount = _amountForQuantity(item, quantity);
        if (amount <= 0) {
          throw StateError(
              '${item.description}: ${tr(context, 'قيمة المرتجع يجب أن تكون أكبر من صفر.', 'Return amount must be greater than zero.')}');
        }
        lines.add(PurchaseLine(
          description: item.description,
          quantityMilli: quantity,
          unitName: item.unitName,
          unitPriceMinor: item.unitPriceMinor,
          sourceInvoiceItemId: item.id,
          totalOverrideMinor: amount,
        ));
      }
      if (lines.isEmpty) {
        throw StateError(tr(context, 'حدد صنفاً واحداً على الأقل للمرتجع.',
            'Select at least one item to return.'));
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      await ref.read(purchaseRepositoryProvider).recordPurchaseReturn(
            supplierId: widget.supplierId,
            invoiceId: detail.id,
            returnNumber: _returnNumber.text.trim(),
            returnDate: _returnDate.text.trim(),
            currency: detail.currency,
            lines: lines,
            notes: _notes.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
