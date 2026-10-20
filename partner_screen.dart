import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';

// ---------------------------------------------------------------
// সাহায্যকারী
// ---------------------------------------------------------------
num _n(dynamic v) => v is num ? v : (num.tryParse("$v") ?? 0);

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => "${d.year}-${_two(d.month)}-${_two(d.day)}";

String _money(dynamic v) {
  final num n = v is num ? v : (num.tryParse("$v") ?? 0);
  final digits = n.abs().round().toString();
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
  return "${n < 0 ? '-' : ''}৳$grouped";
}

Map<String, String> _headers(String token) => {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };

dynamic _json(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

String _detail(http.Response r, String fallback) {
  try {
    final d = _json(r);
    if (d is Map && d["detail"] is String) return d["detail"] as String;
  } catch (_) {}
  return fallback;
}

List<Map<String, dynamic>> _asList(dynamic v) =>
    (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

// ---------------------------------------------------------------
// পার্টনার হিসাব + রানারের পাওনা গাড়ী
// ---------------------------------------------------------------
class PartnerScreen extends StatefulWidget {
  final String token;

  const PartnerScreen({super.key, required this.token});

  @override
  State<PartnerScreen> createState() => _PartnerScreenState();
}

class _PartnerScreenState extends State<PartnerScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _partners = [];
  Map<String, dynamic> _runner = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        http.get(Uri.parse("$apiBaseUrl/partners"), headers: _headers(widget.token)),
        http.get(Uri.parse("$apiBaseUrl/runner-summary"), headers: _headers(widget.token)),
      ]);
      if (!mounted) return;
      if (res[0].statusCode == 200 && res[1].statusCode == 200) {
        setState(() {
          _partners = _asList(_json(res[0]));
          _runner = Map<String, dynamic>.from(_json(res[1]) as Map);
        });
      } else {
        setState(() {
          _error = _detail(res.firstWhere((r) => r.statusCode != 200), "তথ্য আনতে সমস্যা হয়েছে");
        });
      }
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

  Future<void> _addPartner() async {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    String? err;
    bool busy = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("নতুন পার্টনার"),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: "নাম", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneC,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: "ফোন (ঐচ্ছিক)", border: OutlineInputBorder()),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.of(ctx).pop(false), child: const Text("বাতিল")),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (nameC.text.trim().isEmpty) {
                        setD(() => err = "নাম লিখুন");
                        return;
                      }
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        final res = await http.post(
                          Uri.parse("$apiBaseUrl/partners"),
                          headers: _headers(widget.token),
                          body: jsonEncode({"name": nameC.text.trim(), "phone": phoneC.text.trim()}),
                        );
                        if (!ctx.mounted) return;
                        if (res.statusCode == 200) {
                          Navigator.of(ctx).pop(true);
                        } else {
                          setD(() {
                            busy = false;
                            err = _detail(res, "সংরক্ষণ করা যায়নি");
                          });
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setD(() {
                          busy = false;
                          err = "সার্ভারের সাথে সংযোগ করা যায়নি";
                        });
                      }
                    },
              child: const Text("সংরক্ষণ"),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _openDetail(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PartnerDetailScreen(token: widget.token, partnerId: id)),
    );
    if (mounted) _load();
  }

  Widget _runnerCard() {
    final suppliers = _asList(_runner["suppliers"] ?? []);
    final monthly = _asList(_runner["monthly"] ?? []);
    final recent = _asList(_runner["recent_days"] ?? []);
    num pending = 0;
    for (final s in suppliers) {
      pending += _n(s["pending"]);
    }
    return Card(
      color: const Color(0xFFEFF4FF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("রানার থেকে আর কত গাড়ী পাওয়া বাকি", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("$pending টি", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            for (final s in suppliers)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  "${s['supplier_name'] ?? '-'}: অর্ডার ${s['ordered']} • এসেছে ${s['received']} • বাকি ${s['pending']}",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            if (suppliers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text("কোনো চলমান অর্ডার নেই। \"সাপ্লায়ার অর্ডার\" থেকে অর্ডার দিন।",
                    style: TextStyle(fontSize: 13)),
              ),
            if (monthly.isNotEmpty || recent.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text("মাস ও দিন অনুযায়ী", style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                children: [
                  for (final m in monthly)
                    ListTile(
                      dense: true,
                      title: Text("${m['month']}"),
                      trailing: Text("অর্ডার ${m['ordered']} • এসেছে ${m['received']}"),
                    ),
                  if (recent.isNotEmpty) const Divider(),
                  if (recent.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text("গত ১৪ দিনের ডেলিভারি", style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  for (final d in recent)
                    ListTile(
                      dense: true,
                      title: Text("${d['date']}"),
                      trailing: Text("${d['count']} টি"),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _runnerCard(),
          const SizedBox(height: 14),
          const Text("পার্টনারদের হিসাব (রানারের কাছে অগ্রিম)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_partners.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text("কোনো পার্টনার নেই। নিচের বাটনে যোগ করুন।")),
            ),
          for (final p in _partners)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: () => _openDetail(p["id"] as int),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE6DAFB),
                  child: Icon(Icons.handshake_outlined, color: Color(0xFF7C4DDB)),
                ),
                title: Text("${p['name']}", style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  "জমা ${_money(p['deposited'])}\n"
                  "বিক্রি ${p['units_sold']} টি (${_money(p['sold_value'])})",
                ),
                isThreeLine: true,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(p['balance']),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: _n(p['balance']) < 0 ? Colors.red : Colors.black87,
                      ),
                    ),
                    const Text("বাকি অগ্রিম", style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("পার্টনার হিসাব"),
        actions: [
          IconButton(tooltip: "রিফ্রেশ", icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPartner,
        icon: const Icon(Icons.person_add),
        label: const Text("নতুন পার্টনার"),
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

// ---------------------------------------------------------------
// একজন পার্টনারের খাতা
// ---------------------------------------------------------------
class PartnerDetailScreen extends StatefulWidget {
  final String token;
  final int partnerId;

  const PartnerDetailScreen({super.key, required this.token, required this.partnerId});

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        http.get(Uri.parse("$apiBaseUrl/partners/${widget.partnerId}"), headers: _headers(widget.token)),
        http.get(Uri.parse("$apiBaseUrl/parties"), headers: _headers(widget.token)),
      ]);
      if (!mounted) return;
      if (res[0].statusCode == 200 && res[1].statusCode == 200) {
        setState(() {
          _d = Map<String, dynamic>.from(_json(res[0]) as Map);
          _suppliers = _asList(_json(res[1])).where((p) => p["party_type"] == "supplier").toList();
        });
      } else {
        setState(() {
          _error = _detail(res.firstWhere((r) => r.statusCode != 200), "তথ্য আনা যায়নি");
        });
      }
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

  Future<void> _addAdvance() async {
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    DateTime date = DateTime.now();
    int? supplierId = _suppliers.length == 1 ? _suppliers.first["id"] as int : null;
    String mode = "cash";
    String? err;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text("${_d?['name']}-এর পক্ষ থেকে রানারকে অগ্রিম"),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: "রানার / সাপ্লায়ার", border: OutlineInputBorder()),
                    items: _suppliers
                        .map<DropdownMenuItem<int>>((s) => DropdownMenuItem<int>(
                              value: s["id"] as int,
                              child: Text("${s['name']}"),
                            ))
                        .toList(),
                    onChanged: (v) => setD(() => supplierId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "টাকার পরিমাণ", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text("তারিখ: ${_fmtDate(date)}"),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setD(() => date = d);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: "কোথা থেকে দিলেন", border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: "cash", child: Text("নগদ (ক্যাশ)")),
                      DropdownMenuItem(value: "bank", child: Text("ব্যাংক")),
                    ],
                    onChanged: (v) => setD(() => mode = v ?? "cash"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteC,
                    decoration: const InputDecoration(labelText: "নোট (ঐচ্ছিক)", border: OutlineInputBorder()),
                  ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err!, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.of(ctx).pop(false), child: const Text("বাতিল")),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final a = int.tryParse(amountC.text.trim());
                      if (supplierId == null) {
                        setD(() => err = "রানার বেছে নিন");
                        return;
                      }
                      if (a == null || a <= 0) {
                        setD(() => err = "সঠিক পরিমাণ দিন");
                        return;
                      }
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        final res = await http.post(
                          Uri.parse("$apiBaseUrl/partners/${widget.partnerId}/advances"),
                          headers: _headers(widget.token),
                          body: jsonEncode({
                            "supplier_id": supplierId,
                            "amount": a,
                            "adv_date": _fmtDate(date),
                            "payment_mode": mode,
                            "note": noteC.text.trim().isEmpty ? null : noteC.text.trim(),
                          }),
                        );
                        if (!ctx.mounted) return;
                        if (res.statusCode == 200) {
                          Navigator.of(ctx).pop(true);
                        } else {
                          setD(() {
                            busy = false;
                            err = _detail(res, "সংরক্ষণ করা যায়নি");
                          });
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setD(() {
                          busy = false;
                          err = "সার্ভারের সাথে সংযোগ করা যায়নি";
                        });
                      }
                    },
              child: const Text("অগ্রিম দিন"),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _snack("অগ্রিম জমা হয়েছে", color: Colors.green);
      _load();
    }
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E3F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null || d == null) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error ?? "তথ্য পাওয়া যায়নি", style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text("আবার চেষ্টা করুন")),
          ],
        ),
      );
    } else {
      final entries = _asList(d["entries"] ?? []);
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _stat("মোট অগ্রিম জমা", _money(d['deposited']), const Color(0xFF0E7A3E)),
              _stat("বিক্রি গাড়ী", "${d['units_sold']} টি", Colors.black87),
              _stat("বিক্রয়মূল্য কাটা", _money(d['sold_value']), const Color(0xFFB35C00)),
              _stat("বাকি অগ্রিম", _money(d['balance']), _n(d['balance']) < 0 ? Colors.red : Colors.black87),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _addAdvance,
            icon: const Icon(Icons.add),
            label: const Text("রানারকে অগ্রিম দিন"),
          ),
          const SizedBox(height: 18),
          const Text("খাতা (নতুন আগে)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          if (entries.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text("এখনো কোনো লেনদেন নেই")),
          for (final e in entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: (e['type'] == 'deposit' ? const Color(0xFF0E7A3E) : const Color(0xFFB35C00))
                      .withValues(alpha: 0.15),
                  child: Icon(
                    e['type'] == 'deposit' ? Icons.arrow_downward : Icons.two_wheeler,
                    size: 16,
                    color: e['type'] == 'deposit' ? const Color(0xFF0E7A3E) : const Color(0xFFB35C00),
                  ),
                ),
                title: Text(
                  "${e['type'] == 'deposit' ? '+' : '−'} ${_money(e['amount'])}",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: e['type'] == 'deposit' ? const Color(0xFF0E7A3E) : const Color(0xFFB35C00),
                  ),
                ),
                subtitle: Text("${e['date'] ?? ''}\n${e['text'] ?? ''}"),
                isThreeLine: true,
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? "পার্টনার" : "${d['name']}"),
        actions: [
          IconButton(tooltip: "রিফ্রেশ", icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}