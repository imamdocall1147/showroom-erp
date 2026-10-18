import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';

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

/// দুই পার্টনারের (সেল সেন্টারের) অগ্রিমের হিসাব এবং রানারের ডেলিভারি/পাওয়া বাকির হিসাব
class PartnerLedgerScreen extends StatefulWidget {
  final String token;

  const PartnerLedgerScreen({super.key, required this.token});

  @override
  State<PartnerLedgerScreen> createState() => _PartnerLedgerScreenState();
}

class _PartnerLedgerScreenState extends State<PartnerLedgerScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _suppliers = [];
  int? _supplierId;
  Map<String, dynamic>? _ledger;
  Map<String, dynamic>? _deliv;

  Map<String, String> get _h => {"Authorization": "Bearer ${widget.token}"};

  dynamic _decode(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final res = await http.get(Uri.parse("$apiBaseUrl/parties"), headers: _h);
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          _error = "সাপ্লায়ারের তালিকা আনা যায়নি";
          _loading = false;
        });
        return;
      }
      final List<dynamic> all = _decode(res);
      _suppliers = all.where((p) => p["party_type"] == "supplier").toList();
      if (_suppliers.isEmpty) {
        setState(() {
          _error = "কোনো সাপ্লায়ার নেই। আগে রানার অটোমোবাইলকে সাপ্লায়ার হিসেবে যোগ করুন।";
          _loading = false;
        });
        return;
      }
      final runner = _suppliers.firstWhere((p) {
        final n = "${p["name"]}".toLowerCase();
        return n.contains("runner") || n.contains("রানার");
      }, orElse: () => _suppliers.first);
      _supplierId = runner["id"] as int;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "সার্ভারের সাথে সংযোগ করা যায়নি";
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    if (_supplierId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final a = await http.get(
        Uri.parse("$apiBaseUrl/partner-ledger?supplier_id=$_supplierId"),
        headers: _h,
      );
      final b = await http.get(
        Uri.parse("$apiBaseUrl/supplier-deliveries?supplier_id=$_supplierId"),
        headers: _h,
      );
      if (!mounted) return;
      if (a.statusCode == 200 && b.statusCode == 200) {
        setState(() {
          _ledger = Map<String, dynamic>.from(_decode(a));
          _deliv = Map<String, dynamic>.from(_decode(b));
        });
      } else {
        setState(() {
          _error = "হিসাব আনতে সমস্যা হয়েছে";
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

  Widget _supplierPicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: DropdownButtonFormField<int>(
        initialValue: _supplierId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: "সাপ্লায়ার",
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: _suppliers
            .map<DropdownMenuItem<int>>((p) => DropdownMenuItem<int>(
                  value: p["id"] as int,
                  child: Text("${p["name"]}"),
                ))
            .toList(),
        onChanged: (v) {
          setState(() {
            _supplierId = v;
          });
          _load();
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.normal)),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: bold ? 16 : 14,
                  color: color)),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _branchCard(Map<String, dynamic> b) {
    final balance = (b["balance"] ?? 0) as num;
    final entries = (b["entries"] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${b["branch_name"]}",
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const Divider(),
            _row("মোট অগ্রিম জমা", _money(b["deposits_total"])),
            _row("বিক্রি হওয়া গাড়ির দাম কাটা", _money(b["deducted_total"])),
            _row(
              "বর্তমান অগ্রিম ব্যালান্স",
              _money(balance),
              bold: true,
              color: balance < 0 ? Colors.red : Colors.green.shade800,
            ),
            const Divider(),
            _row("বিক্রি হয়েছে", "${b["sold_units"]} টি"),
            _row("স্টকে আছে (অবিক্রীত)", "${b["stock_units"]} টি"),
            _row("অবিক্রীত গাড়ির ক্রয়মূল্য", _money(b["stock_cost"])),
            if (entries.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text("লেনদেনের তালিকা (${entries.length})",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                children: [
                  for (final e in entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        e["kind"] == "deposit" ? Icons.arrow_downward : Icons.arrow_upward,
                        color: e["kind"] == "deposit" ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      title: Text(
                        "${e["kind"] == "deposit" ? "জমা" : "বাদ (গাড়ি বিক্রি)"} — ${_money(e["amount"])}",
                      ),
                      subtitle: Text(
                        "${e["date"] ?? ''}"
                        "${e["mode"] != null ? ' | ${e["mode"]}' : ''}"
                        "${e["note"] != null ? '\n${e["note"]}' : ''}",
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _ledgerTab() {
    final branches = (_ledger?["branches"] as List?) ?? [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              "প্রতিটা সেল সেন্টারের (পার্টনারের) অগ্রিম আলাদা। গাড়ি বিক্রি হলে ওই গাড়ির ক্রয়মূল্য "
              "সেই সেন্টারের অগ্রিম থেকে কাটা যায়।",
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (branches.isEmpty) const Center(child: Text("কোনো হিসাব নেই")),
          for (final b in branches) _branchCard(Map<String, dynamic>.from(b)),
        ],
      ),
    );
  }

  Widget _deliveryTab() {
    final d = _deliv ?? {};
    final totals = Map<String, dynamic>.from(d["totals"] ?? {});
    final months = (d["months"] as List?) ?? [];
    final orders = (d["open_orders"] as List?) ?? [];
    final daily = (d["daily"] as List?) ?? [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _stat("মোট অর্ডার", "${totals["ordered"] ?? 0} টি", Colors.blue),
              _stat("পেয়েছি", "${totals["received"] ?? 0} টি", Colors.green),
              _stat("পাওয়া বাকি", "${totals["remaining"] ?? 0} টি", Colors.orange),
            ],
          ),
          const SizedBox(height: 18),
          const Text("মাসওয়ারি অর্ডার", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (months.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text("কোনো অর্ডার নেই")),
          for (final m in months)
            Card(
              child: ListTile(
                dense: true,
                title: Text("${m["month"]}  (${m["orders"]} টি অর্ডার)"),
                subtitle: Text(
                    "অর্ডার ${m["ordered"]} | পেয়েছি ${m["received"]} | বাকি ${m["remaining"]}"),
              ),
            ),
          const SizedBox(height: 18),
          const Text("চলমান অর্ডার (পাওয়া বাকি)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (orders.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text("কোনো চলমান অর্ডার নেই")),
          for (final o in orders)
            Card(
              child: ListTile(
                dense: true,
                isThreeLine: true,
                title: Text("${o["branch"] ?? ''} — অর্ডার #${o["id"]} (${o["date"] ?? '-'})"),
                subtitle: Text(
                  "অর্ডার ${o["qty"]} টি | পেয়েছি ${o["received"]} টি | বাকি ${o["remaining"]} টি\n"
                  "ইউনিট প্রতি ${_money(o["unit_price"])}"
                  "${o["expected_date"] != null ? ' | আশা: ${o["expected_date"]}' : ''}",
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Text("দৈনিক ডেলিভারি (শেষ ৯০ দিন)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (daily.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text("কোনো ডেলিভারি নেই")),
          for (final r in daily)
            ListTile(
              dense: true,
              leading: const Icon(Icons.local_shipping_outlined, size: 20),
              title: Text("${r["date"]}  —  ${r["count"]} টি"),
              subtitle: Text("${r["branch"] ?? ''}"),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("পার্টনার ও রানার হিসাব"),
          actions: [
            IconButton(
              tooltip: "রিফ্রেশ",
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "পার্টনারের অগ্রিম"),
              Tab(text: "রানার ডেলিভারি"),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_suppliers.isNotEmpty) _supplierPicker(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.red)),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                    onPressed: _init, child: const Text("আবার চেষ্টা করুন")),
                              ],
                            ),
                          ),
                        )
                      : TabBarView(children: [_ledgerTab(), _deliveryTab()]),
            ),
          ],
        ),
      ),
    );
  }
}
