import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'invoice_screen.dart';

/// স্টক ট্রান্সফার: এক শোরুম/গোডাউন থেকে অন্য শোরুমে গাড়ী পাঠানো।
/// পাঠালে গাড়ীটা সাথে সাথে গন্তব্য শোরুমের স্টকে যায়, সেখান থেকে সাধারণ বিক্রয় চলে।
/// প্রতিটা গাড়ীর জন্য আলাদা মেমো (এডিট ও প্রিন্ট করা যায়)।
class StockTransferScreen extends StatefulWidget {
  final String token;

  const StockTransferScreen({super.key, required this.token});

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  bool _loading = true;
  bool _sending = false;
  String? _error;

  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _targets = [];
  List<Map<String, dynamic>> _history = [];

  final Set<int> _selected = {};
  int? _targetId;
  String _search = "";
  final _searchC = TextEditingController();
  final _noteC = TextEditingController();

  Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchC.dispose();
    _noteC.dispose();
    super.dispose();
  }

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        http.get(Uri.parse("$apiBaseUrl/reports/stock"), headers: _headers),
        http.get(Uri.parse("$apiBaseUrl/transfer-targets"), headers: _headers),
        http.get(Uri.parse("$apiBaseUrl/stock-transfers"), headers: _headers),
      ]);
      if (!mounted) return;
      if (res[0].statusCode == 200 && res[1].statusCode == 200 && res[2].statusCode == 200) {
        final stock = _json(res[0]);
        setState(() {
          _units = _asList(stock["units"]);
          _targets = _asList(_json(res[1]));
          _history = _asList(_json(res[2]));
          _selected.removeWhere((id) => !_units.any((u) => u["unit_id"] == id));
        });
      } else {
        setState(() {
          _error = _detail(
            res.firstWhere((r) => r.statusCode != 200),
            "তথ্য আনতে সমস্যা হয়েছে",
          );
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

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ---------------- মেমো ----------------
  Future<void> _openMemo(String batch, Map<String, dynamic> u, String target,
      {DateTime? date}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceScreen(
          invoiceTitle: "স্টক ট্রান্সফার মেমো",
          invoiceNumber: batch,
          storageKey: "transfer_${batch}_${u['chassis_no']}",
          date: date ?? DateTime.now(),
          partyName: target,
          items: const [],
          paymentMode: "cash",
          totalAmount: 0,
          hideAmounts: true,
          chassisNo: "${u['chassis_no'] ?? ''}",
          engineNo: "${u['engine_no'] ?? ''}",
          productName: "${u['brand'] ?? ''} ${u['model'] ?? ''}".trim(),
          note: "উক্ত গাড়িটি শোরুম থেকে শোরুমে পাঠানো হলো",
        ),
      ),
    );
  }

  Future<void> _afterTransfer(
      String batch, List<Map<String, dynamic>> units, String target) async {
    if (!mounted || units.isEmpty) return;
    if (units.length == 1) {
      await _openMemo(batch, units.first, target);
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("মেমো ছাপুন (${units.length} টি গাড়ী)"),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: units
                .map((u) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.receipt_long),
                      title: Text("${u['brand'] ?? ''} ${u['model'] ?? ''}".trim()),
                      subtitle: Text("চেসিস: ${u['chassis_no']}"),
                      onTap: () => _openMemo(batch, u, target),
                    ))
                .toList(),
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

  List<Map<String, dynamic>> get _shown {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _units;
    return _units.where((u) {
      final text = "${u['chassis_no'] ?? ''} ${u['engine_no'] ?? ''} ${u['brand'] ?? ''} "
              "${u['model'] ?? ''} ${u['color'] ?? ''} ${u['warehouse'] ?? ''}"
          .toLowerCase();
      return text.contains(q);
    }).toList();
  }

  String _targetLabel(Map<String, dynamic> t) => "${t["branch_name"] ?? '-'} — ${t["name"]}";

  Future<void> _send() async {
    if (_selected.isEmpty) {
      _snack("অন্তত একটা গাড়ী বেছে নিন", color: Colors.orange);
      return;
    }
    if (_targetId == null) {
      _snack("কোথায় পাঠাবেন সেই গোডাউন বেছে নিন", color: Colors.orange);
      return;
    }
    final target = _targets.firstWhere((t) => t["id"] == _targetId);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ট্রান্সফার নিশ্চিত করুন"),
        content: Text(
          "${_selected.length} টি গাড়ী\n\"${_targetLabel(target)}\"-এ পাঠানো হবে।\n\n"
          "পাঠালে গাড়ীগুলো এই শোরুমের স্টক থেকে বাদ যাবে এবং ওই শোরুমের স্টকে যাবে।",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("না")),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("পাঠান")),
        ],
      ),
    );
    if (ok != true) return;

    // পাঠানোর পর তালিকা বদলে যায়, তাই মেমোর জন্য আগেই গাড়ীগুলো রেখে দেওয়া
    final sentUnits = _units
        .where((u) => _selected.contains(u["unit_id"]))
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
    final targetText = _targetLabel(target);

    setState(() {
      _sending = true;
    });
    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/units/transfer"),
        headers: _headers,
        body: jsonEncode({
          "unit_ids": _selected.toList(),
          "to_warehouse_id": _targetId,
          "note": _noteC.text.trim().isEmpty ? null : _noteC.text.trim(),
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = _json(res);
        _snack("ট্রান্সফার #${d["batch_no"]} সম্পন্ন: ${d["count"]} টি গাড়ী পাঠানো হয়েছে",
            color: Colors.green);
        setState(() {
          _selected.clear();
          _noteC.clear();
        });
        await _load();
        await _afterTransfer("${d["batch_no"]}", sentUnits, targetText);
      } else {
        _snack(_detail(res, "ট্রান্সফার করা যায়নি"), color: Colors.red);
      }
    } catch (e) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  // ---------------- নতুন ট্রান্সফার ট্যাব ----------------
  Widget _newTab() {
    final shown = _shown;
    final allShownSelected =
        shown.isNotEmpty && shown.every((u) => _selected.contains(u["unit_id"]));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: DropdownButtonFormField<int>(
            key: ValueKey("target-$_targetId-${_targets.length}"),
            initialValue: _targetId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: "কোথায় পাঠাবেন (শোরুম — গোডাউন)",
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _targets
                .map<DropdownMenuItem<int>>((t) => DropdownMenuItem<int>(
                      value: t["id"] as int,
                      child: Text(_targetLabel(t), overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              _targetId = v;
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchC,
            decoration: InputDecoration(
              hintText: "চেসিস, ইঞ্জিন, মডেল বা রঙ দিয়ে খুঁজুন (হ্যান্ড স্ক্যানারও চলবে)",
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchC.clear();
                        setState(() {
                          _search = "";
                        });
                      },
                    ),
            ),
            onChanged: (v) => setState(() {
              _search = v;
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "স্টকে ${_units.length} টি • দেখানো ${shown.length} টি • বাছা ${_selected.length} টি",
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
              TextButton(
                onPressed: shown.isEmpty
                    ? null
                    : () => setState(() {
                          if (allShownSelected) {
                            for (final u in shown) {
                              _selected.remove(u["unit_id"]);
                            }
                          } else {
                            for (final u in shown) {
                              _selected.add(u["unit_id"] as int);
                            }
                          }
                        }),
                child: Text(allShownSelected ? "সব বাদ দিন" : "দেখানো সব বাছুন"),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text("পাঠানোর মতো কোনো গাড়ী নেই"))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final u = shown[i];
                    final id = u["unit_id"] as int;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: CheckboxListTile(
                        dense: true,
                        value: _selected.contains(id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        }),
                        title: Text(
                          "${u['brand'] ?? ''} ${u['model'] ?? ''}".trim(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          "চেসিস: ${u['chassis_no']} | ইঞ্জিন: ${u['engine_no']}\n"
                          "রঙ: ${u['color'] ?? '-'} | এখন আছে: ${u['warehouse'] ?? '-'}",
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFD9E3F3))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _noteC,
                  decoration: const InputDecoration(
                    hintText: "মন্তব্য (ঐচ্ছিক)",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.local_shipping),
                  label: Text("পাঠান (${_selected.length})"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- ইতিহাস ট্যাব ----------------
  Widget _historyTab() {
    if (_history.isEmpty) {
      return const Center(child: Text("এখনো কোনো ট্রান্সফার হয়নি"));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _history.length,
      itemBuilder: (context, i) {
        final h = _history[i];
        final newBatch = i == 0 || _history[i - 1]["batch_no"] != h["batch_no"];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (newBatch)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6, left: 4),
                child: Text(
                  "ট্রান্সফার #${h['batch_no']}  •  ${h['date'] ?? '-'}  •  ${h['by_user'] ?? '-'}"
                  "${h['note'] != null ? '\nমন্তব্য: ${h['note']}' : ''}",
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.swap_horiz, color: Color(0xFF1E6BFF)),
                title: Text(
                  "${h['brand'] ?? ''} ${h['model'] ?? ''}".trim().isEmpty
                      ? "${h['chassis_no'] ?? '-'}"
                      : "${h['brand'] ?? ''} ${h['model'] ?? ''}".trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  "চেসিস: ${h['chassis_no'] ?? '-'}\n"
                  "${h['from_branch'] ?? '-'} (${h['from_warehouse'] ?? '-'})  →  "
                  "${h['to_branch'] ?? '-'} (${h['to_warehouse'] ?? '-'})",
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: "মেমো দেখুন / ছাপুন",
                  icon: const Icon(Icons.receipt_long),
                  onPressed: () => _openMemo(
                    "${h['batch_no']}",
                    h,
                    "${h['to_branch'] ?? '-'} (${h['to_warehouse'] ?? '-'})",
                    date: DateTime.tryParse("${h['date']}"),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
      body = TabBarView(
        physics: const NeverScrollableScrollPhysics(),
        children: [_newTab(), _historyTab()],
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("স্টক ট্রান্সফার"),
          actions: [
            IconButton(tooltip: "রিফ্রেশ", icon: const Icon(Icons.refresh), onPressed: _load),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "নতুন ট্রান্সফার"),
              Tab(text: "ইতিহাস"),
            ],
          ),
        ),
        body: body,
      ),
    );
  }
}