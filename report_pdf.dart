import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'invoice_screen.dart' show companyName;

/// যেকোনো তালিকা/রিপোর্টকে PDF করার সাধারণ ব্যবস্থা।
/// headers    : কলামের নাম
/// rightAlign : কোন কলাম ডান দিকে (সংখ্যার কলাম) বসবে
/// rows       : সারিগুলো (আগে থেকেই ফরম্যাট করা লেখা)
/// totals     : শেষের "মোট" সারি (না থাকলে null)
/// subtitle   : ফিল্টারের সারাংশ (তারিখ, কাস্টমার ইত্যাদি)
Future<void> openReportPdf(
  BuildContext context, {
  required String title,
  String subtitle = '',
  required List<String> headers,
  required List<bool> rightAlign,
  required List<List<String>> rows,
  List<String>? totals,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReportPdfScreen(
        title: title,
        subtitle: subtitle,
        headers: headers,
        rightAlign: rightAlign,
        rows: rows,
        totals: totals,
      ),
    ),
  );
}

const Color _ink = Colors.black;

TextStyle _st(double size, {bool b = false, bool i = false}) => TextStyle(
      fontSize: size,
      color: _ink,
      fontWeight: b ? FontWeight.w700 : FontWeight.w400,
      fontStyle: i ? FontStyle.italic : FontStyle.normal,
    );

class _R {
  final List<String> cells;
  final bool total;
  const _R(this.cells, this.total);
}

class _Shot {
  final Uint8List png;
  final int w;
  final int h;
  const _Shot(this.png, this.w, this.h);
}

class ReportPdfScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> headers;
  final List<bool> rightAlign;
  final List<List<String>> rows;
  final List<String>? totals;

  const ReportPdfScreen({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.headers,
    required this.rightAlign,
    required this.rows,
    this.totals,
  });

  @override
  State<ReportPdfScreen> createState() => _ReportPdfScreenState();
}

class _ReportPdfScreenState extends State<ReportPdfScreen> {
  // ---------- মার্জিন (মিলিমিটার), অ্যাপ চালু থাকা পর্যন্ত মনে থাকে ----------
  static double _top = 0;
  static double _bottom = 0;
  static double _left = 0;
  static double _right = 0;
  static bool _center = true;

  bool _panel = true;
  int _gen = 0;

  // ---------- পাতার হিসাব ----------
  late final bool _landscape;
  late final double _pageW;
  late final double _pageH;
  late final double _fs;
  late final double _rowH;
  late final List<int> _flex;
  List<List<_R>> _pages = [];
  List<GlobalKey> _keys = [];

  String _shop = companyName;
  bool _built = false;
  int _done = 0;
  String? _error;
  List<_Shot>? _shots;

  @override
  void initState() {
    super.initState();
    _layout();
    _start();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  void _layout() {
    final n = widget.headers.length;
    _landscape = n > 6;
    _pageW = _landscape ? 1123 : 794;
    _pageH = _landscape ? 794 : 1123;
    _fs = n <= 5 ? 13 : (n <= 8 ? 12 : (n <= 11 ? 10.5 : 9.5));
    _rowH = (_fs * 2.7 + 8).ceilToDouble();

    // কলামের চওড়া: লেখার দৈর্ঘ্য অনুযায়ী
    final weights = <double>[];
    for (var i = 0; i < n; i++) {
      var m = widget.headers[i].length;
      final limit = widget.rows.length < 200 ? widget.rows.length : 200;
      for (var r = 0; r < limit; r++) {
        final row = widget.rows[r];
        if (i < row.length && row[i].length > m) m = row[i].length;
      }
      if (widget.totals != null && i < widget.totals!.length && widget.totals![i].length > m) {
        m = widget.totals![i].length;
      }
      weights.add(m.clamp(5, 30).toDouble());
    }
    _flex = weights.map((w) => (w * 10).round()).toList();

    // সারি ভাগ: প্রথম পাতায় উপরের অংশ বড়, তাই কম সারি
    final items = <_R>[
      for (final r in widget.rows) _R(r, false),
      if (widget.totals != null) _R(widget.totals!, true),
    ];
    final usable = _pageH - 34 - 24 - 40; // উপর, নিচ, ফুটার
    final headH = _rowH + 4;
    final firstCap = ((usable - 118 - headH) / _rowH).floor() - 1;
    final otherCap = ((usable - 34 - headH) / _rowH).floor() - 1;
    final first = firstCap < 1 ? 1 : firstCap;
    final other = otherCap < 1 ? 1 : otherCap;

    final pages = <List<_R>>[];
    var i = 0;
    while (i < items.length || pages.isEmpty) {
      final cap = pages.isEmpty ? first : other;
      final end = (i + cap) > items.length ? items.length : (i + cap);
      pages.add(items.sublist(i, end));
      i = end;
      if (i >= items.length) break;
    }
    _pages = pages;
    _keys = List.generate(pages.length, (_) => GlobalKey());
  }

  Future<void> _start() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = p.getString('inv_name');
      if (n != null && n.trim().isNotEmpty) _shop = n.trim();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _built = true;
      _done = 0;
      _error = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 400));
    final out = <_Shot>[];
    for (var i = 0; i < _keys.length; i++) {
      final shot = await _capture(i);
      if (!mounted) return;
      if (shot == null) {
        setState(() {
          _error = "PDF তৈরি করা যায়নি, আবার চেষ্টা করুন";
        });
        return;
      }
      out.add(shot);
      setState(() {
        _done = i + 1;
      });
      await Future.delayed(const Duration(milliseconds: 10));
    }
    if (mounted) {
      setState(() {
        _shots = out;
      });
    }
  }

  Future<_Shot?> _capture(int i) async {
    try {
      final ro = _keys[i].currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return null;
      final img = await ro.toImage(pixelRatio: 2.0);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return null;
      return _Shot(bd.buffer.asUint8List(), img.width, img.height);
    } catch (_) {
      return null;
    }
  }

  // ---------- এক পাতার চেহারা ----------
  Widget _cellText(String s, int i, {bool bold = false}) {
    final right = i < widget.rightAlign.length && widget.rightAlign[i];
    return Expanded(
      flex: _flex[i],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            s,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: _st(_fs, b: bold),
          ),
        ),
      ),
    );
  }

  Widget _headRow() {
    return Container(
      height: _rowH + 4,
      decoration: BoxDecoration(
        color: const Color(0xFFE6E6E6),
        border: Border.all(color: _ink, width: 1),
      ),
      child: Row(
        children: [
          for (var i = 0; i < widget.headers.length; i++)
            _cellText(widget.headers[i], i, bold: true),
        ],
      ),
    );
  }

  Widget _dataRow(_R r) {
    return Container(
      height: _rowH,
      decoration: BoxDecoration(
        color: r.total ? const Color(0xFFEFEFEF) : Colors.white,
        border: Border(
          left: const BorderSide(color: _ink, width: 1),
          right: const BorderSide(color: _ink, width: 1),
          bottom: BorderSide(color: r.total ? _ink : Colors.black45, width: r.total ? 1.4 : 0.6),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < widget.headers.length; i++)
            _cellText(i < r.cells.length ? r.cells[i] : '', i, bold: r.total),
        ],
      ),
    );
  }

  Widget _page(int idx) {
    final first = idx == 0;
    final now = DateTime.now();
    final dateText = "${_two(now.day)}-${_two(now.month)}-${now.year}";
    return SizedBox(
      width: _pageW,
      height: _pageH,
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 34, 36, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (first) ...[
                Center(child: Text(_shop, style: _st(24, b: true))),
                const SizedBox(height: 4),
                Center(child: Text(widget.title, style: _st(18, b: true))),
                if (widget.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Center(
                    child: Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _st(12),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text("তারিখ: $dateText", style: _st(11.5)),
                ),
                const SizedBox(height: 8),
              ] else ...[
                Row(
                  children: [
                    Text(widget.title, style: _st(13, b: true)),
                    const Spacer(),
                    Text(_shop, style: _st(12)),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              _headRow(),
              for (final r in _pages[idx]) _dataRow(r),
              const Spacer(),
              Container(height: 1, color: Colors.black45),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text("${widget.rows.length} টি সারি", style: _st(11)),
                  const Spacer(),
                  Text("পাতা ${idx + 1} / ${_pages.length}", style: _st(11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- PDF তৈরি (মার্জিনসহ) ----------
  double _fit(double v, double max) => v < 50 ? 50 : (v > max ? max : v);

  Future<Uint8List> _buildPdf() async {
    const mm = PdfPageFormat.mm;
    final doc = pw.Document();
    for (final s in _shots!) {
      final fmt = s.w > s.h ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      final availW = _fit(fmt.width - (_left + _right) * mm, fmt.width);
      final availH = _fit(fmt.height - (_top + _bottom) * mm, fmt.height);
      final kw = availW / s.w;
      final kh = availH / s.h;
      final k = kw < kh ? kw : kh;
      final image = pw.MemoryImage(s.png);
      doc.addPage(
        pw.Page(
          pageFormat: fmt,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Padding(
            padding: pw.EdgeInsets.fromLTRB(_left * mm, _top * mm, _right * mm, _bottom * mm),
            child: pw.Align(
              alignment: _center ? pw.Alignment.center : pw.Alignment.topLeft,
              child: pw.Image(image, width: s.w * k, height: s.h * k, fit: pw.BoxFit.fill),
            ),
          ),
        ),
      );
    }
    return doc.save();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Windows-এ সরাসরি Downloads ফোল্ডারে PDF ফাইল সেভ
  Future<void> _saveToDownloads() async {
    try {
      final bytes = await _buildPdf();
      final home = kIsWeb ? '' : (Platform.environment['USERPROFILE'] ?? '');
      if (home.isEmpty) {
        _snack("Downloads ফোল্ডার পাওয়া যায়নি");
        return;
      }
      final dir = Directory('$home\\Downloads');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final safe = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final n = DateTime.now();
      final stamp =
          "${n.year}${_two(n.month)}${_two(n.day)}_${_two(n.hour)}${_two(n.minute)}${_two(n.second)}";
      final file = File('${dir.path}\\${safe}_$stamp.pdf');
      await file.writeAsBytes(bytes);
      _snack("সেভ হয়েছে: ${file.path}");
      try {
        await Process.run('explorer.exe', ['/select,${file.path}']);
      } catch (_) {}
    } catch (e) {
      _snack("সেভ করা যায়নি: $e");
    }
  }

  // ---------- UI ----------
  Widget _slider(String label, double value, void Function(double) set) {
    return SizedBox(
      width: 300,
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: 60,
              divisions: 60,
              label: "${value.round()} মিমি",
              onChanged: (x) => setState(() => set(x)),
              onChangeEnd: (_) => setState(() => _gen++),
            ),
          ),
          SizedBox(width: 52, child: Text("${value.round()} মিমি", style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _reset() {
    setState(() {
      _top = 0;
      _bottom = 0;
      _left = 0;
      _right = 0;
      _center = true;
      _gen++;
    });
  }

  Widget _buildingView() {
    return Stack(
      children: [
        if (_built && _error == null)
          SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _landscape ? 1000 : 780),
                child: Column(
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: RepaintBoundary(key: _keys[i], child: _page(i)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xDDFFFFFF),
            child: Center(
              child: _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _start,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 14),
                        Text("PDF তৈরি হচ্ছে… $_done / ${_pages.length} পাতা"),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _readyView() {
    return Column(
      children: [
        if (_panel)
          Container(
            width: double.infinity,
            color: Colors.grey.shade100,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 24,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _slider("উপরে", _top, (x) => _top = x),
                _slider("নিচে", _bottom, (x) => _bottom = x),
                _slider("বামে", _left, (x) => _left = x),
                _slider("ডানে", _right, (x) => _right = x),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChoiceChip(
                      label: const Text("মাঝখানে"),
                      selected: _center,
                      onSelected: (_) => setState(() {
                        _center = true;
                        _gen++;
                      }),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("উপরে-বামে"),
                      selected: !_center,
                      onSelected: (_) => setState(() {
                        _center = false;
                        _gen++;
                      }),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text("রিসেট"),
                    ),
                    if (!kIsWeb && Platform.isWindows) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _saveToDownloads,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text("Downloads-এ সেভ"),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: PdfPreview(
            key: ValueKey(_gen),
            build: (_) => _buildPdf(),
            pdfFileName: "${widget.title}.pdf",
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _shots != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (ready)
            IconButton(
              tooltip: _panel ? "মার্জিনের অপশন লুকান" : "মার্জিনের অপশন দেখান",
              icon: Icon(_panel ? Icons.expand_less : Icons.tune),
              onPressed: () => setState(() => _panel = !_panel),
            ),
        ],
      ),
      body: ready ? _readyView() : _buildingView(),
    );
  }
}