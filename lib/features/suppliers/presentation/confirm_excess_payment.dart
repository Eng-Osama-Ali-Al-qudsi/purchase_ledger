import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';

/// Confirmation is only presented before a transaction. Cancel does not write.
Future<bool> confirmExcessSupplierPayment(BuildContext context, {
  required int dueMinor,
  required int amountMinor,
  required String currency,
}) async {
  if (amountMinor <= dueMinor) return true;
  return await showDialog<bool>(context: context, builder: (dialogContext) =>
    AlertDialog(
      title: const Text('تنبيه: دفعة أكبر من المستحق'),
      content: Text('المستحق: ${Money.format(dueMinor, currency)}\n'
        'المدخل: ${Money.format(amountMinor, currency)}\n'
        'الزيادة: ${Money.format(amountMinor - dueMinor, currency)}\n\n'
        'سيُرحّل الفائض إلى رصيد مقدم لدى المورد.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('رجوع لتعديل المبلغ')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('تأكيد الدفع وترحيل الزيادة')),
      ],
    ),
  ) ?? false;
}
