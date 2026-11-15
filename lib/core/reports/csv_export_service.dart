import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/purchases/domain/daily_sheet_models.dart';
import '../../features/suppliers/domain/supplier_accounting_models.dart';

class CsvExportService {
  CsvExportService._();

  static Future<ShareResult> shareDailyHandover(
      DailyHandoverReport report) async {
    final rows = <List<Object?>>[
      ['اسم المحل', report.shopName],
      ['رقم المحل', report.shopNumber ?? ''],
      ['الهاتف', report.shopPhone ?? ''],
      ['العنوان', report.shopAddress ?? ''],
      ['الفرع', report.branchName ?? ''],
      ['رقم الفرع', report.branchCode ?? ''],
      ['المدير', report.managerName ?? ''],
      ['مسؤول المشتريات', report.buyerName ?? ''],
      ['تاريخ التقرير', report.sheet.purchaseDate],
      ['رقم ورقة المشتريات', report.sheet.sheetNumber],
      [],
      ['تفاصيل الأصناف'],
      [
        'رقم العملية',
        'اسم المادة',
        'التصنيف',
        'الكمية',
        'الوحدة',
        'سعر الوحدة',
        'الخصم',
        'الضريبة',
        'إجمالي الصنف',
        'البائع',
        'ملاحظات',
      ],
    ];

    for (final operation in report.sheet.operations) {
      for (final item in operation.items) {
        rows.add([
          operation.operationNumber,
          item.itemName,
          item.categoryName ?? '',
          _quantity(item.quantityMilli),
          item.unitName,
          _money(item.unitPriceMinor),
          _money(item.discountMinor),
          _money(item.taxMinor),
          _money(item.lineTotalMinor),
          item.sellerName ?? operation.sellerName ?? '',
          item.notes ?? operation.notes ?? '',
        ]);
      }
    }

    // Operation-level amounts are exported once per operation, not repeated
    // on every item row where they would be double-counted in spreadsheets.
    rows.add([]);
    rows.add(['ملخص العمليات']);
    rows.add([
      'رقم العملية',
      'مسار الحساب',
      'المورد / البائع',
      'العملة',
      'إجمالي العملية',
      'طريقة الدفع عند الشراء',
      'المدفوع عند الشراء',
      'المدفوع لاحقاً',
      'المتبقي',
      'تاريخ الاستحقاق',
      'الحالة',
      'ملاحظات',
    ]);
    for (final operation in report.sheet.operations) {
      rows.add([
        operation.operationNumber,
        operation.isSupplierAccount ? 'حساب المورد' : 'مستحق يومي',
        operation.supplierName ?? operation.sellerName ?? '',
        operation.currency,
        _money(operation.totalMinor),
        _dailyPaymentLabel(operation),
        _money(operation.amountPaidMinor),
        _money(operation.laterPaidMinor),
        _money(
            operation.outstandingMinor + operation.supplierAccountCreditMinor),
        operation.dueDate ?? '',
        operation.status,
        operation.notes ?? '',
      ]);
    }

    rows.add([]);
    rows.add(['ملخص حسب العملة']);
    rows.add([
      'العملة',
      'إجمالي المشتريات',
      'المدفوع عند الشراء',
      'إجمالي المدفوع',
      'المشتريات الآجلة',
      'المستحق اليومي المتبقي',
      'المسجل بحساب المورد',
    ]);
    for (final total in report.totalsByCurrency) {
      rows.add([
        total.currency,
        _money(total.totalMinor),
        _money(total.cashMinor),
        _money(total.paidMinor),
        _money(total.creditMinor),
        _money(total.outstandingMinor),
        _money(total.supplierAccountCreditMinor),
      ]);
    }

    if (report.amendments.isNotEmpty) {
      rows.add([]);
      rows.add(['الملاحق والتصحيحات']);
      rows.add([
        'رقم الملحق',
        'السبب',
        'التفاصيل',
        'العملة',
        'فرق المبلغ',
        'تاريخ الإضافة'
      ]);
      for (final amendment in report.amendments) {
        rows.add([
          amendment.amendmentNumber,
          amendment.reason,
          amendment.details,
          amendment.currency ?? '',
          _money(amendment.amountDeltaMinor),
          amendment.createdAt,
        ]);
      }
    }

    final path = await _writeCsv(
      rows,
      'daily_handover_${report.sheet.sheetNumber}.csv',
    );
    return SharePlus.instance.share(
      ShareParams(
        title: 'Daily purchase handover',
        subject: 'Daily purchase handover ${report.sheet.sheetNumber}',
        files: [XFile(path, mimeType: 'text/csv')],
      ),
    );
  }

  static Future<ShareResult> shareSupplierStatement(
    SupplierStatement statement, {
    required String shopName,
    String? shopNumber,
    String? shopAddress,
    String? shopPhone,
    String? branchName,
    String? managerName,
    String? buyerName,
  }) async {
    final rows = <List<Object?>>[
      ['اسم المحل', shopName],
      ['رقم المحل', shopNumber ?? ''],
      ['عنوان المحل', shopAddress ?? ''],
      ['هاتف المحل', shopPhone ?? ''],
      ['الفرع', branchName ?? ''],
      ['المدير', managerName ?? ''],
      ['مسؤول المشتريات', buyerName ?? ''],
      ['اسم المورد', statement.supplierName],
      ['هاتف المورد', statement.supplierPhone ?? ''],
      ['عنوان المورد', statement.supplierAddress ?? ''],
      ['العملة', statement.currency],
      ['من تاريخ', statement.periodFrom ?? 'البداية'],
      ['إلى تاريخ', statement.periodTo ?? 'حتى اليوم'],
      [],
      [
        'التاريخ',
        'رقم المستند',
        'نوع الحركة',
        'التفاصيل',
        'مدين',
        'دائن',
        'الرصيد الجاري'
      ],
      [
        statement.periodFrom ?? '',
        'OPENING',
        'رصيد افتتاحي',
        'الرصيد الافتتاحي للفترة',
        '',
        '',
        _money(statement.openingBalanceMinor),
      ],
    ];
    for (final movement in statement.movements) {
      rows.add([
        movement.entryDate,
        movement.documentNumber,
        movement.movementType,
        movement.details,
        movement.signedAmountMinor > 0
            ? _money(movement.signedAmountMinor)
            : '',
        movement.signedAmountMinor < 0
            ? _money(-movement.signedAmountMinor)
            : '',
        _money(movement.runningBalanceMinor),
      ]);
    }
    rows.add([]);
    rows.add(['الملخص']);
    rows.add(['إجمالي المشتريات', _money(statement.totalPurchasesMinor)]);
    rows.add(['إجمالي المدفوعات', _money(statement.totalPaymentsMinor)]);
    rows.add(['إجمالي المرتجعات', _money(statement.totalReturnsMinor)]);
    rows.add(['صافي التسويات', _money(statement.totalAdjustmentsMinor)]);
    rows.add(['الرصيد الختامي', _money(statement.closingBalanceMinor)]);
    rows.add([
      'طبيعة الرصيد',
      statement.closingBalanceMinor > 0
          ? 'مستحق للمورد على المحل'
          : statement.closingBalanceMinor < 0
              ? 'رصيد مقدم للمحل لدى المورد'
              : 'الحساب متوازن',
    ]);

    final path = await _writeCsv(
      rows,
      'supplier_statement_${statement.supplierId}_${statement.currency}.csv',
    );
    return SharePlus.instance.share(
      ShareParams(
        title: 'Supplier account statement',
        subject: 'Supplier statement ${statement.supplierName}',
        files: [XFile(path, mimeType: 'text/csv')],
      ),
    );
  }

  static String _dailyPaymentLabel(DailyPurchaseOperation operation) {
    final method = switch (operation.paymentMethod) {
      'cash' => 'نقداً',
      'bank_transfer' => 'تحويل بنكي',
      'wallet' => 'محفظة إلكترونية',
      'cheque' => 'شيك',
      'other' => 'أخرى',
      _ => 'غير محدد',
    };
    if (operation.isSupplierAccount) {
      return operation.amountPaidMinor > 0
          ? 'حساب المورد • دفعة عند الشراء: $method'
          : 'حساب المورد';
    }
    if (operation.amountPaidMinor <= 0) return 'آجل';
    if (operation.amountPaidMinor < operation.totalMinor) {
      return 'مدفوع جزئياً • $method';
    }
    return method;
  }

  static Future<String> _writeCsv(
      List<List<Object?>> rows, String fileName) async {
    final buffer = StringBuffer('\uFEFF');
    for (final row in rows) {
      buffer.writeln(row.map(_escape).join(','));
    }
    final directory = await getTemporaryDirectory();
    final folder = Directory(p.join(directory.path, 'purchase_ledger_exports'));
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File(p.join(folder.path, fileName));
    await file.writeAsString(buffer.toString(), encoding: utf8, flush: true);
    return file.path;
  }

  static String _escape(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""').replaceAll('\r', ' ').replaceAll('\n', ' ')}"';
  }

  static String _money(int minor) {
    final sign = minor < 0 ? '-' : '';
    final value = minor.abs();
    final whole = (value ~/ 100).toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
    return '$sign$whole.${(value % 100).toString().padLeft(2, '0')}';
  }

  static String _quantity(int milli) {
    final whole = milli ~/ 1000;
    final fraction = milli % 1000;
    if (fraction == 0) return '$whole';
    return '$whole.${fraction.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  }
}
