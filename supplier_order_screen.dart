import 'package:flutter/material.dart';
import 'sync_service.dart';
import 'supplier_quick_add.dart';
import 'supplier_order_report_screen.dart';

/// কোম্পানির কাছে গাড়ীর অর্ডার: কোন মডেল, কত ইউনিট, ইউনিট প্রতি কত দাম।
/// ক্রয় ফর্মে এই অর্ডার বাছলে মডেল ও দাম নিজে বসে যায়, আর কত ইউনিট আসা বাকি তা এখানে দেখা যায়।
class SupplierOrderScreen extends StatefulWidget {
  final String token;

  const SupplierOrderScreen({super.key, required this.token});

  @override
  State<SupplierOrderScreen> createState() => _SupplierOrderScreenState();
}

class _SupplierOrderScreenState extends State<SupplierOrderScreen> {
  bool _loading = true;
  String? _error;
  bool _fromCache = false;
  String _filter = "open";
  List<dynamic> _orders = [];
  List<dynamic> _suppliers = [];
  List<dynamic> _products = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _money(num n) {
    final s = n.abs().round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return "${n < 0 ? '-' : ''}৳$b";
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sync = SyncService();
      final ord = await sync.getList("/supplier-orders", widget.token);
      final parties = await sync.getList("/parties", widget.token);
      final prods = await sync.getList("/products", widget.token);
      if (!mounted) return;
      if (ord["data"] != null && parties["data"] != null && prods["data"] != null) {
        final List<dynamic> all = parties["data"];
        setState(() {
          _orders = List<dynamic>.from(ord["data"]);
          _suppliers = all.where((p) => p["party_type"] == "supplier").toList();
          _products = List<dynamic>.from(prods["data"]);
          _fromCache = ord["fromCache"] == true;
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

  /// নতুন সাপ্লায়ার যোগ করার পর তালিকা নতুন করে এনে ওই সাপ্লায়ারের আইডি ফেরত দেয়
  Future<int?> _reloadSuppliers({int? id, String? name}) async {
    final parties = await SyncService().getList("/parties", widget.token);
    if (!mounted || parties["data"] == null) return null;
    final all = List<dynamic>.from(parties["data"]);
    final sup = all.where((p) => p["party_type"] == "supplier").toList();
    setState(() {
      _suppliers = sup;
    });
    if (id != null && sup.any((s) => s["id"] == id)) return id;
    if (name != null) {
      final m = sup.where((s) => "${s["name"]}" == name).toList();
      if (m.isNotEmpty) return m.last["id"] as int;
    }
    return null;
  }

  Future<void> _cancelOrder(Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("অর্ডার বাতিল করবেন?"),
        content: Text(
          "${o["supplier_name"]} — ${o["model"]}\n"
          "আসা বাকি ${o["remaining"]} টি বাতিল হবে। যে ইউনিট এসে গেছে তা থাকবে।",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("না")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("বাতিল করুন", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await SyncService().apiCall(
      method: "POST",
      endpoint: "/supplier-orders/${o["id"]}/cancel",
      body: {},
      token: widget.token,
      description: "অর্ডার বাতিল #${o["id"]}",
    );
    if (!mounted) return;
    if (res["offline"] == true) {
      _snack("ইন্টারনেট নেই — পরে সিঙ্ক হবে", color: Colors.orange);
    } else if (res["error"] == true) {
      _snack(res["message"] ?? "বাতিল করা যায়নি", color: Colors.red);
    } else {
      _snack("অর্ডার বাতিল হয়েছে");
      _load();
    }
  }

  Future<void> _openCreateDialog() async {
    final qtyC = TextEditingController();
    final priceC = TextEditingController();
    final totalC = TextEditingController();
    final noteC = TextEditingController();
    int? supplierId;
    int? productId;
    String? err;
    bool busy = false;

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final qty = int.tryParse(qtyC.text.trim()) ?? 0;
          final price = int.tryParse(priceC.text.trim()) ?? 0;

          return AlertDialog(
            title: const Text("নতুন অর্ডার"),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      key: ValueKey("sup-$supplierId-${_suppliers.length}"),
                      initialValue: supplierId,
                      decoration: const InputDecoration(
                        labelText: "সাপ্লায়ার / কোম্পানি",
                        border: OutlineInputBorder(),
                      ),
                      items: _suppliers.map<DropdownMenuItem<int>>((s) {
                        return DropdownMenuItem<int>(
                          value: s["id"],
                          child: Text("${s["name"]}"),
                        );
                      }).toList(),
                      onChanged: (v) => setD(() {
                        supplierId = v;
                      }),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("তালিকায় নেই? নতুন সাপ্লায়ার যোগ করুন"),
                        onPressed: () async {
                          final created = await showAddSupplierDialog(ctx, widget.token);
                          if (created == null || created["offline"] == true) return;
                          final newId = await _reloadSuppliers(
                            id: created["id"] is int ? created["id"] as int : null,
                            name: created["name"] as String?,
                          );
                          setD(() {
                            if (newId != null) supplierId = newId;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: productId,
                      decoration: const InputDecoration(
                        labelText: "মডেল",
                        border: OutlineInputBorder(),
                      ),
                      items: _products.map<DropdownMenuItem<int>>((p) {
                        return DropdownMenuItem<int>(
                          value: p["id"],
                          child: Text("${p["model_name"]}"),
                        );
                      }).toList(),
                      onChanged: (v) => setD(() {
                        productId = v;
                      }),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: qtyC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "কত ইউনিট",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setD(() {}),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: totalC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "মোট টাকা (দিলে ইউনিট প্রতি দাম নিজে হিসাব হবে)",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final total = int.tryParse(v.trim()) ?? 0;
                        final q = int.tryParse(qtyC.text.trim()) ?? 0;
                        if (total > 0 && q > 0) {
                          priceC.text = "${(total / q).round()}";
                        }
                        setD(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: priceC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "ইউনিট প্রতি দাম (টাকা)",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setD(() {}),
                    ),
                    if (qty > 0 && price > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          "মোট অর্ডার মূল্য: ${_money(qty * price)}",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteC,
                      decoration: const InputDecoration(
                        labelText: "বিবরণ (ঐচ্ছিক)",
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
                onPressed: busy ? null : () => Navigator.of(ctx).pop(null),
                child: const Text("বাতিল"),
              ),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final q = int.tryParse(qtyC.text.trim());
                        final p = int.tryParse(priceC.text.trim());
                        if (supplierId == null || productId == null) {
                          setD(() {
                            err = "সাপ্লায়ার ও মডেল বেছে নিন";
                          });
                          return;
                        }
                        if (q == null || q <= 0 || p == null || p <= 0) {
                          setD(() {
                            err = "ইউনিট সংখ্যা ও দাম সঠিকভাবে দিন";
                          });
                          return;
                        }
                        setD(() {
                          busy = true;
                          err = null;
                        });
                        try {
                          final res = await SyncService().apiCall(
                            method: "POST",
                            endpoint: "/supplier-orders",
                            body: {
                              "supplier_id": supplierId,
                              "product_id": productId,
                              "qty": q,
                              "unit_price": p,
                              "notes": noteC.text.trim().isEmpty ? null : noteC.text.trim(),
                            },
                            token: widget.token,
                            description: "সাপ্লায়ার অর্ডার: $q টি",
                          );
                          if (res["offline"] == true) {
                            if (ctx.mounted) Navigator.of(ctx).pop("offline");
                          } else if (res["error"] == true) {
                            setD(() {
                              busy = false;
                              err = res["message"] ?? "অর্ডার করা যায়নি";
                            });
                          } else {
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          }
                        } catch (e) {
                          setD(() {
                            busy = false;
                            err = "সার্ভারের সাথে সংযোগ করা যায়নি";
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text("অর্ডার করুন"),
              ),
            ],
          );
        },
      ),
    );

    qtyC.dispose();
    priceC.dispose();
    totalC.dispose();
    noteC.dispose();

    if (result == true) {
      _snack("অর্ডার যোগ হয়েছে", color: Colors.green);
      _load();
    } else if (result == "offline") {
      _snack("ইন্টারনেট নেই — অর্ডারটা পরে সিঙ্ক হবে", color: Colors.orange);
    }
  }

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case "completed":
        bg = const Color(0xFFC9F2D8);
        fg = const Color(0xFF0E7A3E);
        label = "সব এসেছে";
        break;
      case "cancelled":
        bg = const Color(0xFFFFCDD2);
        fg = const Color(0xFFC62828);
        label = "বাতিল";
        break;
      default:
        bg = const Color(0xFFFFE8B8);
        fg = const Color(0xFFB35C00);
        label = "চলমান";
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final received = (o["received"] as num).toInt();
    final qty = (o["qty"] as num).toInt();
    final remaining = (o["remaining"] as num).toInt();
    final progress = qty > 0 ? received / qty : 0.0;
    final advance = (o["advance_balance"] as num).toInt();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${o["supplier_name"] ?? '-'} — ${o["model"] ?? '-'}",
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                _statusChip("${o["status"]}"),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "অর্ডারের তারিখ: ${o["order_date"] ?? '-'}"
              "${o["expected_date"] != null ? '   |   আসার কথা: ${o["expected_date"]}' : ''}",
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            const SizedBox(height: 6),
            Text("এসেছে $received টি, আসা বাকি $remaining টি (মোট $qty টি)"),
            const SizedBox(height: 8),
            Wrap(
              spacing: 18,
              runSpacing: 4,
              children: [
                Text("ইউনিট প্রতি: ${_money(o["unit_price"] as num)}"),
                Text("মোট অর্ডার মূল্য: ${_money(o["total_value"] as num)}",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (advance != 0) Text("এই সাপ্লায়ারের অগ্রিম জমা: ${_money(advance)}"),
              ],
            ),
            if ((o["notes"] ?? "").toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text("${o["notes"]}", style: const TextStyle(color: Colors.black54)),
            ],
            if (o["status"] == "open")
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _cancelOrder(Map<String, dynamic>.from(o)),
                  icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                  label: const Text("অর্ডার বাতিল", style: TextStyle(color: Colors.red)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filter == "all"
        ? _orders
        : _orders.where((o) => o["status"] == _filter).toList();

    num remainingValue = 0;
    int remainingUnits = 0;
    for (final o in _orders) {
      if (o["status"] == "open") {
        remainingUnits += (o["remaining"] as num).toInt();
        remainingValue += (o["remaining"] as num) * (o["unit_price"] as num);
      }
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E6BFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_shipping, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("আসা বাকি (চলমান অর্ডার)", style: TextStyle(color: Colors.white70)),
                      Text(
                        "$remainingUnits টি ইউনিট • ${_money(remainingValue)}",
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final f in const [
                ["open", "চলমান"],
                ["completed", "সব এসেছে"],
                ["cancelled", "বাতিল"],
                ["all", "সব"],
              ])
                ChoiceChip(
                  // থিমের চিপ-রঙ সাদা লেখা দেয়, তাই এখানে রঙ নিজে ঠিক করা
                  label: Text(
                    f[1],
                    style: TextStyle(
                      color: _filter == f[0] ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: _filter == f[0],
                  backgroundColor: Colors.white,
                  selectedColor: const Color(0xFF1E6BFF),
                  checkmarkColor: Colors.white,
                  side: BorderSide(
                    color: _filter == f[0] ? const Color(0xFF1E6BFF) : const Color(0xFFD9E3F3),
                  ),
                  onSelected: (_) => setState(() {
                    _filter = f[0];
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text("কোনো অর্ডার নেই")),
            ),
          for (final o in shown) _orderCard(Map<String, dynamic>.from(o)),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("সাপ্লায়ার অর্ডার"),
        actions: [
          IconButton(
            tooltip: "রিপোর্ট",
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SupplierOrderReportScreen(token: widget.token),
              ),
            ),
          ),
          IconButton(tooltip: "রিফ্রেশ", icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text("নতুন অর্ডার"),
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}
