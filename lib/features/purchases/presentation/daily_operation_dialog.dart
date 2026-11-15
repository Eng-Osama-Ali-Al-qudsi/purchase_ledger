import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/attachments/attachment_service.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/money.dart';
import '../domain/daily_sheet_models.dart';
import '../domain/purchase_line.dart';

class DailyOperationDialog extends ConsumerStatefulWidget {
  const DailyOperationDialog({
    super.key,
    required this.sheetId,
    this.operation,
  });

  final int sheetId;
  final DailyPurchaseOperation? operation;

  @override
  ConsumerState<DailyOperationDialog> createState() =>
      _DailyOperationDialogState();
}

class _DailyOperationDialogState extends ConsumerState<DailyOperationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final List<_DailyLineDraft> _lines = [];
  int? _supplierId;
  int? _responsiblePersonId;
  late Future<List<Map<String, Object?>>> _peopleFuture;
  String _currency = 'YER';
  String _mode = 'cash';
  String _independentPayment = 'outstanding';
  String _paymentMethod = 'cash';
  AttachmentDraft? _attachment;
  bool _saving = false;
  String? _error;
  late final String _idempotencyKey;

  bool get _isEditing => widget.operation != null;

  @override
  void initState() {
    super.initState();
    _peopleFuture = ref.read(dailyPurchasesRepositoryProvider)
        .getResponsiblePeople();
    _idempotencyKey =
        'daily-operation-${widget.sheetId}-${DateTime.now().microsecondsSinceEpoch}';
    final operation = widget.operation;
    if (operation != null) {
      _notes.text = operation.notes ?? '';
      _supplierId = operation.supplierId;
      _currency = operation.currency;
      _mode = operation.accountingMode;
      _paymentMethod = operation.paymentMethod;
      _lines.addAll(operation.items.map(_DailyLineDraft.fromItem));
    }
    if (_lines.isEmpty) _lines.add(_DailyLineDraft());
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);
    final categoriesAsync = ref.watch(dailyPurchaseCategoriesProvider);
    final needsSupplier = _mode == 'supplier_account' ||
        (_mode == 'daily_outstanding' && _independentPayment == 'credit');
    final fullyPaid = _mode == 'cash' ||
        (_mode == 'daily_outstanding' && _independentPayment == 'cash');
    return AlertDialog(
      title: Text(_isEditing ? 'تعديل أصناف العملية' : 'إضافة عملية شراء'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width > 760
            ? 700 : MediaQuery.sizeOf(context).width * .86,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isEditing)
                  Text('${widget.operation!.operationNumber} • ${widget.operation!.currency}',
                    style: const TextStyle(fontWeight: FontWeight.w900))
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _mode,
                    decoration: const InputDecoration(labelText: 'نوع العملية'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('شراء نقدي بالكامل')),
                      DropdownMenuItem(value: 'supplier_account', child: Text('شراء آجل من مورد مسجل')),
                      DropdownMenuItem(value: 'person_account', child: Text('شراء على حساب شخص')),
                      DropdownMenuItem(value: 'daily_outstanding', child: Text('مستحق يومي مستقل')),
                    ],
                    onChanged: (v) => setState(() { _mode = v ?? 'cash'; _supplierId = null; }),
                  ),
                  if (_mode == 'daily_outstanding') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _independentPayment,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'طريقة تسوية المستحق'),
                      items: const [
                        DropdownMenuItem(value: 'outstanding',
                          child: Text('مستحق مستقل غير مسدد (بدون مورد)',
                            overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'cash', child: Text('نقدي، مسدد بالكامل')),
                        DropdownMenuItem(value: 'credit', child: Text('آجل، على مورد محدد')),
                      ],
                      onChanged: (v) => setState(() {
                        _independentPayment = v ?? 'outstanding'; _supplierId = null;
                      }),
                    ),
                  ],
                  if (_mode == 'person_account') ...[
                    const SizedBox(height: 8),
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: _peopleFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('تعذر تحميل الأشخاص: ${snapshot.error}');
                        }
                        if (!snapshot.hasData) {
                          return const LinearProgressIndicator();
                        }
                        final people = snapshot.data!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<int>(
                              key: ValueKey('person-$_responsiblePersonId'),
                              initialValue: people.any((p) =>
                                  p['id'] == _responsiblePersonId)
                                  ? _responsiblePersonId : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'حساب الشخص المسؤول *'),
                              items: people.map((p) => DropdownMenuItem<int>(
                                value: p['id'] as int,
                                child: Text('${p['name']}',
                                    overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (value) => setState(
                                  () => _responsiblePersonId = value),
                              validator: (value) => value == null
                                  ? 'اختر حساب شخص مسجل' : null,
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                onPressed: _saving ? null : _createPerson,
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text('إضافة حساب شخص جديد'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (needsSupplier) ...[
                    const SizedBox(height: 8),
                    suppliersAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('تعذر تحميل الموردين'),
                      data: (suppliers) => DropdownButtonFormField<int>(
                        initialValue: _supplierId,
                        decoration: const InputDecoration(labelText: 'المورد *'),
                        items: suppliers.map((supplier) => DropdownMenuItem<int>(
                          value: supplier.id, child: Text(supplier.name),
                        )).toList(),
                        onChanged: (value) => setState(() => _supplierId = value),
                        validator: (value) => value == null ? 'اختر المورد' : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: 'العملة'),
                    items: const [
                      DropdownMenuItem(value: 'YER', child: Text('YER')),
                      DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) => setState(() => _currency = v ?? 'YER'),
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  const Expanded(child: Text('أصناف العملية',
                    style: TextStyle(fontWeight: FontWeight.w900))),
                  TextButton.icon(
                    onPressed: _saving ? null : () => setState(() => _lines.add(_DailyLineDraft())),
                    icon: const Icon(Icons.add), label: const Text('إضافة صنف'),
                  ),
                ]),
                ..._lines.asMap().entries.map((entry) =>
                  _lineCard(entry.key, entry.value, categoriesAsync)),
                if (_isEditing || fullyPaid) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'وسيلة الدفع'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('نقداً')),
                      DropdownMenuItem(value: 'bank_transfer', child: Text('تحويل بنكي')),
                      DropdownMenuItem(value: 'wallet', child: Text('محفظة')),
                      DropdownMenuItem(value: 'cheque', child: Text('شيك')),
                      DropdownMenuItem(value: 'other', child: Text('أخرى')),
                      DropdownMenuItem(value: 'unspecified', child: Text('غير محدد')),
                    ],
                    onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
                  ),
                ],
                if (!_isEditing) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickReceipt,
                    icon: const Icon(Icons.attach_file),
                    label: Text(_attachment == null ? 'إرفاق فاتورة أو إيصال'
                        : 'تم إرفاق الصورة'),
                  ),
                  if (_attachment != null)
                    Image.file(File(_attachment!.filePath), height: 88, fit: BoxFit.contain),
                ],
                const SizedBox(height: 8),
                TextFormField(controller: _notes, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'ملاحظات عامة')),
                const SizedBox(height: 8),
                _totalPreview(),
                if (_error != null) Text(_error!,
                  style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء')),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save_outlined),
          label: Text(_isEditing ? 'حفظ التعديلات' : 'حفظ العملية'),
        ),
      ],
    );
  }

  Widget _dailyUnitSelector(_DailyLineDraft line) {
    final units = ref.watch(dailyMeasurementUnitsProvider);
    return units.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const Text('تعذر تحميل الوحدات'),
      data: (rows) {
        final names = rows.map((r) => r['name'] as String).toList();
        final selected = names.contains(line.unit.text) ? line.unit.text : null;
        return Column(children: [
          DropdownButtonFormField<String>(
            key: ValueKey('daily-unit-${line.hashCode}-$selected'),
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الوحدة'),
            items: names.map((name) => DropdownMenuItem(
              value: name, child: Text(name, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (value) => setState(() => line.unit.text = value ?? ''),
            validator: (_) => line.unit.text.trim().isEmpty ? 'الوحدة مطلوبة' : null,
          ),
          TextButton(onPressed: () => _addUnit(line), child: const Text('وحدة جديدة +')),
        ]);
      },
    );
  }

  Future<void> _addUnit(_DailyLineDraft line) async {
    var proposed = '';
    final value = await showDialog<String>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة وحدة يومية'),
        content: TextField(autofocus: true, onChanged: (text) => proposed = text,
          decoration: const InputDecoration(labelText: 'اسم الوحدة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, proposed.trim()),
            child: const Text('إضافة')),
        ],
      ),
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    try {
      await ref.read(measurementUnitRepositoryProvider).create('daily', value);
      ref.invalidate(dailyMeasurementUnitsProvider);
      if (mounted) setState(() => line.unit.text = value.trim());
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر حفظ الوحدة: $error');
    }
  }

  Widget _lineCard(
    int index,
    _DailyLineDraft line,
    AsyncValue<List<Map<String, Object?>>> categoriesAsync,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${tr(context, 'الصنف', 'Item')} ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (_lines.length > 1)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _lines.removeAt(index).dispose()),
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                  ),
              ],
            ),
            TextFormField(
              controller: line.name,
              decoration: InputDecoration(
                  labelText: tr(context, 'اسم المادة *', 'Item name *')),
              validator: (value) => value == null || value.trim().isEmpty
                  ? tr(context, 'اسم المادة مطلوب', 'Item name is required')
                  : null,
            ),
            const SizedBox(height: 7),
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stack) => const SizedBox.shrink(),
              data: (categories) => DropdownButtonFormField<int?>(
                initialValue: line.categoryId,
                decoration: InputDecoration(
                    labelText: tr(context, 'التصنيف', 'Category')),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(tr(context, 'بدون تصنيف', 'No category')),
                  ),
                  ...categories.map((category) => DropdownMenuItem<int?>(
                        value: category['id'] as int,
                        child: Text(category['name'] as String),
                      )),
                ],
                onChanged: (value) => setState(() => line.categoryId = value),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: line.quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: tr(context, 'الكمية', 'Quantity')),
                    validator: _quantityValidator,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextFormField(
                    controller: line.price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: tr(context, 'سعر الوحدة', 'Unit price')),
                    validator: _moneyValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _dailyUnitSelector(line),
          ],
        ),
      ),
    );
  }

  Widget _totalPreview() {
    var total = 0;
    try {
      for (final line in _lines) {
        total += line.toPurchaseLine().totalMinor;
      }
    } catch (_) {}
    return Card(
      color:
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .28),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Row(
          children: [
            Expanded(
              child: Text(tr(context, 'إجمالي العملية', 'Operation total'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            Text(
                Money.format(total, _currency,
                    locale: Localizations.localeOf(context).languageCode),
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ],
        ),
      ),
    );
  }

  String? _moneyValidator(String? value) {
    try {
      if (Money.parseMinor(value ?? '0') < 0) {
        return tr(context, 'لا يمكن أن تكون القيمة سالبة',
            'Value cannot be negative');
      }
      return null;
    } catch (_) {
      return tr(context, 'أدخل مبلغاً صحيحاً', 'Enter a valid amount');
    }
  }

  String? _quantityValidator(String? value) {
    try {
      if (_parseQuantityMilli(value ?? '') <= 0) {
        return tr(context, 'الكمية يجب أن تكون أكبر من صفر',
            'Quantity must be positive');
      }
      return null;
    } catch (_) {
      return tr(context, 'أدخل كمية صحيحة حتى 3 منازل عشرية',
          'Enter a valid quantity up to 3 decimals');
    }
  }

  Future<void> _pickReceipt() async {
    try {
      final draft = await AttachmentService.pickImage();
      if (mounted && draft != null) setState(() => _attachment = draft);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _createPerson() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewResponsiblePersonDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final repo = ref.read(dailyPurchasesRepositoryProvider);
      final id = await repo.createResponsiblePerson(name);
      if (!mounted) return;
      setState(() {
        _responsiblePersonId = id;
        _peopleFuture = repo.getResponsiblePeople();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_isEditing && _mode == 'person_account' &&
        _responsiblePersonId == null) {
      setState(() => _error = 'اختر حساب الشخص المسؤول أولاً.');
      return;
    }
    if (!_isEditing && (_mode == 'supplier_account' ||
        (_mode == 'daily_outstanding' && _independentPayment == 'credit')) &&
        _supplierId == null) {
      setState(() => _error =
          tr(context, 'اختر المورد المسجل.', 'Select a registered supplier.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final lines =
          _lines.map((line) => line.toPurchaseLine()).toList(growable: false);
      final repository = ref.read(dailyPurchasesRepositoryProvider);
      if (_isEditing) {
        await repository.updateOperationItems(
          operationId: widget.operation!.id,
          lines: lines,
          paymentMethod: _paymentMethod,
          notes: _notes.text,
        );
      } else {
        await repository.createOperation(
          sheetId: widget.sheetId,
          currency: _currency,
          lines: lines,
          sellerName: null,
          supplierId: (_mode == 'supplier_account' ||
              (_mode == 'daily_outstanding' && _independentPayment == 'credit'))
              ? _supplierId : null,
          accountingMode: (_mode == 'supplier_account' ||
              (_mode == 'daily_outstanding' && _independentPayment == 'credit'))
              ? 'supplier_account' : 'daily_outstanding',
          recordingCategory: _mode == 'person_account' ? 'person' :
              _mode == 'supplier_account' ? 'supplier' :
              _mode == 'cash' ? 'cash' : 'independent',
          responsiblePersonId: _mode == 'person_account'
              ? _responsiblePersonId : null,
          paidMinor: (_mode == 'cash' ||
              (_mode == 'daily_outstanding' && _independentPayment == 'cash'))
              ? lines.fold<int>(0, (sum, line) => sum + line.totalMinor) : 0,
          paymentMethod: _paymentMethod,
          dueDate: null,
          notes: _notes.text,
          attachment: _attachment,
          idempotencyKey: _idempotencyKey,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


}

class _NewResponsiblePersonDialog extends StatefulWidget {
  const _NewResponsiblePersonDialog();

  @override
  State<_NewResponsiblePersonDialog> createState() =>
      _NewResponsiblePersonDialogState();
}

class _NewResponsiblePersonDialogState
    extends State<_NewResponsiblePersonDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('إضافة حساب شخص'),
    content: TextField(
      autofocus: true,
      controller: _name,
      decoration: const InputDecoration(labelText: 'اسم الشخص *'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('رجوع')),
      FilledButton(onPressed: () {
        if (_name.text.trim().isNotEmpty) {
          Navigator.pop(context, _name.text.trim());
        }
      }, child: const Text('إضافة الحساب')),
    ],
  );
}

class _DailyLineDraft {
  _DailyLineDraft({
    String name = '',
    String quantity = '1',
    String unit = 'قطعة',
    String price = '0',
    String discount = '0',
    String tax = '0',
    this.categoryId,
    String seller = '',
    String notes = '',
  }) {
    this.name.text = name;
    this.quantity.text = quantity;
    this.unit.text = unit;
    this.price.text = price;
    this.discount.text = discount;
    this.tax.text = tax;
    this.seller.text = seller;
    this.notes.text = notes;
  }

  factory _DailyLineDraft.fromItem(DailyPurchaseItem item) {
    return _DailyLineDraft(
      name: item.itemName,
      quantity: Money.formatQuantity(item.quantityMilli),
      unit: item.unitName,
      price: _minorInput(item.unitPriceMinor),
      discount: _minorInput(item.discountMinor),
      tax: _minorInput(item.taxMinor),
      categoryId: item.categoryId,
      seller: item.sellerName ?? '',
      notes: item.notes ?? '',
    );
  }

  final name = TextEditingController();
  final quantity = TextEditingController();
  final unit = TextEditingController();
  final price = TextEditingController();
  final discount = TextEditingController();
  final tax = TextEditingController();
  final seller = TextEditingController();
  final notes = TextEditingController();
  int? categoryId;

  PurchaseLine toPurchaseLine() {
    final quantityMilli = _parseQuantityMilli(quantity.text);
    return PurchaseLine(
      description: name.text.trim(),
      quantityMilli: quantityMilli,
      unitName: unit.text.trim(),
      unitPriceMinor: Money.parseMinor(price.text),
      discountMinor: Money.parseMinor(discount.text),
      taxMinor: Money.parseMinor(tax.text),
      categoryId: categoryId,
      sellerName: seller.text,
      notes: notes.text,
    );
  }

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    price.dispose();
    discount.dispose();
    tax.dispose();
    seller.dispose();
    notes.dispose();
  }
}

String _minorInput(int minor) =>
    '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

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
  final fraction = (match.group(2) ?? '').padRight(3, '0');
  return int.parse(match.group(1)!) * 1000 +
      (fraction.isEmpty ? 0 : int.parse(fraction));
}
