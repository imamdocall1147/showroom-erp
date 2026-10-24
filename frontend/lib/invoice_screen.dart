import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
// • লেখা Flutter দিয়ে আঁকা হয় (বাংলা যুক্তাক্ষর ঠিক থাকে), তারপর ছবি করে PDF হয়।
// • এডিট শুধু এই কপিতে থাকে, হিসাব/ব্যালান্স/রিপোর্টে কিছু বদলায় না।
// • সংরক্ষণ হয় এই ডিভাইসে/ব্রাউজারে (SharedPreferences)।
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
  static const double _w = 794;
  static const double _h = 1123;
  static const List<int> _fx = [10, 60, 12, 20, 24];

  final GlobalKey _boundary = GlobalKey();
  Map<String, String> _v = {};
  Color _ink = const Color(0xFF000000);
  Color _accent = const Color(0xFF000000);
  bool _loading = true;
  bool _busy = false;

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
    });
    await _save();
  }

  // ---------------- PDF (পাতার ছবি তুলে) ----------------
  Future<void> _openPdf() async {
    setState(() => _busy = true);
    try {
      final ro = _boundary.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return;
      final img = await ro.toImage(pixelRatio: 2.5);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return;
      final image = pw.MemoryImage(bd.buffer.asUint8List());
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
      final Uint8List bytes = await doc.save();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(widget.invoiceTitle)),
            body: PdfPreview(
              build: (_) async => bytes,
              pdfFileName: "invoice_${widget.invoiceNumber}.pdf",
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("PDF তৈরি করা যায়নি: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- পাতার চেহারা ----------------
  String _g(String k) => _v[k] ?? '';

  TextStyle _st(double size, {bool b = false, Color? c, bool i = false}) => TextStyle(
        fontSize: size,
        color: c ?? _ink,
        fontWeight: b ? FontWeight.w700 : FontWeight.w400,
        fontStyle: i ? FontStyle.italic : FontStyle.normal,
        height: 1.25,
        decoration: TextDecoration.none,
      );

  Widget _dashed(Widget child) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 2), child: child),
        _DashLine(_ink),
      ],
    );
  }

  Widget _line(String label, String value, {double labelW = 120, double top = 10}) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(width: labelW, child: Text(label, style: _st(15, b: true))),
          Expanded(child: _dashed(Text(value.isEmpty ? ' ' : value, style: _st(17)))),
        ],
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Text(_g('brand1'), style: _st(34, b: true, c: _accent)),
            ),
            Expanded(
              flex: 5,
              child: Center(
                child: Text(_g('shop'), style: _st(40, b: true, c: _accent)),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_g('brand2'), style: _st(24, b: true, c: _accent)),
                  Text(_g('brandTag'),
                      textAlign: TextAlign.right, style: _st(10, b: true, c: _accent)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(child: Text(_g('branch1'), textAlign: TextAlign.center, style: _st(13.5))),
        Center(child: Text(_g('branch2'), textAlign: TextAlign.center, style: _st(13.5))),
        Center(child: Text(_g('mobile'), textAlign: TextAlign.center, style: _st(13.5))),
        const SizedBox(height: 2),
        Center(
          child: Text(_g('tagline'), textAlign: TextAlign.center, style: _st(13, b: true)),
        ),
        const SizedBox(height: 8),
        Container(height: 1.4, color: _ink),
      ],
    );
  }

  Widget _topInfo() {
    return Column(
      children: [
        if (_g('title').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(child: Text(_g('title'), style: _st(16, b: true))),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text("${_g('l_memo')}: ", style: _st(16, b: true)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              color: const Color(0xFFE9E9E9),
              child: Text(_g('memoNo'), style: _st(18, b: true)),
            ),
            const Spacer(),
            Text("${_g('l_date')}: ", style: _st(16, b: true)),
            SizedBox(
              width: 150,
              child: _dashed(Center(child: Text(_g('date'), style: _st(17)))),
            ),
          ],
        ),
        _line(_g('l_name'), _g('name')),
        _line(_g('l_father'), _g('father')),
        _line(_g('l_address'), _g('address')),
        _line(_g('l_phone'), _g('phone')),
        _line(_g('l_ref'), _g('ref'), labelW: 60),
      ],
    );
  }

  BorderSide get _bs => BorderSide(color: _ink, width: 1.4);

  Widget _cell(int i, Widget child, {double? h}) {
    return Expanded(
      flex: _fx[i],
      child: Container(
        height: h,
        decoration: BoxDecoration(
          border: Border(right: i == 4 ? BorderSide.none : _bs),
        ),
        child: child,
      ),
    );
  }

  Widget _center(String s, {bool b = false, double size = 16}) =>
      Center(child: Text(s, style: _st(size, b: b)));

  Widget _top(String s) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(s, style: _st(17, b: true)),
        ),
      );

  Widget _vehicleLine(String l, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(width: 118, child: Text(l, style: _st(14.5, b: true))),
          Expanded(child: _dashed(Text(v.isEmpty ? ' ' : v, style: _st(16)))),
        ],
      ),
    );
  }

  Widget _totRow(String label, String value) {
    return Container(
      height: 36,
      decoration: BoxDecoration(border: Border(top: _bs)),
      child: Row(
        children: [
          Expanded(
            flex: _fx[3],
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(border: Border(right: _bs)),
              child: Text(label, style: _st(15, b: true)),
            ),
          ),
          Expanded(
            flex: _fx[4],
            child: Center(child: Text(value, style: _st(16, b: true))),
          ),
        ],
      ),
    );
  }

  Widget _table() {
    final note = _g('note').trim();
    final extra = <Widget>[];
    for (var i = 1; i <= 3; i++) {
      final d = _g('x${i}d');
      final q = _g('x${i}q');
      final r = _g('x${i}r');
      final t = _g('x${i}t');
      if (d.isEmpty && q.isEmpty && r.isEmpty && t.isEmpty) continue;
      extra.add(
        Row(
          children: [
            _cell(0, const SizedBox(), h: 34),
            _cell(
              1,
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 0),
                child: Text(d, style: _st(15)),
              ),
              h: 34,
            ),
            _cell(2, Padding(padding: const EdgeInsets.only(top: 7), child: _center(q, size: 15)), h: 34),
            _cell(3, Padding(padding: const EdgeInsets.only(top: 7), child: _center(r, size: 15)), h: 34),
            _cell(4, Padding(padding: const EdgeInsets.only(top: 7), child: _center(t, size: 15)), h: 34),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(border: Border(bottom: _bs)),
            child: Row(
              children: [
                _cell(0, _center(_g('l_sl'), b: true, size: 15)),
                _cell(1, _center(_g('l_desc'), b: true, size: 15)),
                _cell(2, _center(_g('l_qty'), b: true, size: 15)),
                _cell(3, _center(_g('l_rate'), b: true, size: 15)),
                _cell(4, _center(_g('l_taka'), b: true, size: 15)),
              ],
            ),
          ),
          Row(
            children: [
              _cell(0, const SizedBox(), h: 120),
              _cell(
                1,
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _vehicleLine(_g('l_chassis'), _g('chassis')),
                      _vehicleLine(_g('l_engine'), _g('engine')),
                      _vehicleLine(_g('l_product'), _g('product')),
                    ],
                  ),
                ),
                h: 120,
              ),
              _cell(2, _top(_g('qty')), h: 120),
              _cell(3, _top(_g('rate')), h: 120),
              _cell(4, _top(_g('taka')), h: 120),
            ],
          ),
          ...extra,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cell(0, const SizedBox()),
                _cell(
                  1,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: note.isEmpty
                          ? const SizedBox()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DashLine(_ink),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(note, style: _st(14.5, b: true)),
                                ),
                                _DashLine(_ink),
                              ],
                            ),
                    ),
                  ),
                ),
                _cell(2, const SizedBox()),
                _cell(3, const SizedBox()),
                _cell(4, const SizedBox()),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: _fx[0] + _fx[1] + _fx[2], child: const SizedBox()),
              Expanded(
                flex: _fx[3] + _fx[4],
                child: Column(
                  children: [
                    _totRow(_g('l_total'), _g('total')),
                    _totRow(_g('l_advance'), _g('advance')),
                    _totRow(_g('l_due'), _g('due')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _signatures() {
    return Padding(
      padding: const EdgeInsets.only(top: 40, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 210,
            child: Column(
              children: [
                Container(height: 1.6, color: _ink),
                const SizedBox(height: 4),
                Text(_g('signBuyer'), style: _st(15, b: true)),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 250,
            child: Column(
              children: [
                Container(height: 1.6, color: _ink),
                const SizedBox(height: 4),
                Text(_g('signSeller'), style: _st(15, b: true)),
                const SizedBox(height: 8),
                Text(_g('director'), style: _st(14, c: _accent)),
                Text(_g('directorTitle'),
                    textAlign: TextAlign.center, style: _st(13, c: _accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _page() {
    return SizedBox(
      width: _w,
      height: _h,
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              _topInfo(),
              const SizedBox(height: 14),
              Expanded(child: _table()),
              _signatures(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9EDF3),
      appBar: AppBar(
        title: Text(widget.invoiceTitle),
        actions: [
          IconButton(
            tooltip: "এডিট (লেখা, টাকা, রঙ, সব কিছু)",
            icon: const Icon(Icons.edit),
            onPressed: _loading ? null : _edit,
          ),
          IconButton(
            tooltip: "PDF / প্রিন্ট",
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf),
            onPressed: (_loading || _busy) ? null : _openPdf,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RepaintBoundary(key: _boundary, child: _page()),
                  ),
                ),
              ),
            ),
    );
  }
}

class _DashLine extends StatelessWidget {
  final Color color;
  const _DashLine(this.color);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final n = (box.maxWidth / 9).floor();
        return Row(
          children: [
            for (var i = 0; i < n; i++)
              Container(
                width: 5,
                height: 1.2,
                color: color,
                margin: const EdgeInsets.only(right: 4),
              ),
          ],
        );
      },
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