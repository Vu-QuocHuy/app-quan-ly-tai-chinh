import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/utils/money_formatter.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/backup_provider.dart';
import 'encrypted_backup_service.dart';

class InvoiceExportService {
  const InvoiceExportService({BackupProvider? provider})
    : _provider = provider ?? const FilePickerBackupProvider();

  final BackupProvider _provider;

  Future<Uri?> exportJson(Iterable<InvoiceEntity> invoices) {
    final bytes = Uint8List.fromList(
      utf8.encode(InvoiceExportFormatter.toJson(invoices)),
    );
    return _provider.save(
      BackupArtifact(
        type: BackupArtifactType.json,
        extension: 'json',
        mimeType: 'application/json',
        fileName: 'hoadon-insight-${_timestamp()}.json',
        bytes: bytes,
      ),
    );
  }

  Future<Uri?> exportEncryptedJson(
    Iterable<InvoiceEntity> invoices,
    String password,
  ) async {
    final plaintext = InvoiceExportFormatter.toJson(invoices);
    final encrypted = await const EncryptedBackupService().encrypt(
      plaintext,
      password,
    );
    return _provider.save(
      BackupArtifact(
        type: BackupArtifactType.encrypted,
        extension: 'hdbak',
        mimeType: 'application/octet-stream',
        fileName: 'hoadon-insight-encrypted-${_timestamp()}.hdbak',
        bytes: Uint8List.fromList(utf8.encode(encrypted)),
      ),
    );
  }

  Future<Uri?> exportCsv(Iterable<InvoiceEntity> invoices) {
    final bytes = Uint8List.fromList(
      utf8.encode(InvoiceExportFormatter.toCsv(invoices)),
    );
    return _provider.save(
      BackupArtifact(
        type: BackupArtifactType.csv,
        extension: 'csv',
        mimeType: 'text/csv',
        fileName: 'hoadon-insight-${_timestamp()}.csv',
        bytes: bytes,
      ),
    );
  }

  Future<Uri?> exportPdf({
    required Iterable<InvoiceEntity> invoices,
    required DashboardSnapshot dashboard,
    required Iterable<CategoryEntity> categories,
  }) {
    final bytes = InvoiceReportPdfFormatter.toPdf(
      invoices: invoices,
      dashboard: dashboard,
      categories: categories,
    );
    return _provider.save(
      BackupArtifact(
        type: BackupArtifactType.pdf,
        extension: 'pdf',
        mimeType: 'application/pdf',
        fileName: 'hoadon-insight-report-${_timestamp()}.pdf',
        bytes: bytes,
      ),
    );
  }

  String _timestamp() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}$month$day';
  }
}

abstract final class InvoiceReportPdfFormatter {
  static Uint8List toPdf({
    required Iterable<InvoiceEntity> invoices,
    required DashboardSnapshot dashboard,
    required Iterable<CategoryEntity> categories,
  }) {
    final categoryNames = {
      for (final category in categories) category.id: category.name,
    };
    final orderedInvoices = invoices.toList()
      ..sort((left, right) {
        final leftDate = left.issuedAt ?? left.createdAt;
        final rightDate = right.issuedAt ?? right.createdAt;
        return rightDate.compareTo(leftDate);
      });
    final body = <_PdfLine>[
      _PdfLine('Ky: ${_monthLabel(dashboard.monthKey)}', size: 11, bold: true),
      _PdfLine('Ngay tao: ${_date(DateTime.now())}'),
      const _PdfLine('Bao cao tham khao, khong phai chung tu thue.'),
      const _PdfLine(''),
      const _PdfLine('TONG QUAN', size: 13, bold: true),
      _PdfLine('Tong chi: ${_money(dashboard.totalMinor)}'),
      _PdfLine('So hoa don: ${dashboard.invoiceCount}'),
      _PdfLine('Thang truoc: ${_money(dashboard.previousMonthTotalMinor)}'),
      _PdfLine(
        dashboard.budgetLimitMinor <= 0
            ? 'Ngan sach: Chua thiet lap'
            : 'Ngan sach: ${_money(dashboard.totalMinor)} / '
                  '${_money(dashboard.budgetLimitMinor)} '
                  '(${(dashboard.budgetProgress * 100).round()}%)',
      ),
      const _PdfLine(''),
      const _PdfLine('THEO DANH MUC', size: 13, bold: true),
      ..._categoryLines(dashboard, categoryNames),
      const _PdfLine(''),
      const _PdfLine('DANH SACH HOA DON', size: 13, bold: true),
      if (orderedInvoices.isEmpty) const _PdfLine('Chua co hoa don.'),
      if (orderedInvoices.isNotEmpty)
        const _PdfLine(
          'STT | NGUOI BAN | NGAY | TONG TIEN',
          size: 9,
          bold: true,
        ),
      ...orderedInvoices.indexed.expand(
        (entry) => [
          _PdfLine(
            '${(entry.$1 + 1).toString().padLeft(3)} | '
            '${_truncate(_ascii(entry.$2.sellerName), 25).padRight(25)} | '
            '${_date(entry.$2.issuedAt ?? entry.$2.createdAt)} | '
            '${_money(entry.$2.totalMinor)}',
            size: 9,
          ),
        ],
      ),
    ];

    final chunks = <List<_PdfLine>>[];
    const bodyLinesPerPage = 44;
    for (var index = 0; index < body.length; index += bodyLinesPerPage) {
      final end = index + bodyLinesPerPage < body.length
          ? index + bodyLinesPerPage
          : body.length;
      chunks.add(body.sublist(index, end));
    }
    if (chunks.isEmpty) chunks.add(const []);

    final objects = <String>['<< /Type /Catalog /Pages 2 0 R >>', ''];
    final pageNumbers = <int>[];
    for (var index = 0; index < chunks.length; index++) {
      final pageNumber = objects.length + 1;
      final contentNumber = pageNumber + 1;
      pageNumbers.add(pageNumber);
      final lines = <_PdfLine>[
        const _PdfLine('HOA DON INSIGHT', size: 17, bold: true),
        _PdfLine(
          'BAO CAO CHI TIEU THAM KHAO - Trang ${index + 1}/${chunks.length}',
          size: 10,
          bold: true,
        ),
        const _PdfLine(''),
        ...chunks[index],
      ];
      final content = _pageContent(lines);
      final contentBytes = latin1.encode(content);
      objects.add(
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 ${3 + chunks.length * 2} 0 R '
        '/F2 ${4 + chunks.length * 2} 0 R >> >> '
        '/Contents $contentNumber 0 R >>',
      );
      objects.add(
        '<< /Length ${contentBytes.length} >>\nstream\n$content\nendstream',
      );
    }
    objects[1] =
        '<< /Type /Pages /Kids [${pageNumbers.map((number) => '$number 0 R').join(' ')}] '
        '/Count ${pageNumbers.length} >>';
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>');
    return _serializePdf(objects);
  }

  static List<_PdfLine> _categoryLines(
    DashboardSnapshot dashboard,
    Map<String, String> categoryNames,
  ) {
    if (dashboard.categoryTotals.isEmpty) {
      return const [_PdfLine('Chua co du lieu danh muc.')];
    }
    final entries = dashboard.categoryTotals.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return entries
        .map((entry) {
          final percent = dashboard.totalMinor <= 0
              ? '0.0'
              : (entry.value / dashboard.totalMinor * 100).toStringAsFixed(1);
          return _PdfLine(
            '${_truncate(_ascii(categoryNames[entry.key] ?? entry.key), 28).padRight(28)} | '
            '${_money(entry.value).padLeft(15)} | $percent%',
            size: 9,
          );
        })
        .toList(growable: false);
  }

  static String _pageContent(List<_PdfLine> lines) {
    final buffer = StringBuffer();
    var y = 800.0;
    for (final line in lines) {
      if (line.text.isEmpty) {
        y -= 9;
        continue;
      }
      final font = line.bold ? '/F2' : '/F1';
      buffer
        ..write('BT\n')
        ..write('$font ${line.size} Tf\n')
        ..write('40 ${y.toStringAsFixed(2)} Td\n')
        ..write('(${_escape(line.text)}) Tj\n')
        ..write('ET\n');
      y -= line.size + 5;
    }
    return buffer.toString();
  }

  static Uint8List _serializePdf(List<String> objects) {
    final buffer = StringBuffer('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    final offsets = <int>[0];
    for (var index = 0; index < objects.length; index++) {
      offsets.add(latin1.encode(buffer.toString()).length);
      buffer
        ..write('${index + 1} 0 obj\n')
        ..write(objects[index])
        ..write('\nendobj\n');
    }
    final xrefOffset = latin1.encode(buffer.toString()).length;
    buffer
      ..write('xref\n0 ${objects.length + 1}\n')
      ..write('0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    buffer
      ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
      ..write('startxref\n$xrefOffset\n%%EOF\n');
    return Uint8List.fromList(latin1.encode(buffer.toString()));
  }

  static String _money(int value) =>
      _ascii(MoneyFormatter.format(value)).replaceAll('₫', 'VND');

  static String _monthLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    return 'Thang ${parts[1]}/${parts[0]}';
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 3)}...';
  }

  static String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');

  static String _ascii(String value) {
    const replacements = {
      'à': 'a',
      'á': 'a',
      'ả': 'a',
      'ã': 'a',
      'ạ': 'a',
      'ă': 'a',
      'ằ': 'a',
      'ắ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'ặ': 'a',
      'â': 'a',
      'ầ': 'a',
      'ấ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ậ': 'a',
      'đ': 'd',
      'è': 'e',
      'é': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ẹ': 'e',
      'ê': 'e',
      'ề': 'e',
      'ế': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ệ': 'e',
      'ì': 'i',
      'í': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ị': 'i',
      'ò': 'o',
      'ó': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ọ': 'o',
      'ô': 'o',
      'ồ': 'o',
      'ố': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ộ': 'o',
      'ơ': 'o',
      'ờ': 'o',
      'ớ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ợ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ụ': 'u',
      'ư': 'u',
      'ừ': 'u',
      'ứ': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ự': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'ỵ': 'y',
      'À': 'A',
      'Á': 'A',
      'Ả': 'A',
      'Ã': 'A',
      'Ạ': 'A',
      'Ă': 'A',
      'Ằ': 'A',
      'Ắ': 'A',
      'Ẳ': 'A',
      'Ẵ': 'A',
      'Ặ': 'A',
      'Â': 'A',
      'Ầ': 'A',
      'Ấ': 'A',
      'Ẩ': 'A',
      'Ẫ': 'A',
      'Ậ': 'A',
      'Đ': 'D',
      'È': 'E',
      'É': 'E',
      'Ẻ': 'E',
      'Ẽ': 'E',
      'Ẹ': 'E',
      'Ê': 'E',
      'Ề': 'E',
      'Ế': 'E',
      'Ể': 'E',
      'Ễ': 'E',
      'Ệ': 'E',
      'Ì': 'I',
      'Í': 'I',
      'Ỉ': 'I',
      'Ĩ': 'I',
      'Ị': 'I',
      'Ò': 'O',
      'Ó': 'O',
      'Ỏ': 'O',
      'Õ': 'O',
      'Ọ': 'O',
      'Ô': 'O',
      'Ồ': 'O',
      'Ố': 'O',
      'Ổ': 'O',
      'Ỗ': 'O',
      'Ộ': 'O',
      'Ơ': 'O',
      'Ờ': 'O',
      'Ớ': 'O',
      'Ở': 'O',
      'Ỡ': 'O',
      'Ợ': 'O',
      'Ù': 'U',
      'Ú': 'U',
      'Ủ': 'U',
      'Ũ': 'U',
      'Ụ': 'U',
      'Ư': 'U',
      'Ừ': 'U',
      'Ứ': 'U',
      'Ử': 'U',
      'Ữ': 'U',
      'Ự': 'U',
      'Ỳ': 'Y',
      'Ý': 'Y',
      'Ỷ': 'Y',
      'Ỹ': 'Y',
      'Ỵ': 'Y',
      '₫': 'VND',
      '·': '-',
      '–': '-',
      '—': '-',
      '…': '...',
      '“': '"',
      '”': '"',
      '‘': "'",
      '’': "'",
    };
    var result = value;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}

class _PdfLine {
  const _PdfLine(this.text, {this.size = 10, this.bold = false});

  final String text;
  final int size;
  final bool bold;
}

abstract final class InvoiceExportFormatter {
  static String toJson(Iterable<InvoiceEntity> invoices) {
    final payload = <String, Object?>{
      'format': 'hoadon-insight.invoice-export',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'invoices': invoices.map(_invoiceToMap).toList(growable: false),
    };
    payload['checksumSha256'] = sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static String toCsv(Iterable<InvoiceEntity> invoices) {
    final rows = <List<String>>[
      [
        'id',
        'seller_name',
        'seller_tax_code',
        'invoice_number',
        'invoice_symbol',
        'issued_at',
        'currency',
        'subtotal_minor',
        'tax_minor',
        'total_minor',
        'source',
        'status',
        'category_id',
        'confirmed_at',
        'line_count',
        'line_items_json',
      ],
      ...invoices.map(
        (invoice) => [
          invoice.id,
          invoice.sellerName,
          invoice.sellerTaxCode ?? '',
          invoice.invoiceNumber ?? '',
          invoice.invoiceSymbol ?? '',
          invoice.issuedAt?.toIso8601String() ?? '',
          invoice.currencyCode,
          invoice.subtotalMinor.toString(),
          invoice.taxMinor.toString(),
          invoice.totalMinor.toString(),
          invoice.sourceType.name,
          invoice.status.name,
          invoice.categoryId ?? '',
          invoice.confirmedAt?.toIso8601String() ?? '',
          invoice.lines.length.toString(),
          jsonEncode(
            invoice.lines
                .map(
                  (line) => {
                    'description': line.description,
                    'quantity': line.quantity,
                    'unitPriceMinor': line.unitPriceMinor,
                    'taxRate': line.taxRate,
                    'totalMinor': line.totalMinor,
                    'categoryId': line.categoryId,
                  },
                )
                .toList(growable: false),
          ),
        ],
      ),
    ];
    return '\uFEFF${rows.map((row) => row.map(_csvCell).join(',')).join('\n')}\n';
  }

  static Map<String, Object?> _invoiceToMap(InvoiceEntity invoice) {
    return {
      'id': invoice.id,
      'sellerName': invoice.sellerName,
      'sellerTaxCode': invoice.sellerTaxCode,
      'invoiceNumber': invoice.invoiceNumber,
      'invoiceSymbol': invoice.invoiceSymbol,
      'issuedAt': invoice.issuedAt?.toIso8601String(),
      'currencyCode': invoice.currencyCode,
      'subtotalMinor': invoice.subtotalMinor,
      'taxMinor': invoice.taxMinor,
      'totalMinor': invoice.totalMinor,
      'sourceType': invoice.sourceType.name,
      'sourceHash': invoice.sourceHash,
      'status': invoice.status.name,
      'categoryId': invoice.categoryId,
      'notes': invoice.notes,
      'tags': invoice.tags,
      'createdAt': invoice.createdAt.toIso8601String(),
      'updatedAt': invoice.updatedAt.toIso8601String(),
      'confirmedAt': invoice.confirmedAt?.toIso8601String(),
      'lines': invoice.lines
          .map(
            (line) => {
              'id': line.id,
              'description': line.description,
              'quantity': line.quantity,
              'unitPriceMinor': line.unitPriceMinor,
              'taxRate': line.taxRate,
              'totalMinor': line.totalMinor,
              'categoryId': line.categoryId,
            },
          )
          .toList(growable: false),
      'evidence': invoice.evidence
          .map(
            (item) => {
              'id': item.id,
              'fieldName': item.fieldName,
              'rawValue': item.rawValue,
              'normalizedValue': item.normalizedValue,
              'source': item.source.name,
              'confidence': item.confidence,
              'correctedByUser': item.correctedByUser,
            },
          )
          .toList(growable: false),
    };
  }

  static String _csvCell(String value) {
    if (!value.contains(RegExp(r'[",\n\r]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
