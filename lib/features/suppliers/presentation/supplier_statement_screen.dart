import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/reports/csv_export_service.dart';
import '../../../core/reports/report_pdf_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../domain/supplier_accounting_models.dart';
import 'supplier_financial_details_screen.dart';

class SupplierStatementScreen extends ConsumerStatefulWidget {
  const SupplierStatementScreen({
    super.key,
    required this.supplierId,
    required this.currency,
  });

  final int supplierId;
  final String currency;

  @override
  ConsumerState<SupplierStatementScreen> createState() =>
      _SupplierStatementScreenState();
}

class _SupplierStatementScreenState
    extends ConsumerState<SupplierStatementScreen> {
  late final _from = TextEditingController();
  late final _to = TextEditingController();
  late String _currency = widget.currency;
  Future<SupplierStatement>? _statementFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _statementFuture = _loadStatement();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<SupplierStatement> _loadStatement() {
    return ref.read(supplierAccountingRepositoryProvider).getStatement(
          supplierId: widget.supplierId,
          currency: _currency,
          periodFrom: _from.text.trim().isEmpty ? null : _from.text.trim(),
          periodTo: _to.text.trim().isEmpty ? null : _to.text.trim(),
        );
  }

  void _refresh() {
    final pending = _loadStatement();
    if (!mounted) return;
    setState(() {
      _statementFuture = pending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'كشف حساب المورد', 'Supplier statement')),
        actions: [
          IconButton(
            tooltip: tr(context, 'طباعة PDF', 'Print PDF'),
            onPressed: _busy ? null : () => _print(profile),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: tr(context, 'مشاركة PDF', 'Share PDF'),
            onPressed: _busy ? null : () => _share(profile),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: tr(context, 'تصدير CSV', 'Export CSV'),
            onPressed: _busy ? null : () => _shareCsv(profile),
            icon: const Icon(Icons.table_view_outlined),
          ),
        ],
      ),
      body: SafeArea(top: false, child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _currency,
                            decoration: InputDecoration(
                              labelText: tr(context, 'العملة', 'Currency'),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'YER', child: Text('YER')),
                              DropdownMenuItem(
                                  value: 'SAR', child: Text('SAR')),
                              DropdownMenuItem(
                                  value: 'USD', child: Text('USD')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _currency = value;
                                _statementFuture = _loadStatement();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dateField(
                            controller: _from,
                            label: tr(context, 'من تاريخ', 'From date'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dateField(
                            controller: _to,
                            label: tr(context, 'إلى تاريخ', 'To date'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            _from.clear();
                            _to.clear();
                            _refresh();
                          },
                          child: Text(tr(context, 'كل الفترة', 'All time')),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.filter_alt_outlined, size: 18),
                          label:
                              Text(tr(context, 'تطبيق الفلتر', 'Apply filter')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<SupplierStatement>(
              future: _statementFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _errorState(snapshot.error.toString());
                }
                final statement = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
                    children: [
                      _summary(statement),
                      const SizedBox(height: 10),
                      Text(
                        tr(context, 'حركات الحساب', 'Account movements'),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 7),
                      if (statement.movements.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              tr(context, 'لا توجد حركات خلال الفترة المحددة.',
                                  'No movements in the selected period.'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ...statement.movements.map((movement) =>
                            _movementCard(movement, statement.currency)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      )),
    );
  }

  Widget _dateField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_month_outlined, size: 18),
      ),
      onTap: () async {
        final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          controller.text =
              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
    );
  }

  Widget _summary(SupplierStatement statement) {
    final balance = statement.closingBalanceMinor;
    final color = balance > 0
        ? AppTheme.amber
        : balance < 0
            ? AppTheme.emerald
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final balanceLabel = balance > 0
        ? tr(context, 'مستحق للمورد على المحل', 'Due to supplier')
        : balance < 0
            ? tr(context, 'رصيد مقدم للمحل لدى المورد',
                'Advance held with supplier')
            : tr(context, 'الحساب متوازن', 'Settled account');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(statement.supplierName,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _summaryMetric(
                  tr(context, 'الرصيد الافتتاحي', 'Opening balance'),
                  statement.openingBalanceMinor,
                  statement.currency,
                ),
                _summaryMetric(
                  tr(context, 'المشتريات', 'Purchases'),
                  statement.totalPurchasesMinor,
                  statement.currency,
                ),
                _summaryMetric(
                  tr(context, 'المدفوعات', 'Payments'),
                  statement.totalPaymentsMinor,
                  statement.currency,
                ),
                _summaryMetric(
                  tr(context, 'المرتجعات', 'Returns'),
                  statement.totalReturnsMinor,
                  statement.currency,
                ),
                _summaryMetric(
                  tr(context, 'التسويات', 'Adjustments'),
                  statement.totalAdjustmentsMinor,
                  statement.currency,
                ),
              ],
            ),
            const Divider(height: 20),
            Text(balanceLabel,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            Text(
              Money.format(balance.abs(), statement.currency,
                  locale: Localizations.localeOf(context).languageCode),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryMetric(String label, int value, String currency) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            Money.format(value, currency,
                locale: Localizations.localeOf(context).languageCode),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _movementCard(SupplierStatementMovement movement, String currency) {
    final amount = movement.signedAmountMinor;
    final isDebit = amount > 0;
    final color = isDebit ? AppTheme.amber : AppTheme.emerald;
    final label = _movementLabel(movement.movementType);
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => SupplierMovementDetailScreen(movementId: movement.id))),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    movement.documentNumber,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(movement.entryDate,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w700)),
                      if (movement.details.isNotEmpty)
                        Text(movement.details,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(
                  '${isDebit ? '+' : '−'}${Money.format(amount.abs(), currency, locale: Localizations.localeOf(context).languageCode)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Divider(height: 14),
            Row(
              children: [
                Text(tr(context, 'الرصيد بعد الحركة', 'Balance after movement'),
                    style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                Text(
                  Money.format(movement.runningBalanceMinor.abs(), currency,
                      locale: Localizations.localeOf(context).languageCode),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 5),
                Text(
                  movement.runningBalanceMinor < 0
                      ? tr(context, 'مقدم', 'Advance')
                      : movement.runningBalanceMinor > 0
                          ? tr(context, 'مستحق', 'Due')
                          : tr(context, 'صفر', 'Zero'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _errorState(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.danger, size: 38),
              const SizedBox(height: 8),
              Text(tr(context, 'تعذر تحميل كشف الحساب',
                  'Could not load statement')),
              Text(message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: _refresh,
                  child: Text(tr(context, 'إعادة المحاولة', 'Retry'))),
            ],
          ),
        ),
      );

  Future<void> _shareCsv(AsyncValue<Map<String, Object?>?> profile) async {
    final data = await _statementFuture;
    if (!mounted || data == null) return;
    final shop = profile.valueOrNull ?? {};
    setState(() => _busy = true);
    try {
      await ref.read(supplierAccountingRepositoryProvider).archiveStatement(
            data,
            statementType: 'csv',
            businessProfile: shop,
          );
      if (!mounted) return;
      await CsvExportService.shareSupplierStatement(
        data,
        shopName: shop['shop_name'] as String? ?? 'Purchase Ledger',
        shopNumber: shop['shop_number'] as String?,
        shopAddress: shop['address'] as String?,
        shopPhone: shop['phone'] as String?,
        branchName: shop['branch_name'] as String? ??
            tr(context, 'جميع الفروع', 'All branches'),
        managerName: shop['manager_name'] as String?,
        buyerName: shop['buyer_name'] as String?,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${tr(context, 'تعذر تصدير CSV', 'Could not export CSV')}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(AsyncValue<Map<String, Object?>?> profile) async {
    final data = await _statementFuture;
    if (!mounted || data == null) return;
    final shop = profile.valueOrNull ?? {};
    setState(() => _busy = true);
    try {
      await ref.read(supplierAccountingRepositoryProvider).archiveStatement(
            data,
            businessProfile: shop,
          );
      if (!mounted) return;
      await ReportPdfService.shareSupplierStatement(
        statement: data,
        businessProfile: shop,
        branchName: shop['branch_name'] as String? ??
            tr(context, 'جميع الفروع', 'All branches'),
        buyerName: shop['buyer_name'] as String?,
        managerName: shop['manager_name'] as String?,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${tr(context, 'تعذر إنشاء PDF', 'Could not create PDF')}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print(AsyncValue<Map<String, Object?>?> profile) async {
    final data = await _statementFuture;
    if (!mounted || data == null) return;
    final shop = profile.valueOrNull ?? {};
    setState(() => _busy = true);
    try {
      await ref.read(supplierAccountingRepositoryProvider).archiveStatement(
            data,
            businessProfile: shop,
          );
      if (!mounted) return;
      await ReportPdfService.printSupplierStatement(
        statement: data,
        businessProfile: shop,
        branchName: shop['branch_name'] as String? ??
            tr(context, 'جميع الفروع', 'All branches'),
        buyerName: shop['buyer_name'] as String?,
        managerName: shop['manager_name'] as String?,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${tr(context, 'تعذرت الطباعة', 'Could not print')}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _movementLabel(String type) {
    switch (type) {
      case 'opening_balance':
        return tr(context, 'رصيد افتتاحي', 'Opening balance');
      case 'credit_invoice':
        return tr(context, 'فاتورة مشتريات', 'Purchase invoice');
      case 'payment':
        return tr(context, 'دفعة للمورد', 'Supplier payment');
      case 'purchase_return':
        return tr(context, 'مرتجع مشتريات', 'Purchase return');
      case 'daily_purchase':
        return tr(context, 'شراء يومي على حساب المورد',
            'Daily purchase on supplier account');
      case 'adjustment':
        return tr(context, 'تسوية', 'Adjustment');
      case 'reversal':
        return tr(context, 'عكس حركة', 'Reversal');
      default:
        return type;
    }
  }
}
