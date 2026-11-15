import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_text_shaper/pdf_text_shaper.dart';
import 'package:printing/printing.dart';

import '../../features/purchases/domain/daily_sheet_models.dart';
import '../../features/suppliers/domain/supplier_accounting_models.dart';

class ReportPdfService {
  ReportPdfService._();

  static Future<Uint8List> buildSupplierStatement({
    required SupplierStatement statement,
    required Map<String, Object?> businessProfile,
    String? branchName,
    String? buyerName,
    String? managerName,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/NotoSansArabic.ttf');
    final font = ShapedFont.fromBytes(
      fontData.buffer.asUint8List(),
      name: 'Noto Sans Arabic',
    );
    final logoBytes = await _readLogo(businessProfile['logo_path'] as String?);
    try {
      final document = pw.Document(
        title: 'Supplier statement - ${statement.supplierName}',
        author: (businessProfile['shop_name'] as String?) ?? 'Purchase Ledger',
      );
      document.addPage(
        pw.MultiPage(
          // Seven Arabic columns require a wider printable area so labels
          // and figures remain legible rather than being clipped in portrait.
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(26, 28, 26, 30),
          header: (context) => _documentHeader(
            font: font,
            shopName:
                (businessProfile['shop_name'] as String?) ?? 'دفتر المشتريات',
            shopNumber: businessProfile['shop_number'] as String?,
            phone: businessProfile['phone'] as String?,
            address: businessProfile['address'] as String?,
            reportTitle: 'كشف حساب مورد',
            reportSubtitle: statement.supplierName,
            logoBytes: logoBytes,
          ),
          footer: (context) => _footer(font, context),
          build: (context) {
            final rows = <pw.TableRow>[
              _tableRow(
                font,
                [
                  'الرصيد الجاري',
                  'دائن',
                  'مدين',
                  'تفاصيل الحركة',
                  'نوع الحركة',
                  'رقم المستند',
                  'التاريخ',
                ],
                header: true,
              ),
              _tableRow(
                font,
                [
                  _money(statement.openingBalanceMinor, statement.currency),
                  '',
                  '',
                  'الرصيد الافتتاحي للفترة',
                  'رصيد افتتاحي',
                  'OPENING',
                  statement.periodFrom ?? '—',
                ],
              ),
              ...statement.movements.map((movement) {
                final debit = movement.signedAmountMinor > 0
                    ? movement.signedAmountMinor
                    : 0;
                final credit = movement.signedAmountMinor < 0
                    ? -movement.signedAmountMinor
                    : 0;
                return _tableRow(
                  font,
                  [
                    _money(movement.runningBalanceMinor, statement.currency),
                    credit == 0 ? '' : _money(credit, statement.currency),
                    debit == 0 ? '' : _money(debit, statement.currency),
                    movement.details,
                    _movementLabel(movement.movementType),
                    movement.documentNumber,
                    movement.entryDate,
                  ],
                );
              }),
            ];

            return [
              _supplierInfo(
                  font, statement, branchName, buyerName, managerName),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.blueGrey300,
                  width: .45,
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.15),
                  1: pw.FlexColumnWidth(1.05),
                  2: pw.FlexColumnWidth(1.05),
                  3: pw.FlexColumnWidth(2.2),
                  4: pw.FlexColumnWidth(1.25),
                  5: pw.FlexColumnWidth(1.25),
                  6: pw.FlexColumnWidth(1.05),
                },
                children: rows,
              ),
              pw.SizedBox(height: 14),
              _summaryBlock(
                  font,
                  [
                    ('إجمالي المشتريات', statement.totalPurchasesMinor),
                    ('إجمالي المدفوعات', statement.totalPaymentsMinor),
                    ('إجمالي المرتجعات', statement.totalReturnsMinor),
                    ('صافي التسويات', statement.totalAdjustmentsMinor),
                    ('الرصيد الختامي', statement.closingBalanceMinor),
                  ],
                  statement.currency),
              pw.SizedBox(height: 10),
              _balanceDescription(
                  font, statement.closingBalanceMinor, statement.currency),
            ];
          },
        ),
      );
      return await document.save();
    } finally {
      font.dispose();
    }
  }

  static Future<void> shareSupplierStatement({
    required SupplierStatement statement,
    required Map<String, Object?> businessProfile,
    String? branchName,
    String? buyerName,
    String? managerName,
  }) async {
    final bytes = await buildSupplierStatement(
      statement: statement,
      businessProfile: businessProfile,
      branchName: branchName,
      buyerName: buyerName,
      managerName: managerName,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'supplier_statement_${statement.supplierId}_${statement.currency}.pdf',
    );
  }

  static Future<void> printSupplierStatement({
    required SupplierStatement statement,
    required Map<String, Object?> businessProfile,
    String? branchName,
    String? buyerName,
    String? managerName,
  }) async {
    final bytes = await buildSupplierStatement(
      statement: statement,
      businessProfile: businessProfile,
      branchName: branchName,
      buyerName: buyerName,
      managerName: managerName,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static Future<Uint8List> buildDailyHandoverReport(
    DailyHandoverReport report,
  ) async {
    final fontData = await rootBundle.load('assets/fonts/NotoSansArabic.ttf');
    final font = ShapedFont.fromBytes(
      fontData.buffer.asUint8List(),
      name: 'Noto Sans Arabic',
    );
    final logoBytes = await _readLogo(report.shopLogoPath);
    try {
      final document = pw.Document(
        title: 'Daily purchase handover - ${report.sheet.sheetNumber}',
        author: report.shopName,
      );
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(22, 24, 22, 28),
          header: (context) => _documentHeader(
            font: font,
            shopName: report.shopName,
            shopNumber: report.shopNumber,
            phone: report.shopPhone,
            address: report.shopAddress,
            reportTitle: 'تقرير تسليم المشتريات اليومية',
            reportSubtitle:
                '${report.sheet.sheetNumber} • ${report.sheet.purchaseDate}',
            logoBytes: logoBytes,
          ),
          footer: (context) => _footer(font, context),
          build: (context) {
            final tableRows = <pw.TableRow>[
              _tableRow(
                font,
                [
                  'ملاحظات',
                  'المتبقي',
                  'المدفوع',
                  'طريقة الدفع',
                  'البائع',
                  'الإجمالي',
                  'سعر الوحدة',
                  'الوحدة',
                  'الكمية',
                  'التصنيف',
                  'اسم المادة',
                  'رقم العملية',
                ],
                header: true,
              ),
              for (final operation in report.sheet.operations)
                for (var itemIndex = 0;
                    itemIndex < operation.items.length;
                    itemIndex++)
                  _tableRow(
                    font,
                    [
                      operation.items[itemIndex].notes ?? operation.notes ?? '',
                      itemIndex == 0
                          ? _money(
                              operation.isSupplierAccount
                                  ? operation.supplierAccountCreditMinor
                                  : operation.outstandingMinor,
                              operation.currency,
                            )
                          : '',
                      itemIndex == 0
                          ? _money(
                              operation.amountPaidMinor +
                                  operation.laterPaidMinor,
                              operation.currency,
                            )
                          : '',
                      itemIndex == 0 ? _dailyPaymentLabel(operation) : '',
                      operation.items[itemIndex].sellerName ??
                          operation.sellerName ??
                          '',
                      _money(operation.items[itemIndex].lineTotalMinor,
                          operation.currency),
                      _money(operation.items[itemIndex].unitPriceMinor,
                          operation.currency),
                      operation.items[itemIndex].unitName,
                      _quantity(operation.items[itemIndex].quantityMilli),
                      operation.items[itemIndex].categoryName ?? '',
                      operation.items[itemIndex].itemName,
                      operation.operationNumber,
                    ],
                  ),
            ];

            return [
              _handoverMetadata(font, report),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.blueGrey300,
                  width: .4,
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.1),
                  1: pw.FlexColumnWidth(1.0),
                  2: pw.FlexColumnWidth(1.0),
                  3: pw.FlexColumnWidth(1.0),
                  4: pw.FlexColumnWidth(1.1),
                  5: pw.FlexColumnWidth(1.1),
                  6: pw.FlexColumnWidth(1.1),
                  7: pw.FlexColumnWidth(.7),
                  8: pw.FlexColumnWidth(.7),
                  9: pw.FlexColumnWidth(1.0),
                  10: pw.FlexColumnWidth(1.5),
                  11: pw.FlexColumnWidth(.9),
                },
                children: tableRows,
              ),
              pw.SizedBox(height: 12),
              ...report.totalsByCurrency.map(
                (total) => _summaryBlock(
                    font,
                    [
                      ('إجمالي المشتريات', total.totalMinor),
                      ('المدفوع عند الشراء', total.cashMinor),
                      ('إجمالي المدفوع حتى التسليم', total.paidMinor),
                      ('المشتريات الآجلة', total.creditMinor),
                      ('المستحقات اليومية المتبقية', total.outstandingMinor),
                      (
                        'المبالغ المسجلة بحساب المورد',
                        total.supplierAccountCreditMinor
                      ),
                    ],
                    total.currency),
              ),
              if (report.amendments.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                _arabicText(font, 'الملاحق والتصحيحات', size: 13, bold: true),
                pw.SizedBox(height: 5),
                ...report.amendments.map((amendment) => pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 5),
                      padding: const pw.EdgeInsets.all(7),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.orange300),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          _arabicText(font,
                              '${amendment.amendmentNumber} • ${amendment.reason}',
                              bold: true),
                          _arabicText(font, amendment.details, size: 9),
                          if (amendment.currency != null &&
                              amendment.amountDeltaMinor != 0)
                            pw.Text(
                              _money(amendment.amountDeltaMinor,
                                  amendment.currency!),
                              textDirection: pw.TextDirection.ltr,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                        ],
                      ),
                    )),
              ],
            ];
          },
        ),
      );
      return await document.save();
    } finally {
      font.dispose();
    }
  }

  static Future<void> shareDailyHandoverReport(
    DailyHandoverReport report,
  ) async {
    final bytes = await buildDailyHandoverReport(report);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'daily_handover_${report.sheet.sheetNumber}.pdf',
    );
  }

  static Future<void> printDailyHandoverReport(
    DailyHandoverReport report,
  ) async {
    final bytes = await buildDailyHandoverReport(report);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static pw.Widget _documentHeader({
    required ShapedFont font,
    required String shopName,
    String? shopNumber,
    String? phone,
    String? address,
    required String reportTitle,
    required String reportSubtitle,
    Uint8List? logoBytes,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 9),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.teal700, width: 1.4),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          if (logoBytes != null)
            pw.Container(
              width: 48,
              height: 48,
              padding: const pw.EdgeInsets.all(2),
              child:
                  pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _arabicText(font, shopName, size: 17, bold: true),
                if (shopNumber != null && shopNumber.isNotEmpty)
                  _arabicText(font, 'رقم المحل: $shopNumber', size: 8),
                if (address != null && address.isNotEmpty)
                  _arabicText(font, address, size: 8),
                if (phone != null && phone.isNotEmpty)
                  pw.Text(phone,
                      textDirection: pw.TextDirection.ltr,
                      style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.teal800,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _arabicText(font, reportTitle,
                    size: 12, bold: true, color: PdfColors.white),
                _arabicText(font, reportSubtitle,
                    size: 9, color: PdfColors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _supplierInfo(
    ShapedFont font,
    SupplierStatement statement,
    String? branchName,
    String? buyerName,
    String? managerName,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Wrap(
        spacing: 18,
        runSpacing: 7,
        children: [
          _infoItem(font, 'المورد', statement.supplierName),
          if (statement.supplierPhone != null)
            _infoItem(font, 'هاتف المورد', statement.supplierPhone!, ltr: true),
          if (statement.supplierAddress != null)
            _infoItem(font, 'عنوان المورد', statement.supplierAddress!),
          _infoItem(font, 'العملة', statement.currency, ltr: true),
          _infoItem(font, 'من تاريخ', statement.periodFrom ?? 'البداية',
              ltr: true),
          _infoItem(font, 'إلى تاريخ', statement.periodTo ?? 'حتى اليوم',
              ltr: true),
          if (branchName != null) _infoItem(font, 'الفرع', branchName),
          if (managerName != null) _infoItem(font, 'المدير', managerName),
          if (buyerName != null) _infoItem(font, 'مسؤول المشتريات', buyerName),
        ],
      ),
    );
  }

  static pw.Widget _handoverMetadata(
    ShapedFont font,
    DailyHandoverReport report,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          _infoItem(font, 'رقم الورقة', report.sheet.sheetNumber, ltr: true),
          _infoItem(font, 'التاريخ', report.sheet.purchaseDate, ltr: true),
          _infoItem(font, 'الفرع', report.branchName ?? '—'),
          _infoItem(font, 'رقم الفرع', report.branchCode ?? '—', ltr: true),
          _infoItem(font, 'المدير', report.managerName ?? '—'),
          _infoItem(font, 'مسؤول المشتريات', report.buyerName ?? '—'),
          _infoItem(font, 'حالة الورقة', _sheetStatus(report.sheet.status)),
        ],
      ),
    );
  }

  static pw.Widget _infoItem(
    ShapedFont font,
    String label,
    String value, {
    bool ltr = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        _arabicText(font, label, size: 8, color: PdfColors.grey700),
        if (ltr)
          pw.Text(value,
              textDirection: pw.TextDirection.ltr,
              style: const pw.TextStyle(fontSize: 9))
        else
          _arabicText(font, value, size: 9, bold: true),
      ],
    );
  }

  static pw.Widget _summaryBlock(
    ShapedFont font,
    List<(String, int)> values,
    String currency,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.teal50,
        border: pw.Border.all(color: PdfColors.teal200),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          for (final item in values)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _arabicText(font, item.$1, size: 8, color: PdfColors.grey700),
                pw.Text(
                  _money(item.$2, currency),
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal900,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static pw.Widget _balanceDescription(
    ShapedFont font,
    int balance,
    String currency,
  ) {
    final label = balance > 0
        ? 'المبلغ الختامي مستحق للمورد على المحل'
        : balance < 0
            ? 'يوجد رصيد مقدم للمحل لدى المورد'
            : 'الحساب متوازن ولا يوجد رصيد مستحق';
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.teal300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            _money(balance.abs(), currency),
            textDirection: pw.TextDirection.ltr,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: balance < 0 ? PdfColors.green800 : PdfColors.red800,
            ),
          ),
          _arabicText(font, label, size: 10, bold: true),
        ],
      ),
    );
  }

  static pw.TableRow _tableRow(
    ShapedFont font,
    List<String> values, {
    bool header = false,
  }) {
    return pw.TableRow(
      decoration:
          header ? const pw.BoxDecoration(color: PdfColors.blueGrey800) : null,
      children: values.map((value) {
        final isNumeric =
            RegExp(r'^[0-9,.\- ]+(?: [A-Z]{3})?$').hasMatch(value) ||
                RegExp(r'^[A-Z0-9\-]+$').hasMatch(value);
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          alignment: pw.Alignment.centerRight,
          child: isNumeric
              ? pw.Text(
                  value,
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    fontSize: header ? 9 : 8,
                    fontWeight:
                        header ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: header ? PdfColors.white : PdfColors.black,
                  ),
                )
              : _arabicText(
                  font,
                  value,
                  size: header ? 9 : 8,
                  bold: header,
                  color: header ? PdfColors.white : PdfColors.black,
                ),
        );
      }).toList(),
    );
  }

  static pw.Widget _arabicText(
    ShapedFont font,
    String value, {
    double size = 9,
    bool bold = false,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: ShapedText(
        value,
        style: ShapedTextStyle(
          font: font,
          fontSize: size,
          color: color,
          preserveUnicodeText: true,
        ),
      ),
    );
  }

  static pw.Widget _footer(ShapedFont font, pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: .5),
        ),
      ),
      child: _arabicText(
        font,
        'دفتر المشتريات • صفحة ${context.pageNumber} من ${context.pagesCount}',
        size: 7,
        color: PdfColors.grey700,
      ),
    );
  }

  static Future<Uint8List?> _readLogo(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static String _money(int minor, String currency) {
    final negative = minor < 0;
    final value = minor.abs();
    final whole = (value ~/ 100).toString();
    final grouped = whole.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    final fraction = (value % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$grouped.$fraction $currency';
  }

  static String _quantity(int milli) {
    final whole = milli ~/ 1000;
    final fraction = milli % 1000;
    if (fraction == 0) return '$whole';
    return '$whole.${fraction.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
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

  static String _movementLabel(String type) {
    switch (type) {
      case 'opening_balance':
        return 'رصيد افتتاحي';
      case 'credit_invoice':
        return 'مشتريات آجلة';
      case 'payment':
        return 'دفعة للمورد';
      case 'purchase_return':
        return 'مرتجع مشتريات';
      case 'daily_purchase':
        return 'شراء يومي على حساب المورد';
      case 'adjustment':
        return 'تسوية حساب';
      case 'reversal':
        return 'عكس حركة';
      default:
        return type;
    }
  }

  static String _sheetStatus(String status) {
    switch (status) {
      case 'DRAFT':
        return 'مسودة';
      case 'READY_FOR_HANDOVER':
        return 'جاهزة للتسليم';
      case 'HANDED_OVER':
        return 'تم التسليم';
      case 'CLOSED':
        return 'مغلقة';
      default:
        return status;
    }
  }
}
