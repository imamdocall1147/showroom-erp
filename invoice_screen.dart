import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// এখানে আপনার দোকানের তথ্য দিন — ইনভয়েসের উপরে দেখাবে
const String companyName = "Showroom ERP";
const String companyAddress = ""; // যেমন: "মূল সড়ক, চট্টগ্রাম"
const String companyPhone = ""; // যেমন: "01xxxxxxxxx"

class InvoiceItem {
  final String description;
  final int qty;
  final String unit;
  final int unitPrice;
  final int total;

  InvoiceItem({
    required this.description,
    required this.qty,
    required this.unit,
    required this.unitPrice,
    required this.total,
  });
}

class InvoiceScreen extends StatelessWidget {
  final String invoiceTitle;
  final String invoiceNumber;
  final DateTime date;
  final String partyName;
  final String? partyPhone;
  final List<InvoiceItem> items;
  final String paymentMode;
  final int totalAmount;

  /// এখন জমা। না দিলে পুরনো নিয়ম: cash = পুরো জমা, due = পুরোটা বাকি
  final int? paidAmount;

  /// বিক্রয় ইনভয়েসে "কাস্টমার", ক্রয় ইনভয়েসে "সাপ্লায়ার" দিন
  final String partyLabel;

  /// বিক্রয়ে "গ্রাহকের স্বাক্ষর", ক্রয়ে "বিক্রেতার স্বাক্ষর" দিন
  final String partySignatureLabel;

  const InvoiceScreen({
    super.key,
    required this.invoiceTitle,
    required this.invoiceNumber,
    required this.date,
    required this.partyName,
    this.partyPhone,
    required this.items,
    required this.paymentMode,
    required this.totalAmount,
    this.paidAmount,
    this.partyLabel = "কাস্টমার",
    this.partySignatureLabel = "গ্রাহকের স্বাক্ষর",
  });

  int get _paid => paidAmount ?? (paymentMode == 'cash' ? totalAmount : 0);
  int get _due => totalAmount - _paid;

  String get _paymentText {
    if (_due <= 0) return 'নগদ';
    if (_paid <= 0) return 'বাকি';
    return 'আংশিক জমা';
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final regularFontData = await rootBundle.load("assets/fonts/NotoSansBengali-Regular.ttf");
    final boldFontData = await rootBundle.load("assets/fonts/NotoSansBengali-Bold.ttf");
    final bengaliFont = pw.Font.ttf(regularFontData);
    final bengaliBoldFont = pw.Font.ttf(boldFontData);

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: bengaliFont, bold: bengaliBoldFont),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(companyName, style: pw.TextStyle(fontSize: 20, font: bengaliBoldFont)),
                      if (companyAddress.isNotEmpty) pw.Text(companyAddress),
                      if (companyPhone.isNotEmpty) pw.Text("ফোন: $companyPhone"),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(invoiceTitle, style: pw.TextStyle(fontSize: 16, font: bengaliBoldFont)),
                      pw.Text("ভাউচার নং: $invoiceNumber"),
                      pw.Text("তারিখ: ${date.day}-${date.month}-${date.year}"),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text("$partyLabel: $partyName", style: pw.TextStyle(font: bengaliBoldFont)),
              if (partyPhone != null && partyPhone!.isNotEmpty) pw.Text("ফোন: $partyPhone"),
              pw.Text("পেমেন্ট মোড: $_paymentText"),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: ["বিবরণ", "পরিমাণ", "একক মূল্য", "মোট"],
                data: items
                    .map((item) => [
                          item.description,
                          "${item.qty} ${item.unit}",
                          "\u09f3${item.unitPrice}",
                          "\u09f3${item.total}",
                        ])
                    .toList(),
                cellStyle: pw.TextStyle(font: bengaliFont, fontSize: 11),
                headerStyle: pw.TextStyle(font: bengaliBoldFont, fontSize: 11),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "সর্বমোট: \u09f3$totalAmount",
                      style: pw.TextStyle(fontSize: 16, font: bengaliBoldFont),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text("এখন জমা: \u09f3$_paid", style: pw.TextStyle(fontSize: 12)),
                    pw.Text(
                      "বাকি: \u09f3$_due",
                      style: pw.TextStyle(fontSize: 12, font: _due > 0 ? bengaliBoldFont : bengaliFont),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 40),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.SizedBox(width: 150, child: pw.Divider()),
                      pw.Text(partySignatureLabel),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.SizedBox(width: 150, child: pw.Divider()),
                      pw.Text("অনুমোদনকারী"),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(invoiceTitle)),
      body: PdfPreview(
        build: (format) => _generatePdf(format),
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: "invoice_$invoiceNumber.pdf",
      ),
    );
  }
}
