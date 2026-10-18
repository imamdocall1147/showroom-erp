import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'invoice_screen.dart' show companyName;
import 'sync_service.dart';

// ---------------------------------------------------------------
// ইনপুট ঘরের তালিকা ("তথ্য" ট্যাব)। এখানে ডিফল্ট মান বদলালে সব কাগজে বদলাবে।
// ---------------------------------------------------------------
class _Field {
  final String group;
  final String key;
  final String label;
  final String def;
  final bool multiline;
  const _Field(this.group, this.key, this.label, {this.def = '', this.multiline = false});
}

final List<_Field> _fields = [
  _Field('ডিলার ও রেফারেন্স', 'dealer_name', 'ডিলার / শোরুমের নাম (ইংরেজি)', def: companyName),
  const _Field('ডিলার ও রেফারেন্স', 'ref_prefix', 'রেফারেন্স কোড (যেমন IDEW)'),
  const _Field('ডিলার ও রেফারেন্স', 'ref_no', 'সিরিয়াল নং'),
  const _Field('ডিলার ও রেফারেন্স', 'ref_session', 'অর্থবছর (যেমন 25-26)'),
  const _Field('ডিলার ও রেফারেন্স', 'doc_date', 'তারিখ (দিন-মাস-বছর)'),
  const _Field('ডিলার ও রেফারেন্স', 'reg_city', 'রেজিস্ট্রেশন অফিসের শহর (ইংরেজি)', def: 'Chittagong'),
  const _Field('ডিলার ও রেফারেন্স', 'city_bn', 'শহর (বাংলায়)', def: 'চট্টগ্রাম'),
  const _Field('ডিলার ও রেফারেন্স', 'circle_bn', 'অঙ্গীকারনামার সার্কেল (বাংলায়)', def: 'চট্টগ্রাম সার্কেল'),
  const _Field('ডিলার ও রেফারেন্স', 'circle_bn2', 'ডিলার ঘোষণার সার্কেল (বাংলায়)', def: 'চট্টগ্রাম মেট্রো সার্কেল'),
  const _Field('ডিলার ও রেফারেন্স', 'importer', 'আমদানীকারক কোম্পানি (বাংলায়)'),
  const _Field('ডিলার ও রেফারেন্স', 'veh_bn', 'গাড়ীর ধরন (বাংলায়)', def: 'মোটরসাইকেল'),
  const _Field('মালিক (ক্রেতা)', 'owner_name', 'মালিকের নাম'),
  const _Field('মালিক (ক্রেতা)', 'father', 'পিতা / স্বামীর নাম'),
  const _Field('মালিক (ক্রেতা)', 'address', 'ঠিকানা'),
  const _Field('মালিক (ক্রেতা)', 'phone', 'ফোন'),
  const _Field('মালিক (ক্রেতা)', 'sex', 'লিঙ্গ (MALE / FEMALE)', def: 'MALE'),
  const _Field('মালিক (ক্রেতা)', 'dob', 'জন্ম তারিখ'),
  const _Field('মালিক (ক্রেতা)', 'nationality', 'জাতীয়তা', def: 'BANGLADESHI'),
  const _Field('মালিক (ক্রেতা)', 'guardian', 'অভিভাবকের নাম'),
  const _Field('গাড়ী', 'model', 'মডেল / মেক'),
  const _Field('গাড়ী', 'vclass', 'গাড়ীর শ্রেণী (Class)', def: 'MOTORCYCLE'),
  const _Field('গাড়ী', 'chassis', 'চেসিস নম্বর'),
  const _Field('গাড়ী', 'show_qr', 'চেসিস নম্বরের QR কোড ছাপবেন? (yes / no)', def: 'yes'),
  const _Field('গাড়ী', 'engine', 'ইঞ্জিন নম্বর'),
  const _Field('গাড়ী', 'key_no', 'চাবি নম্বর (Key No)'),
  const _Field('গাড়ী', 'cylinders', 'সিলিন্ডার সংখ্যা'),
  const _Field('গাড়ী', 'cc', 'সিসি (CC)'),
  const _Field('গাড়ী', 'colour', 'রঙ'),
  const _Field('গাড়ী', 'tyre_size', 'টায়ারের সাইজ'),
  const _Field('গাড়ী', 'year', 'তৈরির বছর'),
  const _Field('গাড়ী', 'hp', 'হর্স পাওয়ার'),
  const _Field('গাড়ী', 'laden_weight', 'Laden Weight'),
  const _Field('গাড়ী', 'train_weight', 'Maximum laden / train weight'),
  const _Field('গাড়ী', 'unladen_weight', 'Unladen weight (kg)'),
  const _Field('গাড়ী', 'wheel_base', 'Wheel Base'),
  const _Field('গাড়ী', 'seating', 'আসন সংখ্যা (Seating Capacity)'),
  const _Field('গাড়ী', 'maker', 'প্রস্তুতকারক (Maker)'),
  const _Field('গাড়ী', 'maker_country', 'প্রস্তুতকারক দেশ'),
  const _Field('গাড়ী', 'body_type', 'বডির ধরন'),
  const _Field('গাড়ী', 'fuel', 'জ্বালানি'),
  const _Field('গাড়ী', 'rpm', 'RPM'),
  const _Field('গাড়ী', 'tyres_no', 'টায়ার সংখ্যা'),
  const _Field('গাড়ী', 'axle_no', 'এক্সেল সংখ্যা'),
  const _Field('ইনভয়েস ও ডেলিভারি', 'price', 'বিক্রয় মূল্য (টাকা)'),
  const _Field('ইনভয়েস ও ডেলিভারি', 'advance', 'অগ্রিম / জমা (টাকা)'),
  const _Field('ইনভয়েস ও ডেলিভারি', 'description', 'ইনভয়েসের বিবরণ (Description)'),
  const _Field('ইনভয়েস ও ডেলিভারি', 'accessories',
      'সাথে দেওয়া জিনিস (প্রতি লাইনে একটা, যেমন: Tool Kit = 01pc)',
      def: 'O.M. Book = 01 pc\nTool Kit = 01 pc', multiline: true),
];

const List<String> _tabNames = [
  'তথ্য',
  'বিক্রয় প্রত্যয়ন',
  'সেলস ইনভয়েস',
  'অঙ্গীকারনামা',
  'আবেদন ফর্ম',
  'ডিলার ঘোষণা',
  'ডেলিভারি চালান',
  'মালিকের তথ্য',
];

// ---------------------------------------------------------------
// সংখ্যা ও তারিখ সাহায্যকারী
// ---------------------------------------------------------------
String _group(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return "${parts.join(',')},$last3";
}

int? _intOf(String s) => int.tryParse(s.replaceAll(',', '').replaceAll('৳', '').trim());

String _inr2(int n) => "${_group(n.abs().toString())}.00";

String _bn(String s) {
  const en = '0123456789';
  const bn = '০১২৩৪৫৬৭৮৯';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = en.indexOf(ch);
    b.write(i >= 0 ? bn[i] : ch);
  }
  return b.toString();
}

String _words(int n) {
  if (n <= 0) return "ZERO Only.";
  const ones = [
    "", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN",
    "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN",
    "EIGHTEEN", "NINETEEN"
  ];
  const tens = ["", "", "TWENTY", "THIRTY", "FORTY", "FIFTY", "SIXTY", "SEVENTY", "EIGHTY", "NINETY"];
  String two(int x) {
    if (x < 20) return ones[x];
    return tens[x ~/ 10] + (x % 10 == 0 ? "" : " ${ones[x % 10]}");
  }

  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lac = n ~/ 100000;
  n %= 100000;
  final th = n ~/ 1000;
  n %= 1000;
  final hu = n ~/ 100;
  n %= 100;
  if (crore > 0 && crore < 100) parts.add("${two(crore)} CRORE");
  if (lac > 0) parts.add("${two(lac)} LAC");
  if (th > 0) parts.add("${two(th)} Thousand");
  if (hu > 0) parts.add("${ones[hu]} Hundred");
  if (n > 0) parts.add(two(n));
  return "${parts.join(' ')} Only.";
}

String _fmtDate(DateTime d) =>
    "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}";

String _session(DateTime d) {
  final y = d.year % 100;
  String two(int x) => (x % 100).toString().padLeft(2, '0');
  return d.month >= 7 ? "${two(y)}-${two(y + 1)}" : "${two(y - 1)}-${two(y)}";
}

// ---------------------------------------------------------------
// PDF তৈরির অংশ: প্রতিটা পাতা xls ফাইলের নকশা অনুযায়ী
// ---------------------------------------------------------------
class _Kit {
  final Map<String, String> d;
  final pw.Font reg;
  final pw.Font bold;

  _Kit(this.d, this.reg, this.bold);

  String v(String k) => (d[k] ?? '').trim();
  String dots(String k, [String fill = '………………………………']) => v(k).isEmpty ? fill : v(k);

  pw.Widget t(String s,
          {double size = 11, bool b = false, pw.TextAlign? align, bool u = false, double ls = 0}) =>
      pw.Text(
        s,
        textAlign: align,
        style: pw.TextStyle(
          font: b ? bold : reg,
          fontSize: size,
          lineSpacing: ls,
          decoration: u ? pw.TextDecoration.underline : null,
        ),
      );

  pw.Widget lv(String label, String value, {double lw = 190, double size = 11}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: lw, child: t(label, size: size)),
            t(": ", size: size),
            pw.Expanded(child: t(value, size: size, b: true)),
          ],
        ),
      );

  pw.Widget gap([double h = 10]) => pw.SizedBox(height: h);

  pw.Widget sig(String left, String right) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(children: [pw.SizedBox(width: 150, child: pw.Divider(thickness: 0.8)), t(left)]),
          pw.Column(children: [pw.SizedBox(width: 150, child: pw.Divider(thickness: 0.8)), t(right)]),
        ],
      );

  pw.Widget cell(String s, {double size = 9.5, bool b = false, pw.TextAlign? align}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: t(s, size: size, b: b, align: align),
      );

  /// চেসিস নম্বরের QR কোড (নম্বর লেখাসহ)। "no" দিলে বা চেসিস না থাকলে কিছু দেখায় না।
  pw.Widget qr(double size) {
    final off = ['no', 'না', 'n'].contains(v('show_qr').toLowerCase());
    if (off || v('chassis').isEmpty) return pw.SizedBox();
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: v('chassis'),
          width: size,
          height: size,
        ),
        pw.SizedBox(height: 2),
        t(v('chassis'), size: 7),
      ],
    );
  }

  String get refLine => "Ref: ${v('ref_prefix')}/ ${v('ref_no')} /${v('ref_session')}";
  String get buyerLine => "${v('owner_name')}    S/O: ${v('father')}";
  int get priceInt => _intOf(v('price')) ?? 0;
  int get advanceInt => _intOf(v('advance')) ?? 0;

  // ---- পাতা ১: বিক্রয় প্রত্যয়ন (Sheet1) ----
  List<pw.Widget> pCert() {
    final items = <List<String>>[
      ["Model/Make of vehicle", v('model')],
      ["Class of Vehicle", v('vclass')],
      ["Chassis No", v('chassis')],
      ["Engine No", v('engine')],
      ["Key No", v('key_no')],
      ["Number of Cylinder with CC", "${v('cylinders')} / ${v('cc')} CC"],
      ["Colour of Vehicle", v('colour')],
      ["Size of Tyre", v('tyre_size')],
      ["Year of Manufacture/Assemble", v('year')],
      ["Horse Power", v('hp')],
      ["Laden Weight", v('laden_weight')],
      ["Wheel Base", v('wheel_base')],
      ["Seating Capacity", v('seating')],
      ["Maker’s Name", v('maker')],
      ["Price", priceInt > 0 ? "Tk     ${_inr2(priceInt)}" : ""],
    ];
    return [
      gap(24),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [t(refLine), t("Date: ${v('doc_date')}")],
      ),
      pw.Align(alignment: pw.Alignment.centerRight, child: qr(62)),
      gap(4),
      t("To: The Registration Authority"),
      t("Motor Vehicle Department"),
      t("${v('reg_city')}."),
      gap(16),
      pw.Center(child: t("TO WHOM IT MAY CONCERN", b: true, u: true, size: 12)),
      gap(8),
      t("This is to certify that we have sold a new vehicle to:"),
      gap(6),
      t(buyerLine, b: true),
      t("C/O: ${v('address')}", b: true),
      gap(8),
      for (int i = 0; i < items.length; i++)
        lv("${i + 1}.  ${items[i][0]}", items[i][1], lw: 215),
      gap(26),
      pw.Align(alignment: pw.Alignment.centerRight, child: t("FOR ${v('dealer_name').toUpperCase()}", b: true)),
      gap(40),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [t("Owner’s Signature"), t("Sales Department")],
      ),
    ];
  }

  // ---- পাতা ২: সেলস ইনভয়েস (Sheet2) ----
  List<pw.Widget> pInvoice() {
    final price = priceInt;
    final adv = advanceInt;
    final bal = price - adv;
    final h = ["Sl No:", "Chassis No.", "Engine No.", "Key No", "Colour", "Qnty", "Description", "Unit Price", "Amount"];
    pw.Widget kv(String a, String b2) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [t(a, size: 10.5), t(b2, size: 10.5, b: true)],
          ),
        );
    return [
      gap(20),
      pw.Center(child: t("SALES  INVOICE", b: true, u: true, size: 15)),
      gap(8),
      pw.Align(alignment: pw.Alignment.centerRight, child: t("Date: ${v('doc_date')}")),
      gap(8),
      pw.Row(children: [
        t("BUYER   ", b: true),
        t("${v('owner_name')}   S/O: ${v('father')}      C/O: ${v('address')}", size: 10.5),
      ]),
      gap(8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          t("Invoice No:                                   B/E"),
          t("Sales Invoice No: ${v('ref_prefix')}/${v('ref_no')}"),
        ],
      ),
      gap(6),
      pw.Table(
        border: pw.TableBorder.all(width: 0.7),
        columnWidths: {
          0: const pw.FixedColumnWidth(34),
          1: const pw.FlexColumnWidth(3.3),
          2: const pw.FlexColumnWidth(2.6),
          3: const pw.FlexColumnWidth(1.2),
          4: const pw.FlexColumnWidth(1.5),
          5: const pw.FixedColumnWidth(36),
          6: const pw.FlexColumnWidth(4),
          7: const pw.FlexColumnWidth(2.2),
          8: const pw.FlexColumnWidth(2.2),
        },
        children: [
          pw.TableRow(children: [for (final x in h) cell(x, b: true, size: 9)]),
          pw.TableRow(children: [
            cell("1"),
            cell(v('chassis'), size: 8.5),
            cell(v('engine'), size: 8.5),
            cell(v('key_no')),
            cell(v('colour').toUpperCase(), size: 8.5),
            cell("1"),
            cell(v('description'), size: 8.5),
            cell(price > 0 ? _inr2(price) : "", size: 8.5, align: pw.TextAlign.right),
            cell(""),
          ]),
          for (int i = 0; i < 2; i++) pw.TableRow(children: [for (int j = 0; j < 9; j++) cell(" ")]),
        ],
      ),
      gap(10),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: t(price > 0 ? _words(price) : "")),
          pw.SizedBox(
            width: 230,
            child: pw.Column(children: [
              kv("Total Amount", price > 0 ? _inr2(price) : ""),
              kv("Less Advance", adv > 0 ? _inr2(adv) : "-"),
              kv("Balance", bal > 0 ? _inr2(bal) : "-"),
            ]),
          ),
        ],
      ),
      gap(16),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          t("Payment Reference:"),
          t("For ${v('dealer_name').toUpperCase()}", b: true),
        ],
      ),
      gap(14),
      t("M.R. No-------------------------------------Dated---------------------"),
      gap(6),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          t("For Tk------------------------------( Taka-----------------------Only)"),
          t("SALES DEPARTMENT", b: true),
        ],
      ),
      gap(6),
      t("In Cash/ by-----------------------------------------------------------"),
    ];
  }

  // ---- পাতা ৩: অঙ্গীকারনামা (Sheet4) ----
  List<pw.Widget> pUndertaking() {
    final para =
        "এই মর্মে অঙ্গীকার করিতেছি যে আমার গাড়ীটি যাহার চেসিস নং ${dots('chassis')} "
        "ইঞ্জিন নং ${dots('engine')} প্রস্তুতকারক ${dots('maker', '…………………')} "
        "বডির ধরন ${dots('body_type', '…………………')} রেজিস্ট্রেশন মালিকানা বদলী সংক্রান্ত যাবতীয় সকল কাগজ পত্র সঠিক। "
        "ভবিষ্যতে আমদানী ও ক্রয় বিক্রয় সংক্রান্ত কোন প্রকার জটিলতা সৃষ্টি হইলে আমি সম্পূর্ণ দায়ী থাকিব, "
        "কর্তৃপক্ষ কোন প্রকার দায়ী থাকিবে না এবং এই সংক্রান্ত বাংলাদেশ সরকার যে কোন আদেশ মানিয়া নিতে বাধ্য থাকিব, "
        "ইহাতে কর্তৃপক্ষ আমার রেজিস্ট্রেশন বাতিল করিয়া দিলেও কোন প্রকার আপত্তি থাকিবেনা। "
        "আমি আরও অঙ্গীকার করিতেছি যে, উক্ত গাড়ীর বিরুদ্ধে কোন ফৌজদারী ও দেওয়ানী মামলা নাই।";
    return [
      gap(20),
      t("বরাবর,", b: true, size: 13),
      t("রেজিস্ট্রেশন কর্তৃপক্ষ,", b: true, size: 13),
      t("বি. আর. টি.এ. ${v('circle_bn')},", b: true, size: 13),
      t("${v('city_bn')}।", b: true, size: 13),
      gap(14),
      t("বিষয়: --------------- নং গাড়ীর রেজিস্ট্রেশন/ অন্তর্ভুক্তি/ মালিকানা বদলী এ অঙ্গীকার নামা প্রসঙ্গে।",
          b: true, size: 12.5, ls: 3),
      gap(12),
      t("${v('owner_name')}     S/O: ${v('father')}", b: true, size: 12.5),
      t("C/O: ${v('address')}", b: true, size: 12.5),
      gap(12),
      t(para, size: 12.5, ls: 5),
      gap(40),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Padding(padding: const pw.EdgeInsets.only(right: 60), child: t("বিনীত", b: true, size: 13))),
      gap(26),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: 260,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            t("NAME : ${v('owner_name')}", b: true, size: 12),
            t("S/O: ${v('father')}", b: true, size: 12),
            t("C/O: ${v('address')}", b: true, size: 12),
          ]),
        ),
      ),
    ];
  }

  // ---- পাতা ৪: আবেদন ফর্ম (Sheet5) ----
  List<pw.Widget> pApplication() {
    pw.Widget grid(List<List<String>> rows, {double size = 9.5}) => pw.Table(
          border: pw.TableBorder.all(width: 0.7),
          children: [
            for (final r in rows)
              pw.TableRow(children: [for (final c in r) cell(c, size: size)]),
          ],
        );
    pw.Widget heading(String a, [String? b2]) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
          child: pw.Row(children: [
            t(a, b: true, size: 11),
            if (b2 != null) t("   $b2", size: 10),
          ]),
        );
    pw.Widget two(List<String> l, List<String> r) => pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [for (final s in l) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: t(s, size: 9.5))],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [for (final s in r) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: t(s, size: 9.5))],
                ),
              ),
            ],
          ),
        );

    String f(String s, String k) => "$s ${v(k)}";
    return [
      pw.Center(
        child: t("FORM OF APPLICATION FOR THE REGISTRATION OF MOTOR VEHICLE", b: true, size: 11.5),
      ),
      gap(6),
      t("To be filled in by the office", b: true, size: 10),
      heading("Section I"),
      grid([
        ["Regn No: ", "Date:", "Prev. Regn. No. (if any)"],
        ["Issue No:", "Date:", "Issued by:"],
        ["Dalry No:", "Date:", "Received No:"],
        ["Customer ID:", "District:", "Vehicle No:"],
        ["Veh. Description:", "", "Call no date:"],
        ["Refusal date:", "", "Refused by:"],
        ["P.O./Bank:", "Refusal Code:", "Index No:"],
      ]),
      pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
        padding: const pw.EdgeInsets.all(5),
        child: t("Remarks (if any)", size: 9.5),
      ),
      gap(4),
      t("To be filled in by the office", b: true, size: 10),
      heading("Section II", "(Owner Information)"),
      two([
        f("1. Name of owner :", 'owner_name'),
        f("3. Father/ Husband :", 'father'),
        f("5. Sex:", 'sex'),
        f("7. Owner’s Address (if any):", 'address'),
        f("8. Phone No. (if any):", 'phone'),
        "10. Joint owner:",
        "12. Hire",
      ], [
        f("2. Date of birth:", 'dob'),
        "4. Nationality : Bangladesh",
        f("6. Guardian’s name:", 'guardian'),
        "9. P.O./ Bank:",
        "11. Owner type:",
        "13. Hire purchase:",
      ]),
      heading("Section III", "(Vehicle Information)"),
      two([
        "14. Vehicle or trailer: Vehicle",
        f("15. Class of vehicle:", 'vclass'),
        f("16. Type of body:", 'body_type'),
        f("17. Colour (cabin/body):", 'colour'),
        f("18. Number of cylinders:", 'cylinders'),
        f("24. Engine number:", 'engine'),
        f("30. Horse power:", 'hp'),
        f("31. Cabin capacity:", 'cc'),
        "32. No. of Standee:",
        f("33. Unladen weight (kg):", 'unladen_weight'),
      ], [
        "19. Prev. Regn. No. (if any)",
        f("20. Maker’s name:", 'maker'),
        f("21. Maker’s country:", 'maker_country'),
        f("22. Year of manufacture:", 'year'),
        f("23. Chassis number:", 'chassis'),
        f("25. Fuel used:", 'fuel'),
        f("26. RPM:", 'rpm'),
        f("27. Seats (Incl. driver):", 'seating'),
        f("28. Wheel base:", 'wheel_base'),
        f("29. Maximum laden / train weight:", 'train_weight'),
      ]),
      heading("Section IV", "(Additional Information for transport vehicle)"),
      two([
        f("34. No. of tyres:", 'tyres_no'),
        f("35. No of axle:", 'axle_no'),
        "36. Dimensions (mm):",
        "a) Overall length      b) Overall width      c) Overall height",
        "37. Overhangs (%)",
        "a) Front      b) Rear      c) Other",
      ], [
        f("38. Tyres size:", 'tyre_size'),
        "39. Maximum axle weight (kgs):",
        "a) Front axle   (1)      (2)",
        "b) Central axle (1)      (2)      (3)",
        "c) Rear axle    (1)      (2)      (3)",
      ]),
      gap(6),
      t(
        "40. A copy of the drawing showing the vehicle dimensions, specifications of the body and of the seating arrangements approved by------------------------------------ on-----------------------------------------is attached herewith.",
        size: 9.5,
        ls: 3,
      ),
    ];
  }

  // ---- পাতা ৫: ডিলার ঘোষণা (Sheet6) ----
  List<pw.Widget> pDeclaration() {
    final vb = v('veh_bn').isEmpty ? 'গাড়ী' : v('veh_bn');
    final priceTxt = priceInt > 0 ? "${_bn(_group(priceInt.toString()))}/-" : "…………/-";
    final p1 =
        "আমি নিম্নস্বাক্ষরকারী এই মর্মে অঙ্গীকার পূর্বক ঘোষণা করিতেছি যে, অনুমোদিত ডিলার হিসেবে আমি $vb আমদানীকারক প্রতিষ্ঠান "
        "${dots('importer')} হতে চেসিস নং ${dots('chassis')} ও ইঞ্জিন নং ${dots('engine')} বিশিষ্ট $vb সরবরাহ নিয়ে বর্তমানে জনাব "
        "${dots('owner_name')} s/o: ${dots('father')} C/O: ${dots('address')} এর নিকট $priceTxt টাকায় বিক্রয় করেছি।";
    const p2 =
        "আমদানীকারকের নিকট থেকে প্রাপ্ত বিক্রয় রসিদ ডেলিভারী চালান, সেলস ইন্টিমেশন ও আমদানী সংক্রান্ত দলিল যথা- "
        "বিল অব এন্ট্রি/ইনভয়েস/ এলসিএ ইত্যাদি দলিলাদি ও মূলকপি/সত্যায়িত দাখিলকৃত সকল কাগজপত্রাদি সঠিক রয়েছে মর্মে আমি নিশ্চয়তা প্রদান করছি। "
        "গাড়ি এবং দাখিলকৃত দলিলাদির মধ্যে কোন দলিল/কাগজপত্রাদি ভবিষ্যতে জাল/ভুয়া প্রমাণিত হলে তজ্জন্য আমি অঙ্গীকারকারী দায়ী থাকবো। "
        "বি আর টি এ কর্তৃপক্ষ দায়ী থাকবেন না। এমতাবস্থায় কর্তৃপক্ষ বর্ণিত মোটরযানের বিপরীতে বরাদ্দকৃত রেজিস্ট্রেশন নম্বর বাতিল করে "
        "আমার বিরুদ্ধে আইনানুগ প্রয়োজনীয় ব্যবস্থা গ্রহণ করলে আমার কোন আপত্তি থাকবে না। "
        "নিম্নে ক্রেতার স্বাক্ষর সত্যায়িত করে প্রেরণ করা হল।";
    return [
      gap(14),
      t("বরাবর", size: 13),
      t("রেজিস্ট্রেশন কর্তৃপক্ষ", size: 13),
      t("বাংলাদেশ রোড ট্রান্সপোর্ট অথরিটি", size: 13),
      t(v('circle_bn2'), size: 13),
      t("${v('city_bn')}।", size: 13),
      gap(16),
      t(p1, size: 13, ls: 5),
      gap(8),
      t(p2, size: 13, ls: 5),
      gap(60),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(children: [pw.SizedBox(width: 160, child: pw.Divider(thickness: 0.8)), t("ক্রেতার স্বাক্ষর", size: 13)]),
          pw.Column(children: [pw.SizedBox(width: 190, child: pw.Divider(thickness: 0.8)), t("বিক্রেতা প্রতিষ্ঠানের স্বাক্ষর/ সীল", size: 13)]),
        ],
      ),
      gap(18),
      t("১।", size: 13),
      gap(18),
      t("২।", size: 13),
    ];
  }

  // ---- পাতা ৬: ডেলিভারি চালান (Sheet7) ----
  List<pw.Widget> pChallan() {
    final acc = v('accessories').split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return [
      gap(16),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          t("SL NO: ${v('ref_prefix')}/${v('ref_no')}", b: true),
          t("DATE: ${v('doc_date')}", b: true),
        ],
      ),
      gap(8),
      lv("NAME", v('owner_name'), lw: 110),
      lv("FATHER NAME", v('father'), lw: 110),
      lv("ADDRESS", v('address'), lw: 110),
      lv("MOBILE NO", v('phone'), lw: 110),
      gap(8),
      t("Please Receive the undermentioned vehicle/packages and sing for receipt."),
      gap(8),
      pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
        padding: const pw.EdgeInsets.all(8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            t("Description of vehicle", b: true),
            gap(6),
            pw.Row(children: [
              t("…01 ( one )… Unit      "),
              pw.Expanded(child: t(v('description'), b: true)),
            ]),
            gap(10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    t("ENGINE NO:", b: true),
                    t("1) ${v('engine')}"),
                    t("2) …………………………………"),
                    t("3) …………………………………"),
                  ]),
                ),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    t("CHASSIS NO:", b: true),
                    t("1) ${v('chassis')}"),
                    t("2) …………………………………"),
                    t("3) …………………………………"),
                  ]),
                ),
              ],
            ),
            gap(8),
            t("Color: ${v('colour')}"),
            gap(8),
            t("Along With", b: true),
            for (int i = 0; i < acc.length; i++) t("${i + 1}) ${acc[i]}"),
          ],
        ),
      ),
      gap(8),
      pw.Align(alignment: pw.Alignment.centerRight, child: qr(62)),
      gap(6),
      t("Checked & Found correct and received the above mentioned"),
      t("Vehicle/ Packages in good condition and upto my full satisfaction"),
      gap(70),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          t("Officer`s Signature"),
          t("(Customer`s Authorised Signature)"),
        ],
      ),
    ];
  }

  // ---- পাতা ৭: মালিকের তথ্য (Sheet3) ----
  List<pw.Widget> pOwner() {
    return [
      gap(10),
      pw.Center(child: t("OWNER'S PARTICULARS/SPECIMEN SIGNATURE", b: true, size: 13, u: true)),
      gap(10),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(children: [
              lv("1. NAME", v('owner_name'), lw: 150),
              lv("2. FATHER/HUSBAND", v('father'), lw: 150),
              lv("3. ADDRESS", v('address'), lw: 150),
              lv("4. SEX", v('sex'), lw: 150),
              lv("5. PHONE NO", v('phone'), lw: 150),
              lv("6. NATIONALITY", v('nationality'), lw: 150),
              lv("7. DATE OF BIRTH", v('dob'), lw: 150),
              lv("8. GUARDIAN'S NAME", v('guardian'), lw: 150),
              lv("9. CHASSIS NO", v('chassis'), lw: 150),
              lv("10. ENGINE NO", v('engine'), lw: 150),
              lv("11. YEAR OF MFG", v('year'), lw: 150),
              lv("12. PREV. REGN. NO", "", lw: 150),
              lv("13. P.O./BANK", "", lw: 150),
            ]),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              t("3 Copies", size: 10),
              gap(4),
              pw.Container(
                width: 100,
                height: 120,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
                child: t("Photograph\nstamp\nsize", size: 10, align: pw.TextAlign.center),
              ),
              gap(40),
              t("NEW", b: true, size: 12),
              gap(16),
              qr(70),
            ],
          ),
        ],
      ),
      gap(14),
      t("SPECIMEN SIGNATURE", b: true, u: true),
      gap(8),
      pw.Table(
        border: pw.TableBorder.all(width: 0.7),
        children: [
          for (final r in [
            ["1", "3"],
            ["2", "4"],
          ])
            pw.TableRow(
              children: [
                for (final x in r)
                  pw.Container(
                    height: 46,
                    padding: const pw.EdgeInsets.all(5),
                    child: t(x, size: 10),
                  ),
              ],
            ),
        ],
      ),
    ];
  }

  List<pw.Widget> page(int i) {
    switch (i) {
      case 0:
        return pCert();
      case 1:
        return pInvoice();
      case 2:
        return pUndertaking();
      case 3:
        return pApplication();
      case 4:
        return pDeclaration();
      case 5:
        return pChallan();
      default:
        return pOwner();
    }
  }

  Future<Uint8List> build(List<int> pages) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(base: reg, bold: bold);
    for (final i in pages) {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 34),
        theme: theme,
        build: (_) => page(i),
      ));
    }
    return doc.save();
  }
}

// ---------------------------------------------------------------
// স্ক্রিন: ট্যাবে "তথ্য" + সাতটা কাগজ
// ---------------------------------------------------------------
class BrtaDocumentsScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> unit;

  const BrtaDocumentsScreen({super.key, required this.token, required this.unit});

  @override
  State<BrtaDocumentsScreen> createState() => _BrtaDocumentsScreenState();
}

class _BrtaDocumentsScreenState extends State<BrtaDocumentsScreen> {
  final Map<String, TextEditingController> _c = {
    for (final f in _fields) f.key: TextEditingController(text: f.def),
  };
  bool _loading = true;
  int _ver = 0;
  pw.Font? _reg;
  pw.Font? _bold;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _blank(dynamic v) => v == null || "$v".trim().isEmpty;

  Future<void> _prepare() async {
    final u = Map<String, dynamic>.from(widget.unit);
    final sync = SyncService();
    try {
      final unitId = u["unit_id"] ?? u["id"];
      if (_blank(u["engine_no"]) || _blank(u["color"]) || _blank(u["sold_price"])) {
        final r = await sync.getList("/units?status=sold", widget.token);
        if (r["data"] is List) {
          for (final x in r["data"] as List) {
            if (x is Map &&
                ((unitId != null && (x["id"] == unitId || x["unit_id"] == unitId)) ||
                    "${x["chassis_no"]}" == "${u["chassis_no"]}")) {
              x.forEach((k, v) {
                if (_blank(u[k.toString()])) u[k.toString()] = v;
              });
              break;
            }
          }
        }
      }
    } catch (_) {}
    try {
      final cid = u["customer_id"];
      final cname = u["customer_name"];
      final r = await sync.getList("/parties", widget.token);
      if (r["data"] is List) {
        for (final p in r["data"] as List) {
          if (p is! Map || p["party_type"] != "customer") continue;
          final match = (cid != null && p["id"] == cid) ||
              (cid == null && cname != null && "${p["name"]}" == "$cname");
          if (match) {
            if (_blank(u["customer_name"])) u["customer_name"] = p["name"];
            if (_blank(u["customer_phone"])) u["customer_phone"] = p["phone"];
            if (_blank(u["customer_address"])) u["customer_address"] = p["address"];
            if (_blank(u["customer_nid"])) u["customer_nid"] = p["nid_no"];
            break;
          }
        }
      }
    } catch (_) {}

    final reg = pw.Font.ttf(await rootBundle.load("assets/fonts/NotoSansBengali-Regular.ttf"));
    final bold = pw.Font.ttf(await rootBundle.load("assets/fonts/NotoSansBengali-Bold.ttf"));

    String s(dynamic x) => _blank(x) ? '' : "$x";
    final saleDate = DateTime.tryParse(s(u["sold_date"])) ?? DateTime.now();
    final price = _intOf(s(u["sold_price"]));
    final model = "${s(u["brand"])} ${s(u["model"])}".trim();

    void put(String key, String val) {
      if (val.isNotEmpty) _c[key]!.text = val;
    }

    put('doc_date', _fmtDate(saleDate));
    put('ref_session', _session(saleDate));
    put('ref_no', s(u["unit_id"] ?? u["id"]));
    put('owner_name', s(u["customer_name"]));
    put('father', s(u["customer_father"] ?? u["father_name"]));
    put('address', s(u["customer_address"]));
    put('phone', s(u["customer_phone"]));
    put('model', model);
    put('description', model);
    put('chassis', s(u["chassis_no"]));
    put('engine', s(u["engine_no"]));
    put('colour', s(u["color"]));
    put('year', s(u["year"]));
    if (price != null) {
      put('price', "$price");
      put('advance', "$price");
    }

    if (!mounted) return;
    setState(() {
      _reg = reg;
      _bold = bold;
      _loading = false;
    });
  }

  _Kit _kit() => _Kit({for (final e in _c.entries) e.key: e.value.text}, _reg!, _bold!);

  Widget _form() {
    final groups = <String>[];
    for (final f in _fields) {
      if (!groups.contains(f.group)) groups.add(f.group);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: const Text(
            "এখানে একবার তথ্য দিলে পাশের সব ট্যাবের কাগজে নিজে থেকে বসে যাবে। "
            "ফাঁকা ঘর কাগজে ফাঁকা থাকবে, হাতে লেখা যাবে।",
            style: TextStyle(fontSize: 13),
          ),
        ),
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: Text(g, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final f in _fields.where((x) => x.group == g))
                SizedBox(
                  width: f.multiline ? 520 : 250,
                  child: TextField(
                    controller: _c[f.key],
                    maxLines: f.multiline ? 4 : 1,
                    decoration: InputDecoration(
                      labelText: f.label,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {
                      _ver++;
                    }),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _doc(int i) {
    return PdfPreview(
      key: ValueKey("doc$i-$_ver"),
      build: (_) => _kit().build([i]),
      canChangePageFormat: false,
      canChangeOrientation: false,
      allowPrinting: true,
      allowSharing: true,
      pdfFileName: "brta_page_${i + 1}.pdf",
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("BRTA কাগজপত্র")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return DefaultTabController(
      length: _tabNames.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("BRTA কাগজপত্র"),
          actions: [
            IconButton(
              tooltip: "সব কাগজ একসাথে প্রিন্ট / PDF",
              icon: const Icon(Icons.print),
              onPressed: () => Printing.layoutPdf(
                name: "brta_all.pdf",
                onLayout: (_) => _kit().build([0, 1, 2, 3, 4, 5, 6]),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final n in _tabNames) Tab(text: n)],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _form(),
            for (int i = 0; i < 7; i++) _doc(i),
          ],
        ),
      ),
    );
  }
}
