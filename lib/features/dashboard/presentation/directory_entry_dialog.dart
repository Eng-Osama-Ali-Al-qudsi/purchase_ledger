import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';

/// Owns all text controllers until the dialog route is actually disposed.
/// This also makes cancelling during the route's exit animation safe.
class DirectoryEntryDialog extends ConsumerStatefulWidget {
  const DirectoryEntryDialog({super.key, required this.kind, this.record});

  final String kind;
  final Map<String, Object?>? record;

  @override
  ConsumerState<DirectoryEntryDialog> createState() =>
      _DirectoryEntryDialogState();
}

class _DirectoryEntryDialogState extends ConsumerState<DirectoryEntryDialog> {
  late final _name = TextEditingController(text: _value('name'));
  late final _code = TextEditingController(text: _value('code'));
  late final _address = TextEditingController(text: _value('address'));
  late final _phone = TextEditingController(text: _value('phone'));
  late final _role = TextEditingController(text: _value('role'));
  late final _sku = TextEditingController(text: _value('sku'));
  final _formKey = GlobalKey<FormState>();
  late int? _branchId = widget.record?['branch_id'] as int?;
  late int? _categoryId = widget.record?['category_id'] as int?;
  late String _categoryType =
      widget.record?['category_type'] as String? ?? 'both';
  bool _saving = false;
  String? _error;

  String _value(String key) => widget.record?[key]?.toString() ?? '';

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    _phone.dispose();
    _role.dispose();
    _sku.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.record != null;
    final label = switch (widget.kind) {
      'branch' => tr(context, 'فرع', 'branch'),
      'employee' => tr(context, 'موظف', 'employee'),
      'category' => tr(context, 'تصنيف', 'category'),
      _ => tr(context, 'صنف', 'product'),
    };
    return AlertDialog(
      scrollable: true,
      title: Text('${isEdit ? tr(context, 'تعديل', 'Edit') : tr(context, 'إضافة', 'Add')} $label'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: '${tr(context, 'الاسم', 'Name')} *'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? tr(context, 'الاسم مطلوب', 'Name is required')
                    : null,
              ),
              const SizedBox(height: 10),
              if (widget.kind == 'branch') ...[
                _field(_code, tr(context, 'رقم الفرع', 'Branch code')),
                const SizedBox(height: 10),
                _field(_address, tr(context, 'العنوان', 'Address')),
                const SizedBox(height: 10),
                _field(_phone, tr(context, 'الهاتف', 'Phone'),
                    keyboardType: TextInputType.phone),
              ],
              if (widget.kind == 'employee') ...[
                _field(_phone, tr(context, 'الهاتف', 'Phone'),
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 10),
                _field(_role, tr(context, 'المسمى الوظيفي', 'Role')),
                const SizedBox(height: 10),
                _branchSelector(),
              ],
              if (widget.kind == 'category')
                DropdownButtonFormField<String>(
                  key: ValueKey(_categoryType),
                  initialValue: _categoryType,
                  decoration: InputDecoration(
                      labelText: tr(context, 'نوع الاستخدام', 'Usage')),
                  items: [
                    DropdownMenuItem(
                        value: 'both',
                        child: Text(tr(context, 'كلا النوعين', 'Both'))),
                    DropdownMenuItem(
                        value: 'daily',
                        child: Text(tr(context, 'المشتريات اليومية', 'Daily'))),
                    DropdownMenuItem(
                        value: 'credit',
                        child: Text(tr(context, 'المشتريات الآجلة', 'Credit'))),
                  ],
                  onChanged: (value) =>
                      setState(() => _categoryType = value ?? 'both'),
                ),
              if (widget.kind == 'product') ...[
                _field(_sku, tr(context, 'رمز الصنف', 'SKU')),
                const SizedBox(height: 10),
                _categorySelector(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(tr(context, 'إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving
              ? tr(context, 'جارٍ الحفظ…', 'Saving…')
              : tr(context, 'حفظ', 'Save')),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _branchSelector() {
    final branches = ref.watch(branchesProvider);
    return branches.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stack) => Text(error.toString()),
      data: (rows) {
        final options = [...rows];
        if (_branchId != null && !options.any((r) => r['id'] == _branchId)) {
          options.add({
            'id': _branchId,
            'name': tr(context, 'فرع مؤرشف', 'Archived branch'),
          });
        }
        return DropdownButtonFormField<int?>(
          key: ValueKey('branch-$_branchId'),
          initialValue: _branchId,
          decoration: InputDecoration(labelText: tr(context, 'الفرع', 'Branch')),
          items: [
            DropdownMenuItem<int?>(
                value: null, child: Text(tr(context, 'غير محدد', 'None'))),
            ...options.map((row) => DropdownMenuItem<int?>(
                  value: row['id'] as int,
                  child: Text(row['name'] as String,
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (value) => setState(() => _branchId = value),
        );
      },
    );
  }

  Widget _categorySelector() {
    final categories = ref.watch(purchaseCategoriesProvider);
    return categories.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, stack) => Text(error.toString()),
      data: (rows) {
        final options = [...rows];
        if (_categoryId != null && !options.any((r) => r['id'] == _categoryId)) {
          options.add({
            'id': _categoryId,
            'name': tr(context, 'تصنيف مؤرشف', 'Archived category'),
          });
        }
        return DropdownButtonFormField<int?>(
          key: ValueKey('category-$_categoryId'),
          initialValue: _categoryId,
          decoration: InputDecoration(
              labelText: tr(context, 'التصنيف', 'Category')),
          items: [
            DropdownMenuItem<int?>(
                value: null, child: Text(tr(context, 'بدون تصنيف', 'None'))),
            ...options.map((row) => DropdownMenuItem<int?>(
                  value: row['id'] as int,
                  child: Text(row['name'] as String,
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (value) => setState(() => _categoryId = value),
        );
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(businessDirectoryRepositoryProvider);
      final id = widget.record?['id'] as int?;
      switch (widget.kind) {
        case 'branch':
          if (id == null) {
            await repo.createBranch(
                name: _name.text, code: _code.text,
                address: _address.text, phone: _phone.text);
          } else {
            await repo.updateBranch(
                id: id, name: _name.text, code: _code.text,
                address: _address.text, phone: _phone.text);
          }
          break;
        case 'employee':
          if (id == null) {
            await repo.createEmployee(
                name: _name.text, phone: _phone.text,
                role: _role.text, branchId: _branchId);
          } else {
            await repo.updateEmployee(
                id: id, name: _name.text, phone: _phone.text,
                role: _role.text, branchId: _branchId);
          }
          break;
        case 'category':
          if (id == null) {
            await repo.createCategory(
                name: _name.text, categoryType: _categoryType);
          } else {
            await repo.updateCategory(
                id: id, name: _name.text, categoryType: _categoryType);
          }
          break;
        case 'product':
          if (id == null) {
            await repo.createProduct(
                name: _name.text, sku: _sku.text, categoryId: _categoryId);
          } else {
            await repo.updateProduct(
                id: id, name: _name.text,
                sku: _sku.text, categoryId: _categoryId);
          }
          break;
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
