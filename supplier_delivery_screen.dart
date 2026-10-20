import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'main.dart' show apiBaseUrl;

/// রানারের কাছ থেকে ডেলিভারি: মাসের অর্ডার, দৈনিক গাড়ী পাওয়া,
/// আর সব চলমান অর্ডারে এখনো কত গাড়ী আসা বাকি।
class SupplierDeliveryScreen extends StatefulWidget {
  final String token;
  const SupplierDeliveryScreen({super.key, required this.token});

  @override
  State<SupplierDeliveryScreen> createState() => _SupplierDeliveryScreenState();
}

class _SupplierDeliveryScreenState extends State<SupplierDeliveryScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  String get _monthKey =>
      "${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}";

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _detail(http.Response res) {
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map && d["detail"] is String) return d["detail"] as String;
    } catch (_) {}
    if (res.statusCode == 401) return "লগইনের মেয়াদ শেষ, আবার লগইন করুন";
    return "সমস্যা হয়েছে (${res.statusCode})";
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/reports/supplier-deliveries?month=$_monthKey"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _data = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
        });
      } else {
        setState(() {
          _error = _detail(res);
        });
      }
    } catch (_) {
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

  void _shift(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  String _statusLabel(String? s) {
    switch (s) {
      case "open":
        return "চলমান";
      case "completed":
        return "সম্পন্ন";
      case "cancelled":
        return "বাতিল";
      default:
        return s ?? "";
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    );
  }

  Widget _orderTile(Map<String, dynamic> o) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text("${o['model'] ?? '-'}  —  ${o['supplier_name'] ?? '-'}",
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          "অর্ডার ${o['qty']} টি  •  পাওয়া ${o['received']} টি  •  বাকি ${o['remaining']} টি\n"
          "অর্ডারের তারিখ: ${o['order_date'] ?? '-'}",
        ),
        trailing: Text(_statusLabel(o["status"] as String?)),
        isThreeLine: true,
      ),
    );
  }

  Widget _content() {
    final d = _data!;
    final monthOrders = List<Map<String, dynamic>>.from(
        (d["month_orders"] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final openOrders = List<Map<String, dynamic>>.from(
        (d["open_orders"] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final daily = List<Map<String, dynamic>>.from(
        (d["daily_deliveries"] as List).map((e) => Map<String, dynamic>.from(e as Map)));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statBox("এই মাসে অর্ডার", "${d['month_ordered'] ?? 0} টি", Colors.blue.shade700),
              _statBox("এই মাসে গাড়ী পেয়েছেন", "${d['delivered_in_month'] ?? 0} টি", Colors.green.shade700),
              _statBox("সব চলমান অর্ডারে আসা বাকি", "${d['open_orders_remaining'] ?? 0} টি",
                  Colors.orange.shade800),
            ],
          ),
          _sectionTitle("এই মাসের অর্ডার"),
          if (monthOrders.isEmpty)
            const Text("এই মাসে কোনো অর্ডার দেওয়া হয়নি", style: TextStyle(color: Colors.black54)),
          for (final o in monthOrders) _orderTile(o),
          _sectionTitle("দৈনিক ডেলিভারি (রানার থেকে পাওয়া গাড়ী)"),
          if (daily.isEmpty)
            const Text("এই মাসে এখনো কোনো গাড়ী পাওয়া যায়নি", style: TextStyle(color: Colors.black54)),
          for (final row in daily)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_today, size: 18),
                title: Text("${row['date']}"),
                trailing: Text("${row['count']} টি", style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          _sectionTitle("চলমান অর্ডার (এখনো আসা বাকি)"),
          if (openOrders.isEmpty)
            const Text("কোনো চলমান অর্ডার নেই", style: TextStyle(color: Colors.black54)),
          for (final o in openOrders) _orderTile(o),
        ],
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text("আবার চেষ্টা করুন")),
            ],
          ),
        ),
      );
    } else if (_data == null) {
      body = const SizedBox.shrink();
    } else {
      body = _content();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("রানার ডেলিভারি"),
        actions: [
          IconButton(
            tooltip: "আগের মাস",
            icon: const Icon(Icons.chevron_left),
            onPressed: _loading ? null : () => _shift(-1),
          ),
          Center(
            child: Text(_monthKey, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: "পরের মাস",
            icon: const Icon(Icons.chevron_right),
            onPressed: _loading ? null : () => _shift(1),
          ),
          IconButton(
            tooltip: "রিফ্রেশ",
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: body,
    );
  }
}
