import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../domain/purchase_models.dart';
import 'purchase_entry_dialog.dart';
import '../../suppliers/presentation/supplier_financial_details_screen.dart';
import '../../suppliers/presentation/confirm_excess_payment.dart';

class CreditInvoicesScreen extends ConsumerWidget {
  const CreditInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(creditInvoicesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                    tr(context, 'الفواتير الآجلة المسجلة لدى الموردين',
                        'Credit invoices recorded with suppliers'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              FilledButton.icon(
                onPressed: () => _openEntry(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr(context, 'فاتورة جديدة', 'New invoice')),
              ),
            ],
          ),
        ),
        Expanded(
          child: invoices.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _StateMessage(
              title:
                  tr(context, 'تعذر تحميل الفواتير', 'Could not load invoices'),
              onRetry: () => ref.invalidate(creditInvoicesProvider),
            ),
            data: (items) => items.isEmpty
                ? _StateMessage(
                    title: tr(context, 'لا توجد فواتير آجلة',
                        'No credit invoices yet'),
                    subtitle: tr(
                        context,
                        'أنشئ فاتورة واربطها بالمورد لتبدأ متابعة الرصيد.',
                        'Create an invoice and assign it to a supplier to start tracking balances.'),
                    action: () => _openEntry(context, ref),
                    actionLabel: tr(context, 'إضافة فاتورة', 'Add invoice'),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(creditInvoicesProvider);
                      await ref.read(creditInvoicesProvider.future);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, index) =>
                          _InvoiceCard(invoice: items[index]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openEntry(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
        context: context,
        builder: (_) => const PurchaseEntryDialog(isCredit: true));
    if (result == true) {
      ref.invalidate(creditInvoicesProvider);
      ref.invalidate(suppliersProvider);
      ref.invalidate(dashboardProvider);
    }
  }
}

class _InvoiceCard extends ConsumerWidget {
  const _InvoiceCard({required this.invoice});
  final InvoiceSummary invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = invoice.remainingMinor;
    final settled = remaining <= 0;
    final overdue = !settled &&
        invoice.dueDate != null &&
        invoice.dueDate!
                .compareTo(DateTime.now().toIso8601String().substring(0, 10)) <
            0;
    final statusColor = settled
        ? AppTheme.emerald
        : overdue
            ? AppTheme.danger
            : AppTheme.amber;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${tr(context, 'فاتورة', 'Invoice')} #${invoice.invoiceNumber}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(invoice.supplierName,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(30)),
                  child: Text(
                    settled
                        ? tr(context, 'مسددة', 'Paid')
                        : overdue
                            ? tr(context, 'متأخرة', 'Overdue')
                            : tr(context, 'مستحقة', 'Due'),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _AmountInfo(
                    label: tr(context, 'الإجمالي', 'Total'),
                    value: Money.format(invoice.totalMinor, invoice.currency,
                        locale: Localizations.localeOf(context).languageCode)),
                _AmountInfo(
                    label: tr(context, 'المدفوع', 'Paid'),
                    value: Money.format(invoice.paidMinor, invoice.currency,
                        locale: Localizations.localeOf(context).languageCode)),
                _AmountInfo(
                    label: tr(context, 'المتبقي', 'Remaining'),
                    value: Money.format(remaining, invoice.currency,
                        locale: Localizations.localeOf(context).languageCode),
                    color: statusColor),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                  builder: (_) => SupplierDocumentDetailScreen(
                    documentType: 'credit_invoice', documentId: invoice.id))),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(tr(context, 'تفاصيل الفاتورة', 'Invoice details')),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text(
                        '${tr(context, 'التاريخ', 'Date')}: ${invoice.invoiceDate}${invoice.dueDate == null ? '' : '  •  ${tr(context, 'الاستحقاق', 'Due')}: ${invoice.dueDate}'}',
                        style: Theme.of(context).textTheme.labelSmall)),
                if (!settled)
                  TextButton.icon(
                    onPressed: () async {
                      final result = await showDialog<bool>(
                          context: context,
                          builder: (_) =>
                              _InvoicePaymentDialog(invoice: invoice));
                      if (result == true) {
                        ref.invalidate(creditInvoicesProvider);
                        ref.invalidate(suppliersProvider);
                        ref.invalidate(dashboardProvider);
                      }
                    },
                    icon: const Icon(Icons.payments_outlined, size: 17),
                    label: Text(tr(context, 'تسديد', 'Pay')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicePaymentDialog extends ConsumerStatefulWidget {
  const _InvoicePaymentDialog({required this.invoice});
  final InvoiceSummary invoice;

  @override
  ConsumerState<_InvoicePaymentDialog> createState() =>
      _InvoicePaymentDialogState();
}

class _InvoicePaymentDialogState extends ConsumerState<_InvoicePaymentDialog> {
  final _amount = TextEditingController();
  final _receipt = TextEditingController();
  String _method = 'cash';
  bool _saving = false;
  String? _error;
  late final String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'invoice-payment-${widget.invoice.id}-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _amount.dispose();
    _receipt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title:
            Text(tr(context, 'تسجيل دفعة للمورد', 'Record supplier payment')),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width > 500
              ? 400
              : MediaQuery.sizeOf(context).width * .78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                      '${widget.invoice.supplierName} • #${widget.invoice.invoiceNumber}')),
              const SizedBox(height: 8),
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                      '${tr(context, 'المتبقي', 'Remaining')}: ${Money.format(widget.invoice.remainingMinor, widget.invoice.currency)}')),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText:
                        '${tr(context, 'المبلغ المدفوع', 'Payment amount')} (${widget.invoice.currency})'),
              ),
              const SizedBox(height: 9),
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
              const SizedBox(height: 9),
              TextField(
                  controller: _receipt,
                  decoration: InputDecoration(
                      labelText: tr(
                          context, 'رقم سند الدفع', 'Payment receipt number'))),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
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

  Future<void> _save() async {
    try {
      final amount = Money.parseMinor(_amount.text);
      if (amount <= 0) throw const FormatException('Amount must be positive');
      setState(() {
        _saving = true;
        _error = null;
      });
      final accounting = ref.read(supplierAccountingRepositoryProvider);
      final due = await accounting.getCurrentDueMinor(
        widget.invoice.supplierId, widget.invoice.currency);
      if (!mounted) return;
      final accepted = await confirmExcessSupplierPayment(context,
          dueMinor: due, amountMinor: amount, currency: widget.invoice.currency);
      if (!accepted || !mounted) return;
      await ref.read(purchaseRepositoryProvider).recordSupplierPayment(
            allowAdvance: amount > due,
            expectedDueMinor: due,
            supplierId: widget.invoice.supplierId,
            amountMinor: amount,
            currency: widget.invoice.currency,
            paymentDate: DateTime.now().toIso8601String().substring(0, 10),
            method: _method,
            invoiceId: widget.invoice.id,
            receiptNumber: _receipt.text,
            idempotencyKey: _idempotencyKey,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AmountInfo extends StatelessWidget {
  const _AmountInfo({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ],
      );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage(
      {required this.title,
      this.subtitle,
      this.action,
      this.actionLabel,
      this.onRetry});
  final String title;
  final String? subtitle;
  final VoidCallback? action;
  final String? actionLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 42),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (action != null)
                OutlinedButton(
                    onPressed: action, child: Text(actionLabel ?? '')),
              if (onRetry != null)
                OutlinedButton(
                    onPressed: onRetry,
                    child: Text(tr(context, 'إعادة المحاولة', 'Retry'))),
            ],
          ),
        ),
      );
}
