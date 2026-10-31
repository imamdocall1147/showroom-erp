import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
// ---------------------------------------------------------------
// বিক্রয়ের পর BRTA-র কাগজপত্র। নমুনা এক্সেল ফাইলের সাতটা শিটের হুবহু ছাঁচে:
//  ১. বিক্রয় প্রত্যয়ন   ২. সেলস ইনভয়েস (আড়াআড়ি)   ৩. অঙ্গীকারনামা
//  ৪-৫. আবেদন ফর্ম (২ পাতা)  ৬. ডিলারের ঘোষণা  ৭. ডেলিভারি চালান
//  ৮. মালিকের তথ্য ও নমুনা স্বাক্ষর   ৯. গেট পাস
// তথ্য একবার "তথ্য" ট্যাবে মিলিয়ে নিলে সব কাগজে বসে যায়।
// ---------------------------------------------------------------

const String _dots = '……………………';
String _wordsTitle(int n) {
  final w = _words(n).replaceAll('.', '');
  return w
      .split(' ')
      .where((s) => s.isNotEmpty)
      .map((s) => s[0] + s.substring(1).toLowerCase())
      .join(' ');
}

/// "লেখা ........ লেখা" ধরনের ডটের লাইন; দুই প্রান্তের মাঝে ডট ভরে দেয়
void _dotLine(_Abs a, String left, String right, double x1, double x2, double y, double size) {
  a.p.buf.writeln('$left …… $right');
  a.kids.add(Positioned(
    left: x1 * a.sx,
    width: (x2 - x1) * a.sx,
    top: a._top(y, size),
    child: Row(
      children: [
        Text(left, style: _st(size, b: false)),
        Expanded(
          child: ClipRect(
            child: Text(
              '.' * 300,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: _st(size, b: false),
            ),
          ),
        ),
        Text(right, style: _st(size, b: false)),
      ],
    ),
  ));
}
/// কাগজের নামের তালিকা (প্রতিটি কাগজের প্রিন্ট সেটিং এই নামে সংরক্ষিত হয়, ক্রম বদলাবেন না)
const List<String> _paperTitles = [
  "বিক্রয় প্রত্যয়ন",
  "সেলস ইনভয়েস",
  "অঙ্গীকারনামা",
  "আবেদন ফর্ম",
  "আবেদন ফর্ম ২",
  "ডিলার ঘোষণা",
  "ডেলিভারি চালান",
  "মালিকের তথ্য",
  "গেট পাস",
];
class _FieldDef {
  final String id;
  final String label;
  final List<String> keys;
  final String initial;
  final TextInputType type;

  const _FieldDef(
    this.id,
    this.label, {
    this.keys = const [],
    this.initial = '',
    this.type = TextInputType.text,
  });
}

const Map<String, List<_FieldDef>> _groups = {
  "দোকান, অফিস ও রেফারেন্স": [
    _FieldDef("shop_name", "দোকানের নাম (ইংরেজি)", initial: "IMAM DAINTING ENG. WORKS"),
    _FieldDef("city_en", "রেজিস্ট্রেশন অফিসের শহর (ইংরেজি)", initial: "Chittagong"),
    _FieldDef("city_bn", "শহর (বাংলা)", initial: "চট্টগ্রাম"),
    _FieldDef("circle_bn", "BRTA সার্কেল (বাংলা)", initial: "চট্টগ্রাম মেট্রো সার্কেল"),
    _FieldDef("importer_bn", "আমদানীকারক প্রতিষ্ঠান (বাংলা)", initial: "উত্তরা মোটর্স লিঃ"),
    _FieldDef("ref_prefix", "রেফারেন্সের শুরু", initial: "IDEW"),
    _FieldDef("ref_serial", "ক্রমিক নম্বর (Ref/Invoice/SL)",
        keys: ["voucher_id", "invoice_no", "invoice_number"]),
    _FieldDef("ref_fy", "অর্থবছর (যেমন 23-24, না লাগলে ফাঁকা)"),
    _FieldDef("date", "তারিখ (dd-mm-yyyy)"),
  ],
  "ক্রেতা (মালিক)": [
    _FieldDef("c_name", "নাম",
        keys: ["customer_name", "buyer_name", "sold_to", "customer"]),
    _FieldDef("c_father", "পিতা/স্বামীর নাম (S/O)", keys: ["father_name", "customer_father"]),
    _FieldDef("c_address", "ঠিকানা (C/O)",
        keys: ["customer_address", "customer_area", "area"]),
    _FieldDef("c_phone", "মোবাইল নম্বর",
        keys: ["customer_phone", "buyer_phone"], type: TextInputType.phone),
    _FieldDef("c_sex", "লিঙ্গ", initial: "MALE"),
    _FieldDef("c_nat", "জাতীয়তা", initial: "BANGLADESHI"),
    _FieldDef("c_dob", "জন্ম তারিখ"),
    _FieldDef("c_guardian", "অভিভাবকের নাম"),
    _FieldDef("c_bank", "P.O./Bank (হায়ার পারচেজ হলে)"),
    _FieldDef("c_mother", "মাতার নাম"),
    _FieldDef("c_spouse", "স্বামী/স্ত্রীর নাম"),
    _FieldDef("c_perm", "স্থায়ী ঠিকানা"),
    _FieldDef("c_nid", "NID নম্বর"),
    _FieldDef("c_etin", "E-TIN নম্বর"),
    _FieldDef("c_regno", "গাড়ির রেজি. নম্বর (মালিকানা বদলের ক্ষেত্রে)"),
    _FieldDef("c_prevreg", "Prev. Regn. No (যদি থাকে)"),
  ],
  "গাড়ি": [
    _FieldDef("model_desc", "মডেল/মেক",
        keys: ["model", "model_name", "product_name"],
        initial: "BAJAJ 3-WHEELER 4- STROKE (LPG)  AUTO RICKSHAW"),
    _FieldDef("vclass", "গাড়ির শ্রেণি (Class)", initial: "AUTORICKSHAW"),
    _FieldDef("chassis", "চেসিস নম্বর", keys: ["chassis_no"]),
    _FieldDef("engine", "ইঞ্জিন নম্বর", keys: ["engine_no"]),
    _FieldDef("key_no", "চাবি নম্বর (Key No)"),
    _FieldDef("cyl_cc", "সিলিন্ডার ও সিসি", initial: "1(ONE) / 200 CC"),
    _FieldDef("color", "রঙ", keys: ["color"]),
    _FieldDef("tyre_size", "টায়ারের মাপ", initial: "Front &Rear: 4.00/8/6 PR"),
    _FieldDef("year", "তৈরির সাল", keys: ["year"], type: TextInputType.number),
    _FieldDef("hp", "হর্স পাওয়ার", initial: "9.72 hp @5500 RPM"),
    _FieldDef("laden", "Laden Weight", initial: "719 KG"),
    _FieldDef("wheelbase", "Wheel Base", initial: "2000 MM"),
    _FieldDef("seating", "আসন সংখ্যা", initial: "3+1= 4 (Four)"),
    _FieldDef("maker", "প্রস্তুতকারক (পুরো নাম)", initial: "BAJAJ AUTO LTD. INDIA."),
  ],
  "আবেদন ফর্মের অতিরিক্ত তথ্য": [
    _FieldDef("body_en", "Type of body"),
    _FieldDef("maker_short", "Maker's name (সংক্ষেপে)", initial: "Runner Automobiles PLC"),
    _FieldDef("maker_country", "Maker's country", initial: "Bangladesh"),
    _FieldDef("fuel", "জ্বালানি", initial: "CNG"),
    _FieldDef("rpm", "RPM", initial: "5500"),
    _FieldDef("hp_app", "Horse power (আবেদন ফর্মে)", initial: "200CC"),
    _FieldDef("unladen", "Unladen weight", initial: "400 kg"),
    _FieldDef("train_wt", "Max laden/train weight", initial: "719 kg"),
    _FieldDef("n_cyl", "সিলিন্ডার সংখ্যা", initial: "One (1)"),
    _FieldDef("n_tyres", "টায়ার সংখ্যা", initial: "3 (Three)"),
    _FieldDef("n_axle", "এক্সেল সংখ্যা", initial: "2 (Two)"),
    _FieldDef("tyre_short", "Tyres size", initial: "4.00 X 8 X 6PR"),
    _FieldDef("maker_bn", "প্রস্তুতকারক (বাংলা)", initial: "বাজাজ"),
    _FieldDef("body_bn", "বডির ধরন (বাংলা)", initial: "অটোরিক্সা"),
  ],
  "বিক্রয় ও ডেলিভারি": [
    _FieldDef("price", "বিক্রয় মূল্য (টাকা)",
        keys: ["sold_price", "sale_price", "selling_price"], type: TextInputType.number),
    _FieldDef("paid", "জমা/অগ্রিম পেয়েছেন (টাকা)",
        keys: ["paid_amount"], type: TextInputType.number),
    _FieldDef("pay_ref", "Payment Reference"),
    _FieldDef("invoice_desc", "ইনভয়েসের বিবরণ",
        initial: "3-WHEELER 4-STROKE AUTORICKSHAW IN CBU CONDITION (LPG)"),
    _FieldDef("challan_desc", "চালানের বিবরণ",
        initial: "BAJAJ 3/W 4S RE CNG/ DIESEL Maxmia auto Rickshaw Comp"),
    _FieldDef("acc1", "Spare wheel", initial: "01pc"),
    _FieldDef("acc2", "O.M. Book", initial: "01 pc"),
    _FieldDef("acc3", "Floor Mat", initial: "01 set"),
    _FieldDef("acc4", "Tool Kit", initial: "01pc"),
    _FieldDef("gate_no", "গেট পাস নম্বর (NO. এর পরে)", initial: "RAL/SB/3W/2026"),
  ],
    "প্রত্যয়ন, চালান ও ইনভয়েসের তথ্য": [
    _FieldDef("brand", "BRAND", initial: "BAJAJ"),
    _FieldDef("model_short", "MODEL", initial: "RE-COMPACT CNG"),
    _FieldDef("inv_model", "ইনভয়েসের বিবরণে মডেল", initial: "RE-COMPACT LPG"),
    _FieldDef("body_cls", "CLASS OF BODY", initial: "AUTO RICKSHAW"),
    _FieldDef("cyl_cert", "NUMBER OF CYLINDER", initial: "1 (ONE)"),
    _FieldDef("cc_cert", "CUBIC CAPACITY", initial: "198.88 CC"),
    _FieldDef("hp_cert", "HORSE POWER", initial: "6.55 KW HP 5000RPM"),
    _FieldDef("fuel_cert", "FUEL USED", initial: "Compact CNG/Petrol"),
    _FieldDef("unladen_cert", "UNLADEN WEIGHT", initial: "398 KGS"),
    _FieldDef("tyres_cert", "NUMBER OF TYRES", initial: "THREE WHEELER"),
    _FieldDef("tyre_sz_cert", "SIZE OF TYRES", initial: "FRONT & REAR 4.00*8*4PR"),
    _FieldDef("seats_cert", "SEATS (INCL. DRIVER)", initial: "4 (FOUR) PERSONS"),
  ],
  "কাগজের হেডার ও স্বাক্ষর": [
    _FieldDef("hdr_on", "হেডার ছাপবেন? (হ্যাঁ / না) — প্যাডে আগে থেকে ছাপা থাকলে 'না'", initial: "হ্যাঁ"),
    _FieldDef("hdr_logo", "লোগোর লেখা (ফাঁকা = লোগো নেই)", initial: "SB"),
    _FieldDef("hdr_bn", "প্রতিষ্ঠানের নাম (বাংলা)", initial: "ইমাম মোটর্স"),
    _FieldDef("hdr_en", "প্রতিষ্ঠানের নাম (ইংরেজি)", initial: "IMAM MOTORS"),
    _FieldDef("hdr_addr", "ঠিকানা", initial: "1917, Nurjahan Mansion, Arakan Road, Panchlaish, Chattogram."),
    _FieldDef("hdr_mob", "মোবাইল", initial: "Mobile : 01735-083366, 01754-293849"),
    _FieldDef("hdr_brand", "ডান পাশের ব্র্যান্ড", initial: "RUNNER"),
    _FieldDef("sign_for", "স্বাক্ষরের নিচে (For ...)", initial: "SB CORPORATION"),
  ],
};

// ---------------------------------------------------------------
// ফন্ট ও লেখার ধরন (এক্সেলের মতো: ইংরেজি কাগজে Times, চালানে Verdana, মালিকের পাতায় Calibri)
// ---------------------------------------------------------------
const Color _ink = Colors.black;

enum _F { serif, sans, cal, bn }

TextStyle _st(
  double size, {
  bool b = true,
  bool u = false,
  bool i = false,
  _F f = _F.serif,
  double? h,
}) {
  String? fam;
  List<String>? fb;
  switch (f) {
    case _F.serif:
      fam = 'Times New Roman';
      fb = const ['Liberation Serif', 'Noto Serif', 'serif'];
      break;
    case _F.sans:
      fam = 'Verdana';
      fb = const ['DejaVu Sans', 'Segoe UI', 'sans-serif'];
      break;
    case _F.cal:
      fam = 'Calibri';
      fb = const ['Carlito', 'Segoe UI', 'sans-serif'];
      break;
    case _F.bn:
      fam = null;
      fb = null;
      break;
  }
  return TextStyle(
    fontSize: size,
    fontFamily: fam,
    fontFamilyFallback: fb,
    color: _ink,
    height: h,
    fontWeight: b ? FontWeight.w700 : FontWeight.w400,
    fontStyle: i ? FontStyle.italic : FontStyle.normal,
    decoration: u ? TextDecoration.underline : TextDecoration.none,
  );
}

/// একই সাথে পর্দার লেখা তৈরি করে আর "কপি"-র জন্য সাদা লেখাও জমায়
class _Pg {
  final StringBuffer buf = StringBuffer();

  Text t(
    String s, {
    double size = 14,
    bool b = true,
    bool u = false,
    bool i = false,
    _F f = _F.serif,
    TextAlign? align,
    double? h,
  }) {
    buf.write('$s  ');
    return Text(s, textAlign: align, style: _st(size, b: b, u: u, i: i, f: f, h: h));
  }

  Text l(
    String s, {
    double size = 14,
    bool b = true,
    bool u = false,
    bool i = false,
    _F f = _F.serif,
    TextAlign? align,
    double? h,
  }) {
    final w = t(s, size: size, b: b, u: u, i: i, f: f, align: align, h: h);
    buf.writeln();
    return w;
  }

  Widget r(
    String label,
    String value, {
    double size = 13.5,
    bool lb = false,
    bool vb = true,
    double? vsize,
    _F f = _F.serif,
  }) {
    buf.write('$label$value  ');
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label, style: _st(size, b: lb, f: f)),
          TextSpan(text: value, style: _st(vsize ?? size, b: vb, f: f)),
        ],
      ),
    );
  }

  Widget row(
    List<Widget> c, {
    double? height,
    CrossAxisAlignment cross = CrossAxisAlignment.center,
    MainAxisAlignment main = MainAxisAlignment.start,
  }) {
    buf.writeln();
    final w = Row(mainAxisAlignment: main, crossAxisAlignment: cross, children: c);
    return height == null ? w : SizedBox(height: height, child: w);
  }
}

/// ছবির মাপ (px) ধরে কাগজে ঠিক জায়গায় লেখা বসানোর সহায়ক। ফর্মের ছবির সাথে হুবহু মেলাতে।
class _Abs {
  final _Pg p;
  final double sx;
  final double sy;
  final double pageW;
  final double pageH;
  final List<Widget> kids = [];

  _Abs(this.p, double imgW, double imgH, {this.pageW = _pw, this.pageH = _ph})
      : sx = pageW / imgW,
        sy = pageH / imgH;

  double _top(double y, double size) => y * sy - size * 0.62;

  void t(String s, double x, double y,
      {double size = 14, bool b = false, bool u = false, _F f = _F.serif}) {
    p.buf.writeln(s);
    kids.add(Positioned(
      left: x * sx,
      top: _top(y, size),
      child: Text(s, style: _st(size, b: b, u: u, f: f)),
    ));
  }

  /// ডান প্রান্ত ধরে বসানো (নম্বরের জন্য)
  void rt(String s, double rightX, double y,
      {double size = 14, bool b = false, _F f = _F.serif}) {
    p.buf.write('$s ');
    kids.add(Positioned(
      right: pageW - rightX * sx,
      top: _top(y, size),
      child: Text(s, style: _st(size, b: b, f: f)),
    ));
  }

  void c(String s, double y, {double size = 14, bool b = false, bool u = false, _F f = _F.serif}) {
    p.buf.writeln(s);
    kids.add(Positioned(
      left: 0,
      right: 0,
      top: _top(y, size),
      child: Center(child: Text(s, style: _st(size, b: b, u: u, f: f))),
    ));
  }

  /// লেবেল + মান (মান আলাদা ধরনে)
  void r(String label, String value, double x, double y,
      {double size = 14,
      bool lb = false,
      bool vb = true,
      double? vsize,
      _F f = _F.serif,
      _F? vf}) {
    p.buf.writeln('$label$value');
    kids.add(Positioned(
      left: x * sx,
      top: _top(y, size),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: label, style: _st(size, b: lb, f: f)),
        TextSpan(text: value, style: _st(vsize ?? size, b: vb, f: vf ?? f)),
      ])),
    ));
  }

  void rich(String plain, List<InlineSpan> spans, double x, double y, {double size = 14}) {
    p.buf.writeln(plain);
    kids.add(Positioned(
      left: x * sx,
      top: _top(y, size),
      child: Text.rich(TextSpan(children: spans)),
    ));
  }

  /// অনুচ্ছেদ (দুই পাশ সমান)
  void para(String plain, double x1, double x2, double y,
      {double size = 14, List<InlineSpan>? spans, double h = 1.34}) {
    p.buf.writeln(plain);
    final st = _st(size, b: false, h: h);
    kids.add(Positioned(
      left: x1 * sx,
      width: (x2 - x1) * sx,
      top: y * sy - size * 0.62 - (h - 1.2) * size / 2,
      child: Text.rich(
        TextSpan(text: spans == null ? plain : null, style: st, children: spans),
        textAlign: TextAlign.justify,
      ),
    ));
  }

  void box(double x1, double y1, double x2, double y2,
      {double w = 1.6, bool open = false}) {
    kids.add(Positioned(
      left: x1 * sx,
      top: y1 * sy,
      width: (x2 - x1) * sx,
      height: (y2 - y1) * sy,
      child: Container(
        decoration: BoxDecoration(
          border: open
              ? Border(
                  top: BorderSide(color: _ink, width: w),
                  left: BorderSide(color: _ink, width: w),
                  right: BorderSide(color: _ink, width: w),
                )
              : Border.all(color: _ink, width: w),
        ),
      ),
    ));
  }

  Widget build() => SizedBox(
        width: pageW,
        height: pageH,
        child: Stack(clipBehavior: Clip.hardEdge, children: kids),
      );
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.8;
    double x = 0;
    while (x < s.width) {
      canvas.drawLine(Offset(x, 0), Offset((x + 9).clamp(0, s.width), 0), paint);
      x += 14;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PD {
  final Widget w;
  final String text;
  final bool landscape;
  const _PD(this.w, this.text, this.landscape);
}

const double _pw = 794; // A4 পোর্ট্রেট (96 dpi)
const double _ph = 1123;

_PD _page(_Pg p, Widget child, {bool landscape = false}) {
  return _PD(
    SizedBox(
      width: landscape ? _ph : _pw,
      height: landscape ? _pw : _ph,
      child: ColoredBox(
        color: Colors.white,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [Positioned(left: 0, top: 0, right: 0, child: child)],
        ),
      ),
    ),
    p.buf.toString().trim(),
    landscape,
  );
}

class _HexPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(0, s.height / 2)
      ..lineTo(s.width * 0.195, 0)
      ..lineTo(s.width * 0.805, 0)
      ..lineTo(s.width, s.height / 2)
      ..lineTo(s.width * 0.805, s.height)
      ..lineTo(s.width * 0.195, s.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------
// সংখ্যা: লাখ-কোটি কমা, ইংরেজি কথায়, বাংলা অঙ্ক
// ---------------------------------------------------------------
String _inr(int n, {bool decimals = false}) {
  final digits = n.abs().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = "${parts.join(',')},$last3";
  }
  return "${n < 0 ? '-' : ''}$grouped${decimals ? '.00' : ''}";
}

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

const List<String> _ones = [
  "", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN",
  "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN",
  "EIGHTEEN", "NINETEEN",
];
const List<String> _tens = [
  "", "", "TWENTY", "THIRTY", "FORTY", "FIFTY", "SIXTY", "SEVENTY", "EIGHTY", "NINETY",
];

String _two(int x) {
  if (x < 20) return _ones[x];
  final o = x % 10;
  return _tens[x ~/ 10] + (o > 0 ? " ${_ones[o]}" : "");
}

String _three(int x) {
  final parts = <String>[];
  if (x >= 100) {
    parts.add("${_ones[x ~/ 100]} HUNDRED");
    x = x % 100;
  }
  if (x > 0) parts.add(_two(x));
  return parts.join(" ");
}

String _words(int n) {
  if (n <= 0) return "ZERO ONLY.";
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lac = n ~/ 100000;
  n %= 100000;
  final th = n ~/ 1000;
  n %= 1000;
  if (crore > 0) parts.add("${_three(crore)} CRORE");
  if (lac > 0) parts.add("${_two(lac)} LAC");
  if (th > 0) parts.add("${_two(th)} THOUSAND");
  if (n > 0) parts.add(_three(n));
  return "${parts.join(' ')} ONLY.";
}

class _Shot {
  final Uint8List png;
  final int w;
  final int h;
  final String label;
  const _Shot(this.png, this.w, this.h, [this.label = '']);
}

class BrtaPapersScreen extends StatefulWidget {
  /// বিক্রীত গাড়ির তথ্য (সার্ভার থেকে যা এসেছে)। না থাকলে ঘরগুলো হাতে ভরা যাবে।
  final Map<String, dynamic> unit;

  const BrtaPapersScreen({super.key, this.unit = const {}});

  @override
  State<BrtaPapersScreen> createState() => _BrtaPapersScreenState();
}

class _BrtaPapersScreenState extends State<BrtaPapersScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, TextEditingController> _c = {};
  late final TabController _tab;
  final List<GlobalKey> _keys = List.generate(9, (_) => GlobalKey());
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 10, vsync: this);
    final now = DateTime.now();
    final today =
        "${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}";
    for (final defs in _groups.values) {
      for (final d in defs) {
        var text = _pick(d.keys) ?? d.initial;
        if (d.id == "date") text = today;
        _c[d.id] = TextEditingController(text: text);
      }
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _pick(List<String> keys) {
    for (final k in keys) {
      final v = widget.unit[k];
      if (v != null && "$v".trim().isNotEmpty && "$v" != "null") return "$v";
    }
    return null;
  }

  String _g(String id) => _c[id]!.text.trim();
  String _v(String id) => _g(id).isEmpty ? _dots : _g(id);

  int? _int(String id) {
    final n = num.tryParse(_g(id).replaceAll(',', ''));
    return n?.toInt();
  }

  String get _serial => _g("ref_serial").isEmpty ? '………' : _g("ref_serial");
  String get _prefix => _g("ref_prefix").isEmpty ? '' : '${_g("ref_prefix")}/ ';

  // =============================================================
  // ১. বিক্রয় প্রত্যয়ন
  // =============================================================
  _PD _certificate() {
    final p = _Pg();
    final price = _int("price");
    final fy = _g("ref_fy");
    final ref = "Ref:    $_prefix$_serial     ${fy.isEmpty ? '' : '/$fy'}";

    Widget n(String no, String label, String value, {bool big = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          child: p.row(
            [
              SizedBox(width: 38, child: p.t(no, size: 15)),
              SizedBox(width: 290, child: p.t(label, size: 15)),
              SizedBox(width: 24, child: p.t(':', size: 15)),
              Expanded(child: p.t(value, size: big ? 18 : 15)),
            ],
            cross: CrossAxisAlignment.start,
          ),
        );

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(64, 190, 64, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          p.row([
            Expanded(child: p.t(ref, size: 14)),
            p.t("Date: ${_v("date")}", size: 13),
          ]),
          const SizedBox(height: 10),
          p.l("To: The Registration Authority", size: 14),
          const SizedBox(height: 6),
          p.l("Motor Vehicle Department", size: 12.5),
          p.l("${_v("city_en")}.", size: 14),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 100),
            child: p.l("TO WHOM IT MAY CONCERN", size: 19, u: true),
          ),
          const SizedBox(height: 6),
          p.l("This is to certify that we have sold a new vehicle to:", size: 14),
          const SizedBox(height: 4),
          p.row([
            const SizedBox(width: 100),
            SizedBox(width: 300, child: p.t(_v("c_name"), size: 15)),
            SizedBox(width: 60, child: p.t("S/O:", size: 15)),
            Expanded(child: p.t(_v("c_father"), size: 14)),
          ]),
          const SizedBox(height: 4),
          p.row([
            SizedBox(width: 56, child: p.t("C/O:", size: 14, f: _F.sans)),
            Expanded(child: p.t(_v("c_address"), size: 15)),
          ]),
          const SizedBox(height: 2),
          n("1.", "Model/Make of vehicle", _v("model_desc")),
          n("2.", "Class of Vehicle", _v("vclass")),
          n("3.", "Chassis No", _v("chassis"), big: true),
          n("4.", "Engine No", _v("engine"), big: true),
          n("5.", "Key No", _g("key_no")),
          n("6.", "Number of Cylinder with CC", _v("cyl_cc")),
          n("7.", "Colour of Vehicle", _v("color")),
          n("8.", "Size of  Tyre", _v("tyre_size")),
          n("9.", "Year of Manufacture/Assemble", _v("year")),
          n("10.", "Horse Power", _v("hp")),
          n("11.", "Laden Weight", _v("laden")),
          n("12.", "Wheel Base", _v("wheelbase")),
          n("13.", "Seating Capacity", _v("seating")),
          n("14.", "Marker’s Name", _v("maker")),
          n("15.", "Price", price == null ? _dots : "Tk     ${_inr(price, decimals: true)}"),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 330),
            child: p.l("FOR ${_v("shop_name")}", size: 14, f: _F.sans),
          ),
          const SizedBox(height: 44),
          p.row([
            const SizedBox(width: 70),
            SizedBox(width: 300, child: p.t("Owner’s Signature", size: 13)),
            p.t("Sales Department", size: 13, f: _F.sans),
          ]),
        ],
      ),
    );
    return _page(p, w);
  }

  // =============================================================
  // ২. সেলস ইনভয়েস (আড়াআড়ি পাতা)
  // =============================================================
  _PD _invoice() {
    final p = _Pg();
    final price = _int("price");
    final paid = _int("paid") ?? 0;
    final amount = price == null ? _dots : _inr(price, decimals: true);
    final adv = paid == 0 ? '-' : _inr(paid, decimals: true);
    final bal = price == null
        ? _dots
        : (price - paid == 0 ? '-' : _inr(price - paid, decimals: true));
    const cw = [67, 209, 150, 60, 94, 130, 124, 112];
    final border = BoxDecoration(border: Border.all(color: _ink, width: 1.4));

    Widget bc(String s, int i, double h, {double size = 13}) => Expanded(
          flex: cw[i],
          child: Container(
            height: h,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: border,
            child: p.t(s, size: size, align: TextAlign.center),
          ),
        );

    Widget tot(String a, String b) => Expanded(
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _ink, width: 1.4)),
            ),
            child: Row(
              children: [
                Expanded(flex: 124, child: Center(child: p.t(a, size: 11.5))),
                Container(width: 1.4, color: _ink),
                Expanded(flex: 112, child: Center(child: p.t(b, size: 11.5))),
              ],
            ),
          ),
        );

    Widget dash(String s) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: p.l(s, size: 13),
        );

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(60, 196, 60, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: p.l("SALES  INVOICE", size: 22, u: true)),
          const SizedBox(height: 8),
          p.row([
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 60),
              child: p.t("Date:  ${_v("date")}", size: 12.5),
            ),
          ]),
          const SizedBox(height: 14),
          p.row([
            SizedBox(width: 72, child: p.t("BUYER", size: 13.5)),
            SizedBox(width: 215, child: p.t(_v("c_name"), size: 13)),
            SizedBox(width: 150, child: p.t("S/O:", size: 14)),
            SizedBox(width: 160, child: p.t(_v("c_father"), size: 13)),
            Expanded(child: p.t("C/O:   ${_v("c_address")}", size: 14)),
          ]),
          const SizedBox(height: 4),
          p.row([
            SizedBox(width: 140, child: p.t("Invoice No:", size: 13)),
            SizedBox(width: 300, child: p.t("B/E No :", size: 13)),
            const Spacer(),
            p.t("Sales Invoice No:   $_prefix$_serial", size: 13, i: true, f: _F.sans),
            const SizedBox(width: 40),
          ]),
          const SizedBox(height: 2),
          p.row([
            bc("Sl No:", 0, 38),
            bc("Chassis No.", 1, 38),
            bc("Engine No.", 2, 38),
            bc("Key No", 3, 38),
            bc("Colour", 4, 38),
            bc("Description", 5, 38),
            bc("Unit Price", 6, 38),
            bc("Amount", 7, 38),
          ]),
          p.row([
            bc("1", 0, 104),
            bc(_g("chassis"), 1, 104, size: 17),
            bc(_g("engine"), 2, 104, size: 17),
            bc(_g("key_no"), 3, 104),
            bc(_g("color").toUpperCase(), 4, 104),
            bc(_g("invoice_desc"), 5, 104, size: 11),
            bc(amount, 6, 104),
            bc(amount, 7, 104),
          ]),
          p.row([
            Expanded(
              flex: 710,
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: border,
                child: p.t(price == null ? _dots : _words(price), size: 18),
              ),
            ),
            Expanded(
              flex: 236,
              child: Container(
                height: 58,
                decoration: border,
                child: Column(
                  children: [
                    tot("Total Amount", amount),
                    tot("Less Advance", adv),
                    tot("Balance", bal),
                  ],
                ),
              ),
            ),
          ]),
          Container(
            height: 150,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: _ink, width: 1.4),
                right: BorderSide(color: _ink, width: 1.4),
                bottom: BorderSide(color: _ink, width: 1.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 640,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: _ink, width: 1.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        p.l("Payment Reference: ${_g("pay_ref")}", size: 13),
                        dash("M.R. No-------------------------------------Dated-----------------------------------"),
                        dash("For Tk------------------------------( Taka-----------------------Only)-----------"),
                        dash("In Cash/ by----------------------------------------------------------------------"),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 366,
                  child: Column(
                    children: [
                      const SizedBox(height: 22),
                      Center(child: p.l("For ${_v("shop_name")}", size: 17)),
                      const Spacer(),
                      Center(child: p.l("SALES DEPARTMENT", size: 13)),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return _page(p, w, landscape: true);
  }

  // =============================================================
  // ৩. অঙ্গীকারনামা
  // =============================================================
  _PD _undertaking() {
    final p = _Pg();
    Widget bn(String s, {bool b = false, double size = 16}) =>
        p.l(s, size: size, b: b, f: _F.bn, h: 1.7);

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(64, 70, 64, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bn("বরাবর,"),
          bn("রেজিস্ট্রেশন কর্তৃপক্ষ,"),
          bn("বি. আর. টি. এ. ${_v("circle_bn")},"),
          bn("${_v("city_bn")}।"),
          const SizedBox(height: 14),
          bn(
            "বিষয়: --------------- নং গাড়ীর রেজিস্ট্রেশন/ অন্তর্ভুক্তি/ মালিকানা বদলী এ অঙ্গীকার নামা প্রসঙ্গে।",
            b: true,
          ),
          const SizedBox(height: 14),
          p.row([
            Expanded(flex: 3, child: p.t(_v("c_name"), size: 15)),
            Expanded(flex: 3, child: p.t("S/O: ${_v("c_father")}", size: 14)),
          ]),
          const SizedBox(height: 4),
          p.l("C/O: ${_v("c_address")}", size: 14),
          const SizedBox(height: 10),
          p.l(
            "এই মর্মে অঙ্গীকার করিতেছি যে, আমার গাড়ীটির চেসিস নং ${_v("chassis")}, "
            "ইঞ্জিন নং ${_v("engine")}, প্রস্তুতকারক ${_v("maker_bn")}, বডির ধরন ${_v("body_bn")}। "
            "উক্ত গাড়ীর রেজিস্ট্রেশন ও মালিকানা বদলী সংক্রান্ত যাবতীয় সকল কাগজপত্র সঠিক। "
            "ভবিষ্যতে আমদানী ও ক্রয় বিক্রয় সংক্রান্ত কোন প্রকার জটিলতা সৃষ্টি হইলে আমি সম্পূর্ণ দায়ী থাকিব, "
            "কর্তৃপক্ষ কোন প্রকার দায়ী থাকিবে না এবং এই সংক্রান্ত বাংলাদেশ সরকারের যে কোন আদেশ মানিয়া নিতে "
            "বাধ্য থাকিব। ইহাতে কর্তৃপক্ষ আমার রেজিস্ট্রেশন বাতিল করিয়া দিলেও কোন প্রকার আপত্তি থাকিবে না। "
            "আমি আরও অঙ্গীকার করিতেছি যে, উক্ত গাড়ীর বিরুদ্ধে কোন ফৌজদারী ও দেওয়ানী মামলা নাই।",
            size: 16,
            b: false,
            f: _F.bn,
            h: 1.9,
            align: TextAlign.justify,
          ),
          const SizedBox(height: 60),
          Padding(
            padding: const EdgeInsets.only(left: 380),
            child: bn("বিনীত", b: true),
          ),
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.only(left: 330),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                p.l("NAME :  ${_v("c_name")}", size: 14),
                p.l("S/O:  ${_v("c_father")}", size: 14),
                p.l("C/O:  ${_v("c_address")}", size: 13),
              ],
            ),
          ),
        ],
      ),
    );
    return _page(p, w);
  }

  // =============================================================
  // ৪. রেজিস্ট্রেশন আবেদন ফর্ম (১ম পাতা) — আসল ফর্মের ছবির মাপে
  // =============================================================
  _PD _application() {
    final p = _Pg();
    final a = _Abs(p, 1200, 1600);
    const z = 14.0;
    a.c("FORM OF APPLICATION FOR THE REGISTRATION OF MOTOR VEHICLE", 75, size: 16.5, b: true);
    a.c("To be filled in by the office :", 104, size: 13.5);
    a.c("Section-I", 140, size: 14.5, b: true);
    a.t("Regn No. :", 185, 168, size: z);
    a.t("Date :", 503, 168, size: z);
    a.t("Prev. Regn. No. (if any)", 677, 165, size: 13);
    a.t("Issue No. :", 185, 194, size: z);
    a.t("Date :", 503, 194, size: z);
    a.t("Issued by :", 677, 191, size: z);
    a.t("Dairy No. :", 185, 221, size: z);
    a.t("Date :", 503, 221, size: z);
    a.t("Received by :", 677, 217, size: z);
    a.t("Customer ID :", 183, 248, size: z);
    a.t("District :", 503, 247, size: z);
    a.t("Vehicle ID :", 677, 244, size: z);
    a.t("Veh. Description :", 180, 275, size: z);
    a.t("Call on date :", 677, 270, size: z);
    a.t("Refusal Date :", 180, 302, size: z);
    a.t("Refusal Code :", 503, 300, size: z);
    a.t("Refused by :", 677, 297, size: z);
    a.t("P.O./Bank :", 180, 329, size: z);
    a.t("Index No. :", 677, 324, size: z);
    a.t("Remarks (if any)", 177, 357, size: z);

    a.c("To be filled in by the Owner", 386, size: 13.5);
    a.c("Section-II", 416, size: 14.5, b: true);
    a.c("(Owner Information)", 441, size: 12);

    // মালিকের তথ্য
    a.rt("1.", 190, 474, size: z);
    a.r("Name of Owner: ", _g("c_name"), 217, 474, size: z);
    a.rt("2.", 696, 468, size: z);
    a.r("Date of Birth : ", _g("c_dob"), 726, 468, size: z);
    a.rt("3.", 190, 498, size: z);
    a.r("Father/Husband: ", _g("c_father"), 216, 498, size: z);
    a.rt("4.", 696, 493, size: z);
    a.r("Nationality : ", "Bangladeshi", 726, 493, size: z);
    a.rt("5.", 190, 525, size: z);
    a.r("Sex : ", _g("c_sex").toLowerCase(), 216, 525, size: z, vb: false);
    a.rt("6.", 696, 518, size: z);
    a.r("Guardian’s name : ", _g("c_guardian"), 726, 518, size: 13);
    a.rt("7.", 190, 551, size: z);
    a.r("Address: ", _g("c_address"), 214, 551, size: z);
    a.rt("8.", 190, 583, size: z);
    a.r("Phone No. (if any) : ", _g("c_phone"), 212, 583, size: 13, vb: false);
    a.rt("9.", 696, 575, size: z);
    a.r("P.O /Bank : ", _g("c_bank"), 727, 575, size: z);
    a.rt("10.", 190, 612, size: z);
    a.t("Joint Owner :", 210, 612, size: 13);
    a.rt("11.", 696, 604, size: z);
    a.t("Owner type :", 728, 604, size: z);
    a.rt("12.", 190, 641, size: z);
    a.t("Hire :", 210, 641, size: z);
    a.rt("13.", 696, 633, size: z);
    a.t("Hire purchases :", 728, 633, size: 13);

    a.c("Section-III", 673, size: 14.5, b: true);
    a.c("(Vehicle Information)", 701, size: 12);

    // গাড়ির তথ্য — বাম
    a.rt("14.", 190, 736, size: z);
    a.r("Vehicle or trailer : ", "Vehicle", 213, 736, size: z);
    a.rt("14a.", 190, 763, size: z);
    a.r("Class of vehicle : ", _g("vclass").isEmpty ? "" : _titleCase(_g("vclass")), 211, 763, size: z);
    a.rt("16.", 190, 789, size: z);
    a.r("Type of body : ", _g("body_en"), 211, 789, size: z);
    a.rt("18.", 190, 814, size: z);
    a.r("Colour (cabin/body) : ", _g("color"), 209, 814, size: z);
    a.rt("20.", 190, 843, size: z);
    a.r("Number of cylinders : ", _g("n_cyl"), 208, 843, size: z);
    a.rt("22.", 190, 875, size: z);
    a.r("Engine number : ", _g("engine"), 206, 875, size: 13);
    a.rt("24.", 190, 903, size: z);
    a.r("Horse power :", _g("hp_app"), 205, 903, size: z);
    a.rt("26.", 190, 931, size: z);
    a.t("Cubic capacity :", 204, 931, size: z);
    a.rt("28.", 190, 959, size: z);
    a.t("No. of Standee :", 203, 959, size: z);
    a.rt("30.", 190, 986, size: z);
    a.r("Unladen weight (kgs) : ", _g("unladen"), 202, 986, size: z);

    // গাড়ির তথ্য — ডান
    a.rt("15.", 690, 726, size: z);
    a.r("Prev. Regn. No. (if any) :", _g("c_prevreg").isEmpty ? "New" : _g("c_prevreg"), 711, 726, size: 13);
    a.rt("15a.", 690, 751, size: z);
    a.r("Makers. name: ", _g("maker_short"), 711, 751, size: z);
    a.rt("17.", 690, 779, size: z);
    a.r("Maker’s country : ", _g("maker_country"), 711, 779, size: z);
    a.rt("19.", 690, 806, size: z);
    a.r("Year of manufacture :", _g("year"), 711, 806, size: 13, vb: false);
    a.rt("21.", 690, 832, size: z);
    a.r("Chassis number : ", _g("chassis"), 711, 832, size: z);
    a.rt("23.", 690, 865, size: z);
    a.r("Fuel used:", _g("fuel"), 711, 865, size: z, vb: false);
    a.rt("25.", 690, 893, size: z);
    a.r("RPM : ", _g("rpm"), 711, 893, size: z);
    a.rt("27.", 690, 921, size: z);
    a.r("Seats (incl. driver) : ", _g("seating"), 711, 921, size: z);
    a.rt("29.", 690, 948, size: z);
    a.r("Wheel base : ", _g("wheelbase"), 711, 948, size: z);
    a.rt("31.", 690, 973, size: z);
    a.r("Maximum laden / train weight (kgs) : ", _g("train_wt"), 715, 973, size: z);

    a.c("Section-IV", 1022, size: 14.5, b: true);
    a.c("(Additional information for transport vehicle)", 1048, size: 12.5);
    a.rt("32.", 172, 1091, size: z);
    a.r("No. of tyres : ", _g("n_tyres"), 187, 1091, size: z);
    a.rt("34.", 172, 1122, size: z);
    a.r("No. of axle:", _g("n_axle"), 185, 1122, size: z);
    a.rt("33.", 590, 1083, size: z);
    a.r("Tyres Size : ", _g("tyre_short"), 617, 1083, size: z);
    a.rt("35.", 590, 1113, size: z);
    a.t("Maximum axle weight (kgs) :", 617, 1113, size: z);
    a.t("a.", 623, 1146, size: 12.5);
    a.t("Front axle(1)(2)", 664, 1146, size: 12.5);
    a.t("b.", 623, 1177, size: 12.5);
    a.t("Central axle(1)(2)  (3)", 664, 1177, size: 12.5);
    a.t("c.", 623, 1206, size: 12.5);
    a.t("Rear axle(1)(2)", 664, 1206, size: 12.5);
    a.t("(3)", 882, 1204, size: 12.5);

    a.t("36.   Dimension (mm) :", 130, 1246, size: z);
    a.t("a) Overall Length", 127, 1280, size: z);
    a.t("b) Overall width", 417, 1275, size: z);
    a.t("c) Overall Height", 679, 1272, size: z);
    a.t("38.   A Copy of the drawing showing the vehicle dimension, specification  of the body and of the seating", 126, 1313, size: 13.5);
    a.t("arrangements approved by ........................................ on .......................................... is attached herewith.", 123, 1370, size: 13.5);

    a.t("39.   Hire purchase/hypothecation information :", 120, 1437, size: z);
    a.t("The vehicle is subject to hire purchase/hypothecation with :", 120, 1472, size: z);
    a.t("a)  Name :", 168, 1512, size: z);
    a.t("b) Date :", 870, 1503, size: z);
    return _page(p, a.build());
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  // =============================================================
  // ৫. আবেদন ফর্ম (২য় পাতা: Section V ও VI)
  // =============================================================
  _PD _application2() {
    final p = _Pg();
    final a = _Abs(p, 1132, 1600);
    const z = 14.5;
    a.c("Section V", 54, size: 15, b: true);
    a.rt("39.", 106, 92, size: z);
    a.t("Hire purchase/hypothecation information:", 131, 88, size: z);
    a.t("The vehicle is subject to hire purchase/hypothecation with:", 126, 108, size: z);
    a.t("a) Name:", 126, 145, size: z);
    a.t("b) Date:", 752, 127, size: z);
    a.t("Address:", 126, 171, size: z);
    a.t("40.Insurance information:", 79, 196, size: z);
    a.t("a) Policy no:", 126, 223, size: z);
    a.t("b) Type of Policy", 477, 214, size: z);
    a.t("c) Insurer's name & address:", 755, 206, size: z);
    a.t("d) Date of expiry:", 126, 249, size: z);
    a.t("41.  Joint owner information:", 79, 276, size: z);
    a.t("a) Name:", 126, 302, size: z);
    a.t("b) Name", 479, 298, size: z);
    a.t("Father/ Husband:", 126, 328, size: z);
    a.t("Father/ Husband:", 479, 323, size: z);

    a.c("Section VI", 371, size: 15, b: true);
    a.c("(Declaration. Certificates and Documents)", 397, size: 14.5, b: true);

    a.t("42.Declaration by owner:", 79, 444, size: z);
    a.para(
      "(a) In the undersigned do hereby declare that to the best of my knowledge and belief, the information "
      "given and the documents enclosed (as per list attached) are true. I also declare that in case the papers/ "
      "documents and information furnished are found to be incorrect at any later stage, I shall be liable for "
      "legal action.",
      126, 1080, 468,
      size: z,
    );
    a.rt("Signature of owner", 1020, 578, size: z, b: true);
    a.t("Date:", 56, 615, size: z);
    a.t("Encl:  List of documents", 56, 641, size: z);

    a.t("43.  Registered dealer's certificate", 79, 667, size: z);
    a.para(
      "I the undersigned do hereby certify that the vehicle in question has been sold by me/ my firm and the "
      "ownership documents attached with the application for registration are true. The information/ "
      "specifications pertaining to the vehicle are correct and the vehicle complies with all the requirements "
      "of the registration.",
      130, 1080, 692,
      size: z,
    );
    a.t("Date:", 57, 832, size: z);
    a.rt("Signature of registered dealer", 1080, 843, size: z, b: true);
    a.t("Seal", 905, 870, size: z, b: true);
    a.t("Encl:  List of documents", 58, 910, size: z);

    a.t("44.Certificate by the Inspector of Motor Vehicles:", 77, 943, size: z);
    final cert = "Certified that the particulars pertaining to the owner and the vehicle "
        "(Chassis No. ${_v("chassis")} Engine No ${_v("engine")}) Given in the application match with the "
        "ownership documents attached to this application. It is further certified that the vehicle complies "
        "with the registration requirements specified in the MV Act and the Rules and / or Regulations made "
        "thereunder and the vehicle is not mechanically defective. The necessary documents/ papers are "
        "available as per list enclosed.";
    a.para(
      cert,
      131, 1082, 980,
      size: z,
      spans: [
        TextSpan(text: "Certified that the particulars pertaining to the owner and the vehicle "),
        TextSpan(
          text: "(Chassis No. ${_v("chassis")} Engine No ${_v("engine")}) ",
          style: _st(12, b: true, f: _F.sans),
        ),
        const TextSpan(
          text: "Given in the application match with the ownership documents attached to this application. "
              "It is further certified that the vehicle complies with the registration requirements specified "
              "in the MV Act and the Rules and / or Regulations made thereunder and the vehicle is not "
              "mechanically defective. The necessary documents/ papers are available as per list enclosed.",
        ),
      ],
    );
    a.t("Date", 58, 1159, size: z);
    a.rt("Signature of Inspector of Motor Vehicles", 1080, 1132, size: z, b: true);
    a.t("Official Seal", 843, 1160, size: z, b: true);

    a.t("45.Registration Status:", 77, 1237, size: z);
    a.t("Registration allowed/ not allowed", 133, 1262, size: z);
    a.rt("Signature of Registering Authority", 1088, 1240, size: z, b: true);
    a.t("Seal", 915, 1266, size: z, b: true);

    a.t("46.Fees and Tax Accounts:", 77, 1314, size: z);
    a.t("has been", 1003, 1311, size: z);
    a.t("Necessary fees and taxes amounting to taka ....................  ...................................", 133, 1337, size: z);
    a.t("paid to Po/Bank ..........................................................  vide vouchers and receipts enclosed.", 133, 1366, size: z);
    a.rt("Signature of dealing assistant", 1090, 1390, size: z, b: true);
    a.t("Signature of owner", 135, 1418, size: z);
    a.t("or his representative", 135, 1443, size: z);
    a.t("Counter signature by the registering authority", 407, 1462, size: z);
    return _page(p, a.build());
  }

  // =============================================================
  // ৫. ডিলারের ঘোষণাপত্র
  // =============================================================
  _PD _declaration() {
    final p = _Pg();
    final price = _int("price");
    final priceBn = price == null ? _dots : "${_bn(_inr(price))}/-";
    Widget bn(String s) => p.l(s, size: 16, b: false, f: _F.bn, h: 1.7);
    Widget sg(String s) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                Container(height: 1.2, color: _ink),
                const SizedBox(height: 4),
                p.l(s, size: 14, b: false, f: _F.bn, align: TextAlign.center),
              ],
            ),
          ),
        );

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(64, 70, 64, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bn("বরাবর"),
          bn("রেজিস্ট্রেশন কর্তৃপক্ষ"),
          bn("বাংলাদেশ রোড ট্রান্সপোর্ট অথরিটি"),
          bn(_v("circle_bn")),
          bn("${_v("city_bn")}।"),
          const SizedBox(height: 16),
          p.l(
            "আমি নিম্নস্বাক্ষরকারী এই মর্মে অঙ্গীকার পূর্বক ঘোষণা করিতেছি যে, অনুমোদিত ডিলার হিসেবে "
            "আমি থ্রি হুইলার অটোরিক্সার আমদানীকারক প্রতিষ্ঠান ${_v("importer_bn")} হতে "
            "চেসিস নং ${_v("chassis")} ও ইঞ্জিন নং ${_v("engine")} বিশিষ্ট থ্রি হুইলার অটোরিক্সা সরবরাহ নিয়ে "
            "বর্তমানে জনাব ${_v("c_name")}, S/O: ${_v("c_father")}, C/O: ${_v("c_address")} এর নিকট "
            "$priceBn টাকায় বিক্রয় করেছি। আমদানিকারকের নিকট থেকে প্রাপ্ত বিক্রয় রসিদ, ডেলিভারী চালান, "
            "সেলস ইন্টিমেশন ও আমদানি সংক্রান্ত দলিল যথা- বিল অব এন্ট্রি/ইনভয়েস/এলসিএ ইত্যাদি দলিলাদি ও "
            "মূলকপি/সত্যায়িত দাখিলকৃত সকল কাগজপত্রাদি সঠিক রয়েছে মর্মে আমি নিশ্চয়তা প্রদান করছি। "
            "গাড়ি এবং দাখিলকৃত দলিলাদির মধ্যে কোন দলিল/কাগজপত্রাদি ভবিষ্যতে জাল/ভুয়া প্রমাণিত হলে তজ্জন্য "
            "আমি অঙ্গীকারকারী দায়ী থাকবো। বি আর টি এ কর্তৃপক্ষ দায়ী থাকবেনা। এমতাবস্থায় কর্তৃপক্ষ বর্ণিত "
            "মোটরযানের বিপরীতে বরাদ্দকৃত রেজিস্ট্রেশন নম্বরও বাতিল করে আমার বিরুদ্ধে আইনানুগ প্রয়োজনীয় ব্যবস্থা "
            "গ্রহণ করলে আমার কোন আপত্তি থাকবে না। নিম্নে ক্রেতার স্বাক্ষর সত্যায়িত করে প্রেরণ করা হল।",
            size: 16,
            b: false,
            f: _F.bn,
            h: 1.9,
            align: TextAlign.justify,
          ),
          const SizedBox(height: 70),
          Row(children: [sg("ক্রেতার স্বাক্ষর"), sg("বিক্রেতা প্রতিষ্ঠানের স্বাক্ষর/সীল")]),
          const SizedBox(height: 40),
          bn("১।"),
          const SizedBox(height: 24),
          bn("২।"),
        ],
      ),
    );
    return _page(p, w);
  }

  // =============================================================
  // ৬. ডেলিভারি চালান
  // =============================================================
  _PD _challan() {
    final p = _Pg();
    const sz = 14.5;
    Widget kv(String l, String v, {double vs = 14}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: p.row([
            SizedBox(width: 138, child: p.t(l, size: 15.5, f: _F.sans)),
            Expanded(child: p.t(v, size: vs)),
          ]),
        );
    Widget cell(String no, String v) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 26, top: 3, bottom: 3),
            child: p.r("$no  ", v, size: 15, lb: true, vb: true, f: _F.serif),
          ),
        );
    Widget acc(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: p.row(
            [
              SizedBox(
                width: 210,
                child: p.t(l, size: sz, f: _F.sans, align: TextAlign.right),
              ),
              const SizedBox(width: 36),
              SizedBox(width: 120, child: p.t("= $v", size: sz, f: _F.sans)),
            ],
            main: MainAxisAlignment.center,
          ),
        );
    Widget sg(String s) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Container(height: 1.6, color: _ink),
                const SizedBox(height: 4),
                p.l(s, size: 14, f: _F.sans, align: TextAlign.center),
              ],
            ),
          ),
        );

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(48, 188, 48, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 370,
              height: 46,
              child: CustomPaint(
                painter: _HexPainter(),
                child: Center(child: p.l("DELIVERY CHALLAN", size: 17, i: true)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          p.row([
            SizedBox(width: 90, child: p.t("SL NO:", size: 12.5, f: _F.sans)),
            SizedBox(width: 220, child: p.t(_serial, size: 15, f: _F.sans)),
            const Spacer(),
            p.t("DATE:", size: 12.5, f: _F.sans),
            const SizedBox(width: 16),
            p.t(_v("date"), size: 15, f: _F.sans),
          ]),
          kv("NAME:", _v("c_name")),
          kv("FATHER NAME:", _v("c_father")),
          kv("ADDRESS:", _v("c_address")),
          const SizedBox(height: 4),
          kv("MOBILE NO:", _g("c_phone")),
          Container(height: 2, color: _ink),
          const SizedBox(height: 6),
          p.l(
            "Please Receive the undermentioned vehicle/packages and sign for receipt.",
            size: sz,
            f: _F.sans,
            align: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Center(child: p.l("Description of vehicle", size: sz, f: _F.sans)),
          const SizedBox(height: 4),
          p.row(
            [
              SizedBox(
                width: 150,
                child: p.t("…01 ( one )… Unit", size: sz, f: _F.sans, align: TextAlign.center),
              ),
              const SizedBox(width: 12),
              Expanded(child: p.t(_g("challan_desc"), size: sz, f: _F.sans)),
            ],
            cross: CrossAxisAlignment.start,
          ),
          const SizedBox(height: 14),
          p.row([
            Expanded(child: p.t("ENGINE NO:", size: 15, f: _F.sans)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 40),
                child: p.t("CHASSIS NO:", size: 15, f: _F.sans),
              ),
            ),
          ]),
          p.row([cell("1)", _g("engine")), cell("1)", _g("chassis"))]),
          p.row([cell("2)", "………………………………"), cell("2)", "………………………………")]),
          p.row([cell("3)", "………………………………"), cell("3)", "………………………………")]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: p.l("Color: ${_g("color")}", size: 15, f: _F.sans),
          ),
          Center(child: p.l("Along With", size: 15, u: true, f: _F.sans)),
          const SizedBox(height: 4),
          acc("1) Spare wheel", _g("acc1")),
          acc("2) O.M. Book", _g("acc2")),
          acc("3) Floor Mat", _g("acc3")),
          acc("4) Tool Kit", _g("acc4")),
          const SizedBox(height: 6),
          p.l(
            "Checked &Found correct and received the above mentioned",
            size: sz,
            f: _F.sans,
            align: TextAlign.center,
          ),
          p.l(
            "Vehicle/ Packages in good condition and upto my full satisfaction",
            size: sz,
            f: _F.sans,
            align: TextAlign.center,
          ),
          const SizedBox(height: 56),
          Row(children: [
            sg("Officer`s Signature"),
            const SizedBox(width: 56),
            sg("(Customer`s Authorised Signature)"),
          ]),
        ],
      ),
    );
    return _page(p, w);
  }

  // =============================================================
  // ৮. মালিকের তথ্য ও নমুনা স্বাক্ষর — আসল ফর্মের ছবির মাপে
  // =============================================================
  _PD _owner() {
    final p = _Pg();
    final a = _Abs(p, 1124, 1599);
    const z = 16.0;
    a.c("OWNER’S PARTICULARS/SPECIMEN SIGNATURE", 82, size: 17, b: true);
    a.box(908, 122, 1068, 312);
    a.t("Stamp", 955, 192, size: 13, b: true);
    a.t("Size", 968, 216, size: 13, b: true);

    void row(String no, String label, String value, double y,
        {double lx = 128, double vs = 16, bool vb = false, _F vf = _F.serif, bool lb = false}) {
      a.t(no, 82, y, size: z);
      a.r(label, value, lx, y, size: z, lb: lb, vb: vb, vsize: vs, vf: vf);
    }

    row("01.", "NAME: ", _g("c_name"), 168, vs: 17, vb: true);
    row("02.", "FATHER NAME: ", _g("c_father"), 213);
    row("03.", "MOTHER NAME: ", _g("c_mother"), 257);
    row("04.", "SPOUSE NAME: ", _g("c_spouse"), 301);
    row("05.", "PRESENT ADDRESS: ", _g("c_address"), 344, vs: 11, vb: true, vf: _F.sans);
    row("06.", "PERMANENT ADDRESS: ", _g("c_perm"), 387, vs: 11, vb: true, vf: _F.sans);
    row("07.", "SEX: ", _g("c_sex"), 436);
    row("08.", "PHONE NO: ", _g("c_phone"), 479, vs: 16, vf: _F.sans);
    row("09.", "NATIONALITY: ", _g("c_nat"), 523);
    row("10.", "DATE OF BIRTH: ", _g("c_dob"), 567);
    row("11.", "NID NO (WITH COPY): ", _g("c_nid"), 611, lx: 139);
    row("12.", "E-TIN NO (WITH COPY): ", _g("c_etin"), 655);
    row("13.", "GUARDIAN’S NAME: ", _g("c_guardian"), 703);
    a.t("(IN CASE OF MINOR)", 160, 745, size: 11);
    row("14.", "VEHICLE REGISTRATION NO: ", _g("c_regno"), 772);
    a.t("(IN CASE OF OWNERSHIP TRANSFER)", 165, 816, size: 11);
    row("15.", "CHASSIS NO.: ", _g("chassis"), 852, lb: true, vb: true, vs: 16.5);
    row("16.", "ENGINE NO.: ", _g("engine"), 898, lb: true, vb: true, vs: 16.5);
    row("17.", "YEAR OF MFG.: ", _g("year"), 946, lb: true, vb: true, vs: 16.5);
    row("18.", "PREV. REGN. NO (IF ANY): ", _g("c_prevreg"), 990);
    a.t("19.", 82, 1040, size: z);
    a.rich(
      "P.O./ BANK (FOR FEE/TAX DEPOSIT): ${_g("c_bank")}",
      [
        TextSpan(text: "P.O./ BANK ", style: _st(z, b: false)),
        TextSpan(text: "(FOR FEE/TAX DEPOSIT):", style: _st(11, b: false)),
        TextSpan(text: " ${_g("c_bank")}", style: _st(z, b: true)),
      ],
      128,
      1040,
    );

    a.t("SPECIMEN SIGNATURE", 98, 1085, size: 16.5, b: true);
    a.t("1.", 133, 1190, size: z);
    a.box(235, 1158, 535, 1245, w: 2);
    a.t("2.", 698, 1166, size: z);
    a.box(795, 1140, 1093, 1222, w: 2);
    a.t("3.", 127, 1338, size: z);
    a.box(237, 1325, 540, 1411, w: 2);
    a.t("4.", 710, 1314, size: z);
    a.box(802, 1305, 1105, 1388, w: 2);
    return _page(p, a.build());
  }

  // =============================================================
  // ৯. গেট পাস
  // =============================================================
  _PD _gate() {
    final p = _Pg();
    final date = _g("date").replaceAll('-', '/');
    Widget hc(String s, int flex, double h) => Expanded(
          flex: flex,
          child: Container(
            height: h,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.5)),
            child: p.t(s, size: 15.5),
          ),
        );
    Widget vc(String s, int flex, double h) => Expanded(
          flex: flex,
          child: Container(
            height: h,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.5)),
            child: p.t(s, size: 16.5, align: TextAlign.center),
          ),
        );
    Widget sg(String s) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              children: [
                SizedBox(height: 2, width: double.infinity, child: CustomPaint(painter: _DashPainter())),
                const SizedBox(height: 4),
                p.l(s, size: 17),
              ],
            ),
          ),
        );

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(130, 118, 50, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: p.l("GATE PASS", size: 21, u: true)),
          const SizedBox(height: 34),
          p.row([
            Expanded(child: p.t("NO.${_g("gate_no")}", size: 14.5)),
            p.t("DATE: $date", size: 13.5),
          ]),
          const SizedBox(height: 14),
          p.l("Receiver:", size: 15, b: false),
          const SizedBox(height: 14),
          p.l("${_v("c_name")} S/O:${_v("c_father")}", size: 15),
          p.l("${_v("c_address")} .", size: 15),
          const SizedBox(height: 34),
          // টেবিল: Description (Chassis | Engine) এবং ডানে Remarks
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 450,
                  child: Column(
                    children: [
                      Row(children: [hc("Description", 1, 46)]),
                      Row(children: [hc("Chassis No.", 209, 74), hc("Engine No.", 241, 74)]),
                      Row(children: [vc(_g("chassis"), 209, 91), vc(_g("engine"), 241, 91)]),
                    ],
                  ),
                ),
                Expanded(
                  flex: 161,
                  child: Column(
                    children: [
                      Row(children: [hc("Remarks", 1, 46)]),
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: _ink, width: 1.5),
                              right: BorderSide(color: _ink, width: 1.5),
                              bottom: BorderSide(color: _ink, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 225),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [sg("Incharge"), sg("Driver’s Signature"), sg("Receiver’s Signature")],
          ),
        ],
      ),
    );
    return _page(p, w);
  }

  // =============================================================
  // নমুনা PDF-এর ছাঁচে নতুন কাগজ
  // =============================================================
    bool get _showHeader {
    final v = _g("hdr_on").trim().toLowerCase();
    return !(v == "না" || v == "no" || v == "n" || v == "off" || v == "0");
  }

  Widget _header(_Pg p) {
    if (!_showHeader) return const SizedBox(height: 146);
    final logo = _g("hdr_logo");
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 100,
          child: Stack(
            children: [
              if (logo.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 16,
                  child: Container(
                    width: 66,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _ink,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      logo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Column(
                  children: [
                    p.l(_g("hdr_bn"), size: 34, f: _F.bn),
                    p.l(_g("hdr_en"), size: 31),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 2,
                child: p.l(_g("hdr_brand"), size: 20, i: true, f: _F.sans),
              ),
            ],
          ),
        ),
        Center(child: p.l(_g("hdr_addr"), size: 12.5, b: false)),
        Center(child: p.l(_g("hdr_mob"), size: 12.5, b: false)),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _nameBlock(_Pg p, {double size = 13.5}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          p.l("${_v("c_name")} S/O: ${_v("c_father")}", size: size),
          p.l("${_v("c_address")} .", size: size),
        ],
      );

  Widget _refDate(_Pg p) => p.row([
        Expanded(child: p.t("NO.${_g("gate_no")}", size: 12.5, b: false)),
        p.t("DATE: ${_g("date").replaceAll('-', '/')}", size: 12.5),
      ]);

  Widget _signFor(_Pg p, {String? role, double gap = 56}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          p.l("For ${_g("sign_for")}", size: 14),
          SizedBox(height: gap),
          if (role != null) p.l(role, size: 12.5),
        ],
      );

  // ---------------- প্রত্যয়ন ----------------
  _PD _certificateNew() {
    final p = _Pg();
    final price = _int("price");

    Widget val(String s, {bool b = false}) => p.t(s, size: 13, b: b);

    Widget hpWidget() {
      final hp = _g("hp_cert");
      final i = hp.toUpperCase().indexOf(" HP");
      if (i <= 0) return val(hp, b: true);
      p.buf.write('$hp  ');
      return Text.rich(TextSpan(children: [
        TextSpan(text: hp.substring(0, i), style: _st(13, b: true)),
        TextSpan(text: hp.substring(i), style: _st(13, b: false)),
      ]));
    }

    Widget it(String no, String label, Widget v, {bool colon = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.2),
          child: p.row(
            [
              SizedBox(width: 26, child: p.t(no, size: 12.5, b: false)),
              SizedBox(width: 244, child: p.t(label, size: 12.5, b: false)),
              SizedBox(width: 14, child: p.t(colon ? ":" : "", size: 13, b: false)),
              Expanded(child: v),
            ],
            cross: CrossAxisAlignment.start,
          ),
        );

    const enclosures = [
      "1. REGISTRATION FORM",
      "2. ORIGINAL SALES RECEIPT NO",
      "3. ORIGINAL GATE PASS NO",
      "4. INVOICE NO",
      "5. PACKING LIST (WITH ENGINE & CHASSIS)",
      "6. BILL OF LADING COPY",
      "7. BILL OF ENTRY (WITH ASSES NOTICE) NO",
      "8. L.C.A NO",
      "9. L.C. NO",
    ];

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(48, 34, 48, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(p),
          _refDate(p),
          const SizedBox(height: 8),
          p.l("TO", size: 12, b: false),
          p.l("THE REGISTRATION AUTHORITY", size: 12, b: false),
          p.l("MOTOR VEHICLE DEPARTMENT", size: 12, b: false),
          const SizedBox(height: 10),
          Center(child: p.l("TO WHOM IT MAY CONCERN", size: 17, i: true)),
          const SizedBox(height: 6),
          p.l("THIS IS TO CERTIFY THAT WE HAVE SOLD NEW VEHICLE TO:", size: 11.5, b: false),
          const SizedBox(height: 8),
          _nameBlock(p),
          const SizedBox(height: 8),
          p.l("THE SPECIFICATION OF THE THREE WHEELER DETAILED BELLOW: -", size: 12, b: false),
          const SizedBox(height: 3),
          it("1.", "BRAND", val(_g("brand"))),
          it("2.", "MODEL", val(_g("model_short"))),
          it("3.", "CLASS OF BODY", val(_g("body_cls"))),
          it("4.", "CHASSIS NO.", val(_v("chassis"), b: true), colon: false),
          it("5.", "ENGINE NO.", val(_v("engine"), b: true), colon: false),
          it("6.", "COLOR", val(_g("color").toUpperCase())),
          it("7.", "NUMBER OF CYLINDER", val(_g("cyl_cert"))),
          it("8.", "CUBIC CAPACITY", val(_g("cc_cert"), b: true)),
          it("9.", "HORSE POWER", hpWidget()),
          it("10.", "FUEL USED", val(_g("fuel_cert"))),
          it("11.", "YEAR OF MANUFACTURE", val(_g("year"), b: true)),
          it("12.", "MAKERS NAME", val(_g("maker_short"))),
          it("13.", "MAKERS COUNTRY", val(_g("maker_country"))),
          it("14.", "UNLADEN WEIGHT", val(_g("unladen_cert"))),
          it("15.", "NUMBER OF TYRES", val(_g("tyres_cert"))),
          it("16.", "SIZE OF TYRES", val(_g("tyre_sz_cert"))),
          it("17.", "SEATS (INCL. DRIVER)", val(_g("seats_cert"))),
          it("18.", "WHEEL BASE", val(_g("wheelbase"))),
          it(
            "19.",
            "UNIT PRICE",
            val(price == null ? _dots : _inr(price, decimals: true), b: true),
            colon: false,
          ),
          const SizedBox(height: 10),
          p.l("WE ARE ENCLOSING HEREWITH THE FOLLOWING DOCUMENTS TOWARDS REGISTRATION",
              size: 12, b: false),
          const SizedBox(height: 2),
          for (final e in enclosures)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: p.l(e, size: 12, b: false),
            ),
          const SizedBox(height: 24),
          p.row(
            [
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: p.t("OWNER’S SIGNATURE", size: 12.5, b: false),
              ),
              const Spacer(),
              _signFor(p),
            ],
            cross: CrossAxisAlignment.start,
          ),
        ],
      ),
    );
    return _page(p, w);
  }

  // ---------------- ডেলিভারি চালান ----------------
  _PD _challanNew() {
    final p = _Pg();
    Widget val(String s, {bool b = false}) => p.t(s, size: 13, b: b);
    Widget line(String l, Widget v, {bool colon = true}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF8A8A8A), width: 0.9)),
          ),
          child: p.row([
            SizedBox(width: 280, child: p.t(l, size: 12.5, b: false)),
            SizedBox(width: 14, child: p.t(colon ? ":" : "", size: 13, b: false)),
            Expanded(child: v),
          ]),
        );
    const note =
        "Please received the undermentioned vehicles/with standard/extra tools with spare wheel and accessories on the following particulars.";

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(48, 34, 48, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(p),
          Center(child: p.l("DELIVERY CHALLAN", size: 17, i: true, u: true)),
          const SizedBox(height: 8),
          _refDate(p),
          const SizedBox(height: 10),
          _nameBlock(p),
          const SizedBox(height: 12),
          p.l(note, size: 9, b: false, u: true),
          const SizedBox(height: 6),
          line("1. CHASSIS NO.", val(_v("chassis"), b: true), colon: false),
          line("2. ENGINE NO.", val(_v("engine"), b: true), colon: false),
          line("3. MAKE & MODEL OF VEHICLE", val(_g("model_short"))),
          line("4. YEAR OF MANUFACTURE", val(_g("year"), b: true)),
          line("5. NO. OF CYLINDER WITH CC", val(_g("cyl_cert"))),
          line("7. SEATING CAPACITY (INCL. DRIVER)", val(_g("seats_cert"))),
          line("8. CLASS OF VEHICAL", val("${_g("tyres_cert")}, ${_g("body_cls")}")),
          line("9. COLOR OF VEHICAL", val(_g("color").toUpperCase())),
          line("10. SIZE OF TYRES", val(_g("tyre_sz_cert"))),
          const SizedBox(height: 14),
          Container(
            height: 64,
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            alignment: Alignment.topLeft,
            decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.6)),
            child: p.t("REMARKS :", size: 13),
          ),
          const SizedBox(height: 3),
          p.l(note, size: 8.5, b: false),
          const SizedBox(height: 90),
          p.row(
            [
              p.t("BUYER’S SIGNATURE", size: 12.5, b: false),
              const Spacer(),
              p.t("For ${_g("sign_for")}", size: 14),
            ],
            cross: CrossAxisAlignment.start,
          ),
        ],
      ),
    );
    return _page(p, w);
  }

  // ---------------- সেলস ইনভয়েস (পোর্ট্রেট) ----------------
  _PD _invoiceNew() {
    final p = _Pg();
    final price = _int("price");
    final amount = price == null ? _dots : _inr(price, decimals: true);
    const flex = [22, 11, 21, 17, 11, 18];
    final border = BoxDecoration(border: Border.all(color: _ink, width: 1.1));

    Widget c(int i, String s, double h, {double size = 10.5, bool b = false}) => Expanded(
          flex: flex[i],
          child: Container(
            height: h,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: border,
            child: p.t(s, size: size, b: b, align: TextAlign.center),
          ),
        );

    final desc = "BRAND : ${_g("brand")}\n"
        "MODEL : ${_g("inv_model")}\n"
        "CC : ${_g("cc_cert")}\n"
        "${_g("tyres_cert")}";

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(48, 34, 48, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(p),
          Center(child: p.l("Sales Invoice", size: 18, u: true)),
          const SizedBox(height: 8),
          p.row([
            Expanded(
              child: p.t("Sales Invoice    NO.${_g("gate_no")}", size: 12, b: false),
            ),
            p.t("DATE: ${_g("date").replaceAll('-', '/')}", size: 12.5),
          ]),
          const SizedBox(height: 10),
          _nameBlock(p),
          const SizedBox(height: 14),
          p.row([
            c(0, "DESCRIPTION OF\nVEHICLE", 40, size: 9.5),
            c(1, "MODEL", 40, size: 9.5),
            c(2, "CHASSIS NUMBER", 40, size: 9.5),
            c(3, "ENGINE NUMBER", 40, size: 9.5),
            c(4, "COLOUR", 40, size: 9.5),
            c(5, "PRICE\n(INTK)", 40, size: 9.5),
          ]),
          p.row([
            c(0, desc, 330),
            c(1, _g("model_short"), 330),
            c(2, _g("chassis"), 330, size: 11, b: true),
            c(3, _g("engine"), 330, size: 11, b: true),
            c(4, _g("color").toUpperCase(), 330),
            c(5, amount, 330, size: 11),
          ]),
          const SizedBox(height: 14),
          p.row([
            p.t("Amount in Words:  ", size: 12.5),
            Expanded(
              child: p.t(price == null ? _dots : _wordsTitle(price), size: 12.5, u: true),
            ),
          ]),
          const SizedBox(height: 70),
          p.row(
            [
              p.t("Prepared by", size: 13),
              const Spacer(),
              _signFor(p, role: "Sales Admin."),
            ],
            cross: CrossAxisAlignment.start,
          ),
        ],
      ),
    );
    return _page(p, w);
  }

  // ---------------- গেট পাস ----------------
  _PD _gateNew() {
    final p = _Pg();
    Widget cell(Widget child, double h) => Container(
          height: h,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.2)),
          child: child,
        );
    Widget sg(String s) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              children: [
                SizedBox(
                  height: 2,
                  width: double.infinity,
                  child: CustomPaint(painter: _DashPainter()),
                ),
                const SizedBox(height: 4),
                p.l(s, size: 15),
              ],
            ),
          ),
        );

    final w = Padding(
      padding: const EdgeInsets.fromLTRB(48, 34, 48, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(p),
          Center(child: p.l("GATE PASS", size: 18, u: true)),
          const SizedBox(height: 10),
          _refDate(p),
          const SizedBox(height: 12),
          p.l("Receiver:", size: 13, b: false),
          const SizedBox(height: 10),
          _nameBlock(p),
          const SizedBox(height: 26),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 68,
                child: Column(
                  children: [
                    cell(p.t("Description", size: 14), 40),
                    Row(children: [
                      Expanded(child: cell(p.t("Chassis No.", size: 14), 52)),
                      Expanded(child: cell(p.t("Engine No.", size: 14), 52)),
                    ]),
                    Row(children: [
                      Expanded(child: cell(p.t(_g("chassis"), size: 12.5), 78)),
                      Expanded(child: cell(p.t(_g("engine"), size: 12.5), 78)),
                    ]),
                  ],
                ),
              ),
              Expanded(
                flex: 32,
                child: Column(
                  children: [
                    cell(p.t("Remarks", size: 14), 40),
                    cell(const SizedBox(), 130),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 90),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [sg("Incharge"), sg("Driver’s Signature"), sg("Receiver’s Signature")],
          ),
        ],
      ),
    );
    return _page(p, w);
  }

  // ---------------- আবেদন ফর্ম ২য় পাতা (Section-V, ৪০-৪৬) ----------------
  _PD _application2New() {
    final p = _Pg();
    final a = _Abs(p, 927, 1288);
    const z = 13.0;

    a.t("Address :", 137, 108, size: z);
    a.t("40.   Insurance Information :", 137, 133, size: z);
    a.t("a)  Policy no :", 172, 155, size: z);
    a.t("b)  Type of policy :", 352, 157, size: z);
    a.t("c)  Insurer’s name & address :", 551, 156, size: z);
    a.t("d)  Date of expiry :", 172, 178, size: z);
    a.t("41.  Joint owner Information :", 137, 197, size: z);
    a.t("a)  Name :", 172, 219, size: z);
    a.t("b)  Name :", 527, 227, size: z);
    a.t("Father/Husband :", 172, 245, size: z);
    a.t("Father/Husband :", 300, 247, size: z);

    a.c("Section-V", 281, size: 14.5, b: true);
    a.c("(Declaration, Certificates and documents)", 305, size: 11.5);

    a.t("42.   Declaration by owner :", 137, 318, size: z);
    a.t("a)", 172, 342, size: 10.5);
    a.t("I the undersigned do hereby declare that to the best of my knowledge and belief, the information",
        198, 342, size: z);
    a.t("b)", 172, 367, size: 10.5);
    a.t("given and the documents enclosed (as per list attached) are true, I also declare that in case the",
        198, 367, size: z);
    a.t("paper/documents and information furnished are found to be incorrect at any state, I shall be liablefor",
        198, 385, size: z);
    a.t("legal action.", 198, 402, size: z);
    a.t("Date :", 197, 419, size: z);
    a.t("Encl : List of documents", 197, 443, size: z);
    a.rt("Signature of owner", 841, 453, size: z);

    a.t("43.   Registered dealer’s certificate :", 137, 483, size: z);
    a.t("I the undersigned do hereby certify that the vehicle in question has been sold by me/my firm and the",
        137, 506, size: z);
    a.t("ownership documents attached with the application for registration for true. The information/specifications",
        137, 528, size: z);
    a.t("pertaining to the vehicle are correct and the vehicle complies with all the requirements of the registration.",
        137, 549, size: z);
    a.t("Date :", 197, 573, size: z);
    a.t("Encl : List of documents", 197, 595, size: z);
    a.t("Signature of registered dealer", 628, 625, size: z);
    a.t("Seal", 720, 649, size: z);

    a.t("44.   Certificate by the Inspector of Motor Vehicles :", 137, 662, size: z);
    a.rich(
      "Certified that the par ticulars pertaining to the owner and the vechicle chassis No",
      [
        TextSpan(
          text: "Certified that the par ticulars pertaining to the owner and the vechicle ",
          style: _st(z, b: false),
        ),
        TextSpan(text: "chassis No", style: _st(z, b: true)),
      ],
      137,
      694,
      size: z,
    );
    a.t("Engine", 779, 702, size: z, b: true);
    a.t("No.", 137, 732, size: z, b: true);
    a.t("given in the application match with the owner ship documents attached to this application Its is",
        205, 732, size: z);
    a.t("further certified that the vehicle complies with the registration requirements specified in the MV Act and the",
        137, 760, size: z);
    a.t("Rules and / or Regulations made there under and the vehicle is not", 137, 788, size: z);
    a.t("mechanically defective. The necessary documents/papers are available as per list enclosed.",
        137, 817, size: z);
    a.t("Date :", 137, 832, size: z);
    a.t("Encl : List of documents", 137, 857, size: z);
    a.t("Signature of Inspector of Motor Vehicles official Seal", 506, 898, size: z);

    a.t("45.   Registration Status ;", 137, 916, size: z);
    a.t("Registration allowed/not allowed", 169, 942, size: z);
    a.t("Signature of Registering Authority Seal.", 593, 970, size: z);

    a.t("46.   Fees and Tax Accounts :", 137, 985, size: z);
    _dotLine(a, "Necessary fees and taxes amounting to take", "has been paid to", 137, 845, 1017, z);
    _dotLine(a, "P.O/Bank", "vide vouchers and receipts enclosed.", 137, 657, 1045, z);
    a.t("Signature of owner", 137, 1086, size: z);
    a.t("or his representative", 137, 1106, size: z);
    a.t("Signature of dealing assistant.", 659, 1092, size: z);
    a.t("Counter Signature by the registering authority.", 333, 1132, size: z);
    return _page(p, a.build());
  }
  

  // =============================================================
  // PDF / প্রিন্ট — পর্দার কাগজের ছবি তুলে PDF-এ বসানো হয়, তাই বাংলা যুক্তাক্ষর ঠিক থাকে
  // =============================================================
  Future<_Shot?> _capture(int i) async {
    try {
      final ctx = _keys[i].currentContext;
      if (ctx == null) return null;
      final ro = ctx.findRenderObject();
      if (ro is! RenderRepaintBoundary) return null;
      final img = await ro.toImage(pixelRatio: 2.5);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return null;
      return _Shot(bd.buffer.asUint8List(), img.width, img.height, _paperTitles[i]);
    } catch (_) {
      return null;
    }
  }

  Future<List<_Shot>> _captureTabs(List<int> idx) async {
    final out = <_Shot>[];
    for (final i in idx) {
      _tab.index = i + 1;
      for (var t = 0; t < 40 && _keys[i].currentContext == null; t++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 120));
      final shot = await _capture(i);
      if (shot != null) out.add(shot);
    }
    return out;
  }

  Future<void> _openPdf(List<int> idx, String name) async {
    if (_busy) return;
    final back = _tab.index;
    setState(() {
      _busy = true;
    });
    try {
      final shots = await _captureTabs(idx);
      if (shots.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("PDF তৈরি করা যায়নি, আবার চেষ্টা করুন")),
          );
        }
        return;
      }
      _tab.index = back;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PdfViewScreen(shots: shots, name: name),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("PDF তৈরি করা যায়নি: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  Widget _paper(int i, String title, _PD d) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: d.landscape ? 1000 : 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black26),
                boxShadow: const [
                  BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(key: _keys[i], child: d.w),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copy(d.text, "\"$title\" কপি হয়েছে"),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text("কপি"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : () => _openPdf([i], title),
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text("PDF / প্রিন্ট"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: const Text(
            "নয়টা কাগজ আপনার নমুনা এক্সেল ফাইল ও আসল ফর্মের ছবির ছাঁচে সাজানো। নিচের তথ্য একবার মিলিয়ে নিন, "
            "সব কাগজে সাথে সাথে বসে যাবে। ফাঁকা থাকলে কাগজে ডটের লাইন থাকে, হাতে লেখা যায়।\n"
            "বাংলা কাগজ দুটোর লেখা নমুনার পুরনো SutonnyMJ ফন্ট থেকে ইউনিকোডে রূপান্তর করা। "
            "ছাপার আগে একবার পড়ে নেবেন।",
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        for (final g in _groups.entries) ...[
          const SizedBox(height: 18),
          Text(g.key, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final d in g.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _c[d.id],
                keyboardType: d.type,
                decoration: InputDecoration(
                  labelText: d.label,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = const [
      "বিক্রয় প্রত্যয়ন",
      "সেলস ইনভয়েস",
      "অঙ্গীকারনামা",
      "আবেদন ফর্ম",
      "আবেদন ফর্ম ২",
      "ডিলার ঘোষণা",
      "ডেলিভারি চালান",
      "মালিকের তথ্য",
      "গেট পাস",
    ];
      final docs = [
      _certificateNew(),
      _invoiceNew(),
      _undertaking(),
      _application(),
      _application2New(),
      _declaration(),
      _challanNew(),
      _owner(),
      _gateNew(),
    ];

    return Scaffold(
      appBar: AppBar(
      title: const Text("BRTA কাগজপত্র — নতুন ছাঁচ"),
        actions: [
          IconButton(
            tooltip: "সব কাগজ একসাথে PDF / প্রিন্ট",
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _busy ? null : () => _openPdf([0, 1, 2, 3, 4, 5, 6, 7, 8], "BRTA কাগজপত্র"),
          ),
          IconButton(
            tooltip: "সব কাগজ একসাথে কপি",
            icon: const Icon(Icons.copy_all),
            onPressed: () {
              final all = StringBuffer();
              for (var i = 0; i < docs.length; i++) {
                all.writeln("==== ${titles[i]} ====");
                all.writeln(docs[i].text);
                all.writeln();
              }
              _copy(all.toString(), "নয়টা কাগজই কপি হয়েছে");
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: [
            const Tab(text: "তথ্য"),
            for (final t in titles) Tab(text: t),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tab,
            children: [
              _infoTab(),
              for (var i = 0; i < docs.length; i++)
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _paper(i, titles[i], docs[i]),
                ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

/// প্রতিটি কাগজের নিজস্ব প্রিন্ট সেটিং (মিলিমিটারে)
class _PageSetup {
  double top;
  double bottom;
  double left;
  double right;
  double dx; // ডানে (+) / বামে (−)
  double dy; // নিচে (+) / উপরে (−)
  bool shift; // true = মাপ ঠিক রেখে শুধু সরান, false = মার্জিনের ভেতরে আঁটান
  bool center;

  _PageSetup({
    this.top = 0,
    this.bottom = 0,
    this.left = 0,
    this.right = 0,
    this.dx = 0,
    this.dy = 0,
    this.shift = true,
    this.center = true,
  });

  _PageSetup copy() => _PageSetup(
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        dx: dx,
        dy: dy,
        shift: shift,
        center: center,
      );

  Map<String, dynamic> toJson() => {
        'top': top,
        'bottom': bottom,
        'left': left,
        'right': right,
        'dx': dx,
        'dy': dy,
        'shift': shift,
        'center': center,
      };

  factory _PageSetup.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] is num) ? (j[k] as num).toDouble() : 0;
    return _PageSetup(
      top: d('top'),
      bottom: d('bottom'),
      left: d('left'),
      right: d('right'),
      dx: d('dx'),
      dy: d('dy'),
      shift: j['shift'] != false,
      center: j['center'] != false,
    );
  }
}

/// PDF দেখা, প্রতিটি কাগজের আলাদা মার্জিন/সরানো বেছে প্রিন্ট ও সেভ/শেয়ার করার পাতা
class _PdfViewScreen extends StatefulWidget {
  final List<_Shot> shots;
  final String name;

  const _PdfViewScreen({required this.shots, required this.name});

  @override
  State<_PdfViewScreen> createState() => _PdfViewScreenState();
}

class _PdfViewScreenState extends State<_PdfViewScreen> {
  static const String _prefKey = 'brta_print_setup';

  final Map<String, _PageSetup> _setup = {};
  int _sel = 0;
  bool _panel = true;
  bool _loaded = false;
  int _gen = 0; // সেটিং বদলালে প্রিভিউ নতুন করে তৈরি করার জন্য

  @override
  void initState() {
    super.initState();
    _loadSetup();
  }

  _PageSetup _of(int i) => _setup.putIfAbsent(widget.shots[i].label, () => _PageSetup());

  Future<void> _loadSetup() async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = jsonDecode(p.getString(_prefKey) ?? '{}') as Map<String, dynamic>;
      m.forEach((k, v) {
        _setup[k] = _PageSetup.fromJson(Map<String, dynamic>.from(v as Map));
      });
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _gen++;
    });
  }

  Future<void> _saveSetup() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _prefKey,
        jsonEncode({for (final e in _setup.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {}
  }

  double _fit(double v, double max) => v < 50 ? 50 : (v > max ? max : v);

  Future<Uint8List> _build(PdfPageFormat _) async {
    const mm = PdfPageFormat.mm;
    final doc = pw.Document();
    for (var i = 0; i < widget.shots.length; i++) {
      final s = widget.shots[i];
      final c = _of(i);
      final fmt = s.w > s.h ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      final image = pw.MemoryImage(s.png);

      if (c.shift) {
        // মাপ ঠিক থাকে, পুরো কাগজ ডানে/নিচে সরে (কিনারার বাইরের অংশ কাটা পড়ে)
        doc.addPage(
          pw.Page(
            pageFormat: fmt,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Stack(
              fit: pw.StackFit.expand,
              children: [
                pw.Positioned(
                  left: c.dx * mm,
                  top: c.dy * mm,
                  child: pw.Image(image, width: fmt.width, height: fmt.height, fit: pw.BoxFit.fill),
                ),
              ],
            ),
          ),
        );
      } else {
        final availW = _fit(fmt.width - (c.left + c.right) * mm, fmt.width);
        final availH = _fit(fmt.height - (c.top + c.bottom) * mm, fmt.height);
        final kw = availW / s.w;
        final kh = availH / s.h;
        final k = kw < kh ? kw : kh; // অনুপাত ঠিক রেখে মার্জিনের ভেতরে আঁটানো
        doc.addPage(
          pw.Page(
            pageFormat: fmt,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Padding(
              padding: pw.EdgeInsets.fromLTRB(c.left * mm, c.top * mm, c.right * mm, c.bottom * mm),
              child: pw.Align(
                alignment: c.center ? pw.Alignment.center : pw.Alignment.topLeft,
                child: pw.Image(image, width: s.w * k, height: s.h * k, fit: pw.BoxFit.fill),
              ),
            ),
          ),
        );
      }
    }
    return doc.save();
  }

  void _changed() {
    _saveSetup();
    setState(() => _gen++);
  }

  void _resetThis() {
    _setup[widget.shots[_sel].label] = _PageSetup();
    _changed();
  }

  void _applyToAll() {
    final c = _of(_sel);
    for (var i = 0; i < widget.shots.length; i++) {
      _setup[widget.shots[i].label] = c.copy();
    }
    _changed();
  }

  Widget _slider(String label, double value, double min, double max, void Function(double) set,
      {double labelW = 56}) {
    final v = value.clamp(min, max).toDouble();
    return SizedBox(
      width: 330,
      child: Row(
        children: [
          SizedBox(width: labelW, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Slider(
              value: v,
              min: min,
              max: max,
              divisions: ((max - min) * 2).round(),
              label: "${v.toStringAsFixed(1)} মিমি",
              onChanged: (x) => setState(() => set(x)),
              onChangeEnd: (_) => _changed(),
            ),
          ),
          SizedBox(
            width: 58,
            child: Text("${v.toStringAsFixed(1)} মিমি", style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _chipLabel(int i) =>
      widget.shots[i].label.isEmpty ? "পাতা ${i + 1}" : widget.shots[i].label;

  @override
  Widget build(BuildContext context) {
    final multi = widget.shots.length > 1;
    final c = _of(_sel);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            tooltip: _panel ? "সেটিং লুকান" : "মার্জিন / সরানোর সেটিং",
            icon: Icon(_panel ? Icons.expand_less : Icons.tune),
            onPressed: () => setState(() => _panel = !_panel),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_panel)
                  Container(
                    width: double.infinity,
                    color: Colors.grey.shade100,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (multi) ...[
                          const Text("কোন কাগজের সেটিং বদলাবেন:",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (var i = 0; i < widget.shots.length; i++)
                                ChoiceChip(
                                  label: Text(_chipLabel(i)),
                                  selected: _sel == i,
                                  onSelected: (_) => setState(() => _sel = i),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text("মাপ ঠিক রেখে সরান"),
                              selected: c.shift,
                              onSelected: (_) {
                                c.shift = true;
                                _changed();
                              },
                            ),
                            ChoiceChip(
                              label: const Text("মার্জিনের ভেতরে আঁটান"),
                              selected: !c.shift,
                              onSelected: (_) {
                                c.shift = false;
                                _changed();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 16,
                          children: c.shift
                              ? [
                                  _slider("ডানে(+) বামে(−)", c.dx, -30, 30, (x) => c.dx = x, labelW: 110),
                                  _slider("নিচে(+) উপরে(−)", c.dy, -30, 30, (x) => c.dy = x, labelW: 110),
                                ]
                              : [
                                  _slider("উপরে", c.top, 0, 60, (x) => c.top = x),
                                  _slider("নিচে", c.bottom, 0, 60, (x) => c.bottom = x),
                                  _slider("বামে", c.left, 0, 60, (x) => c.left = x),
                                  _slider("ডানে", c.right, 0, 60, (x) => c.right = x),
                                ],
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (!c.shift) ...[
                              ChoiceChip(
                                label: const Text("মাঝখানে"),
                                selected: c.center,
                                onSelected: (_) {
                                  c.center = true;
                                  _changed();
                                },
                              ),
                              ChoiceChip(
                                label: const Text("উপরে-বামে"),
                                selected: !c.center,
                                onSelected: (_) {
                                  c.center = false;
                                  _changed();
                                },
                              ),
                            ],
                            TextButton.icon(
                              onPressed: _resetThis,
                              icon: const Icon(Icons.restart_alt, size: 18),
                              label: const Text("এই কাগজ রিসেট"),
                            ),
                            if (multi)
                              TextButton.icon(
                                onPressed: _applyToAll,
                                icon: const Icon(Icons.copy_all, size: 18),
                                label: const Text("সব কাগজে এই মান"),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: PdfPreview(
                    key: ValueKey(_gen),
                    build: _build,
                    pdfFileName: "BRTA_papers.pdf",
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                  ),
                ),
              ],
            ),
    );
  }
}