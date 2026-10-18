import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'partner_screen.dart';

// ---------------------------------------------------------------
// সাহায্যকারী
// ---------------------------------------------------------------
num _n(dynamic v) => v is num ? v : (num.tryParse("$v") ?? 0);

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => "${d.year}-${_two(d.month)}-${_two(d.day)}";

/// লাখ-কোটি গ্রুপিংসহ টাকা: ৳12,34,567
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

const Map<String, String> _typeLabel = {
  "invest": "বিনিয়োগ নেওয়া হয়েছে",
  "profit": "লাভ / রিটার্ন দেওয়া হয়েছে",
  "withdraw": "মূল টাকা ফেরত দেওয়া হয়েছে",
};

const Map<String, String> _modeLabel = {
  "cash": "নগদ",
  "bank": "ব্যাংক",
  "other": "অন্যান্য",
};

Color _typeColor(String t) {
  switch (t) {
    case "invest":
      return const Color(0xFF0E7A3E);
    case "profit":
      return const Color(0xFF1E6BFF);
    default:
      return const Color(0xFFB35C00);
  }
}

IconData _typeIcon(String t) {
  switch (t) {
    case "invest":
      return Icons.arrow_downward;
    case "profit":
      return Icons.trending_up;
    default:
      return Icons.arrow_upward;
  }
}

// ---------------------------------------------------------------
// বিনিয়োগকারীদের তালিকা
// ---------------------------------------------------------------
class InvestorListScreen extends StatefulWidget {
  final String token;

  const InvestorListScreen({super.key, required this.token});

  @override
  State<InvestorListScreen> createState() => _InvestorListScreenState();
}

class _InvestorListScreenState extends State<InvestorListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _list = [];
  String _search = "";

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
      final res = await http.get(Uri.parse("$apiBaseUrl/investors"), headers: _headers(widget.token));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _list = (_json(res) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      } else {
        setState(() {
          _error = _detail(res, "তালিকা আনতে সমস্যা হয়েছে");
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

  Future<void> _openForm({Map<String, dynamic>? investor}) async {
    final ok = await showInvestorForm(context, widget.token, investor: investor);
    if (ok == true) _load();
  }

  Future<void> _openDetail(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvestorDetailScreen(token: widget.token, investorId: id),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final shown = q.isEmpty
        ? _list
        : _list.where((i) => "${i['name']} ${i['phone'] ?? ''}".toLowerCase().contains(q)).toList();

    num principal = 0, profit = 0, invested = 0;
    for (final i in _list) {
      principal += _n(i["principal_balance"]);
      profit += _n(i["profit_paid"]);
      invested += _n(i["invested"]);
    }

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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DDB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("বিনিয়োগকারীদের কাছে এখন মূল টাকা বাকি", style: TextStyle(color: Colors.white70)),
                Text(
                  _money(principal),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  "${_list.length} জন • মোট বিনিয়োগ ${_money(invested)} • লাভ/রিটার্ন দেওয়া ${_money(profit)}",
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              hintText: "নাম বা ফোন দিয়ে খুঁজুন",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() {
              _search = v;
            }),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text("কোনো বিনিয়োগকারী নেই। নিচের বাটনে নতুন যোগ করুন।")),
            ),
          for (final i in shown)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: () => _openDetail(i["id"] as int),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE6DAFB),
                  child: Icon(Icons.person, color: Color(0xFF7C4DDB)),
                ),
                title: Text("${i['name']}", style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  "${i['phone'] ?? '-'}\n"
                  "বিনিয়োগ ${_money(i['invested'])} • লাভ দেওয়া ${_money(i['profit_paid'])}",
                ),
                isThreeLine: true,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(i['principal_balance']),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const Text("মূল বাকি", style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("বিনিয়োগকারী"),
        actions: [
          IconButton(tooltip: "রিফ্রেশ", icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add),
        label: const Text("নতুন বিনিয়োগকারী"),
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

/// নতুন বিনিয়োগকারী যোগ বা এডিটের ডায়ালগ। সফল হলে true ফেরত দেয়।
Future<bool?> showInvestorForm(BuildContext context, String token, {Map<String, dynamic>? investor}) {
  final nameC = TextEditingController(text: "${investor?['name'] ?? ''}");
  final phoneC = TextEditingController(text: "${investor?['phone'] ?? ''}");
  final addrC = TextEditingController(text: "${investor?['address'] ?? ''}");
  final noteC = TextEditingController(text: "${investor?['note'] ?? ''}");
  String? err;
  bool busy = false;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(investor == null ? "নতুন বিনিয়োগকারী" : "তথ্য এডিট"),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
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
                const SizedBox(height: 12),
                TextField(
                  controller: addrC,
                  decoration: const InputDecoration(labelText: "ঠিকানা (ঐচ্ছিক)", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteC,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "নোট (যেমন: লাভের শর্ত, মেয়াদ)",
                    border: OutlineInputBorder(),
                  ),
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
          TextButton(
            onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
            child: const Text("বাতিল"),
          ),
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
                      final body = jsonEncode({
                        "name": nameC.text.trim(),
                        "phone": phoneC.text.trim(),
                        "address": addrC.text.trim(),
                        "note": noteC.text.trim(),
                      });
                      final res = investor == null
                          ? await http.post(Uri.parse("$apiBaseUrl/investors"), headers: _headers(token), body: body)
                          : await http.patch(Uri.parse("$apiBaseUrl/investors/${investor['id']}"),
                              headers: _headers(token), body: body);
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
}

// ---------------------------------------------------------------
// একজন বিনিয়োগকারীর বিস্তারিত ও লেনদেনের তালিকা
// ---------------------------------------------------------------
class InvestorDetailScreen extends StatefulWidget {
  final String token;
  final int investorId;

  const InvestorDetailScreen({super.key, required this.token, required this.investorId});

  @override
  State<InvestorDetailScreen> createState() => _InvestorDetailScreenState();
}

class _InvestorDetailScreenState extends State<InvestorDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _d;

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
      final res = await http.get(
        Uri.parse("$apiBaseUrl/investors/${widget.investorId}"),
        headers: _headers(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _d = Map<String, dynamic>.from(_json(res) as Map);
        });
      } else {
        setState(() {
          _error = _detail(res, "তথ্য আনা যায়নি");
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

  Future<void> _addEntry(String type) async {
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    DateTime date = DateTime.now();
    String mode = "cash";
    String? err;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(_typeLabel[type] ?? ""),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (type == "withdraw")
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text("এখন মূল টাকা বাকি: ${_money(_d?['principal_balance'])}"),
                    ),
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
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setD(() => date = d);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: "কীভাবে", border: OutlineInputBorder()),
                    items: _modeLabel.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
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
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
              child: const Text("বাতিল"),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final a = int.tryParse(amountC.text.trim());
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
                          Uri.parse("$apiBaseUrl/investors/${widget.investorId}/entries"),
                          headers: _headers(widget.token),
                          body: jsonEncode({
                            "entry_type": type,
                            "amount": a,
                            "entry_date": _fmtDate(date),
                            "mode": mode,
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
              child: const Text("সংরক্ষণ"),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _snack("সংরক্ষণ হয়েছে", color: Colors.green);
      _load();
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("লেনদেন মুছবেন?"),
        content: Text("${_typeLabel[e['entry_type']] ?? ''}: ${_money(e['amount'])} (${e['entry_date']})"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("না")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("মুছুন", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await http.delete(
        Uri.parse("$apiBaseUrl/investor-entries/${e['id']}"),
        headers: _headers(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _snack("মুছে ফেলা হয়েছে");
        _load();
      } else {
        _snack(_detail(res, "মুছা যায়নি"), color: Colors.red);
      }
    } catch (_) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    }
  }

  Future<void> _deleteInvestor() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("বিনিয়োগকারী মুছবেন?"),
        content: Text("\"${_d?['name']}\" মুছে যাবে। (লেনদেন থাকলে মোছা যাবে না)"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("না")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("মুছুন", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await http.delete(
        Uri.parse("$apiBaseUrl/investors/${widget.investorId}"),
        headers: _headers(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.of(context).pop();
      } else {
        _snack(_detail(res, "মুছা যায়নি"), color: Colors.red);
      }
    } catch (_) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
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
      final entries = (d["entries"] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFF3EEFD),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${d['name']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (d['phone'] != null) Text("ফোন: ${d['phone']}"),
                  if (d['address'] != null) Text("ঠিকানা: ${d['address']}"),
                  if (d['note'] != null) ...[
                    const SizedBox(height: 6),
                    Text("নোট: ${d['note']}", style: const TextStyle(color: Colors.black87)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _stat("মোট বিনিয়োগ", _money(d['invested']), const Color(0xFF0E7A3E)),
              _stat("মূল টাকা ফেরত", _money(d['withdrawn']), const Color(0xFFB35C00)),
              _stat("মূল টাকা বাকি", _money(d['principal_balance']), Colors.black87),
              _stat("লাভ/রিটার্ন দেওয়া", _money(d['profit_paid']), const Color(0xFF1E6BFF)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () => _addEntry("invest"),
                icon: const Icon(Icons.add),
                label: const Text("বিনিয়োগ নিন"),
              ),
              OutlinedButton.icon(
                onPressed: () => _addEntry("profit"),
                icon: const Icon(Icons.trending_up),
                label: const Text("লাভ / রিটার্ন দিন"),
              ),
              OutlinedButton.icon(
                onPressed: () => _addEntry("withdraw"),
                icon: const Icon(Icons.undo),
                label: const Text("মূল টাকা ফেরত দিন"),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text("লেনদেনের তালিকা", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text("এখনো কোনো লেনদেন নেই"),
            ),
          for (final e in entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: _typeColor("${e['entry_type']}").withValues(alpha: 0.15),
                  child: Icon(_typeIcon("${e['entry_type']}"), size: 16, color: _typeColor("${e['entry_type']}")),
                ),
                title: Text(
                  "${_typeLabel[e['entry_type']] ?? ''} — ${_money(e['amount'])}",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  "${e['entry_date'] ?? ''} | ${_modeLabel[e['mode']] ?? ''}"
                  "${e['note'] != null ? '\n${e['note']}' : ''}",
                ),
                trailing: IconButton(
                  tooltip: "মুছুন",
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => _deleteEntry(e),
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(d == null ? "বিনিয়োগকারী" : "${d['name']}"),
        actions: [
          if (d != null)
            IconButton(
              tooltip: "তথ্য এডিট",
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final ok = await showInvestorForm(context, widget.token, investor: d);
                if (ok == true) _load();
              },
            ),
          if (d != null)
            IconButton(
              tooltip: "বিনিয়োগকারী মুছুন",
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: _deleteInvestor,
            ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}