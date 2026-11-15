import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/attachments/attachment_service.dart';
import '../../../core/localization/app_strings.dart';

class BusinessProfileDialog extends ConsumerStatefulWidget {
  const BusinessProfileDialog({super.key, this.profile});
  final Map<String, Object?>? profile;

  @override
  ConsumerState<BusinessProfileDialog> createState() =>
      _BusinessProfileDialogState();
}

class _BusinessProfileDialogState extends ConsumerState<BusinessProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _shopName = TextEditingController(
      text: widget.profile?['shop_name'] as String? ?? '');
  late final _commercial = TextEditingController(
      text: widget.profile?['commercial_number'] as String? ?? '');
  late final _shopNumber = TextEditingController(
      text: widget.profile?['shop_number'] as String? ?? '');
  late final _owner = TextEditingController(
      text: widget.profile?['owner_name'] as String? ?? '');
  late final _manager = TextEditingController(
      text: widget.profile?['manager_name'] as String? ?? '');
  late final _buyer = TextEditingController(
      text: widget.profile?['buyer_name'] as String? ?? '');
  late final _phone =
      TextEditingController(text: widget.profile?['phone'] as String? ?? '');
  late final _address =
      TextEditingController(text: widget.profile?['address'] as String? ?? '');
  late final _city =
      TextEditingController(text: widget.profile?['city'] as String? ?? '');
  String _currency = 'YER';
  String? _logoPath;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currency = widget.profile?['default_currency'] as String? ?? 'YER';
    _logoPath = widget.profile?['logo_path'] as String?;
  }

  @override
  void dispose() {
    _shopName.dispose();
    _commercial.dispose();
    _shopNumber.dispose();
    _owner.dispose();
    _manager.dispose();
    _buyer.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'بيانات المحل', 'Business profile')),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width > 600
              ? 520
              : MediaQuery.sizeOf(context).width * .78,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickLogo,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                        tr(context, 'اختيار شعار المحل', 'Choose shop logo')),
                  ),
                  if (_logoPath != null && File(_logoPath!).existsSync())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Center(
                        child: Image.file(File(_logoPath!),
                            height: 72, fit: BoxFit.contain),
                      ),
                    ),
                  _input(_shopName, tr(context, 'اسم المحل *', 'Shop name *'),
                      required: true),
                  const SizedBox(height: 8),
                  _input(_commercial,
                      tr(context, 'الرقم التجاري', 'Commercial number')),
                  const SizedBox(height: 8),
                  _input(_shopNumber, tr(context, 'رقم المحل', 'Shop number')),
                  const SizedBox(height: 8),
                  _input(_owner, tr(context, 'اسم المالك', 'Owner name')),
                  const SizedBox(height: 8),
                  _input(_manager, tr(context, 'اسم المدير', 'Manager name')),
                  const SizedBox(height: 8),
                  _input(_buyer,
                      tr(context, 'مسؤول المشتريات', 'Purchasing officer')),
                  const SizedBox(height: 8),
                  _input(_phone, tr(context, 'رقم الهاتف', 'Phone number'),
                      keyboard: TextInputType.phone),
                  const SizedBox(height: 8),
                  _input(_address, tr(context, 'العنوان', 'Address')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: _input(_city, tr(context, 'المدينة', 'City'))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          decoration: InputDecoration(
                              labelText: tr(context, 'العملة الافتراضية',
                                  'Default currency')),
                          items: const [
                            DropdownMenuItem(value: 'YER', child: Text('YER')),
                            DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                          ],
                          onChanged: (value) =>
                              setState(() => _currency = value ?? 'YER'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(tr(context, 'إغلاق', 'Close'))),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(tr(context, 'حفظ البيانات', 'Save profile'))),
        ],
      );

  Widget _input(TextEditingController controller, String label,
          {bool required = false, TextInputType? keyboard}) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboard,
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? tr(context, 'هذا الحقل مطلوب', 'This field is required')
                : null
            : null,
        decoration: InputDecoration(labelText: label, isDense: true),
      );

  Future<void> _pickLogo() async {
    try {
      final draft = await AttachmentService.pickImage();
      if (mounted && draft != null) setState(() => _logoPath = draft.filePath);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(businessProfileRepositoryProvider).saveProfile(
            shopName: _shopName.text,
            commercialNumber: _commercial.text,
            shopNumber: _shopNumber.text,
            logoPath: _logoPath,
            ownerName: _owner.text,
            managerName: _manager.text,
            buyerName: _buyer.text,
            phone: _phone.text,
            address: _address.text,
            city: _city.text,
            defaultCurrency: _currency,
          );
      ref.invalidate(businessProfileProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
