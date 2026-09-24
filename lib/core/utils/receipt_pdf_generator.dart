import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class ReceiptPdfGenerator {
  static const _primaryColor = PdfColor.fromInt(0xFF0D6B4E);
  static const _secondaryColor = PdfColor.fromInt(0xFF1E293B);
  static const _borderColor = PdfColor.fromInt(0xFFE2E8F0);

  static Future<void> printFeeReceipt({
    required String studentName,
    required String grNo,
    required String className,
    required double amountPaid,
    required String feeType,
    required double remainingBalance,
    required String date,
    String? receiptNo,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    
    final finalReceiptNo = (receiptNo != null && receiptNo.trim().isNotEmpty)
        ? receiptNo.trim()
        : 'FE-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final formattedDate = DateFormat('MMM dd, yyyy').format(DateTime.tryParse(date) ?? DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MADARSA EDUCATION SOCIETY',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 14,
                          color: _primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Pincode Area, Delhi, India',
                        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: _primaryColor,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      'FEE RECEIPT',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 10,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(color: _borderColor, thickness: 1),
              pw.SizedBox(height: 8),

              // Meta Details
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Receipt No: $finalReceiptNo', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  pw.Text('Date: $formattedDate', style: pw.TextStyle(font: font, fontSize: 9)),
                ],
              ),
              pw.SizedBox(height: 12),

              // Student details card
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: _borderColor),
                ),
                child: pw.Column(
                  children: [
                    _buildRowDetail(font, fontBold, 'Student Name:', studentName),
                    pw.SizedBox(height: 4),
                    _buildRowDetail(font, fontBold, 'GR Number:', grNo),
                    pw.SizedBox(height: 4),
                    _buildRowDetail(font, fontBold, 'Class Name:', className),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Items Table
              pw.Table(
                border: pw.TableBorder.all(color: _borderColor, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Description', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Amount', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('$feeType Payment', style: pw.TextStyle(font: font, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Rs. ${amountPaid.toStringAsFixed(2)}', style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Summary card
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Total Paid: Rs. ${amountPaid.toStringAsFixed(2)}',
                        style: pw.TextStyle(font: fontBold, fontSize: 10, color: _primaryColor),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Remaining Balance: Rs. ${remainingBalance.toStringAsFixed(2)}',
                        style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.red900),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 80, height: 0.5, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Receiver Signature', style: pw.TextStyle(font: font, fontSize: 7)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 80, height: 0.5, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Authorized Signatory', style: pw.TextStyle(font: font, fontSize: 7)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Receipt_${studentName.replaceAll(' ', '_')}.pdf');
  }

  static Future<void> printDonationReceipt({
    String? receiptNo,
    required String? donorName,
    required String? donorPhone,
    String? village,
    String? taluka,
    String? district,
    String? state,
    String? country,
    String? pinCode,
    required double amount,
    required String donationType,
    required String paymentMethod,
    required String date,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    
    final finalReceiptNo = (receiptNo != null && receiptNo.trim().isNotEmpty)
        ? receiptNo.trim()
        : 'DN-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final formattedDate = DateFormat('MMM dd, yyyy').format(DateTime.tryParse(date) ?? DateTime.now());

    final addressParts = [village, taluka, district, state, country, pinCode]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .toList();
    final fullAddressStr = addressParts.isNotEmpty ? addressParts.join(', ') : '-';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MADARSA EDUCATION SOCIETY',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 14,
                          color: _primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Pincode Area, Delhi, India',
                        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: _primaryColor,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      'DONATION RECEIPT',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 10,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(color: _borderColor, thickness: 1),
              pw.SizedBox(height: 8),

              // Meta Details
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Receipt No: $finalReceiptNo', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  pw.Text('Date: $formattedDate', style: pw.TextStyle(font: font, fontSize: 9)),
                ],
              ),
              pw.SizedBox(height: 12),

              // Donor details card
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: _borderColor),
                ),
                child: pw.Column(
                  children: [
                    _buildRowDetail(font, fontBold, 'Donor Name:', donorName ?? 'Anonymous (Lillah)'),
                    pw.SizedBox(height: 4),
                    _buildRowDetail(font, fontBold, 'Contact Number:', donorPhone ?? '-'),
                    pw.SizedBox(height: 4),
                    _buildRowDetail(font, fontBold, 'Address / Location:', fullAddressStr),
                    pw.SizedBox(height: 4),
                    _buildRowDetail(font, fontBold, 'Payment Method:', paymentMethod),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Items Table
              pw.Table(
                border: pw.TableBorder.all(color: _borderColor, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Contribution Category', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Amount', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('$donationType Contribution', style: pw.TextStyle(font: font, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Rs. ${amount.toStringAsFixed(2)}', style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Summary
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    'Total Contributed: Rs. ${amount.toStringAsFixed(2)}',
                    style: pw.TextStyle(font: fontBold, fontSize: 10, color: _primaryColor),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'May Allah reward you abundantly for your generous contribution. Ameen.',
                  style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 80, height: 0.5, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Receiver Signature', style: pw.TextStyle(font: font, fontSize: 7)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 80, height: 0.5, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Authorized Signatory', style: pw.TextStyle(font: font, fontSize: 7)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'DonationReceipt_${receiptNo}.pdf');
  }

  static Future<void> printPurchaseSellInvoice({
    required String receiptNo,
    required String type, // 'Purchase' or 'Sell'
    required String category,
    required String contactPerson,
    required String date,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    String? remarks,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    
    final isPurchase = type == 'Purchase';
    final formattedDate = DateFormat('MMM dd, yyyy').format(DateTime.tryParse(date) ?? DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MADARSA EDUCATION SOCIETY',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 16,
                          color: _primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Pincode Area, Delhi, India',
                        style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: isPurchase ? _primaryColor : PdfColor.fromInt(0xFF1E3A8A), // Green for Purchase, Blue for Sell
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      isPurchase ? 'PURCHASE INVOICE' : 'SALES INVOICE',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 11,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: _borderColor, thickness: 1),
              pw.SizedBox(height: 12),

              // Meta Details
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Receipt/Bill No: $receiptNo', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                  pw.Text('Date: $formattedDate', style: pw.TextStyle(font: font, fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 16),

              // Contact Details Card
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: _borderColor),
                ),
                child: pw.Column(
                  children: [
                    _buildRowDetail(font, fontBold, isPurchase ? 'Supplier Name:' : 'Customer Name:', contactPerson),
                    pw.SizedBox(height: 6),
                    _buildRowDetail(font, fontBold, 'Category:', category),
                    if (remarks != null && remarks.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      _buildRowDetail(font, fontBold, 'Remarks:', remarks),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Items Table Header
              pw.Text('Billing Items List', style: pw.TextStyle(font: fontBold, fontSize: 11, color: _primaryColor)),
              pw.SizedBox(height: 8),
              
              // Table of items
              pw.Table(
                border: pw.TableBorder.all(color: _borderColor, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3), // Item Name
                  1: const pw.FlexColumnWidth(1), // Quantity
                  2: const pw.FlexColumnWidth(1), // Unit
                  3: const pw.FlexColumnWidth(1.5), // Price/Unit
                  4: const pw.FlexColumnWidth(1.5), // Total
                },
                children: [
                  // Table Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Item Name / Description', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Quantity', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Unit', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Unit Price', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Total', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                  // Table Data Rows
                  ...items.map((item) {
                    final qty = double.tryParse(item['quantity']?.toString() ?? '0') ?? 0.0;
                    final price = double.tryParse(item['price_per_unit']?.toString() ?? '0') ?? 0.0;
                    final total = double.tryParse(item['total_price']?.toString() ?? '0') ?? 0.0;
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(item['item_name']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(qty.toStringAsFixed(1), style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.right),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(item['unit']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Rs. ${price.toStringAsFixed(2)}', style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.right),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Rs. ${total.toStringAsFixed(2)}', style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.right),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 24),

              // Grand Total Display
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('Grand Total: ', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                  pw.Text(
                    'Rs. ${totalAmount.toStringAsFixed(2)}',
                    style: pw.TextStyle(font: fontBold, fontSize: 13, color: isPurchase ? _primaryColor : PdfColor.fromInt(0xFF1E3A8A)),
                  ),
                ],
              ),
              
              pw.Spacer(),
              
              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 100, height: 0.5, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text(isPurchase ? 'Prepared By' : 'Customer Signature', style: pw.TextStyle(font: font, fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 100, height: 0.5, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Authorized Seal & Signatory', style: pw.TextStyle(font: font, fontSize: 8)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Invoice_${receiptNo}.pdf');
  }

  static pw.Widget _buildRowDetail(pw.Font font, pw.Font fontBold, String label, String value) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 80,
          child: pw.Text(
            label,
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(font: fontBold, fontSize: 8, color: _secondaryColor),
          ),
        ),
      ],
    );
  }

  static Future<void> printDailyMenuRationIssue({
    required String dayOfWeek,
    required String date,
    required List<Map<String, dynamic>> ingredients,
    required double totalCost,
    String? remarks,
  }) async {
    final pdf = pw.Document();

    final font = await PdfGoogleFonts.poppinsRegular();
    final fontBold = await PdfGoogleFonts.poppinsBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Design
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'JAMIA ARABIA MASJID-E-IBRAHIM',
                        style: pw.TextStyle(font: fontBold, fontSize: 13, color: _primaryColor),
                      ),
                      pw.Text(
                        'DAILY MENU RATION ISSUE SHEET',
                        style: pw.TextStyle(font: fontBold, fontSize: 10, color: _secondaryColor),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: $date', style: pw.TextStyle(font: font, fontSize: 8)),
                      pw.Text('Day: $dayOfWeek', style: pw.TextStyle(font: fontBold, fontSize: 9, color: _primaryColor)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1.5, color: _primaryColor),
              pw.SizedBox(height: 16),

              // Detail Section Card
              pw.Container(
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                padding: const pw.EdgeInsets.all(12),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Issue Details', style: pw.TextStyle(font: fontBold, fontSize: 9, color: _primaryColor)),
                    pw.SizedBox(height: 6),
                    _buildRowDetail(font, fontBold, 'Menu Day:', dayOfWeek),
                    _buildRowDetail(font, fontBold, 'Issue Date:', date),
                    if (remarks != null) _buildRowDetail(font, fontBold, 'Remarks:', remarks),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Ingredients Issued Table
              pw.Text('Ingredients Consumed / Issued', style: pw.TextStyle(font: fontBold, fontSize: 10, color: _primaryColor)),
              pw.SizedBox(height: 8),

              pw.Table(
                border: const pw.TableBorder(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3), // Ingredient Name
                  1: const pw.FlexColumnWidth(1), // Quantity
                  2: const pw.FlexColumnWidth(1), // Unit
                  3: const pw.FlexColumnWidth(1.5), // Latest Unit Price
                  4: const pw.FlexColumnWidth(1.5), // Total Cost
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: _primaryColor),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: pw.Text('Ingredient Name', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: pw.Text('Qty', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: pw.Text('Unit', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: pw.Text('Unit Price', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: pw.Text('Sub Total', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white)),
                      ),
                    ],
                  ),
                  // Table Rows
                  ...ingredients.map((ing) {
                    final double qty = (ing['quantity'] ?? 0.0).toDouble();
                    final double price = (ing['latest_price'] ?? 0.0).toDouble();
                    final double subtotal = (ing['cost'] ?? 0.0).toDouble();

                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: pw.Text(ing['item_name'] ?? '-', style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: pw.Text(qty.toStringAsFixed(1), style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: pw.Text(ing['unit'] ?? 'kg', style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: pw.Text('Rs ${price.toStringAsFixed(0)}', style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: pw.Text('Rs ${subtotal.toStringAsFixed(0)}', style: pw.TextStyle(font: fontBold, fontSize: 8, color: _secondaryColor)),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.SizedBox(height: 20),

              // Total Cost Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('Total Issued Cost: ', style: pw.TextStyle(font: fontBold, fontSize: 10, color: _primaryColor)),
                  pw.Text('Rs ${totalCost.toStringAsFixed(0)}', style: pw.TextStyle(font: fontBold, fontSize: 12, color: _secondaryColor)),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Menu_Issue_${dayOfWeek}_${date}.pdf');
  }

  static Future<void> printHostelStayRecordsReport({
    required List<Map<String, dynamic>> records,
    String? hostelName,
    String? roomNumber,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    final formattedDate = DateFormat('MMM dd, yyyy').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MADARSA EDUCATION SOCIETY',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 16,
                          color: _primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Pincode Area, Delhi, India',
                        style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: _primaryColor,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      'HOSTEL STAY REPORT',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 11,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: _borderColor, thickness: 1),
              pw.SizedBox(height: 12),

              // Filter Header Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (hostelName != null)
                        pw.Text('Hostel: $hostelName', style: pw.TextStyle(font: fontBold, fontSize: 11, color: _secondaryColor))
                      else
                        pw.Text('Hostel: All Hostels', style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.SizedBox(height: 2),
                      if (roomNumber != null)
                        pw.Text('Room Number: Room $roomNumber', style: pw.TextStyle(font: fontBold, fontSize: 10, color: _primaryColor))
                      else
                        pw.Text('Room Number: All Rooms', style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                  pw.Text('Date: $formattedDate', style: pw.TextStyle(font: font, fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 20),

              pw.Table(
                border: pw.TableBorder.all(color: _borderColor, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),     // Student Name
                  1: const pw.FlexColumnWidth(2.5),   // Father Name
                  2: const pw.FlexColumnWidth(2),     // Surname
                  3: const pw.FlexColumnWidth(2.5),   // Village
                  4: const pw.FlexColumnWidth(1.5),   // Bed No
                  5: const pw.FlexColumnWidth(1.2),   // Age
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Student Name', style: pw.TextStyle(font: fontBold, fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("Father's Name", style: pw.TextStyle(font: fontBold, fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Surname', style: pw.TextStyle(font: fontBold, fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Village', style: pw.TextStyle(font: fontBold, fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Bed No', style: pw.TextStyle(font: fontBold, fontSize: 8), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Age', style: pw.TextStyle(font: fontBold, fontSize: 8), textAlign: pw.TextAlign.center),
                      ),
                    ],
                  ),
                  ...records.map((r) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(r['student_name']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(r['father_name']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(r['surname']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(r['village']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(r['bed_number']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(r['age']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Generated by Madarsa Management System', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('Page 1 of 1', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Hostel_Stay_Report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  // ─── LIBRARY INVENTORY REPORT ───────────────────────────────────────
  static Future<void> printLibraryInventoryReport({
    required List<Map<String, dynamic>> books,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('MADARSA MANAGEMENT SYSTEM', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.indigo900)),
                      pw.Text('LIBRARY INVENTORY REPORT', style: pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: ${DateTime.now().toString().split(' ')[0]}', style: pw.TextStyle(font: font, fontSize: 9)),
                      pw.Text('Total Books: ${books.length}', style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.indigo900),
              pw.SizedBox(height: 15),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3), // Title
                  1: const pw.FlexColumnWidth(2), // Author
                  2: const pw.FlexColumnWidth(2), // Category
                  3: const pw.FlexColumnWidth(1.5), // Language
                  4: const pw.FlexColumnWidth(1.2), // Copies (T/A)
                  5: const pw.FlexColumnWidth(1.8), // Location
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Title', style: pw.TextStyle(font: boldFont, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Author', style: pw.TextStyle(font: boldFont, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Category', style: pw.TextStyle(font: boldFont, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Language', style: pw.TextStyle(font: boldFont, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Copies (T/A)', style: pw.TextStyle(font: boldFont, fontSize: 9), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Location', style: pw.TextStyle(font: boldFont, fontSize: 9))),
                    ],
                  ),
                  ...books.map((b) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(b['title']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(b['author']?.toString() ?? '-', style: pw.TextStyle(font: font, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(b['category_name']?.toString() ?? '-', style: pw.TextStyle(font: font, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(b['language']?.toString() ?? 'Urdu', style: pw.TextStyle(font: font, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${b['total_copies'] ?? 1} / ${b['available_copies'] ?? 1}', style: pw.TextStyle(font: font, fontSize: 8), textAlign: pw.TextAlign.center)),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(b['shelf_location']?.toString() ?? '-', style: pw.TextStyle(font: font, fontSize: 8))),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Generated by Madarsa Management System', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('Page 1 of 1', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Library_Inventory_Report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  // ─── OVERDUE BOOKS REPORT ──────────────────────────────────────────
  static Future<void> printOverdueBooksReport({
    required List<Map<String, dynamic>> records,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('MADARSA MANAGEMENT SYSTEM', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.red900)),
                      pw.Text('OVERDUE BOOKS REPORT', style: pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: ${DateTime.now().toString().split(' ')[0]}', style: pw.TextStyle(font: font, fontSize: 9)),
                      pw.Text('Overdue Count: ${records.length}', style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.red900),
              pw.SizedBox(height: 15),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5), // Student Name
                  1: const pw.FlexColumnWidth(2), // Father Name
                  2: const pw.FlexColumnWidth(2.5), // Book Title
                  3: const pw.FlexColumnWidth(1.5), // Issue Date
                  4: const pw.FlexColumnWidth(1.5), // Due Date
                  5: const pw.FlexColumnWidth(1), // Days Overdue
                  6: const pw.FlexColumnWidth(1), // Fine (Rs)
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Student Name', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Father Name', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Book Title', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Issue Date', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Due Date', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Overdue', style: pw.TextStyle(font: boldFont, fontSize: 8), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Fine', style: pw.TextStyle(font: boldFont, fontSize: 8), textAlign: pw.TextAlign.center)),
                    ],
                  ),
                  ...records.map((r) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${r['student_name'] ?? ''} ${r['surname'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(r['father_name']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(r['book_title']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(r['issue_date']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(r['due_date']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${r['overdue_days'] ?? 0} days', style: pw.TextStyle(font: font, fontSize: 7.5), textAlign: pw.TextAlign.center)),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rs. ${r['fine_amount'] ?? 0}', style: pw.TextStyle(font: font, fontSize: 7.5), textAlign: pw.TextAlign.center)),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Generated by Madarsa Management System', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('Page 1 of 1', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Library_Overdue_Report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  // ─── STUDENT BORROWING HISTORY ─────────────────────────────────────
  static Future<void> printStudentBorrowingHistory({
    required String studentName,
    required String fatherName,
    required String grNo,
    required List<Map<String, dynamic>> history,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('MADARSA MANAGEMENT SYSTEM', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.teal900)),
                      pw.Text('STUDENT BORROWING HISTORY', style: pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: ${DateTime.now().toString().split(' ')[0]}', style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.teal900),
              pw.SizedBox(height: 10),
              // Student Info Card
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Student: $studentName', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                    pw.Text('Father: $fatherName', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                    pw.Text('GR No: $grNo', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3), // Book Title
                  1: const pw.FlexColumnWidth(2), // Author
                  2: const pw.FlexColumnWidth(1.5), // Issue Date
                  3: const pw.FlexColumnWidth(1.5), // Return/Due Date
                  4: const pw.FlexColumnWidth(1.2), // Status
                  5: const pw.FlexColumnWidth(1), // Fine
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Book Title', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Author', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Issue Date', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Returned Date', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Status', style: pw.TextStyle(font: boldFont, fontSize: 8), textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Fine', style: pw.TextStyle(font: boldFont, fontSize: 8), textAlign: pw.TextAlign.center)),
                    ],
                  ),
                  ...history.map((h) {
                    final returnText = h['return_date']?.toString() ?? 'Due: ${h['due_date']?.toString() ?? ''}';
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(h['book_title']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(h['book_author']?.toString() ?? '-', style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(h['issue_date']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(returnText, style: pw.TextStyle(font: font, fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(h['computed_status']?.toString() ?? h['status']?.toString() ?? '', style: pw.TextStyle(font: font, fontSize: 7.5), textAlign: pw.TextAlign.center)),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rs. ${h['fine_amount'] ?? 0}', style: pw.TextStyle(font: font, fontSize: 7.5), textAlign: pw.TextAlign.center)),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Generated by Madarsa Management System', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('Page 1 of 1', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: '${studentName.replaceAll(' ', '_')}_Borrowing_History_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  // ─── PRINT BOOK QR LABEL ───────────────────────────────────────────
  static Future<void> printBookQrLabel({
    required String bookId,
    required String qrData,
    required String title,
    String? author,
    String? shelfLocation,
    String? copyInfo,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(
      pw.Page(
        // Small label size (8cm x 5cm)
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, 50 * PdfPageFormat.mm, marginAll: 5 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // QR Code (Left)
              pw.Container(
                width: 35 * PdfPageFormat.mm,
                height: 35 * PdfPageFormat.mm,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrData,
                ),
              ),
              pw.SizedBox(width: 4 * PdfPageFormat.mm),
              // Book Info details (Right)
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('MADARSA LIBRARY', style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.indigo900)),
                    pw.Divider(thickness: 1, color: PdfColors.grey400),
                    pw.Text(
                      title, 
                      style: pw.TextStyle(font: boldFont, fontSize: 9), 
                      maxLines: 2, 
                      overflow: pw.TextOverflow.clip
                    ),
                    if (author != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text('By: $author', style: pw.TextStyle(font: font, fontSize: 7.5), maxLines: 1),
                    ],
                    if (copyInfo != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(copyInfo, style: pw.TextStyle(font: boldFont, fontSize: 7.5, color: PdfColors.indigo700)),
                    ],
                    if (shelfLocation != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        child: pw.Text('Shelf: $shelfLocation', style: pw.TextStyle(font: boldFont, fontSize: 7)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final filenameSafeId = bookId.length >= 8 ? bookId.substring(0, 8) : bookId;
    await Printing.sharePdf(bytes: bytes, filename: 'Book_Label_$filenameSafeId.pdf');
  }

  static Future<void> printAllBookQrLabels({
    required String bookId,
    required String title,
    String? author,
    String? shelfLocation,
    required List<String> qrDataList,
    required List<String> copyInfoList,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    for (int i = 0; i < qrDataList.length; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, 50 * PdfPageFormat.mm, marginAll: 5 * PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // QR Code (Left)
                pw.Container(
                  width: 35 * PdfPageFormat.mm,
                  height: 35 * PdfPageFormat.mm,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrDataList[i],
                  ),
                ),
                pw.SizedBox(width: 4 * PdfPageFormat.mm),
                // Book Info details (Right)
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('MADARSA LIBRARY', style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.indigo900)),
                      pw.Divider(thickness: 1, color: PdfColors.grey400),
                      pw.Text(
                        title, 
                        style: pw.TextStyle(font: boldFont, fontSize: 9), 
                        maxLines: 2, 
                        overflow: pw.TextOverflow.clip
                      ),
                      if (author != null) ...[
                        pw.SizedBox(height: 2),
                        pw.Text('By: $author', style: pw.TextStyle(font: font, fontSize: 7.5), maxLines: 1),
                      ],
                      pw.SizedBox(height: 2),
                      pw.Text(copyInfoList[i], style: pw.TextStyle(font: boldFont, fontSize: 7.5, color: PdfColors.indigo700)),
                      if (shelfLocation != null) ...[
                        pw.SizedBox(height: 4),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          child: pw.Text('Shelf: $shelfLocation', style: pw.TextStyle(font: boldFont, fontSize: 7)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    final bytes = await pdf.save();
    final filenameSafeId = bookId.length >= 8 ? bookId.substring(0, 8) : bookId;
    await Printing.sharePdf(bytes: bytes, filename: 'All_Book_Labels_$filenameSafeId.pdf');
  }

  static Future<void> printTransactionQrLabel({
    required String transactionId,
    required String borrowerName,
    required String borrowerType,
    required String bookTitle,
    required String issueDate,
    required String dueDate,
    String? copyInfo,
    String? hostelInfo,
    String? qrData,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, 50 * PdfPageFormat.mm, marginAll: 5 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // QR Code (Left)
              pw.Container(
                width: 35 * PdfPageFormat.mm,
                height: 35 * PdfPageFormat.mm,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrData ?? 'TX:$transactionId',
                ),
              ),
              pw.SizedBox(width: 4 * PdfPageFormat.mm),
              // Transaction Details (Right)
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('MADARSA LIBRARY', style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.indigo900)),
                    pw.Text('RETURN RECEIPT QR', style: pw.TextStyle(font: boldFont, fontSize: 6.5, color: PdfColors.grey700)),
                    pw.Divider(thickness: 1, color: PdfColors.grey400),
                    pw.Text(
                      bookTitle, 
                      style: pw.TextStyle(font: boldFont, fontSize: 8), 
                      maxLines: 1, 
                      overflow: pw.TextOverflow.clip
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text('To: $borrowerName ($borrowerType)', style: pw.TextStyle(font: boldFont, fontSize: 7.5), maxLines: 1),
                    pw.SizedBox(height: 2),
                    if (hostelInfo != null && hostelInfo.isNotEmpty) ...[
                      pw.Text(hostelInfo, style: pw.TextStyle(font: font, fontSize: 6.5)),
                      pw.SizedBox(height: 2),
                    ],
                    pw.Text('Issued: $issueDate', style: pw.TextStyle(font: font, fontSize: 7)),
                    pw.Text('Due: $dueDate', style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.red900)),
                    if (copyInfo != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(copyInfo, style: pw.TextStyle(font: font, fontSize: 6.5)),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final filenameSafeId = transactionId.length >= 8 ? transactionId.substring(0, 8) : transactionId;
    await Printing.sharePdf(bytes: bytes, filename: 'Return_Receipt_$filenameSafeId.pdf');
  }
}

