import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../localization/app_strings.dart';

class MeasurementUnitsScreen extends ConsumerStatefulWidget {
  const MeasurementUnitsScreen({super.key});

  @override
  ConsumerState<MeasurementUnitsScreen> createState() =>
      _MeasurementUnitsScreenState();
}

class _MeasurementUnitsScreenState extends ConsumerState<MeasurementUnitsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_updateTab);

  String get _scope => _tabs.index == 0 ? 'credit' : 'daily';

  void _updateTab() {
    if (mounted && !_tabs.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_updateTab);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(tr(context, 'إدارة وحدات القياس', 'Measurement units')),
          bottom: TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: tr(context, 'الآجلة', 'Credit')),
              Tab(text: tr(context, 'اليومية', 'Daily')),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _unitsList('credit', ref.watch(creditMeasurementUnitsProvider)),
            _unitsList('daily', ref.watch(dailyMeasurementUnitsProvider)),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(_scope),
          icon: const Icon(Icons.add),
          label: Text(tr(context, 'إضافة وحدة', 'Add unit')),
        ),
      );

  Widget _unitsList(String scope,
      AsyncValue<List<Map<String, Object?>>> result) {
    return result.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: TextButton(
          onPressed: () => _refresh(scope),
          child: Text('${tr(context, 'إعادة المحاولة', 'Retry')}: $error'),
        ),
      ),
      data: (rows) => RefreshIndicator(
        onRefresh: () async {
          _refresh(scope);
          await ref.read(
              scope == 'credit'
                  ? creditMeasurementUnitsProvider.future
                  : dailyMeasurementUnitsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
          children: [
            Text(
              tr(context,
                  'تُستخدم هذه القائمة عند اختيار وحدة الصنف. تبقى وحدات الفواتير والسجلات السابقة محفوظة عند الأرشفة أو تعديل الاسم.',
                  'These units are available when entering items. Existing invoice units remain unchanged when a name is edited or archived.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(22),
                child: Text(tr(context, 'لا توجد وحدات مفعّلة', 'No active units')),
              ),
            ...rows.map((row) => Card(
                  child: ListTile(
                    title: Text(row['name'] as String),
                    onTap: () => _edit(scope, row),
                    trailing: PopupMenuButton<String>(
                      tooltip: tr(context, 'إجراءات الوحدة', 'Unit actions'),
                      onSelected: (action) => action == 'edit'
                          ? _edit(scope, row)
                          : _archive(scope, row),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'edit',
                            child: Text(tr(context, 'تعديل', 'Edit'))),
                        PopupMenuItem(
                            value: 'archive',
                            child: Text(tr(context, 'أرشفة', 'Archive'))),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _refresh(String scope) {
    ref.invalidate(scope == 'credit'
        ? creditMeasurementUnitsProvider
        : dailyMeasurementUnitsProvider);
  }

  Future<void> _edit(String scope, [Map<String, Object?>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UnitNameDialog(scope: scope, record: row),
    );
    if (mounted && saved == true) _refresh(scope);
  }

  Future<void> _archive(String scope, Map<String, Object?> row) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'أرشفة وحدة القياس', 'Archive unit')),
        content: Text(tr(context,
            'ستختفي الوحدة من الاختيارات الجديدة فقط، وستبقى في السجلات والفواتير السابقة.',
            'The unit will disappear from new selections only. Historical records keep it.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr(context, 'إلغاء', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr(context, 'تأكيد', 'Confirm'))),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await ref.read(measurementUnitRepositoryProvider)
          .archive(row['id'] as int, scope);
      if (mounted) _refresh(scope);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _UnitNameDialog extends ConsumerStatefulWidget {
  const _UnitNameDialog({required this.scope, this.record});
  final String scope;
  final Map<String, Object?>? record;

  @override
  ConsumerState<_UnitNameDialog> createState() => _UnitNameDialogState();
}

class _UnitNameDialogState extends ConsumerState<_UnitNameDialog> {
  late final _name = TextEditingController(
      text: widget.record?['name'] as String? ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.record == null
            ? tr(context, 'إضافة وحدة قياس', 'Add measurement unit')
            : tr(context, 'تعديل وحدة قياس', 'Edit measurement unit')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: tr(context, 'اسم الوحدة *', 'Unit name *')),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(tr(context, 'إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(tr(context, 'حفظ', 'Save')),
          ),
        ],
      );

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = tr(context, 'اسم الوحدة مطلوب', 'Unit name required'));
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final repo = ref.read(measurementUnitRepositoryProvider);
      if (widget.record == null) {
        await repo.create(widget.scope, _name.text);
      } else {
        await repo.rename(widget.record!['id'] as int, widget.scope, _name.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
