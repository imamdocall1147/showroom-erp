import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// report_pdf.dart এই নামটা ব্যবহার করে, তাই রাখা হয়েছে
const String companyName = "ইমাম মোটর্স";

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

// ---------------------------------------------------------------
// সব মেমোতে একই থাকে (একবার বদলালে সব জায়গায় বদলায়)
// ---------------------------------------------------------------
const Map<String, String> _shared = {
  'brand1': 'RUNNER',
  'shop': 'ইমাম মোটর্স',
  'brand2': 'BAJAJ',
  'brandTag': 'LOVED IN 70 COUNTRIES',
  'branch1': 'শাখা ১: ১৯১৭, নুরজাহান ম্যানশন, আরকান রোড, বাদুরতলা, পাঁচলাইশ, চট্টগ্রাম।',
  'branch2': 'শাখা ২: ১১৪৭, ছোটপুল কাঁচাবাজার, হালিশহর, চট্টগ্রাম।',
  'mobile': 'মোবাইল: ০১৭৫৪-২৯৩৮৪৯',
  'tagline': '*বাজাজ সি এন জি, এল পি জি, ও ম্যাক্রিমা গাড়ী ক্রয় বিক্রয় এর বিশ্বাসযোগ্য প্রতিষ্ঠান*',
  'signSeller': 'পক্ষে, ইমাম মোটর্স',
  'director': 'Md. Imam Hossain',
  'directorTitle': '(Director)\nIMAM MOTORS',
  'l_memo': 'মেমো নং',
  'l_date': 'তারিখ',
  'l_father': 'পিতার নাম',
  'l_address': 'ঠিকানা',
  'l_phone': 'ফোন',
  'l_ref': 'রেফ',
  'l_sl': 'ক্রমিক',
  'l_desc': 'বিবরণ',
  'l_qty': 'পরিমাণ',
  'l_rate': 'দর',
  'l_taka': 'টাকা',
  'l_chassis': 'চেসিস নং',
  'l_engine': 'ইঞ্জিন নং',
  'l_product': 'প্রোডাক্টের নাম',
  'l_total': 'মোট',
  'l_advance': 'অগ্রিম',
  'l_due': 'বাকি',
};

class _F {
  final String k;
  final String cap;
  final bool multi;
  const _F(this.k, this.cap, {this.multi = false});
}

List<_F> _extraFields() => [
      for (var i = 1; i <= 3; i++) ...[
        _F('x${i}d', 'অতিরিক্ত সারি $i — বিবরণ'),
        _F('x${i}q', 'অতিরিক্ত সারি $i — পরিমাণ'),
        _F('x${i}r', 'অতিরিক্ত সারি $i — দর'),
        _F('x${i}t', 'অতিরিক্ত সারি $i — টাকা'),
      ],
    ];

Map<String, List<_F>> _groups() => {
      'এই মেমোর তথ্য (শুধু এই মেমো)': const [
        _F('title', 'শিরোনাম (ছোট করে মাঝখানে)'),
        _F('memoNo', 'মেমো নং'),
        _F('date', 'তারিখ'),
        _F('l_name', 'নামের লেবেল (নাম / সাপ্লায়ার)'),
        _F('name', 'নাম'),
        _F('father', 'পিতার নাম'),
        _F('address', 'ঠিকানা'),
        _F('phone', 'ফোন'),
        _F('ref', 'রেফ'),
      ],
      'গাড়ি ও টাকা (শুধু এই মেমো)': [
        const _F('chassis', 'চেসিস নং'),
        const _F('engine', 'ইঞ্জিন নং'),
        const _F('product', 'প্রোডাক্টের নাম'),
        const _F('qty', 'পরিমাণ'),
        const _F('rate', 'দর'),
        const _F('taka', 'টাকা'),
        const _F('note', 'নোট (টেবিলের নিচে)', multi: true),
        ..._extraFields(),
        const _F('total', 'মোট'),
        const _F('advance', 'অগ্রিম'),
        const _F('due', 'বাকি'),
        const _F('signBuyer', 'বাঁ পাশের স্বাক্ষরের লেখা'),
      ],
      'হেডার (সব মেমোতে বদলাবে)': const [
        _F('brand1', 'বাঁ পাশের ব্র্যান্ড লেখা'),
        _F('shop', 'দোকানের নাম'),
        _F('brand2', 'ডান পাশের ব্র্যান্ড লেখা'),
        _F('brandTag', 'ডান পাশের ছোট লেখা'),
        _F('branch1', 'শাখা ১ ঠিকানা'),
        _F('branch2', 'শাখা ২ ঠিকানা'),
        _F('mobile', 'মোবাইল'),
        _F('tagline', 'ট্যাগলাইন'),
      ],
      'স্বাক্ষর (সব মেমোতে বদলাবে)': const [
        _F('signSeller', 'ডান পাশের স্বাক্ষরের লেখা'),
        _F('director', 'পরিচালকের নাম'),
        _F('directorTitle', 'পদবি / সিলের লেখা', multi: true),
      ],
      'লেবেল (সব মেমোতে বদলাবে)': const [
        _F('l_memo', 'মেমো নং'),
        _F('l_date', 'তারিখ'),
        _F('l_father', 'পিতার নাম'),
        _F('l_address', 'ঠিকানা'),
        _F('l_phone', 'ফোন'),
        _F('l_ref', 'রেফ'),
        _F('l_sl', 'ক্রমিক'),
        _F('l_desc', 'বিবরণ'),
        _F('l_qty', 'পরিমাণ'),
        _F('l_rate', 'দর'),
        _F('l_taka', 'টাকা'),
        _F('l_chassis', 'চেসিস নং'),
        _F('l_engine', 'ইঞ্জিন নং'),
        _F('l_product', 'প্রোডাক্টের নাম'),
        _F('l_total', 'মোট'),
        _F('l_advance', 'অগ্রিম'),
        _F('l_due', 'বাকি'),
      ],
    };

const List<Color> _palette = [
  Color(0xFF000000),
  Color(0xFF1A237E),
  Color(0xFFB71C1C),
  Color(0xFF1B5E20),
  Color(0xFF4A148C),
  Color(0xFFE65100),
  Color(0xFF006064),
  Color(0xFF455A64),
];

// ---------------------------------------------------------------
// ইনভয়েস / মেমো স্ক্রিন
// • এডিট শুধু এই কপিতে থাকে, হিসাব/ব্যালান্স/রিপোর্টে কিছু বদলায় না।
// • সংরক্ষণ হয় এই ডিভাইসে (SharedPreferences)।
// ---------------------------------------------------------------
class InvoiceScreen extends StatefulWidget {
  final String invoiceTitle;
  final String invoiceNumber;
  final DateTime date;
  final String partyName;
  final String? partyPhone;
  final List<InvoiceItem> items;
  final String paymentMode;
  final int totalAmount;

  /// এখন জমা। না দিলে: cash = পুরো জমা, due = পুরোটা বাকি
  final int? paidAmount;

  /// বিক্রয়ে "কাস্টমার", ক্রয়ে "সাপ্লায়ার"
  final String partyLabel;

  /// বিক্রয়ে "ক্রেতার স্বাক্ষর", ক্রয়ে "বিক্রেতার স্বাক্ষর"
  final String partySignatureLabel;

  // ---- নতুন (সব ঐচ্ছিক) ----
  /// প্রতিটা মেমোর আলাদা সংরক্ষণের চাবি, যেমন "sale_123"। না দিলে শিরোনাম+নম্বর থেকে হয়।
  final String? storageKey;
  final String? address;
  final String? fatherName;
  final String? refText;
  final String? chassisNo;
  final String? engineNo;
  final String? productName;
  final String? note;

  /// true হলে দর, টাকা, মোট, অগ্রিম, বাকি ফাঁকা থাকবে (স্টক ট্রান্সফারের মেমোর জন্য)
  final bool hideAmounts;

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
    this.partySignatureLabel = "ক্রেতার স্বাক্ষর",
    this.storageKey,
    this.address,
    this.fatherName,
    this.refText,
    this.chassisNo,
    this.engineNo,
    this.productName,
    this.note,
    this.hideAmounts = false,
  });

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  Map<String, String> _v = {};
  Color _ink = const Color(0xFF000000);
  Color _accent = const Color(0xFF000000);
  pw.Font? _reg;
  pw.Font? _bold;
  bool _loading = true;
  String? _error;
  int _gen = 0;

  String get _key => widget.storageKey ?? "inv_${widget.invoiceTitle}_${widget.invoiceNumber}";

  int get _paid =>
      widget.paidAmount ?? (widget.paymentMode == 'cash' ? widget.totalAmount : 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Map<String, String> _initialValues() {
    final d = widget.date;
    final items = widget.items;
    final first = items.isNotEmpty ? items.first : null;
    final hide = widget.hideAmounts;
    final due = widget.totalAmount - _paid;

    final m = <String, String>{
      'title': widget.invoiceTitle,
      'l_name': widget.partyLabel == 'কাস্টমার' ? 'নাম' : widget.partyLabel,
      'signBuyer': widget.partySignatureLabel,
      'memoNo': widget.invoiceNumber,
      'date': "${_two(d.day)}.${_two(d.month)}.${d.year}",
      'name': widget.partyName,
      'father': widget.fatherName ?? '',
      'address': widget.address ?? '',
      'phone': widget.partyPhone ?? '',
      'ref': widget.refText ?? '',
      'chassis': widget.chassisNo ?? '',
      'engine': widget.engineNo ?? '',
      'product': widget.productName ??
          ((widget.chassisNo == null && first != null) ? first.description : ''),
      'qty': first == null ? (widget.chassisNo != null ? '1' : '') : '${first.qty}',
      'rate': (first == null || hide) ? '' : '${first.unitPrice}',
      'taka': (first == null || hide) ? '' : '${first.total}',
      'note': widget.note ?? '',
      'total': hide ? '' : '${widget.totalAmount}',
      'advance': hide ? '' : '$_paid',
      'due': hide ? '' : '$due',
    };
    for (var i = 1; i <= 3; i++) {
      final it = items.length > i ? items[i] : null;
      m['x${i}d'] = it?.description ?? '';
      m['x${i}q'] = it == null ? '' : '${it.qty}';
      m['x${i}r'] = (it == null || hide) ? '' : '${it.unitPrice}';
      m['x${i}t'] = (it == null || hide) ? '' : '${it.total}';
    }
    return m;
  }

  Future<void> _load() async {
    try {
      final reg = await rootBundle.load("assets/fonts/NotoSansBengali-Regular.ttf");
      final bold = await rootBundle.load("assets/fonts/NotoSansBengali-Bold.ttf");
      _reg = pw.Font.ttf(reg);
      _bold = pw.Font.ttf(bold);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "বাংলা ফন্ট লোড হয়নি: $e";
          _loading = false;
        });
      }
      return;
    }

    Map<String, dynamic> t = {};
    Map<String, dynamic> m = {};
    try {
      final p = await SharedPreferences.getInstance();
      t = jsonDecode(p.getString('memo_template') ?? '{}') as Map<String, dynamic>;
      m = jsonDecode(p.getString('memo_$_key') ?? '{}') as Map<String, dynamic>;
    } catch (_) {}

    final v = <String, String>{..._shared, ..._initialValues()};
    t.forEach((k, x) {
      if (_shared.containsKey(k)) v[k] = '$x';
    });
    m.forEach((k, x) {
      v[k] = '$x';
    });

    if (!mounted) return;
    setState(() {
      _v = v;
      _ink = Color(int.tryParse('${t['inkColor']}') ?? 0xFF000000);
      _accent = Color(int.tryParse('${t['accentColor']}') ?? 0xFF000000);
      _loading = false;
    });
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      final t = <String, String>{
        for (final k in _shared.keys) k: _v[k] ?? '',
        'inkColor': '${_ink.toARGB32()}',
        'accentColor': '${_accent.toARGB32()}',
      };
      final m = <String, String>{
        for (final e in _v.entries)
          if (!_shared.containsKey(e.key)) e.key: e.value,
      };
      await p.setString('memo_template', jsonEncode(t));
      await p.setString('memo_$_key', jsonEncode(m));
    } catch (_) {}
  }

  Future<void> _edit() async {
    final res = await Navigator.of(context).push<_EditResult>(
      MaterialPageRoute(
        builder: (_) => _MemoEditScreen(values: _v, ink: _ink, accent: _accent),
      ),
    );
    if (res == null || !mounted) return;
    setState(() {
      _v = res.values;
      _ink = res.ink;
      _accent = res.accent;
      _gen++;
    });
    await _save();
  }

  // ---------------- PDF ----------------
  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final reg = _reg!;
    final bold = _bold!;
    final ink = PdfColor.fromInt(_ink.toARGB32());
    final accent = PdfColor.fromInt(_accent.toARGB32());
    String g(String k) => _v[k] ?? '';

    pw.TextStyle st(double size, {bool b = false, PdfColor? c}) =>
        pw.TextStyle(fontSize: size, color: c ?? ink, font: b ? bold : reg);

    pw.Widget dashed() => pw.Divider(
          height: 3,
          thickness: 0.8,
          color: ink,
          borderStyle: pw.BorderStyle.dashed,
        );

    pw.Widget field(String label, String value, {double labelW = 80, double top = 7}) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(top: top),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(width: labelW, child: pw.Text(label, style: st(11, b: true))),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(value.isEmpty ? ' ' : value, style: st(12.5)),
                  dashed(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    const fx = [10, 60, 12, 20, 24];
    final bd = pw.BorderSide(color: ink, width: 1);

    pw.Widget cell(int i, pw.Widget child, {double? h}) {
      return pw.Expanded(
        flex: fx[i],
        child: pw.Container(
          height: h,
          decoration: pw.BoxDecoration(
            border: pw.Border(right: i == 4 ? pw.BorderSide.none : bd),
          ),
          child: child,
        ),
      );
    }

    pw.Widget centerText(String s, {bool b = false, double size = 12}) =>
        pw.Center(child: pw.Text(s, style: st(size, b: b)));

    pw.Widget topText(String s) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Align(
            alignment: pw.Alignment.topCenter,
            child: pw.Text(s, style: st(12.5, b: true)),
          ),
        );

    // ---- হেডার ----
    final header = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Text(g('brand1'), style: st(26, b: true, c: accent)),
            ),
            pw.Expanded(
              flex: 5,
              child: pw.Center(child: pw.Text(g('shop'), style: st(30, b: true, c: accent))),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(g('brand2'), style: st(17, b: true, c: accent)),
                  pw.Text(g('brandTag'),
                      textAlign: pw.TextAlign.right, style: st(7, b: true, c: accent)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text(g('branch1'), style: st(10))),
        pw.Center(child: pw.Text(g('branch2'), style: st(10))),
        pw.Center(child: pw.Text(g('mobile'), style: st(10))),
        pw.SizedBox(height: 2),
        pw.Center(child: pw.Text(g('tagline'), style: st(9.5, b: true))),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.2, color: ink),
      ],
    );

    // ---- ক্রেতার তথ্য ----
    final info = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (g('title').trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Center(child: pw.Text(g('title'), style: st(12, b: true))),
          ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            pw.Text("${g('l_memo')}: ", style: st(12, b: true)),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              color: PdfColors.grey300,
              child: pw.Text(g('memoNo'), style: st(14, b: true)),
            ),
            pw.Spacer(),
            pw.Text("${g('l_date')}: ", style: st(12, b: true)),
            pw.SizedBox(
              width: 110,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Center(child: pw.Text(g('date'), style: st(12.5))),
                  dashed(),
                ],
              ),
            ),
          ],
        ),
        field(g('l_name'), g('name')),
        field(g('l_father'), g('father')),
        field(g('l_address'), g('address')),
        field(g('l_phone'), g('phone')),
        field(g('l_ref'), g('ref'), labelW: 40),
      ],
    );

    // ---- টেবিল ----
    pw.Widget vehicleLine(String l, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(width: 82, child: pw.Text(l, style: st(11, b: true))),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(v.isEmpty ? ' ' : v, style: st(12)),
                    dashed(),
                  ],
                ),
              ),
            ],
          ),
        );

    final headRow = pw.Container(
      height: 26,
      decoration: pw.BoxDecoration(border: pw.Border(bottom: bd)),
      child: pw.Row(
        children: [
          cell(0, centerText(g('l_sl'), b: true, size: 11.5)),
          cell(1, centerText(g('l_desc'), b: true, size: 11.5)),
          cell(2, centerText(g('l_qty'), b: true, size: 11.5)),
          cell(3, centerText(g('l_rate'), b: true, size: 11.5)),
          cell(4, centerText(g('l_taka'), b: true, size: 11.5)),
        ],
      ),
    );

    final vehicleRow = pw.Row(
      children: [
        cell(0, pw.SizedBox(), h: 92),
        cell(
          1,
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                vehicleLine(g('l_chassis'), g('chassis')),
                vehicleLine(g('l_engine'), g('engine')),
                vehicleLine(g('l_product'), g('product')),
              ],
            ),
          ),
          h: 92,
        ),
        cell(2, topText(g('qty')), h: 92),
        cell(3, topText(g('rate')), h: 92),
        cell(4, topText(g('taka')), h: 92),
      ],
    );

    final extraRows = <pw.Widget>[];
    for (var i = 1; i <= 3; i++) {
      final d = g('x${i}d');
      final q = g('x${i}q');
      final r = g('x${i}r');
      final t = g('x${i}t');
      if (d.isEmpty && q.isEmpty && r.isEmpty && t.isEmpty) continue;
      extraRows.add(
        pw.Row(
          children: [
            cell(0, pw.SizedBox(), h: 24),
            cell(
              1,
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 0),
                child: pw.Text(d, style: st(12)),
              ),
              h: 24,
            ),
            cell(2, pw.Padding(padding: const pw.EdgeInsets.only(top: 5), child: centerText(q)), h: 24),
            cell(3, pw.Padding(padding: const pw.EdgeInsets.only(top: 5), child: centerText(r)), h: 24),
            cell(4, pw.Padding(padding: const pw.EdgeInsets.only(top: 5), child: centerText(t)), h: 24),
          ],
        ),
      );
    }

    final note = g('note').trim();
    final fillRow = pw.Expanded(
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          cell(0, pw.SizedBox()),
          cell(
            1,
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: pw.Align(
                alignment: pw.Alignment.bottomLeft,
                child: note.isEmpty
                    ? pw.SizedBox()
                    : pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          dashed(),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 3),
                            child: pw.Text(note, style: st(11.5, b: true)),
                          ),
                          dashed(),
                        ],
                      ),
              ),
            ),
          ),
          cell(2, pw.SizedBox()),
          cell(3, pw.SizedBox()),
          cell(4, pw.SizedBox()),
        ],
      ),
    );

    pw.Widget totRow(String label, String value) => pw.Container(
          height: 26,
          decoration: pw.BoxDecoration(border: pw.Border(top: bd)),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: fx[3],
                child: pw.Container(
                  alignment: pw.Alignment.centerLeft,
                  padding: const pw.EdgeInsets.only(left: 5),
                  decoration: pw.BoxDecoration(border: pw.Border(right: bd)),
                  child: pw.Text(label, style: st(11.5, b: true)),
                ),
              ),
              pw.Expanded(
                flex: fx[4],
                child: pw.Center(child: pw.Text(value, style: st(12.5, b: true))),
              ),
            ],
          ),
        );

    final totals = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(flex: fx[0] + fx[1] + fx[2], child: pw.SizedBox()),
        pw.Expanded(
          flex: fx[3] + fx[4],
          child: pw.Column(
            children: [
              totRow(g('l_total'), g('total')),
              totRow(g('l_advance'), g('advance')),
              totRow(g('l_due'), g('due')),
            ],
          ),
        ),
      ],
    );

    final table = pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: ink, width: 1.4)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          headRow,
          vehicleRow,
          ...extraRows,
          fillRow,
          totals,
        ],
      ),
    );

    // ---- স্বাক্ষর ----
    final signs = pw.Padding(
      padding: const pw.EdgeInsets.only(top: 30),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            children: [
              pw.Container(width: 150, height: 1.2, color: ink),
              pw.SizedBox(height: 3),
              pw.Text(g('signBuyer'), style: st(11.5, b: true)),
            ],
          ),
          pw.Column(
            children: [
              pw.Container(width: 180, height: 1.2, color: ink),
              pw.SizedBox(height: 3),
              pw.Text(g('signSeller'), style: st(11.5, b: true)),
              pw.SizedBox(height: 6),
              pw.Text(g('director'), style: st(10.5, c: accent)),
              pw.Text(g('directorTitle'),
                  textAlign: pw.TextAlign.center, style: st(9.5, c: accent)),
            ],
          ),
        ],
      ),
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 22),
        theme: pw.ThemeData.withFont(base: reg, bold: bold),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            header,
            info,
            pw.SizedBox(height: 10),
            pw.Expanded(child: table),
            signs,
          ],
        ),
      ),
    );
    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.invoiceTitle),
        actions: [
          IconButton(
            tooltip: "এডিট (লেখা, টাকা, রঙ, সব কিছু)",
            icon: const Icon(Icons.edit),
            onPressed: _loading || _error != null ? null : _edit,
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : PdfPreview(
                  key: ValueKey(_gen),
                  build: (format) => _generatePdf(format),
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowPrinting: true,
                  allowSharing: true,
                  pdfFileName: "invoice_${widget.invoiceNumber}.pdf",
                ),
    );
  }
}

// ---------------------------------------------------------------
// এডিট স্ক্রিন
// ---------------------------------------------------------------
class _EditResult {
  final Map<String, String> values;
  final Color ink;
  final Color accent;
  const _EditResult(this.values, this.ink, this.accent);
}

class _MemoEditScreen extends StatefulWidget {
  final Map<String, String> values;
  final Color ink;
  final Color accent;
  const _MemoEditScreen({required this.values, required this.ink, required this.accent});

  @override
  State<_MemoEditScreen> createState() => _MemoEditScreenState();
}

class _MemoEditScreenState extends State<_MemoEditScreen> {
  final Map<String, TextEditingController> _c = {};
  late final Map<String, List<_F>> _g;
  late Color _ink;
  late Color _accent;

  @override
  void initState() {
    super.initState();
    _ink = widget.ink;
    _accent = widget.accent;
    _g = _groups();
    for (final list in _g.values) {
      for (final f in list) {
        _c[f.k] = TextEditingController(text: widget.values[f.k] ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(String k) => int.tryParse(_c[k]!.text.replaceAll(',', '').trim()) ?? 0;

  void _autoTotals() {
    var sum = _n('taka');
    for (var i = 1; i <= 3; i++) {
      sum += _n('x${i}t');
    }
    setState(() {
      _c['total']!.text = '$sum';
      _c['due']!.text = '${sum - _n('advance')}';
    });
  }

  void _done() {
    final v = Map<String, String>.from(widget.values);
    _c.forEach((k, c) {
      v[k] = c.text;
    });
    Navigator.of(context).pop(_EditResult(v, _ink, _accent));
  }

  Widget _colorRow(String label, Color value, void Function(Color) set) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _palette)
                  InkWell(
                    onTap: () => setState(() => set(c)),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: value.toARGB32() == c.toARGB32()
                              ? Colors.amber
                              : Colors.black26,
                          width: value.toARGB32() == c.toARGB32() ? 3.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          "এখানকার পরিবর্তন শুধু এই ইনভয়েসের কপিতে থাকবে। হিসাব, বাকি, একাউন্ট ও রিপোর্টে কিছু বদলাবে না।",
          style: TextStyle(fontSize: 13),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("রঙ (সব মেমোতে বদলাবে)",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              _colorRow("লেখা ও বর্ডার", _ink, (c) => _ink = c),
              _colorRow("নাম ও ব্র্যান্ড", _accent, (c) => _accent = c),
            ],
          ),
        ),
      ),
    ];

    _g.forEach((title, fields) {
      children.add(const SizedBox(height: 14));
      children.add(Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)));
      children.add(const SizedBox(height: 8));
      for (final f in fields) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _c[f.k],
              maxLines: f.multi ? 3 : 1,
              minLines: 1,
              decoration: InputDecoration(
                labelText: f.cap,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        );
        if (f.k == 'due') {
          children.add(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _autoTotals,
                icon: const Icon(Icons.calculate, size: 18),
                label: const Text("মোট ও বাকি হিসাব করে বসান"),
              ),
            ),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text("ইনভয়েস এডিট"),
        actions: [
          TextButton(
            onPressed: _done,
            child: const Text("সংরক্ষণ", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...children,
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ElevatedButton(onPressed: _done, child: const Text("সংরক্ষণ করুন")),
          ),
        ],
      ),
    );
  }
}