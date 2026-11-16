import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../purchases/presentation/purchase_entry_dialog.dart';
import '../domain/supplier.dart';
import '../domain/supplier_accounting_models.dart';
import 'supplier_advance_allocation_dialog.dart';
import 'supplier_adjustment_dialog.dart';
import 'supplier_payment_dialog.dart';
import 'supplier_statement_screen.dart';
import 'supplier_financial_details_screen.dart';
import 'supplier_return_dialog.dart';

class SupplierDashboardScreen extends ConsumerWidget {
  const SupplierDashboardScreen({super.key, required this.supplierId});

  final int supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(supplierDashboardProvider(supplierId));
    return dashboard.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.danger, size: 38),
                const SizedBox(height: 8),
                Text(tr(context, 'تعذر تحميل حساب المورد',
                    'Could not load supplier account')),
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(supplierDashboardProvider(supplierId)),
                  child: Text(tr(context, 'إعادة المحاولة', 'Retry')),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (data) => _SupplierDashboardContent(data: data),
    );
  }
}

class _SupplierDashboardContent extends ConsumerWidget {
  const _SupplierDashboardContent({required this.data});
  final SupplierDashboard data;

  Supplier get _supplier => Supplier(
        id: data.supplierId,
        name: data.name,
        phone: data.phone,
        address: data.address,
        companyName: data.companyName,
        activityType: data.activityType,
        notes: data.notes,
        defaultCurrency: data.defaultCurrency,
        balancesMinorByCurrency: {
          for (final summary in data.currencySummaries)
            summary.currency: summary.netBalanceMinor,
        },
        invoiceCount: data.invoiceCount,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(data.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: tr(context, 'كشف الحساب', 'Statement'),
              onPressed: () => _openStatement(context, data.defaultCurrency),
              icon: const Icon(Icons.receipt_long_outlined),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: tr(context, 'نظرة عامة', 'Overview')),
              Tab(text: tr(context, 'الفواتير', 'Invoices')),
              Tab(text: tr(context, 'الدفعات', 'Payments')),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(
            children: [
              _overview(context, ref),
              _invoices(context, ref),
              _payments(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overview(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context).languageCode;
    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.teal.withValues(alpha: .15),
                        child: const Icon(Icons.storefront_outlined,
                            color: AppTheme.teal),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 17)),
                            if (data.companyName?.isNotEmpty == true)
                              Text(data.companyName!,
                                  style: Theme.of(context).textTheme.bodySmall),
                            if (data.phone?.isNotEmpty == true)
                              Text(data.phone!,
                                  style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (data.address?.isNotEmpty == true ||
                      data.activityType?.isNotEmpty == true) ...[
                    const Divider(height: 20),
                    if (data.activityType?.isNotEmpty == true)
                      _detailLine(
                          context, Icons.category_outlined, data.activityType!),
                    if (data.address?.isNotEmpty == true)
                      _detailLine(
                          context, Icons.location_on_outlined, data.address!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _actionGrid(context, ref),
          const SizedBox(height: 12),
          Text(
            tr(context, 'ملخص الحساب حسب العملة',
                'Account summary by currency'),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          if (data.currencySummaries.isEmpty)
            _emptyCard(
                context,
                tr(context, 'لا توجد حركات مالية مسجلة.',
                    'No financial movements yet.'))
          else
            ...data.currencySummaries
                .map((summary) => _currencyCard(context, summary, locale)),
          const SizedBox(height: 12),
          Text(
            tr(context, 'البضائع المستلمة', 'Goods received'),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${data.receivedLineCount} ${tr(context, 'سطر صنف مستلم', 'received item lines')}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) =>
                          SupplierPurchasesScreen(supplierId: data.supplierId))),
                      icon: const Icon(Icons.list_alt_outlined),
                      label: Text(tr(context, 'عرض التفاصيل', 'View purchases')),
                    ),
                  ),
                  if (data.receivedQuantitiesByUnit.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: data.receivedQuantitiesByUnit.entries
                          .map((entry) => Text(
                                '${Money.formatQuantity(entry.value)} ${entry.key}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr(context, 'حالة الفواتير', 'Invoice status'),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          IntrinsicHeight(
            child: Row(children: [
              Expanded(child: _countCard(context,
                  tr(context, 'غير مسددة', 'Unpaid'),
                  data.unpaidInvoiceCount, AppTheme.danger,
                  onTap: () => _openInvoicesByStatus(context, 'unpaid'))),
              Expanded(child: _countCard(context,
                  tr(context, 'مسددة جزئياً', 'Partial'),
                  data.partiallyPaidInvoiceCount, AppTheme.amber,
                  onTap: () => _openInvoicesByStatus(context, 'partial'))),
              Expanded(child: _countCard(context,
                  tr(context, 'مسددة', 'Paid'),
                  data.paidInvoiceCount, AppTheme.emerald,
                  onTap: () => _openInvoicesByStatus(context, 'paid'))),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            tr(context, 'حركة التعامل عبر الزمن', 'Account activity over time'),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          if (data.monthlyActivity.isEmpty)
            _activityChart(context, const <SupplierMonthlyActivity>[],
                data.defaultCurrency)
          else
            for (final currency in data.monthlyActivity
                .map((entry) => entry.currency).toSet())
              _activityChart(context, data.monthlyActivity
                  .where((entry) => entry.currency == currency)
                  .toList(growable: false), currency),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                children: [
                  _dateLine(
                      context,
                      tr(context, 'آخر عملية شراء', 'Last purchase'),
                      data.lastPurchaseDate),
                  const Divider(height: 14),
                  _dateLine(context, tr(context, 'آخر دفعة', 'Last payment'),
                      data.lastPaymentDate),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionGrid(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 8) / 2;
      return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final button in [
        _actionButton(
          context,
          icon: Icons.add_shopping_cart,
          label: tr(context, 'إضافة مشتريات', 'Add purchase'),
          color: AppTheme.teal,
          onTap: () async {
            final result = await showDialog<bool>(
              context: context,
              builder: (_) => PurchaseEntryDialog(
                isCredit: true,
                initialSupplierId: data.supplierId,
              ),
            );
            if (result == true) _refresh(ref);
          },
        ),
        _actionButton(
          context,
          icon: Icons.payments_outlined,
          label: tr(context, 'تسجيل دفعة', 'Record payment'),
          color: AppTheme.emerald,
          onTap: () async {
            final result = await showDialog<bool>(
              context: context,
              builder: (_) => SupplierPaymentDialog(supplier: _supplier),
            );
            if (result == true) _refresh(ref);
          },
        ),
        _actionButton(
          context,
          icon: Icons.account_balance_wallet_outlined,
          label: tr(context, 'تخصيص رصيد مقدم', 'Allocate advance'),
          color: AppTheme.amber,
          onTap: () async {
            final result = await showDialog<bool>(
              context: context,
              builder: (_) =>
                  SupplierAdvanceAllocationDialog(supplier: _supplier),
            );
            if (result == true) _refresh(ref);
          },
        ),
        _actionButton(
          context,
          icon: Icons.receipt_long_outlined,
          label: tr(context, 'كشف الحساب PDF', 'Statement PDF'),
          color: const Color(0xFF75B9F0),
          onTap: () => _openStatement(context, data.defaultCurrency),
        ),
        _actionButton(
          context,
          icon: Icons.tune,
          label: tr(context, 'تسوية الحساب', 'Account adjustment'),
          color: AppTheme.amber,
          onTap: () async {
            final result = await showDialog<bool>(
              context: context,
              builder: (_) => SupplierAdjustmentDialog(supplier: _supplier),
            );
            if (result == true) _refresh(ref);
          },
        ),
        ])
          SizedBox(width: width, child: button),
      ],
    );
    });
  }

  Widget _invoices(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(supplierInvoicesProvider(data.supplierId));
    return invoices.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text(error.toString())),
      data: (items) {
        if (items.isEmpty) {
          return _emptyCard(
              context,
              tr(context, 'لا توجد فواتير مشتريات لهذا المورد.',
                  'No purchase invoices for this supplier.'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            _refresh(ref);
            await ref.read(supplierInvoicesProvider(data.supplierId).future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final invoice = items[index];
              final paid = invoice.allocatedMinor;
              final color = invoice.outstandingMinor == 0
                  ? AppTheme.emerald
                  : paid > 0 || invoice.returnedMinor > 0
                      ? AppTheme.amber
                      : AppTheme.danger;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('#${invoice.invoiceNumber}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          ),
                          _statusChip(context, invoice.status, color),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                          '${invoice.invoiceDate} • ${invoice.dueDate ?? tr(context, 'دون تاريخ استحقاق', 'No due date')}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const Divider(height: 16),
                      _moneyLine(
                          context,
                          tr(context, 'قيمة الفاتورة', 'Invoice total'),
                          invoice.totalMinor,
                          invoice.currency),
                      _moneyLine(
                          context,
                          tr(context, 'المخصص من الدفعات',
                              'Allocated payments'),
                          invoice.allocatedMinor,
                          invoice.currency),
                      _moneyLine(context, tr(context, 'المرتجعات', 'Returns'),
                          invoice.returnedMinor, invoice.currency),
                      _moneyLine(context, tr(context, 'المتبقي', 'Outstanding'),
                          invoice.outstandingMinor, invoice.currency,
                          strong: true, color: color),
                      const SizedBox(height: 5),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () => Navigator.push(context,
                            MaterialPageRoute<void>(builder: (_) =>
                              SupplierDocumentDetailScreen(
                                documentType: 'credit_invoice', documentId: invoice.id))),
                          icon: const Icon(Icons.visibility_outlined, size: 17),
                          label: Text(tr(context, 'تفاصيل الفاتورة', 'Invoice details')),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () async {
                            final result = await showDialog<bool>(
                              context: context,
                              builder: (_) => SupplierReturnDialog(
                                supplierId: data.supplierId,
                                invoiceId: invoice.id,
                              ),
                            );
                            if (result == true) _refresh(ref);
                          },
                          icon: const Icon(Icons.assignment_return_outlined,
                              size: 17),
                          label:
                              Text(tr(context, 'تسجيل مرتجع', 'Record return')),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _payments(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(supplierPaymentsProvider(data.supplierId));
    return payments.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text(error.toString())),
      data: (items) {
        if (items.isEmpty) {
          return _emptyCard(
              context,
              tr(context, 'لا توجد دفعات مسجلة لهذا المورد.',
                  'No payments recorded for this supplier.'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            _refresh(ref);
            await ref.read(supplierPaymentsProvider(data.supplierId).future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final payment = items[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SupplierDocumentDetailScreen(
                        documentType: 'payment', documentId: payment.id),
                    ),
                  ).then((_) {
                    if (context.mounted) _refresh(ref);
                  }),
                  child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              payment.receiptNumber ?? 'PAY-${payment.id}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (payment.isReversed)
                            _statusChip(context, 'reversed', AppTheme.danger),
                          if (!payment.isReversed)
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'reverse')
                                  _reversePayment(context, ref, payment);
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'reverse',
                                  child: Text(tr(context, 'عكس الدفعة',
                                      'Reverse payment')),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                          '${payment.paymentDate} • ${_methodLabel(context, payment.method)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const Divider(height: 15),
                      _moneyLine(
                          context,
                          tr(context, 'مبلغ الدفعة', 'Payment amount'),
                          payment.amountMinor,
                          payment.currency,
                          strong: true,
                          color: payment.isReversed
                              ? AppTheme.danger
                              : AppTheme.emerald),
                      _moneyLine(
                          context,
                          tr(context, 'المخصص للفواتير',
                              'Allocated to invoices'),
                          payment.allocatedMinor,
                          payment.currency),
                      _moneyLine(
                          context,
                          tr(context, 'الرصيد غير المخصص',
                              'Unallocated advance'),
                          payment.unallocatedMinor,
                          payment.currency),
                      if (payment.notes?.isNotEmpty == true)
                        Text(payment.notes!,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _currencyCard(
      BuildContext context, SupplierCurrencySummary summary, String locale) {
    final balanceColor = summary.netBalanceMinor > 0
        ? AppTheme.amber
        : summary.netBalanceMinor < 0
            ? AppTheme.emerald
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(summary.currency,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 9),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _smallMetric(context, tr(context, 'المشتريات', 'Purchases'),
                    summary.totalPurchasesMinor, '', locale),
                _smallMetric(context, tr(context, 'المدفوعات', 'Payments'),
                    summary.totalPaymentsMinor, '', locale),
                _smallMetric(context, tr(context, 'المرتجعات', 'Returns'),
                    summary.totalReturnsMinor, '', locale),
              ],
            ),
            const Divider(height: 18),
            Text(
              summary.netBalanceMinor > 0
                  ? tr(context, 'مستحق للمورد على المحل', 'Due to supplier')
                  : summary.netBalanceMinor < 0
                      ? tr(context, 'رصيد مقدم للمحل لدى المورد',
                          'Advance held with supplier')
                      : tr(context, 'الحساب متوازن', 'Settled'),
              style:
                  TextStyle(color: balanceColor, fontWeight: FontWeight.w700),
            ),
            Text(
              Money.format(summary.netBalanceMinor.abs(), '',
                  locale: locale).trim(),
              style: TextStyle(
                  color: balanceColor,
                  fontSize: 21,
                  fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallMetric(BuildContext context, String label, int value,
      String currency, String locale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(Money.format(value, currency, locale: locale).trim(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }

  void _openInvoicesByStatus(BuildContext context, String status) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _SupplierInvoicesByStatusScreen(
        supplierId: data.supplierId,
        status: status,
      ),
    ));
  }

  Widget _countCard(BuildContext context, String label, int count, Color color,
      {required VoidCallback onTap}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    color: color, fontSize: 21, fontWeight: FontWeight.w900)),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
      ),
    );
  }

  Widget _activityChart(
      BuildContext context, List<SupplierMonthlyActivity> activity,
      String currency) {
    if (activity.isEmpty) {
      return _emptyCard(
          context,
          tr(context, 'لا توجد بيانات كافية للمخطط.',
              'Not enough data for a chart.'));
    }
    final visible =
        activity.length > 6 ? activity.sublist(activity.length - 6) : activity;
    final maxValue = visible.fold<int>(
        0,
        (max, item) => math.max(
              max,
              math.max(item.returnsMinor,
                  math.max(item.purchasesMinor, item.paymentsMinor)),
            ));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(currency,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _legendDot(context, AppTheme.teal,
                    tr(context, 'المشتريات', 'Purchases')),
                _legendDot(context, AppTheme.emerald,
                    tr(context, 'المدفوعات', 'Payments')),
                _legendDot(context, AppTheme.amber,
                    tr(context, 'المرتجعات', 'Returns')),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: visible.map((item) {
                  final purchaseHeight = maxValue == 0
                      ? 0.0
                      : 105 * item.purchasesMinor / maxValue;
                  final paymentHeight =
                      maxValue == 0 ? 0.0 : 105 * item.paymentsMinor / maxValue;
                  final returnHeight =
                      maxValue == 0 ? 0.0 : 105 * item.returnsMinor / maxValue;
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 112,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _bar(purchaseHeight, AppTheme.teal),
                              const SizedBox(width: 2),
                              _bar(paymentHeight, AppTheme.emerald),
                              const SizedBox(width: 2),
                              _bar(returnHeight, AppTheme.amber),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(item.month.substring(5),
                            style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double height, Color color) {
    if (height <= 0) return const SizedBox(width: 7);
    return Container(
      width: 7,
      height: height.clamp(2, 105).toDouble(),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: .14),
        foregroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  Widget _detailLine(BuildContext context, IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.teal),
          const SizedBox(width: 6),
          Expanded(
              child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _moneyLine(
    BuildContext context,
    String label,
    int value,
    String currency, {
    bool strong = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: strong
                    ? const TextStyle(fontWeight: FontWeight.w800)
                    : Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            Money.format(value, currency,
                locale: Localizations.localeOf(context).languageCode),
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status, Color color) {
    final label = switch (status) {
      'paid' => tr(context, 'مسددة', 'Paid'),
      'partial' => tr(context, 'جزئية', 'Partial'),
      'unpaid' => tr(context, 'غير مسددة', 'Unpaid'),
      'reversed' => tr(context, 'معكوسة', 'Reversed'),
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _dateLine(BuildContext context, String label, String? value) {
    final parsed = value == null ? null : DateTime.tryParse(value);
    final readable = parsed == null
        ? (value ?? '—')
        : MaterialLocalizations.of(context).formatFullDate(parsed);
    return Row(
      children: [
        Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Flexible(child: Text(readable,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700))),
      ],
    );
  }

  Widget _emptyCard(BuildContext context, String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  String _methodLabel(BuildContext context, String method) {
    switch (method) {
      case 'cash':
        return tr(context, 'نقداً', 'Cash');
      case 'bank_transfer':
        return tr(context, 'تحويل بنكي', 'Bank transfer');
      case 'wallet':
        return tr(context, 'محفظة إلكترونية', 'E-wallet');
      case 'cheque':
        return tr(context, 'شيك', 'Cheque');
      default:
        return tr(context, 'أخرى', 'Other');
    }
  }

  Future<void> _reversePayment(
    BuildContext context,
    WidgetRef ref,
    SupplierPaymentRecord payment,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _SupplierPaymentReversalDialog(),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;
    try {
      await ref.read(supplierAccountingRepositoryProvider).reversePayment(
            paymentId: payment.id,
            reversalDate: DateTime.now().toIso8601String().substring(0, 10),
            reason: reason,
          );
      _refresh(ref);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(supplierDashboardProvider(data.supplierId));
    ref.invalidate(supplierInvoicesProvider(data.supplierId));
    ref.invalidate(supplierPaymentsProvider(data.supplierId));
    ref.invalidate(supplierAdvancesProvider(data.supplierId));
    ref.invalidate(creditInvoicesProvider);
    ref.invalidate(suppliersProvider);
    ref.invalidate(dashboardProvider);
  }

  void _openStatement(BuildContext context, String currency) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SupplierStatementScreen(
        supplierId: data.supplierId,
        currency: currency,
      ),
    ));
  }
}

/// Owns its input controller until Flutter unmounts the dialog's route.
/// Disposing a controller immediately after showDialog returns can happen
/// before the reverse pop animation has finished building its TextField.
class _SupplierPaymentReversalDialog extends StatefulWidget {
  const _SupplierPaymentReversalDialog();

  @override
  State<_SupplierPaymentReversalDialog> createState() =>
      _SupplierPaymentReversalDialogState();
}

class _SupplierPaymentReversalDialogState
    extends State<_SupplierPaymentReversalDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(tr(context, 'عكس دفعة المورد', 'Reverse supplier payment')),
        content: TextField(
          controller: _reason,
          maxLines: 2,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: tr(context, 'سبب العكس *', 'Reversal reason *')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: _reason.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, _reason.text.trim()),
            child: Text(tr(context, 'تأكيد العكس', 'Confirm reversal')),
          ),
        ],
      );
}

/// The same invoice status model powers both the overview counters and the
/// destination list; an unallocated advance never changes an invoice status.
class _SupplierInvoicesByStatusScreen extends ConsumerWidget {
  const _SupplierInvoicesByStatusScreen({
    required this.supplierId,
    required this.status,
  });

  final int supplierId;
  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(supplierInvoicesProvider(supplierId));
    final title = switch (status) {
      'unpaid' => tr(context, 'فواتير غير مسددة', 'Unpaid invoices'),
      'partial' => tr(context, 'فواتير مسددة جزئياً', 'Partially paid invoices'),
      'paid' => tr(context, 'فواتير مسددة', 'Paid invoices'),
      _ => tr(context, 'فواتير المورد', 'Supplier invoices'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: invoices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Text(tr(context, 'تعذر عرض الفواتير', 'Could not load invoices')),
          ),
          data: (all) {
            final visible = all.where((invoice) => invoice.status == status)
                .toList(growable: false);
            if (visible.isEmpty) {
              return Center(child: Text(tr(context,
                  'لا توجد فواتير في هذه الحالة.',
                  'There are no invoices with this status.')));
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(supplierInvoicesProvider(supplierId));
                await ref.read(supplierInvoicesProvider(supplierId).future);
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final invoice = visible[index];
                  final locale = Localizations.localeOf(context).languageCode;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => SupplierDocumentDetailScreen(
                            documentType: 'credit_invoice', documentId: invoice.id),
                        ));
                        if (context.mounted) {
                          ref.invalidate(supplierInvoicesProvider(supplierId));
                          ref.invalidate(supplierDashboardProvider(supplierId));
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Expanded(child: Text('#${invoice.invoiceNumber}',
                                style: const TextStyle(fontWeight: FontWeight.w700))),
                              const Icon(Icons.chevron_left),
                            ]),
                            Text(invoice.invoiceDate,
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 6),
                            for (final detail in <(String, int)>[
                              (tr(context, 'الإجمالي', 'Total'), invoice.totalMinor),
                              (tr(context, 'المخصص', 'Allocated'), invoice.allocatedMinor),
                              (tr(context, 'المرتجع', 'Returned'), invoice.returnedMinor),
                              (tr(context, 'المتبقي', 'Remaining'), invoice.outstandingMinor),
                            ])
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text('${detail.$1}: '
                                  '${Money.format(detail.$2, invoice.currency, locale: locale)}'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
