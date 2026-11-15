import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../domain/supplier.dart';
import 'supplier_dashboard_screen.dart';
import 'confirm_excess_payment.dart';

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'سجل الموردين وحساباتهم',
                      'Supplier directory and balances'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openSupplierForm(context, ref),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: Text(tr(context, 'مورد جديد', 'Add supplier')),
              ),
            ],
          ),
        ),
        Expanded(
          child: suppliers.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _MessageState(
              icon: Icons.error_outline,
              title: tr(
                  context, 'تعذر تحميل الموردين', 'Could not load suppliers'),
              actionLabel: tr(context, 'إعادة المحاولة', 'Retry'),
              onAction: () => ref.invalidate(suppliersProvider),
            ),
            data: (items) => items.isEmpty
                ? _MessageState(
                    icon: Icons.storefront_outlined,
                    title: tr(
                        context, 'لا يوجد موردون حتى الآن', 'No suppliers yet'),
                    subtitle: tr(
                        context,
                        'أضف أول مورد لبدء تسجيل المشتريات الآجلة.',
                        'Add your first supplier to start recording credit purchases.'),
                    actionLabel: tr(context, 'إضافة مورد', 'Add supplier'),
                    onAction: () => _openSupplierForm(context, ref),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(suppliersProvider);
                      await ref.read(suppliersProvider.future);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, index) =>
                          _SupplierCard(supplier: items[index]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openSupplierForm(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
        context: context, builder: (_) => const _SupplierFormDialog());
    if (result == true) {
      ref.invalidate(suppliersProvider);
      ref.invalidate(dashboardProvider);
    }
  }
}

class _SupplierCard extends ConsumerWidget {
  const _SupplierCard({required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positive = supplier.balanceMinor > 0;
    final advance = supplier.balanceMinor < 0;
    final color = advance
        ? AppTheme.emerald
        : (positive
            ? AppTheme.amber
            : Theme.of(context).colorScheme.onSurfaceVariant);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SupplierDashboardScreen(supplierId: supplier.id),
        )),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.storefront_outlined,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(supplier.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        if ((supplier.companyName ?? '').isNotEmpty ||
                            (supplier.phone ?? '').isNotEmpty)
                          Text(
                            [
                              supplier.companyName,
                              supplier.phone,
                              supplier.activityType
                            ]
                                .whereType<String>()
                                .where((value) => value.isNotEmpty)
                                .join(' • '),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'payment') {
                        final result = await showDialog<bool>(
                          context: context,
                          builder: (_) =>
                              _SupplierPaymentDialog(supplier: supplier),
                        );
                        if (result == true) {
                          ref.invalidate(suppliersProvider);
                          ref.invalidate(dashboardProvider);
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'payment',
                          child: Text(tr(context, 'تسجيل دفعة مقدمة',
                              'Record advance payment'))),
                    ],
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${tr(context, 'رصيد', 'Balance')} (${supplier.defaultCurrency})',
                            style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 3),
                        Text(
                          Money.format(
                              supplier.balanceMinor, supplier.defaultCurrency,
                              locale:
                                  Localizations.localeOf(context).languageCode),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: color,
                              fontSize: 16),
                        ),
                        Text(
                          advance
                              ? tr(context, 'رصيد مقدم لصالح المحل',
                                  'Advance held with supplier')
                              : positive
                                  ? tr(context, 'مستحق للمورد',
                                      'Due to supplier')
                                  : tr(context, 'لا يوجد رصيد مستحق',
                                      'No outstanding balance'),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: color),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${supplier.invoiceCount}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(tr(context, 'فاتورة', 'Invoices'),
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
              if (supplier.balancesMinorByCurrency.keys
                  .any((code) => code != supplier.defaultCurrency)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: supplier.balancesMinorByCurrency.entries
                      .where((entry) => entry.key != supplier.defaultCurrency)
                      .map((entry) => Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(Money.format(entry.value, entry.key,
                                locale: Localizations.localeOf(context)
                                    .languageCode)),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierFormDialog extends ConsumerStatefulWidget {
  const _SupplierFormDialog();

  @override
  ConsumerState<_SupplierFormDialog> createState() =>
      _SupplierFormDialogState();
}

class _SupplierFormDialogState extends ConsumerState<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _activity = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _opening = TextEditingController(text: '0');
  String _currency = 'YER';
  String _openingSide = 'due';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(businessProfileProvider.future).then((profile) {
      final currency = profile?['default_currency'] as String?;
      if (mounted &&
          currency != null &&
          ['YER', 'SAR', 'USD'].contains(currency)) {
        setState(() => _currency = currency);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _activity.dispose();
    _phone.dispose();
    _address.dispose();
    _opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr(context, 'إضافة مورد جديد', 'Add new supplier')),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width > 560
              ? 460
              : MediaQuery.sizeOf(context).width * .78,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _input(_name, tr(context, 'اسم المورد *', 'Supplier name *'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? tr(context, 'الاسم مطلوب', 'Name is required')
                          : null),
                  const SizedBox(height: 9),
                  _input(_company, tr(context, 'اسم الشركة', 'Company name')),
                  const SizedBox(height: 9),
                  _input(_activity,
                      tr(context, 'نوع النشاط', 'Business activity')),
                  const SizedBox(height: 9),
                  _input(_phone, tr(context, 'رقم الهاتف', 'Phone number'),
                      keyboard: TextInputType.phone),
                  const SizedBox(height: 9),
                  _input(_address, tr(context, 'العنوان', 'Address')),
                  const SizedBox(height: 9),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: InputDecoration(
                        labelText: tr(
                            context, 'العملة الافتراضية', 'Default currency')),
                    items: const [
                      DropdownMenuItem(value: 'YER', child: Text('YER')),
                      DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) => setState(() => _currency = v ?? 'YER'),
                  ),
                  const SizedBox(height: 9),
                  _input(
                      _opening,
                      tr(context, 'قيمة الرصيد الافتتاحي',
                          'Opening balance amount'),
                      keyboard:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _amountValidator),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _openingSide,
                    decoration: InputDecoration(
                        labelText: tr(context, 'طبيعة الرصيد الافتتاحي',
                            'Opening balance type')),
                    items: [
                      DropdownMenuItem(
                          value: 'due',
                          child: Text(tr(context, 'مستحق للمورد على المحل',
                              'Due to supplier'))),
                      DropdownMenuItem(
                          value: 'advance',
                          child: Text(tr(context, 'رصيد مقدم للمحل لدى المورد',
                              'Advance held with supplier'))),
                    ],
                    onChanged: (value) =>
                        setState(() => _openingSide = value ?? 'due'),
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
              child: Text(tr(context, 'إلغاء', 'Cancel'))),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(tr(context, 'حفظ المورد', 'Save supplier'))),
        ],
      );

  Widget _input(TextEditingController controller, String label,
          {TextInputType? keyboard, String? Function(String?)? validator}) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboard,
        validator: validator,
        decoration: InputDecoration(labelText: label, isDense: true),
      );

  String? _amountValidator(String? value) {
    try {
      if (Money.parseMinor(value ?? '0') < 0)
        return tr(context, 'لا يمكن أن يكون سالباً', 'Cannot be negative');
      return null;
    } catch (_) {
      return tr(context, 'أدخل مبلغاً صحيحاً', 'Enter a valid amount');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supplierRepositoryProvider).createSupplier(
            name: _name.text,
            companyName: _company.text,
            activityType: _activity.text,
            phone: _phone.text,
            address: _address.text,
            currency: _currency,
            openingBalanceMinor: _openingSide == 'advance'
                ? -Money.parseMinor(_opening.text).abs()
                : Money.parseMinor(_opening.text).abs(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SupplierPaymentDialog extends ConsumerStatefulWidget {
  const _SupplierPaymentDialog({required this.supplier});
  final Supplier supplier;

  @override
  ConsumerState<_SupplierPaymentDialog> createState() =>
      _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState
    extends ConsumerState<_SupplierPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _receipt = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'cash';
  late String _currency = widget.supplier.defaultCurrency;
  late final String _idempotencyKey =
      'advance-${widget.supplier.id}-${DateTime.now().microsecondsSinceEpoch}';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _receipt.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(tr(context, 'دفعة مقدمة للمورد', 'Supplier advance payment')),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width > 520
              ? 420
              : MediaQuery.sizeOf(context).width * .78,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(widget.supplier.name,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: InputDecoration(
                      labelText:
                          tr(context, 'عملة الدفعة', 'Payment currency')),
                  items: const [
                    DropdownMenuItem(value: 'YER', child: Text('YER')),
                    DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                  ],
                  onChanged: (value) => setState(() =>
                      _currency = value ?? widget.supplier.defaultCurrency),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText:
                          '${tr(context, 'المبلغ', 'Amount')} ($_currency)'),
                  validator: (v) {
                    try {
                      if (Money.parseMinor(v ?? '0') <= 0)
                        return tr(context, 'أدخل مبلغاً أكبر من صفر',
                            'Enter an amount greater than zero');
                      return null;
                    } catch (_) {
                      return tr(context, 'مبلغ غير صحيح', 'Invalid amount');
                    }
                  },
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  initialValue: _method,
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
                  onChanged: (v) => setState(() => _method = v ?? 'cash'),
                ),
                const SizedBox(height: 9),
                TextFormField(
                    controller: _receipt,
                    decoration: InputDecoration(
                        labelText: tr(context, 'رقم السند', 'Receipt number'))),
                const SizedBox(height: 9),
                TextFormField(
                    controller: _notes,
                    decoration: InputDecoration(
                        labelText: tr(context, 'ملاحظات', 'Notes'))),
                if (_error != null)
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                const SizedBox(height: 5),
                Text(
                  tr(
                      context,
                      'ستُخصّص الدفعة للفواتير المستحقة إن وجدت، ويُحفظ الفائض رصيداً مقدماً للمورد.',
                      'The payment is allocated to outstanding invoices; any excess remains an advance.'),
                  style: Theme.of(context).textTheme.bodySmall,
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
              child: Text(tr(context, 'تسجيل الدفعة', 'Record payment'))),
        ],
      );

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final amount = Money.parseMinor(_amount.text);
      final accounting = ref.read(supplierAccountingRepositoryProvider);
      final due = await accounting.getCurrentDueMinor(
          widget.supplier.id, _currency);
      if (!mounted) return;
      final accepted = await confirmExcessSupplierPayment(context,
          dueMinor: due, amountMinor: amount, currency: _currency);
      if (!accepted || !mounted) return;
      await accounting.recordPayment(
            supplierId: widget.supplier.id,
            amountMinor: amount,
            currency: _currency,
            paymentDate: DateTime.now().toIso8601String().substring(0, 10),
            method: _method,
            receiptNumber: _receipt.text,
            notes: _notes.text,
            idempotencyKey: _idempotencyKey,
            allowAdvance: amount > due,
            expectedDueMinor: due,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState(
      {required this.icon,
      required this.title,
      this.subtitle,
      required this.actionLabel,
      required this.onAction});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(subtitle!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      );
}
