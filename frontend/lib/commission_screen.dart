import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';

String _msg(http.Response r, String fallback) {
  try {
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    if (d is Map && d["detail"] is String) return d["detail"];
  } catch (_) {}
  return fallback;
}

String _fmt(DateTime d) =>
    "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

class CommissionScreen extends StatefulWidget {
  final String token;
  const CommissionScreen({super.key, required this.token});

  @override
  State<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends State<CommissionScreen> {
  Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

  bool _loading = true;
  String? _error;
  List<dynamic> _pending = [];
  List<dynamic> _units = [];
  List<dynamic> _suppliers = [];
  Map<String, dynamic> _report = {};
  final Set<int> _selected = {};

  // কমিশন বসানোর ফর্ম
  int? _unitId;
  int? _companyId;
  final _amountCtrl = TextEditingController();

  // গ্রহণের ফর্ম
  final _totalCtrl = TextEditingController();
  DateTime _receivedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  void _snack(String m, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await http.get(
          Uri.parse("$apiBaseUrl/commissions?status=pending"),
          headers: _headers);
      final r = await http.get(Uri.parse("$apiBaseUrl/commissions/report"),
          headers: _headers);
      if (p.statusCode != 200) {
        setState(() => _error = _msg(p, "তালিকা আনতে সমস্যা হয়েছে"));
        return;
      }
      _pending = jsonDecode(utf8.decode(p.bodyBytes));
      if (r.statusCode == 200) {
        _report = Map<String, dynamic>.from(jsonDecode(r.body));
      }
      // গাড়ি ও সাপ্লায়ার (না পেলেও বাকি অংশ চলবে)
      try {
        final u = await http.get(Uri.parse("$apiBaseUrl/units"),
            headers: _headers);
        if (u.statusCode == 200) {
          _units = jsonDecode(utf8.decode(u.bodyBytes));
        }
      } catch (_) {}
      try {
        final s = await http.get(Uri.parse("$apiBaseUrl/parties"),
            headers: _headers);
        if (s.statusCode == 200) {
          final all = jsonDecode(utf8.decode(s.bodyBytes)) as List;
          _suppliers = all.where((x) => x["party_type"] == "supplier").toList();
        }
      } catch (_) {}
      _selected.removeWhere((id) => !_pending.any((c) => c["id"] == id));
        } catch (e) {
      setState(() => _error = "সমস্যা: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveCommission() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (_unitId == null) return _snack("গাড়ি বাছুন", color: Colors.red);
    if (amount == null || amount <= 0) {
      return _snack("সঠিক পরিমাণ দিন", color: Colors.red);
    }
    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/commissions"),
        headers: _headers,
        body: jsonEncode({
          "unit_id": _unitId,
          "company_id": _companyId,
          "amount": amount,
        }),
      );
      if (res.statusCode == 200) {
        _amountCtrl.clear();
        setState(() => _unitId = null);
        _snack("কমিশন সংরক্ষিত হয়েছে");
        await _loadAll();
      } else {
        _snack(_msg(res, "সংরক্ষণ করা যায়নি"), color: Colors.red);
      }
    } catch (_) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    }
  }

  int get _selectedSum => _pending
      .where((c) => _selected.contains(c["id"]))
      .fold<int>(0, (s, c) => s + (c["amount"] as int));

  Future<void> _receive() async {
    final total = int.tryParse(_totalCtrl.text.trim());
    if (_selected.isEmpty) {
      return _snack("কমিশন টিক দিন", color: Colors.red);
    }
    if (total == null || total <= 0) {
      return _snack("প্রাপ্ত টাকার সঠিক অঙ্ক দিন", color: Colors.red);
    }
    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/commission-receipts"),
        headers: _headers,
        body: jsonEncode({
          "commission_ids": _selected.toList(),
          "total_amount": total,
          "received_date": _fmt(_receivedDate),
        }),
      );
      if (res.statusCode == 200) {
        _totalCtrl.clear();
        _selected.clear();
        _snack("কমিশন গ্রহণ সংরক্ষিত হয়েছে");
        await _loadAll();
      } else {
        _snack(_msg(res, "গ্রহণ সংরক্ষণ করা যায়নি"), color: Colors.red);
      }
    } catch (_) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    }
  }

  Widget _pendingTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              title: const Text("মোট বাকি কমিশন"),
              subtitle: Text("${_report["pending_count"] ?? 0} টি গাড়ি"),
              trailing: Text("৳ ${_report["pending_total"] ?? 0}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ),
          if (_pending.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text("কোনো বাকি কমিশন নেই")),
            ),
          ..._pending.map((c) => Card(
                child: ListTile(
                  title: Text("চেসিস: ${c["chassis_no"]}"),
                  trailing: Text("৳ ${c["amount"]}",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )),
        ],
      ),
    );
  }

  Widget _addTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey("unit$_unitId"),
          initialValue: _unitId,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: "গাড়ি (চেসিস নং)", border: OutlineInputBorder()),
          items: _units.map<DropdownMenuItem<int>>((u) {
            final name = "${u["brand"] ?? ''} ${u["model"] ?? ''}".trim();
            return DropdownMenuItem<int>(
              value: u["id"] as int,
              child: Text("${u["chassis_no"] ?? u["id"]}  $name",
                  overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (v) => setState(() => _unitId = v),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          key: ValueKey("co$_companyId"),
          initialValue: _companyId,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: "কোম্পানি (ঐচ্ছিক)", border: OutlineInputBorder()),
          items: _suppliers
              .map<DropdownMenuItem<int>>((s) => DropdownMenuItem<int>(
                    value: s["id"] as int,
                    child: Text("${s["name"]}"),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _companyId = v),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: "কমিশনের পরিমাণ (টাকা)",
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: ElevatedButton(
              onPressed: _saveCommission, child: const Text("সংরক্ষণ করুন")),
        ),
        const SizedBox(height: 8),
        const Text(
          "একই গাড়ির বাকি কমিশন থাকলে নতুন পরিমাণ দিয়ে আপডেট হবে।",
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _receiveTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.all(4),
          child: Text("যে কমিশনগুলো টাকা হিসেবে পেয়েছেন সেগুলো টিক দিন",
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (_pending.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text("গ্রহণের জন্য কোনো কমিশন নেই")),
          ),
        ..._pending.map((c) => CheckboxListTile(
              value: _selected.contains(c["id"]),
              title: Text("চেসিস: ${c["chassis_no"]}"),
              secondary: Text("৳ ${c["amount"]}"),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(c["id"] as int);
                } else {
                  _selected.remove(c["id"]);
                }
                _totalCtrl.text = _selected.isEmpty ? "" : "$_selectedSum";
              }),
            )),
        const Divider(),
        Text("টিক দেওয়া কমিশনের যোগফল: ৳ $_selectedSum"),
        const SizedBox(height: 12),
        TextField(
          controller: _totalCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "আসলে প্রাপ্ত মোট টাকা",
            helperText: "কোম্পানি কম/বেশি দিলে এখানে আসল অঙ্ক দিন",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text("প্রাপ্তির তারিখ: ${_fmt(_receivedDate)}"),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _receivedDate,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (d != null) setState(() => _receivedDate = d);
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton(
              onPressed: _receive, child: const Text("গ্রহণ করুন")),
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            title: const Text("এ পর্যন্ত মোট প্রাপ্ত কমিশন"),
            trailing: Text("৳ ${_report["received_in_period"] ?? 0}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("কোম্পানি কমিশন"),
          bottom: const TabBar(tabs: [
            Tab(text: "বাকি কমিশন"),
            Tab(text: "কমিশন বসান"),
            Tab(text: "গ্রহণ"),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                            onPressed: _loadAll,
                            child: const Text("আবার চেষ্টা করুন")),
                      ],
                    ),
                  )
                : TabBarView(
                    children: [_pendingTab(), _addTab(), _receiveTab()],
                  ),
      ),
    );
  }
}