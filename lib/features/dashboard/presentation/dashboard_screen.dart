import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import 'business_profile_dialog.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, this.onNavigate});

  final void Function(int index, {required bool overdueOnly})? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardProvider);
    final profile = ref.watch(businessProfileProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardProvider);
        await ref.read(dashboardProvider.future);
      },
      child: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorPanel(
          message: tr(context, 'تعذر تحميل بيانات لوحة التحكم',
              'Could not load dashboard data'),
          onRetry: () => ref.invalidate(dashboardProvider),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _WelcomeCard(shopName: profile.value?['shop_name'] as String?),
            if (profile.value == null) ...[
              const SizedBox(height: 12),
              _SetupProfileCard(onTap: () async {
                final result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const BusinessProfileDialog());
                if (result == true) ref.invalidate(businessProfileProvider);
              }),
            ],
            const SizedBox(height: 16),
            Text(
              tr(context, 'ملخص النشاط', 'Activity overview'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 620 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _MetricCard(
                  icon: Icons.storefront_outlined,
                  label: tr(context, 'الموردون', 'Suppliers'),
                  value: '${data.supplierCount}',
                  tint: AppTheme.teal,
                  onTap: () => onNavigate?.call(1, overdueOnly: false),
                ),
                _MetricCard(
                  icon: Icons.receipt_long_outlined,
                  label: tr(context, 'الفواتير الآجلة', 'Credit invoices'),
                  value: '${data.invoiceCount}',
                  tint: AppTheme.navy,
                  onTap: () => onNavigate?.call(2, overdueOnly: false),
                ),
                _MetricCard(
                  icon: Icons.event_busy_outlined,
                  label: tr(context, 'فواتير متأخرة', 'Overdue invoices'),
                  value: '${data.overdueInvoiceCount}',
                  tint: AppTheme.danger,
                  onTap: () => onNavigate?.call(2, overdueOnly: true),
                ),
                _MetricCard(
                  icon: Icons.shopping_basket_outlined,
                  label: tr(context, 'عمليات يومية', 'Daily purchases'),
                  value: '${data.dailyPurchaseCount}',
                  tint: AppTheme.emerald,
                  onTap: () => onNavigate?.call(3, overdueOnly: false),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              tr(context, 'الأرصدة حسب العملة', 'Balances by currency'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (data.totalsByCurrency.isEmpty)
              _EmptyPanel(
                icon: Icons.account_balance_wallet_outlined,
                title: tr(context, 'لا توجد حركات مالية بعد',
                    'No financial activity yet'),
                subtitle: tr(
                    context,
                    'أضف مورداً أو سجّل أول عملية شراء لعرض الأرقام هنا.',
                    'Add a supplier or record your first purchase to see figures here.'),
              )
            else
              ...data.totalsByCurrency.map((total) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(total.currency,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 12),
                            _BalanceRow(
                              label: tr(context, 'المشتريات الآجلة',
                                  'Credit purchases'),
                              value: Money.format(
                                  total.creditPurchasesMinor, total.currency,
                                  locale: Localizations.localeOf(context)
                                      .languageCode),
                            ),
                            _BalanceRow(
                              label: tr(context, 'المشتريات اليومية',
                                  'Daily purchases'),
                              value: Money.format(
                                  total.dailyPurchasesMinor, total.currency,
                                  locale: Localizations.localeOf(context)
                                      .languageCode),
                            ),
                            const Divider(height: 18),
                            _BalanceRow(
                              label: tr(context, 'صافي حساب الموردين',
                                  'Net supplier balance'),
                              value: Money.format(
                                  total.supplierDueMinor, total.currency,
                                  locale: Localizations.localeOf(context)
                                      .languageCode),
                              emphasized: true,
                              color: total.supplierDueMinor < 0
                                  ? AppTheme.emerald
                                  : AppTheme.amber,
                            ),
                            _BalanceRow(
                              label: tr(context, 'متبقي المشتريات اليومية',
                                  'Daily purchase outstanding'),
                              value: Money.format(
                                  total.dailyDueMinor, total.currency,
                                  locale: Localizations.localeOf(context)
                                      .languageCode),
                              emphasized: true,
                              color: AppTheme.amber,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
            const SizedBox(height: 8),
            Text(
              tr(
                  context,
                  'ملاحظة محاسبية: لا يتم جمع العملات المختلفة في إجمالي واحد.',
                  'Accounting note: different currencies are never combined into one total.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({this.shopName});
  final String? shopName;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [AppTheme.navy, AppTheme.teal],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.menu_book_rounded, color: Colors.white, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      (shopName == null || shopName!.isEmpty)
                          ? tr(context, 'دفتر المشتريات', 'Purchase Ledger')
                          : shopName!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    tr(context, 'إدارة مشترياتك وحسابات الموردين من مكان واحد',
                        'Manage purchases and supplier accounts in one place'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SetupProfileCard extends StatelessWidget {
  const _SetupProfileCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.store_mall_directory_outlined,
              color: AppTheme.teal),
          title: Text(
              tr(context, 'أكمل بيانات المحل', 'Complete business profile'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tr(
              context,
              'أدخل اسم المحل وبيانات التواصل والعملة الافتراضية.',
              'Add your shop name, contact details and default currency.')),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.tint,
      this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: tint, size: 22),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          ),
        ),
      );
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow(
      {required this.label,
      required this.value,
      this.emphasized = false,
      this.color});
  final String label;
  final String value;
  final bool emphasized;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
                child:
                    Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Text(value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          emphasized ? FontWeight.w800 : FontWeight.w600,
                      color: color,
                    )),
          ],
        ),
      );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Icon(icon,
                  size: 34, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.danger, size: 36),
              const SizedBox(height: 8),
              Text(message),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr(context, 'إعادة المحاولة', 'Retry'))),
            ],
          ),
        ),
      );
}
