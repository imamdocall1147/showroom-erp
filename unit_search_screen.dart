import 'package:flutter/material.dart';
import 'sync_service.dart';

/// গাড়ী খুঁজুন: চেসিস, ইঞ্জিন নম্বর, মডেল বা রঙ লিখে স্টকের ও বিক্রি হয়ে যাওয়া গাড়ী খোঁজা।
class UnitSearchScreen extends StatefulWidget {
  final String token;

  const UnitSearchScreen({super.key, required this.token});

  @override
  State<UnitSearchScreen> createState() => _UnitSearchScreenState();
}

class _UnitSearchScreenState extends State<UnitSearchScreen> {
  final _searchC = TextEditingController();
  bool _loading = true;
  String? _error;
  bool _fromCache = false;
  String _query = "";
  String _filter = "all"; // all | in_stock | sold
  List<Map<String, dynamic>> _units = [];
  Map<dynamic, String> _productNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse("$v");
    if (n == null) return "-";
    final s = n.abs().round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return "${n < 0 ? '-' : ''}৳$b";
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sync = SyncService();
      final stockRes = await sync.getList("/units?status=in_stock", widget.token);
      Map<String, dynamic>? soldRes;
      try {
        soldRes = await sync.getList("/units?status=sold", widget.token);
      } catch (_) {
        soldRes = null;
      }
      Map<String, dynamic>? prodRes;
      try {
        prodRes = await sync.getList("/products", widget.token);
      } catch (_) {
        prodRes = null;
      }
      if (!mounted) return;

      if (stockRes["data"] is! List) {
        setState(() {
          _error = "গাড়ীর তালিকা আনা যায়নি";
        });
        return;
      }

      final names = <dynamic, String>{};
      if (prodRes != null && prodRes["data"] is List) {
        for (final p in prodRes["data"] as List) {
          names[p["id"]] = "${p["model_name"] ?? ''}";
        }
      }

      final byKey = <String, Map<String, dynamic>>{};
      void addAll(dynamic list, String fallbackStatus) {
        if (list is! List) return;
        for (final raw in list) {
          if (raw is! Map) continue;
          final u = Map<String, dynamic>.from(raw);
          final hasStatus = u["status"] != null;
          u["status"] ??= fallbackStatus;
          final key = "${u["id"] ?? u["unit_id"] ?? u["chassis_no"]}";
          if (!byKey.containsKey(key) || hasStatus) {
            byKey[key] = u;
          }
        }
      }

      addAll(stockRes["data"], "in_stock");
      if (soldRes != null) addAll(soldRes["data"], "sold");

      setState(() {
        _units = byKey.values.toList();
        _productNames = names;
        _fromCache = stockRes["fromCache"] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "সার্ভারের সাথে সংযোগ করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _modelOf(Map<String, dynamic> u) {
    final direct = u["model"] ?? u["model_name"];
    if (direct != null && "$direct".isNotEmpty) return "$direct";
    return _productNames[u["product_id"]] ?? "";
  }

  String _brandOf(Map<String, dynamic> u) => "${u["brand"] ?? ''}";

  List<Map<String, dynamic>> get _results {
    final q = _query.trim().toLowerCase();
    return _units.where((u) {
      if (_filter != "all" && u["status"] != _filter) return false;
      if (q.isEmpty) return true;
      final text = "${u["chassis_no"] ?? ''} ${u["engine_no"] ?? ''} ${_brandOf(u)} "
              "${_modelOf(u)} ${u["color"] ?? ''} ${u["warehouse"] ?? ''} ${u["gate_pass_no"] ?? ''}"
          .toLowerCase();
      return text.contains(q);
    }).toList();
  }

  Widget _statusChip(String status) {
    final sold = status == "sold";
    final bg = sold ? const Color(0xFFFFE0B2) : const Color(0xFFC9F2D8);
    final fg = sold ? const Color(0xFFB35C00) : const Color(0xFF0E7A3E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        sold ? "বিক্রি হয়েছে" : "স্টকে আছে",
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> u) {
    final rows = <List<String>>[
      ["মডেল", "${_brandOf(u)} ${_modelOf(u)}".trim()],
      ["চেসিস নম্বর", "${u["chassis_no"] ?? '-'}"],
      ["ইঞ্জিন নম্বর", "${u["engine_no"] ?? '-'}"],
      ["রঙ", "${u["color"] ?? '-'}"],
      if (u["year"] != null) ["বছর", "${u["year"]}"],
      if (u["gate_pass_no"] != null && "${u["gate_pass_no"]}".isNotEmpty)
        ["গেট পাস নং", "${u["gate_pass_no"]}"],
      if (u["warehouse"] != null) ["গোডাউন", "${u["warehouse"]}"],
      if (u["purchase_price"] != null) ["ক্রয় মূল্য", _money(u["purchase_price"])],
      if (u["sold_price"] != null) ["বিক্রয় মূল্য", _money(u["sold_price"])],
      if (u["sold_date"] != null) ["বিক্রয়ের তারিখ", "${u["sold_date"]}".split('T').first],
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text("গাড়ীর তথ্য")),
            _statusChip("${u["status"]}"),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(r[0], style: const TextStyle(color: Colors.black54)),
                      ),
                      Expanded(
                        child: Text(r[1], style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("বন্ধ করুন"),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: selected,
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFF1E6BFF),
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: selected ? const Color(0xFF1E6BFF) : const Color(0xFFD9E3F3),
      ),
      onSelected: (_) => setState(() {
        _filter = value;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text("আবার চেষ্টা করুন")),
          ],
        ),
      );
    } else if (results.isEmpty) {
      body = const Center(child: Text("কোনো গাড়ী পাওয়া যায়নি"));
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: results.length,
        itemBuilder: (context, i) {
          final u = results[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => _showDetail(u),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F0FB),
                child: Icon(Icons.two_wheeler, color: Color(0xFF1E6BFF)),
              ),
              title: Text(
                "${_brandOf(u)} ${_modelOf(u)}".trim().isEmpty
                    ? "${u["chassis_no"] ?? '-'}"
                    : "${_brandOf(u)} ${_modelOf(u)}".trim(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                "চেসিস: ${u["chassis_no"] ?? '-'}\n"
                "ইঞ্জিন: ${u["engine_no"] ?? '-'} | রঙ: ${u["color"] ?? '-'}"
                "${u["gate_pass_no"] != null && "${u["gate_pass_no"]}".isNotEmpty ? '\nগেট পাস: ${u["gate_pass_no"]}' : ''}",
              ),
              isThreeLine: true,
              trailing: _statusChip("${u["status"]}"),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("গাড়ী খুঁজুন"),
        actions: [
          IconButton(tooltip: "রিফ্রেশ", icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (_fromCache)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.amber.shade100,
              child: const Text(
                "অফলাইন — সর্বশেষ সংরক্ষিত তালিকা থেকে খোঁজা হচ্ছে",
                style: TextStyle(fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchC,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "চেসিস, ইঞ্জিন নম্বর, মডেল বা রঙ লিখুন",
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: "মুছুন",
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchC.clear();
                          setState(() {
                            _query = "";
                          });
                        },
                      ),
              ),
              onChanged: (v) => setState(() {
                _query = v;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  _filterChip("all", "সব"),
                  _filterChip("in_stock", "স্টকে আছে"),
                  _filterChip("sold", "বিক্রি হয়েছে"),
                ],
              ),
            ),
          ),
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "${results.length} টি গাড়ী",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
