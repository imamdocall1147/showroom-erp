import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'reports_config.dart';
import 'sync_service.dart';

// ---------------------------------------------------------------
// ফরম্যাটিং সাহায্যকারী ফাংশন
// ---------------------------------------------------------------
String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => "${d.year}-${_two(d.month)}-${_two(d.day)}";

/// বাংলাদেশি লাখ-কোটি গ্রুপিং: 1234567 -> 12,34,567
String _groupLakh(String digits) {
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

String _fmtNumber(dynamic v) {
  final n = v is num ? v : num.tryParse("$v");
  if (n == null) return "$v";
  final neg = n < 0;
  final fixed = n.abs().toStringAsFixed(2);
  final pieces = fixed.split('.');
  final dec = pieces[1].replaceFirst(RegExp(r'0+$'), '');
  final res = _groupLakh(pieces[0]) + (dec.isEmpty ? '' : '.$dec');
  return neg ? '-$res' : res;
}

String _fmtCell(dynamic v, String type) {
  if (v == null) return "-";
  switch (type) {
    case 'money':
      return "৳${_fmtNumber(v)}";
    case 'number':
      return _fmtNumber(v);
    case 'percent':
      return "${_fmtNumber(v)}%";
    case 'date':
      final s = "$v";
      return (s.length >= 10 && s.contains('T')) ? s.substring(0, 10) : s;
    default:
      return "$v";
  }
}

bool _isNumericType(String type) =>
    type == 'money' || type == 'number' || type == 'percent';

String _csvEscape(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

// ---------------------------------------------------------------
// যেকোনো স্ক্রিনের AppBar-এ বসানোর রিপোর্ট আইকন।
// groups  : কোন ক্যাটাগরির রিপোর্ট দেখাবে (নামের শুরু মিললেই চলে), যেমন ['Stock'], ['Sales']
// onlyKeys: শুধু নির্দিষ্ট রিপোর্ট দেখাবে, যেমন {'advance_orders'}
// দুটোই না দিলে সব রিপোর্ট দেখায়।
// ---------------------------------------------------------------
class ReportsIconButton extends StatelessWidget {
  final String token;
  final String title;
  final List<String>? groups;
  final Set<String>? onlyKeys;
  final IconData icon;

  const ReportsIconButton({
    super.key,
    required this.token,
    this.title = "রিপোর্ট",
    this.groups,
    this.onlyKeys,
    this.icon = Icons.bar_chart,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: title,
      icon: Icon(icon),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReportsHomeScreen(
              token: token,
              title: title,
              groups: groups,
              onlyKeys: onlyKeys,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------
// রিপোর্টের তালিকা (গ্রুপ অনুযায়ী, সার্চসহ)
// ---------------------------------------------------------------
class ReportsHomeScreen extends StatefulWidget {
  final String token;
  final String title;
  final List<String>? groups;
  final Set<String>? onlyKeys;

  const ReportsHomeScreen({
    super.key,
    required this.token,
    this.title = "রিপোর্ট",
    this.groups,
    this.onlyKeys,
  });

  @override
  State<ReportsHomeScreen> createState() => _ReportsHomeScreenState();
}

class _ReportsHomeScreenState extends State<ReportsHomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final scoped = widget.groups != null || widget.onlyKeys != null;
    final tiles = <Widget>[];

    for (final g in reportGroups) {
      if (widget.groups != null &&
          !widget.groups!.any((p) => g.title.startsWith(p))) {
        continue;
      }
      final list = g.reports
          .where((r) =>
              (widget.onlyKeys == null || widget.onlyKeys!.contains(r.key)) &&
              (q.isEmpty || r.title.toLowerCase().contains(q)))
          .toList();
      if (list.isEmpty) continue;

      tiles.add(
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            key: ValueKey("${g.title}-${q.isNotEmpty}-$scoped"),
            initiallyExpanded: q.isNotEmpty || scoped,
            leading: Icon(g.icon),
            title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${list.length} টি রিপোর্ট"),
            children: list
                .map(
                  (r) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.description_outlined, size: 20),
                    title: Text(r.title),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ReportViewerScreen(token: widget.token, def: r),
                        ),
                      );
                    },
                  ),
                )
                .toList(),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: "রিপোর্ট খুঁজুন (ইংরেজি নামে)",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: tiles.isEmpty
                ? const Center(child: Text("কোনো রিপোর্ট পাওয়া যায়নি"))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: tiles,
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// জেনেরিক রিপোর্ট ভিউয়ার।
// ব্যাকএন্ডের GET /report-data/<key> থেকে এই ফরম্যাটে ডেটা আশা করে:
// {
//   "columns": [{"key": "amount", "label": "বিক্রয় মূল্য", "type": "money"}],
//   "rows":    [{"amount": 250000}],
//   "totals":  {"amount": 250000}
// }
// type হতে পারে: text | number | money | percent | date
// ---------------------------------------------------------------
class ReportViewerScreen extends StatefulWidget {
  final String token;
  final ReportDef def;

  const ReportViewerScreen({super.key, required this.token, required this.def});

  @override
  State<ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends State<ReportViewerScreen> {
  static const Map<RFilter, String> _labels = {
    RFilter.dateRange: "তারিখ",
    RFilter.customer: "কাস্টমার",
    RFilter.supplier: "সাপ্লায়ার",
    RFilter.product: "প্রোডাক্ট",
    RFilter.warehouse: "শোরুম/গোডাউন",
    RFilter.brand: "ব্র্যান্ড",
    RFilter.category: "ক্যাটেগরি",
    RFilter.paymentMode: "পেমেন্ট মোড",
    RFilter.area: "এলাকা",
    RFilter.account: "একাউন্ট",
    RFilter.search: "চেসিস/ইঞ্জিন নম্বর",
    RFilter.days: "দিন",
  };

  static const Map<RFilter, String> _params = {
    RFilter.customer: "customer_id",
    RFilter.supplier: "supplier_id",
    RFilter.product: "product_id",
    RFilter.warehouse: "warehouse_id",
    RFilter.brand: "brand",
    RFilter.category: "category",
    RFilter.paymentMode: "payment_mode",
    RFilter.area: "area",
    RFilter.account: "account",
    RFilter.search: "q",
    RFilter.days: "days",
  };

  static const List<RFilter> _idFilters = [
    RFilter.customer,
    RFilter.supplier,
    RFilter.product,
    RFilter.warehouse,
  ];

  static const List<RFilter> _textFilters = [
    RFilter.brand,
    RFilter.category,
    RFilter.area,
    RFilter.account,
    RFilter.search,
    RFilter.days,
  ];

  DateTime? _from;
  DateTime? _to;
  final Map<RFilter, int?> _ids = {};
  String? _payment;
  final Map<RFilter, TextEditingController> _texts = {};

  List<dynamic> _customers = [];
  List<dynamic> _suppliers = [];
  List<dynamic> _products = [];
  List<dynamic> _warehouses = [];

  bool _loading = false;
  bool _loaded = false;
  bool _fromCache = false;
  String? _error;
  List<Map<String, dynamic>> _columns = [];
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _totals = {};

  @override
  void initState() {
    super.initState();
    _applyRange(widget.def.range);
    for (final f in _textFilters) {
      if (widget.def.filters.contains(f)) {
        _texts[f] = TextEditingController(
          text: f == RFilter.days ? "${widget.def.days ?? ''}" : '',
        );
      }
    }
    _loadOptions();
    if (widget.def.mustHave.isEmpty) {
      _run();
    }
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyRange(RRange r) {
    final now = DateTime.now();
    switch (r) {
      case RRange.today:
        _from = now;
        _to = now;
        break;
      case RRange.thisMonth:
        _from = DateTime(now.year, now.month, 1);
        _to = now;
        break;
      case RRange.thisYear:
        _from = DateTime(now.year, 1, 1);
        _to = now;
        break;
      case RRange.none:
        _from = null;
        _to = null;
        break;
    }
  }

  Future<void> _loadOptions() async {
    final f = widget.def.filters;
    final sync = SyncService();
    try {
      if (f.contains(RFilter.customer) || f.contains(RFilter.supplier)) {
        final r = await sync.getList("/parties", widget.token);
        if (!mounted) return;
        if (r["data"] is List) {
          final all = r["data"] as List;
          setState(() {
            _customers = all.where((p) => p["party_type"] == "customer").toList();
            _suppliers = all.where((p) => p["party_type"] == "supplier").toList();
          });
        }
      }
      if (f.contains(RFilter.product)) {
        final r = await sync.getList("/products", widget.token);
        if (!mounted) return;
        if (r["data"] is List) {
          setState(() => _products = r["data"] as List);
        }
      }
      if (f.contains(RFilter.warehouse)) {
        final r = await sync.getList("/warehouses", widget.token);
        if (!mounted) return;
        if (r["data"] is List) {
          setState(() => _warehouses = r["data"] as List);
        }
      }
    } catch (_) {
      // ড্রপডাউনের তালিকা না এলেও রিপোর্ট চালানো যাবে
    }
  }

  bool _isEmptyFilter(RFilter f) {
    if (f == RFilter.dateRange) return _from == null || _to == null;
    if (_idFilters.contains(f)) return _ids[f] == null;
    if (f == RFilter.paymentMode) return _payment == null;
    final c = _texts[f];
    return c == null || c.text.trim().isEmpty;
  }

  String _buildEndpoint() {
    final f = widget.def.filters;
    final q = <String, String>{};

    if (f.contains(RFilter.dateRange)) {
      if (_from != null) q['from'] = _fmtDate(_from!);
      if (_to != null) q['to'] = _fmtDate(_to!);
    }
    for (final x in _idFilters) {
      if (f.contains(x) && _ids[x] != null) q[_params[x]!] = "${_ids[x]}";
    }
    if (f.contains(RFilter.paymentMode) && _payment != null) {
      q['payment_mode'] = _payment!;
    }
    for (final x in _textFilters) {
      if (f.contains(x)) {
        final t = _texts[x]!.text.trim();
        if (t.isNotEmpty) q[_params[x]!] = t;
      }
    }

    final qs = q.entries
        .map((e) => "${e.key}=${Uri.encodeQueryComponent(e.value)}")
        .join('&');
    return "/report-data/${widget.def.key}${qs.isEmpty ? '' : '?$qs'}";
  }

  Future<void> _run() async {
    for (final f in widget.def.mustHave) {
      if (_isEmptyFilter(f)) {
        setState(() {
          _error = "${_labels[f]} বেছে নিন";
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await SyncService().getList(_buildEndpoint(), widget.token);
      if (!mounted) return;
      final data = res["data"];

      if (data is Map) {
        final cols = (data["columns"] as List? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        final rows = (data["rows"] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        final totals = data["totals"] is Map
            ? Map<String, dynamic>.from(data["totals"] as Map)
            : <String, dynamic>{};
        setState(() {
          _columns = cols;
          _rows = rows;
          _totals = totals;
          _fromCache = res["fromCache"] == true;
          _loaded = true;
        });
      } else {
        setState(() {
          _error =
              "রিপোর্ট আনা যায়নি। সংযোগ দেখুন, অথবা ব্যাকএন্ডে /report-data/${widget.def.key} এন্ডপয়েন্ট আছে কিনা পরীক্ষা করুন।";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "রিপোর্ট লোড করতে সমস্যা হয়েছে";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyCsv() async {
    final buf = StringBuffer();
    buf.writeln(_columns.map((c) => _csvEscape("${c['label']}")).join(','));
    for (final r in _rows) {
      buf.writeln(_columns
          .map((c) => _csvEscape(r[c['key']] == null ? '' : "${r[c['key']]}"))
          .join(','));
    }
    if (_totals.isNotEmpty) {
      buf.writeln(_columns.asMap().entries.map((e) {
        final key = "${e.value['key']}";
        if (_totals.containsKey(key)) return _csvEscape("${_totals[key]}");
        return e.key == 0 ? "মোট" : "";
      }).join(','));
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("CSV কপি হয়েছে — Excel বা Google Sheets-এ পেস্ট করুন")),
    );
  }

  // ---------------- ফিল্টার UI ----------------
  String _label(RFilter f) =>
      "${_labels[f]}${widget.def.mustHave.contains(f) ? ' *' : ''}";

  Widget _dateButton(String label, DateTime? value, void Function(DateTime) onPick) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today, size: 16),
      label: Text("$label: ${value == null ? '—' : _fmtDate(value)}"),
      onPressed: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (d != null) {
          setState(() => onPick(d));
        }
      },
    );
  }

  Widget _rangeChip(String label, RRange r) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        setState(() => _applyRange(r));
        _run();
      },
    );
  }

  Widget _idDropdown(RFilter f, List<dynamic> list, String nameKey) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<int>(
        initialValue: _ids[f],
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _label(f),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<int>(value: null, child: Text("সব")),
          ...list.map<DropdownMenuItem<int>>(
            (p) => DropdownMenuItem<int>(
              value: p["id"],
              child: Text("${p[nameKey]}", overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (v) => setState(() => _ids[f] = v),
      ),
    );
  }

  Widget _buildFilters() {
    final f = widget.def.filters;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (f.contains(RFilter.dateRange)) ...[
              _rangeChip("আজ", RRange.today),
              _rangeChip("এই মাস", RRange.thisMonth),
              _rangeChip("এই বছর", RRange.thisYear),
              _dateButton("থেকে", _from, (d) => _from = d),
              _dateButton("পর্যন্ত", _to, (d) => _to = d),
            ],
            if (f.contains(RFilter.customer))
              _idDropdown(RFilter.customer, _customers, 'name'),
            if (f.contains(RFilter.supplier))
              _idDropdown(RFilter.supplier, _suppliers, 'name'),
            if (f.contains(RFilter.product))
              _idDropdown(RFilter.product, _products, 'model_name'),
            if (f.contains(RFilter.warehouse))
              _idDropdown(RFilter.warehouse, _warehouses, 'name'),
            if (f.contains(RFilter.paymentMode))
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: _payment,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _label(RFilter.paymentMode),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem<String>(value: null, child: Text("সব")),
                    DropdownMenuItem<String>(value: "cash", child: Text("নগদ")),
                    DropdownMenuItem<String>(value: "due", child: Text("বাকি")),
                  ],
                  onChanged: (v) => setState(() => _payment = v),
                ),
              ),
            for (final t in _textFilters)
              if (f.contains(t))
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _texts[t],
                    keyboardType:
                        t == RFilter.days ? TextInputType.number : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: _label(t),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _run(),
                  ),
                ),
            ElevatedButton.icon(
              onPressed: _loading ? null : _run,
              icon: const Icon(Icons.search),
              label: const Text("রিপোর্ট দেখুন"),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- টেবিল ----------------
  Widget _buildTable() {
    final cols = _columns;
    final hasTotals = _totals.isNotEmpty;

    String typeOf(Map<String, dynamic> c) => "${c['type'] ?? 'text'}";

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(Colors.blue.shade50),
          columns: [
            for (final c in cols)
              DataColumn(
                numeric: _isNumericType(typeOf(c)),
                label: Text(
                  "${c['label']}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
          rows: [
            for (final r in _rows)
              DataRow(
                cells: [
                  for (final c in cols)
                    DataCell(Text(_fmtCell(r[c['key']], typeOf(c)))),
                ],
              ),
            if (hasTotals)
              DataRow(
                color: WidgetStatePropertyAll(Colors.grey.shade200),
                cells: [
                  for (int i = 0; i < cols.length; i++)
                    DataCell(
                      Text(
                        _totals.containsKey(cols[i]['key'])
                            ? _fmtCell(_totals[cols[i]['key']], typeOf(cols[i]))
                            : (i == 0 ? "মোট" : ""),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _run, child: const Text("আবার চেষ্টা করুন")),
            ],
          ),
        ),
      );
    }
    if (!_loaded) {
      return Center(
        child: Text(
          _loading ? "" : "ফিল্টার বেছে \"রিপোর্ট দেখুন\" চাপুন",
          style: const TextStyle(color: Colors.black54),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(child: Text("এই ফিল্টারে কোনো তথ্য নেই"));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text("${_rows.length} টি সারি",
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ),
        Expanded(child: _buildTable()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.def.title),
        actions: [
          IconButton(
            tooltip: "CSV কপি করুন (Excel-এ পেস্ট করা যাবে)",
            icon: const Icon(Icons.copy_all),
            onPressed: _rows.isEmpty ? null : _copyCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          if (_fromCache)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.amber.shade100,
              child: const Text(
                "অফলাইন — সর্বশেষ সংরক্ষিত রিপোর্ট দেখানো হচ্ছে",
                style: TextStyle(fontSize: 13),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}
