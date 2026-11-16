import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/attachments/attachment_service.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money.dart';
import '../domain/purchase_line.dart';

class PurchaseEntryDialog extends ConsumerStatefulWidget {
  const PurchaseEntryDialog(
      {super.key, required this.isCredit, this.initialSupplierId});

  final bool isCredit;
  final int? initialSupplierId;

  @override
  ConsumerState<PurchaseEntryDialog> createState() =>
      _PurchaseEntryDialogState();
}

class _PurchaseEntryDialogState extends ConsumerState<PurchaseEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceNumber = TextEditingController();
  final _sellerName = TextEditingController();
  final _date = TextEditingController(text: _today());
  final _dueDate = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _notes = TextEditingController();
  final List<_LineDraft> _lines = [_LineDraft()];
  int? _supplierId;
  int? _branchId;
  int? _employeeId;
  DateTime _receivedAt = DateTime.now();
  AttachmentDraft? _attachment;
  String _currency = 'YER';
  String _paymentMethod = 'cash';
  bool _currencyChanged = false;
  bool _saving = false;
  String? _error;

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _supplierId = widget.initialSupplierId;
    ref.read(businessProfileProvider.future).then((profile) {
      final currency = profile?['default_currency'] as String?;
      if (mounted &&
          !_currencyChanged &&
          currency != null &&
          ['YER', 'SAR', 'USD'].contains(currency)) {
        setState(() => _currency = currency);
      }
    });
  }

  @override
  void dispose() {
    _invoiceNumber.dispose();
    _sellerName.dispose();
    _date.dispose();
    _dueDate.dispose();
    _paid.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);
    return AlertDialog(
      title: Text(widget.isCredit
          ? tr(context, 'فاتورة مشتريات آجلة', 'New credit invoice')
          : tr(context, 'عملية شراء يومية', 'New daily purchase')),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width > 720
            ? 620
            : MediaQuery.sizeOf(context).width * .78,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.isCredit) ...[
                  suppliersAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stack) => Text(tr(context,
                        'تعذر تحميل الموردين', 'Could not load suppliers')),
                    data: (suppliers) => DropdownButtonFormField<int>(
                      initialValue: _supplierId,
                      decoration: InputDecoration(
                          labelText: tr(context, 'المورد *', 'Supplier *')),
                      items: suppliers
                          .map((supplier) => DropdownMenuItem<int>(
                                value: supplier.id,
                                child: Text(supplier.name,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _supplierId = value;
                          final selected =
                              suppliers.where((s) => s.id == value).toList();
                          if (selected.isNotEmpty)
                            _currency = selected.first.defaultCurrency;
                          _currencyChanged = true;
                        });
                      },
                      validator: (value) => value == null
                          ? tr(context, 'اختر المورد', 'Select a supplier')
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _field(
                    controller: _invoiceNumber,
                    label: tr(context, 'رقم الفاتورة *', 'Invoice number *'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? tr(context, 'رقم الفاتورة مطلوب',
                            'Invoice number is required')
                        : null,
                  ),
                  const SizedBox(height: 9),
                  _directorySelectors(),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _chooseReceivedAt,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      '${tr(context, 'وقت استلام البضائع', 'Goods received at')}: ${_receivedAt.toLocal().toString().substring(0, 16)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickInvoiceImage,
                    icon: const Icon(Icons.attach_file),
                    label: Text(_attachment == null
                        ? tr(context, 'إرفاق صورة الفاتورة (اختياري)',
                            'Attach invoice image (optional)')
                        : tr(context, 'تم إرفاق صورة الفاتورة',
                            'Invoice image attached')),
                  ),
                  if (_attachment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_attachment!.filePath),
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                ] else
                  _field(
                      controller: _sellerName,
                      label: tr(context, 'اسم البائع أو المحل',
                          'Seller / shop name')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _field(
                            controller: _date,
                            label: tr(context, 'تاريخ العملية *',
                                'Transaction date *'),
                            validator: _dateValidator)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: InputDecoration(
                            labelText: tr(context, 'العملة', 'Currency')),
                        items: const [
                          DropdownMenuItem(value: 'YER', child: Text('YER')),
                          DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                        ],
                        onChanged: (value) => setState(() {
                          _currency = value ?? 'YER';
                          _currencyChanged = true;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _field(
                    controller: _dueDate,
                    label: tr(context, 'تاريخ الاستحقاق (اختياري)',
                        'Due date (optional)'),
                    validator: _optionalDateValidator),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(tr(context, 'الأصناف', 'Items'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _lines.add(_LineDraft())),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr(context, 'إضافة صنف', 'Add item')),
                    ),
                  ],
                ),
                ..._lines
                    .asMap()
                    .entries
                    .map((entry) => _lineCard(entry.key, entry.value)),
                const SizedBox(height: 10),
                _field(
                  controller: _paid,
                  label: tr(context, 'المبلغ المدفوع الآن', 'Amount paid now'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _moneyValidator,
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: InputDecoration(
                      labelText: tr(context, 'طريقة الدفع', 'Payment method')),
                  items: [
                    DropdownMenuItem(
                        value: 'cash',
                        child: Text(tr(context, 'نقداً', 'Cash'))),
                    DropdownMenuItem(
                        value: 'bank_transfer',
                        child:
                            Text(tr(context, 'تحويل بنكي', 'Bank transfer'))),
                    DropdownMenuItem(
                        value: 'wallet',
                        child:
                            Text(tr(context, 'محفظة إلكترونية', 'E-wallet'))),
                    DropdownMenuItem(
                        value: 'cheque',
                        child: Text(tr(context, 'شيك', 'Cheque'))),
                    DropdownMenuItem(
                        value: 'other',
                        child: Text(tr(context, 'أخرى', 'Other'))),
                  ],
                  onChanged: (value) =>
                      setState(() => _paymentMethod = value ?? 'cash'),
                ),
                const SizedBox(height: 10),
                _field(
                    controller: _notes,
                    label: tr(context, 'ملاحظات', 'Notes'),
                    maxLines: 2),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(tr(context, 'إلغاء', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(tr(context, 'حفظ العملية', 'Save transaction')),
        ),
      ],
    );
  }

  Widget _directorySelectors() {
    final branchesAsync = ref.watch(branchesProvider);
    final employeesAsync = ref.watch(employeesProvider(_branchId));
    return Column(
      children: [
        branchesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) =>
              Text(tr(context, 'تعذر تحميل الفروع', 'Could not load branches')),
          data: (branches) => DropdownButtonFormField<int?>(
            initialValue: _branchId,
            decoration:
                InputDecoration(labelText: tr(context, 'الفرع', 'Branch')),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(tr(context, 'غير محدد', 'Not specified')),
              ),
              ...branches.map((branch) => DropdownMenuItem<int?>(
                    value: branch['id'] as int,
                    child: Text(branch['name'] as String),
                  )),
            ],
            onChanged: (value) => setState(() {
              _branchId = value;
              _employeeId = null;
            }),
          ),
        ),
        const SizedBox(height: 8),
        employeesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => Text(
              tr(context, 'تعذر تحميل الموظفين', 'Could not load employees')),
          data: (employees) => DropdownButtonFormField<int?>(
            initialValue: _employeeId,
            decoration: InputDecoration(
                labelText:
                    tr(context, 'مسؤول المشتريات', 'Purchasing officer')),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(tr(context, 'غير محدد', 'Not specified')),
              ),
              ...employees.map((employee) => DropdownMenuItem<int?>(
                    value: employee['id'] as int,
                    child: Text(employee['name'] as String),
                  )),
            ],
            onChanged: (value) => setState(() => _employeeId = value),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseReceivedAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _receivedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_receivedAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _receivedAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickInvoiceImage() async {
    try {
      final draft = await AttachmentService.pickImage();
      if (mounted && draft != null) setState(() => _attachment = draft);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Widget _lineCard(int index, _LineDraft line) {
    return Card(
      key: ObjectKey(line),
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('${tr(context, 'الصنف', 'Item')} ${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                if (_lines.length > 1)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr(context, 'حذف الصنف', 'Remove item'),
                    onPressed: () {
                      setState(() {
                        final removed = _lines.removeAt(index);
                        // The old TextFormField subtree stays mounted until
                        // this frame ends; dispose after it is unmounted.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          removed.dispose();
                        });
                      });
                    },
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                  ),
              ],
            ),
            _field(
              controller: line.name,
              label: tr(context, 'اسم الصنف *', 'Item name *'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? tr(context, 'اسم الصنف مطلوب', 'Item name is required')
                  : null,
            ),
            const SizedBox(height: 8),
            if (widget.isCredit) ...[
              _creditUnitSelector(line),
              const SizedBox(height: 8),
              _field(
                controller: line.quantity,
                label: tr(context, 'الكمية', 'Quantity'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _quantityValidator,
              ),
              const SizedBox(height: 8),
              _field(
                controller: line.price,
                label: tr(context, 'سعر الوحدة', 'Unit price'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _moneyValidator,
              ),
            ] else Row(
              children: [
                Expanded(
                    child: _field(
                        controller: line.quantity,
                        label: tr(context, 'الكمية', 'Quantity'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _quantityValidator)),
                const SizedBox(width: 7),
                Expanded(
                  child: _field(
                          controller: line.unit,
                          label: tr(context, 'الوحدة', 'Unit'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? tr(context, 'مطلوب', 'Required')
                              : null),
                ),
                const SizedBox(width: 7),
                Expanded(
                    child: _field(
                        controller: line.price,
                        label: tr(context, 'سعر الوحدة', 'Unit price'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _moneyValidator)),
              ],
            ),
            if (!widget.isCredit) ...[
              const SizedBox(height: 8),
              Row(
              children: [
                Expanded(
                    child: _field(
                        controller: line.discount,
                        label: tr(context, 'الخصم', 'Discount'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _moneyValidator)),
                const SizedBox(width: 7),
                Expanded(
                    child: _field(
                        controller: line.tax,
                        label: tr(context, 'الضريبة', 'Tax'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _moneyValidator)),
              ],
            ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _creditUnitSelector(_LineDraft line) {
    final units = ref.watch(creditMeasurementUnitsProvider);
    return units.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stack) => Text(
          tr(context, 'تعذر تحميل الوحدات', 'Unable to load units')),
      data: (rows) {
        final names = rows.map((r) => r['name'] as String).toList();
        return Column(children: [DropdownButtonFormField<String>(
          key: ValueKey('credit-unit-${line.hashCode}-${line.unit.text}'),
          initialValue: names.contains(line.unit.text) ? line.unit.text : null,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: tr(context, 'الوحدة *', 'Unit *')),
          items: names.map((name) => DropdownMenuItem<String>(
                value: name,
                child: Text(name, overflow: TextOverflow.ellipsis),
              )).toList(),
          onChanged: (value) => setState(() => line.unit.text = value ?? ''),
          validator: (_) => line.unit.text.trim().isEmpty
              ? tr(context, 'اختر وحدة من الإعدادات', 'Select a saved unit')
              : null,
        ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _addCreditUnit(line),
              icon: const Icon(Icons.add_circle_outline),
              label: Text(tr(context, 'إضافة وحدة جديدة', 'Add a new unit')),
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _addCreditUnit(_LineDraft line) async {
    var proposed = '';
    final name = await showDialog<String>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'إضافة وحدة مشتريات آجلة', 'Add a credit-purchase unit')),
        content: TextField(autofocus: true, onChanged: (v) => proposed = v,
          decoration: InputDecoration(labelText: tr(context, 'اسم الوحدة', 'Unit name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr(context, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, proposed.trim()),
            child: Text(tr(context, 'حفظ', 'Save'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await ref.read(measurementUnitRepositoryProvider).create('credit', name);
      ref.invalidate(creditMeasurementUnitsProvider);
      if (mounted) setState(() => line.unit.text = name.trim());
    } catch (error) {
      if (mounted) setState(() => _error =
          '${tr(context, 'تعذر حفظ الوحدة', 'Could not save the unit')}: $error');
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, isDense: true),
      );

  bool _isValidDateOnly(String value) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
        DateTime.tryParse(value) != null;
  }

  String? _dateValidator(String? value) {
    if (value == null || !_isValidDateOnly(value.trim())) {
      return tr(context, 'أدخل التاريخ بصيغة YYYY-MM-DD',
          'Use YYYY-MM-DD date format');
    }
    return null;
  }

  String? _optionalDateValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return !_isValidDateOnly(value.trim())
        ? tr(context, 'صيغة التاريخ غير صحيحة', 'Use YYYY-MM-DD date format')
        : null;
  }

  String? _moneyValidator(String? value) {
    try {
      final parsed = Money.parseMinor(value ?? '0');
      if (parsed < 0)
        return tr(context, 'لا يمكن أن تكون القيمة سالبة',
            'Value cannot be negative');
      return null;
    } on FormatException {
      return tr(context, 'أدخل مبلغاً صحيحاً', 'Enter a valid amount');
    }
  }

  String? _quantityValidator(String? value) {
    try {
      if (_parseQuantityMilli(value ?? '') <= 0)
        return tr(context, 'الكمية يجب أن تكون أكبر من صفر',
            'Quantity must be positive');
      return null;
    } catch (_) {
      return tr(context, 'أدخل كمية صحيحة (حتى 3 منازل عشرية)',
          'Enter a valid quantity (up to 3 decimals)');
    }
  }

  int _parseQuantityMilli(String input) {
    var normalized = input.trim().replaceAll('٫', '.');
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(arabicDigits[i], '$i');
      normalized = normalized.replaceAll(persianDigits[i], '$i');
    }
    final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(normalized);
    if (match == null) throw const FormatException('Invalid quantity');
    final whole = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(3, '0');
    return whole * 1000 + (fraction.isEmpty ? 0 : int.parse(fraction));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (widget.isCredit && _supplierId == null) {
      setState(() =>
          _error = tr(context, 'يجب اختيار المورد.', 'Select a supplier.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final lines = _lines
          .map((line) => PurchaseLine(
                description: line.name.text.trim(),
                quantityMilli: _parseQuantityMilli(line.quantity.text),
                unitName: line.unit.text.trim(),
                unitPriceMinor: Money.parseMinor(line.price.text),
                discountMinor: Money.parseMinor(line.discount.text),
                taxMinor: Money.parseMinor(line.tax.text),
              ))
          .toList(growable: false);
      final paid = Money.parseMinor(_paid.text);
      final repository = ref.read(purchaseRepositoryProvider);
      if (widget.isCredit) {
        await repository.createCreditInvoice(
          supplierId: _supplierId!,
          invoiceNumber: _invoiceNumber.text,
          invoiceDate: _date.text.trim(),
          dueDate: _dueDate.text.trim().isEmpty ? null : _dueDate.text.trim(),
          currency: _currency,
          lines: lines,
          paidMinor: paid,
          initialPaymentMethod: _paymentMethod,
          notes: _notes.text,
          branchId: _branchId,
          employeeId: _employeeId,
          receivedAt: _receivedAt.toIso8601String(),
          attachment: _attachment,
        );
        ref.invalidate(creditInvoicesProvider);
        ref.invalidate(suppliersProvider);
        ref.invalidate(supplierDashboardProvider);
      } else {
        await repository.createDailyPurchase(
          purchaseDate: _date.text.trim(),
          sellerName: _sellerName.text,
          currency: _currency,
          lines: lines,
          paidMinor: paid,
          paymentMethod: _paymentMethod,
          dueDate: _dueDate.text.trim().isEmpty ? null : _dueDate.text.trim(),
          notes: _notes.text,
        );
        ref.invalidate(dailyPurchasesProvider);
      }
      ref.invalidate(dashboardProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LineDraft {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unit = TextEditingController(text: 'قطعة');
  final price = TextEditingController(text: '0');
  final discount = TextEditingController(text: '0');
  final tax = TextEditingController(text: '0');

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    price.dispose();
    discount.dispose();
    tax.dispose();
  }
}
