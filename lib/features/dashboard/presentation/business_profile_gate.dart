import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import 'business_profile_dialog.dart';
import 'home_shell.dart';

class BusinessProfileGate extends ConsumerWidget {
  const BusinessProfileGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider);
    return profile.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 40, color: AppTheme.danger),
                const SizedBox(height: 12),
                Text(tr(context, 'تعذر فتح قاعدة بيانات التطبيق.',
                    'Could not open the application database.')),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () => ref.invalidate(businessProfileProvider),
                    child: Text(tr(context, 'إعادة المحاولة', 'Retry'))),
              ],
            ),
          ),
        ),
      ),
      data: (business) =>
          business == null ? _FirstRunSetup() : const HomeShell(),
    );
  }
}

class _FirstRunSetup extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                            color: AppTheme.navy,
                            borderRadius: BorderRadius.circular(22)),
                        child: const Icon(Icons.menu_book_rounded,
                            color: Colors.white, size: 42),
                      ),
                      const SizedBox(height: 18),
                      Text(
                          tr(context, 'مرحباً بك في دفتر المشتريات',
                              'Welcome to Purchase Ledger'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                            context,
                            'قبل البدء، أدخل بيانات المحل والعملة الافتراضية. ستستخدم هذه البيانات في التقارير وكشوف الحساب.',
                            'Before you begin, enter your business details and default currency. These details will be used in reports and statements.'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final saved = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const BusinessProfileDialog(),
                            );
                            if (saved == true)
                              ref.invalidate(businessProfileProvider);
                          },
                          icon: const Icon(Icons.store_mall_directory_outlined),
                          label: Text(tr(context, 'إعداد بيانات المحل',
                              'Set up business profile')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
