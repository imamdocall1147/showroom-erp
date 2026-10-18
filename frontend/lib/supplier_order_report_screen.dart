import 'package:flutter/material.dart';
import 'sync_service.dart';

/// কম্পানির অর্ডার রিপোর্ট: কোন কম্পানিকে কত ইউনিট অর্ডার, কত এসেছে, কত আসা বাকি,
/// মোট/বাকি মূল্য এবং জমা অগ্রিম। কম্পানি, অবস্থা ও তারিখ দিয়ে ছেঁকে দেখা যায়।
class SupplierOrderReportScreen extends StatefulWidget {
  final String token;

  const SupplierOrderReportScreen({super.key, required this.token});

  @override
  State<SupplierOrderReportScreen> createState() => _SupplierOrderReportScreenState();
}

class _SupplierOrderReportScreenState extends State<SupplierOrderReportScreen> {
  bool _loading = true;
  String? _error;
  bool _fromCache = false;
  List<Map<String, dynamic>> _orders = [];

  String _status = "all";
  String? _supplier; // কম্পানির নাম, null মানে সব
  DateTimeRange? _range;

  static const _statusItems = [
    ["all", "সব"],
    ["open", "চলমান"],
    ["completed", "সব এসেছে"],
    ["cancelled", "বাতিল"],
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  num _n(dynamic v) => v is num ? v : (num.tryParse("$v") ?? 0);

  String _money(num n) {
    final s = n.abs().round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return "${n < 0 ? '-' : ''}৳$b";
  }

  String _fmt(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await SyncService().getList("/supplier-orders", widget.token);
      if (!mounted) return;
      if (res["data"] != null) {
        setState(() {
          _orders = List<dynamic>.from(res["data"])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _fromCache = res["fromCache"] == true;
        });
      } else {
        setState(() {
          _error = "তথ্য আনা যায়নি";
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _range,
    );
    if (r != null) {
      setState(() {
        _range = r;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _orders.where((o) {
      if (_status != "all" && o["status"] != _status) return false;
      if (_supplier != null && "${o["supplier_name"]}" != _supplier) return false;
      if (_range != null) {
        final d = DateTime.tryParse("${o["order_date"]}");
        if (d == null) return false;
        final day = DateTime(d.year, d.month, d.day);
        final from = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
        final to = DateTime(_range!.end.year, _range!.end.month, _range!.end.day);
        if (day.isBefore(from) || day.isAfter(to)) return false;
      }
      return true;
    }).toList();
  }

  bool _isOverdue(Map<String, dynamic> o) {
    if (o["status"] != "open") return false;
    final e = DateTime.tryParse("${o["expected_date"]}");
    if (e == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(e.year, e.month, e.day).isBefore(today);
  }

  /// বাতিল অর্ডারের আসা-বাকি গণনায় ধরা হয় না
  num _remaining(Map<String, dynamic> o) => o["status"] == "cancelled" ? 0 : _n(o["remaining"]);

  Widget _stat(String label, String value, {Color? color}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
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
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color ?? Colors.black87),
          ),
        ],
      ),
    );
  }

  String _statusText(String s) {
    switch (s) {
      case "completed":
        return "সব এসেছে";
      case "cancelled":
        return "বাতিল";
      default:
        return "চলমান";
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case "completed":
        return const Color(0xFF0E7A3E);
      case "cancelled":
        return const Color(0xFFC62828);
      default:
        return const Color(0xFFB35C00);
    }
  }

  Widget _filters() {
    final names = _orders.map((o) => "${o["supplier_name"] ?? '-'}").toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final f in _statusItems)
              ChoiceChip(
                label: Text(
                  f[1],
                  style: TextStyle(
                    color: _status == f[0] ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: _status == f[0],
                backgroundColor: Colors.white,
                selectedColor: const Color(0xFF1E6BFF),
                checkmarkColor: Colors.white,
                side: BorderSide(
                  color: _status == f[0] ? const Color(0xFF1E6BFF) : const Color(0xFFD9E3F3),
                ),
                onSelected: (_) => setState(() {
                  _status = f[0];
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: ValueKey("sup-$_supplier"),
          initialValue: _supplier,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: "কম্পানি",
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text("সব কম্পানি")),
            ...names.map((n) => DropdownMenuItem<String?>(value: n, child: Text(n))),
          ],
          onChanged: (v) => setState(() {
            _supplier = v;
          }),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  _range == null
                      ? "অর্ডারের তারিখ (সব সময়)"
                      : "${_fmt(_range!.start)} — ${_fmt(_range!.end)}",
                ),
                onPressed: _pickRange,
              ),
            ),
            if (_range != null)
              IconButton(
                tooltip: "তারিখ মুছুন",
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() {
                  _range = null;
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _summary(List<Map<String, dynamic>> list) {
    num qty = 0, received = 0, remaining = 0, total = 0, receivedValue = 0, remainingValue = 0;
    for (final o in list) {
      final price = _n(o["unit_price"]);
      final r = _remaining(o);
      qty += _n(o["qty"]);
      received += _n(o["received"]);
      remaining += r;
      total += _n(o["total_value"]);
      receivedValue += _n(o["received"]) * price;
      remainingValue += r * price;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _stat("অর্ডার", "${list.length} টি"),
          _stat("অর্ডার করা ইউনিট", "$qty টি"),
          _stat("এসেছে", "$received টি", color: const Color(0xFF0E7A3E)),
          _stat("আসা বাকি", "$remaining টি", color: const Color(0xFFB35C00)),
          _stat("মোট অর্ডার মূল্য", _money(total)),
          _stat("এসে যাওয়া মূল্য", _money(receivedValue), color: const Color(0xFF0E7A3E)),
          _stat("আসা বাকির মূল্য", _money(remainingValue), color: const Color(0xFFB35C00)),
        ],
      ),
    );
  }

  Widget _supplierCard(String name, List<Map<String, dynamic>> list) {
    num qty = 0, received = 0, remaining = 0, total = 0, remainingValue = 0;
    for (final o in list) {
      final r = _remaining(o);
      qty += _n(o["qty"]);
      received += _n(o["received"]);
      remaining += r;
      total += _n(o["total_value"]);
      remainingValue += r * _n(o["unit_price"]);
    }
    final advance = _n(list.first["advance_balance"]);
    final net = remainingValue - advance;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "${list.length} টি অর্ডার • অর্ডার $qty টি • এসেছে $received টি • আসা বাকি $remaining টি\n"
            "মোট ${_money(total)} • আসা বাকির মূল্য ${_money(remainingValue)}",
            style: const TextStyle(fontSize: 12.5, color: Colors.black87),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EEFD),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("জমা অগ্রিম: ${_money(advance)}",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  net > 0
                      ? "আসা বাকি গাড়ীর মূল্য থেকে অগ্রিম বাদ দিলে আরও দিতে হবে: ${_money(net)}"
                      : "অগ্রিম আসা বাকি গাড়ীর মূল্যের চেয়ে ${_money(-net)} বেশি আছে",
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final o in list) ...[
            const Divider(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${o["model"] ?? '-'}",
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        "তারিখ: ${o["order_date"] ?? '-'}"
                        "${o["expected_date"] != null ? '  |  আসার কথা: ${o["expected_date"]}' : ''}"
                        "${_isOverdue(o) ? '  ⚠ দেরি' : ''}",
                        style: TextStyle(
                          fontSize: 12,
                          color: _isOverdue(o) ? Colors.red.shade700 : Colors.black54,
                        ),
                      ),
                      Text(
                        "অর্ডার ${_n(o["qty"])} টি • এসেছে ${_n(o["received"])} টি • "
                        "বাকি ${_remaining(o)} টি",
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money(_n(o["total_value"])),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text("ইউনিট ${_money(_n(o["unit_price"]))}",
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    Text(
                      _statusText("${o["status"]}"),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _statusColor("${o["status"]}"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final o in list) {
      groups.putIfAbsent("${o["supplier_name"] ?? '-'}", () => []).add(o);
    }
    final names = groups.keys.toList()..sort();

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
          if (_fromCache)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text("অফলাইন — সর্বশেষ সংরক্ষিত তালিকা দেখানো হচ্ছে"),
            ),
          _filters(),
          const SizedBox(height: 14),
          _summary(list),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text("এই শর্তে কোনো অর্ডার নেই")),
            ),
          for (final n in names) _supplierCard(n, groups[n]!),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("কম্পানির অর্ডার রিপোর্ট"),
        actions: [
          IconButton(tooltip: "রিফ্রেশ", icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}
