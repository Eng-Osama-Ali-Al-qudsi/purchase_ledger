import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import 'directory_entry_dialog.dart';

class BusinessDirectoryScreen extends ConsumerStatefulWidget {
  const BusinessDirectoryScreen({super.key});

  @override
  ConsumerState<BusinessDirectoryScreen> createState() =>
      _BusinessDirectoryScreenState();
}

class _BusinessDirectoryScreenState
    extends ConsumerState<BusinessDirectoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  static const _kinds = ['branch', 'employee', 'category', 'product'];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'إدارة بيانات التشغيل', 'Business directory')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: tr(context, 'الفروع', 'Branches')),
            Tab(text: tr(context, 'الموظفون', 'Employees')),
            Tab(text: tr(context, 'التصنيفات', 'Categories')),
            Tab(text: tr(context, 'الأصناف', 'Products')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _listPage(ref.watch(branchesProvider), kind: 'branch',
              title: tr(context, 'الفروع المسجلة', 'Registered branches'),
              subtitle: (r) => '${r['code'] ?? '—'} • ${r['phone'] ?? '—'}'),
          _listPage(ref.watch(employeesProvider(null)), kind: 'employee',
              title: tr(context, 'الموظفون', 'Employees'),
              subtitle: (r) => '${r['role'] ?? '—'} • ${r['phone'] ?? '—'}'),
          _listPage(ref.watch(purchaseCategoriesProvider), kind: 'category',
              title: tr(context, 'تصنيفات المشتريات', 'Categories'),
              subtitle: (r) => r['category_type'] as String? ?? ''),
          _listPage(ref.watch(purchaseProductsProvider), kind: 'product',
              title: tr(context, 'الأصناف المسجلة', 'Products'),
              subtitle: (r) => '${r['sku'] ?? '—'} • ${r['category_name'] ?? '—'}'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(_kinds[_tabs.index]),
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'إضافة', 'Add')),
      ),
    );
  }

  Widget _listPage(
    AsyncValue<List<Map<String, Object?>>> data, {
    required String kind,
    required String title,
    required String Function(Map<String, Object?>) subtitle,
  }) {
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text(error.toString())),
      data: (items) => RefreshIndicator(
        onRefresh: _refreshAndWait,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 96),
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 70),
                child: Text(
                  tr(context,
                      'لا توجد بيانات مسجلة. استخدم زر الإضافة لإنشاء أول سجل.',
                      'No records yet. Use Add to create the first record.'),
                  textAlign: TextAlign.center,
                ),
              ),
            ...items.map((item) => Card(
                  child: ListTile(
                    onTap: () => _edit(kind, item),
                    leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                    title: Text(item['name'] as String? ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(subtitle(item)),
                    trailing: PopupMenuButton<String>(
                      tooltip: tr(context, 'إجراءات السجل', 'Record actions'),
                      onSelected: (value) => value == 'edit'
                          ? _edit(kind, item)
                          : _archive(kind, item),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(tr(context, 'تعديل', 'Edit')),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text(tr(context, 'حذف / أرشفة', 'Remove / archive')),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(String kind, [Map<String, Object?>? record]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => DirectoryEntryDialog(kind: kind, record: record),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _archive(String kind, Map<String, Object?> record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'تأكيد الأرشفة', 'Confirm archive')),
        content: Text(tr(
          context,
          'سيُخفى هذا السجل من القوائم النشطة مع الإبقاء على الفواتير والأوراق والحركات السابقة المرتبطة به. هل تريد المتابعة؟',
          'The record will be hidden from active lists. Historical invoices, sheets and ledger entries will remain intact. Continue?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(context, 'إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(context, 'أرشفة', 'Archive')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(businessDirectoryRepositoryProvider).archiveRecord(
            kind: kind, id: record['id'] as int);
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _refresh() {
    ref.invalidate(branchesProvider);
    ref.invalidate(employeesProvider(null));
    ref.invalidate(dailyPurchaseCategoriesProvider);
    ref.invalidate(purchaseCategoriesProvider);
    ref.invalidate(purchaseProductsProvider);
  }

  Future<void> _refreshAndWait() async {
    _refresh();
    await Future.wait([
      ref.read(branchesProvider.future),
      ref.read(employeesProvider(null).future),
      ref.read(purchaseCategoriesProvider.future),
      ref.read(purchaseProductsProvider.future),
    ]);
  }
}
