import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'app_theme.dart';
import 'invoice_screen.dart';
import 'reports_screen.dart';

// ---------------------------------------------------------------
// সাহায্যকারী
// ---------------------------------------------------------------
Map<String, String> _headers(String token) => {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };

String _detail(http.Response res, String fallback) {
  try {
    final d = jsonDecode(res.body);
    if (d is Map && d["detail"] is String) return d["detail"] as String;
  } catch (_) {}
  return fallback;
}

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

const Map<String, String> _statusLabel = {
  "open": "চলমান",
  "delivered": "ডেলিভারি হয়েছে",
  "cancelled": "বাতিল",
};

Color _statusColor(String s) {
  switch (s) {
    case "delivered":
      return Colors.green;
    case "cancelled":
      return Colors.grey;
    default:
      return Colors.orange;
  }
}

// ---------------------------------------------------------------
// অর্ডারের তালিকা
// ---------------------------------------------------------------
class AdvanceOrderListScreen extends StatefulWidget {
  final String token;

  const AdvanceOrderListScreen({super.key, required this.token});

  @override
  State<AdvanceOrderListScreen> createState() => _AdvanceOrderListScreenState();
}

class _AdvanceOrderListScreenState extends State<AdvanceOrderListScreen> {
  String _status = "open";
  bool _loading = true;
  String? _error;
  List<dynamic> _orders = [];

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
      final res = await http.get(
        Uri.parse("$apiBaseUrl/advance-orders?status=$_status"),
        headers: _headers(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _orders = jsonDecode(res.body);
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

  Future<void> _openNew() async {
    final ok = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdvanceOrderFormScreen(token: widget.token)),
    );
    if (ok == true) _load();
  }

  Future<void> _openDetail(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvanceOrderDetailScreen(token: widget.token, orderId: id),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    num totalHeld = 0;
    num totalBalance = 0;
    num totalUnits = 0;
    for (final o in _orders) {
      totalHeld += (o["advance_held"] ?? 0) as num;
      totalBalance += (o["balance"] ?? 0) as num;
      totalUnits += (o["quantity"] ?? 1) as num;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("অগ্রিম অর্ডার"),
        actions: [
          ReportsIconButton(
            token: widget.token,
            title: "অগ্রিম অর্ডার রিপোর্ট",
            onlyKeys: const {'advance_orders'},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text("নতুন অগ্রিম অর্ডার"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final e in _statusLabel.entries)
                  ChoiceChip(
                    label: Text(e.value, style: const TextStyle(color: Colors.black87)),
                    backgroundColor: Colors.white,
                    selectedColor: const Color(0xFFE3DDF7),
                    selected: _status == e.key,
                    onSelected: (_) {
                      setState(() {
                        _status = e.key;
                      });
                      _load();
                    },
                  ),
              ],
            ),
          ),
          if (_status == "open" && _orders.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 24,
                runSpacing: 4,
                children: [
                  Text("চলমান অর্ডার: ${_orders.length} টি (মোট $totalUnits ইউনিট)",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text("জমা অগ্রিম: ${_money(totalHeld)}"),
                  Text("ডেলিভারিতে পাওনা: ${_money(totalBalance)}"),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_error!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              ElevatedButton(onPressed: _load, child: const Text("আবার চেষ্টা করুন")),
                            ],
                          ),
                        )
                      : _orders.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(child: Text("কোনো অর্ডার নেই")),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _orders.length,
                              itemBuilder: (context, i) {
                                final o = _orders[i];
                                final status = "${o["status"]}";
                                final overdue = o["overdue"] == true;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    onTap: () => _openDetail(o["id"] as int),
                                    isThreeLine: true,
                                    leading: CircleAvatar(
                                      backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                                      child: Icon(Icons.event_available, color: _statusColor(status)),
                                    ),
                                    title: Text(
                                      "${o["customer_name"] ?? '-'}",
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      "${o["brand"] ?? ''} ${o["model"] ?? ''}"
                                      "${o["color"] != null ? ' (${o["color"]})' : ''}"
                                      " — ${o["quantity"] ?? 1} ইউনিট\n"
                                      "মোট ${_money(o["agreed_price"])} | অগ্রিম ${_money(o["advance_held"])}"
                                      " | বাকি ${_money(o["balance"])}\n"
                                      "ডেলিভারি: ${o["expected_delivery_date"] ?? '-'}"
                                      "${overdue ? '  ⚠ দেরি হয়ে গেছে' : ''}",
                                      style: TextStyle(color: overdue ? Colors.red.shade700 : null),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// নতুন অগ্রিম অর্ডার
// ---------------------------------------------------------------
class AdvanceOrderFormScreen extends StatefulWidget {
  final String token;

  const AdvanceOrderFormScreen({super.key, required this.token});

  @override
  State<AdvanceOrderFormScreen> createState() => _AdvanceOrderFormScreenState();
}

class _AdvanceOrderFormScreenState extends State<AdvanceOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _colorC = TextEditingController();
  final _qtyC = TextEditingController(text: "1");
  final _priceC = TextEditingController();
  final _advanceC = TextEditingController(text: "0");
  final _notesC = TextEditingController();

  List<dynamic> _customers = [];
  List<dynamic> _products = [];
  int? _customerId;
  int? _productId;
  DateTime? _delivery;
  String _mode = "cash";

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  int get _qty => int.tryParse(_qtyC.text.trim()) ?? 1;
  int get _unitPrice => int.tryParse(_priceC.text.trim()) ?? 0;
  int get _total => _qty * _unitPrice;
  int get _adv => int.tryParse(_advanceC.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _colorC.dispose();
    _qtyC.dispose();
    _priceC.dispose();
    _advanceC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    try {
      final h = _headers(widget.token);
      final parties = await http.get(Uri.parse("$apiBaseUrl/parties"), headers: h);
      final products = await http.get(Uri.parse("$apiBaseUrl/products"), headers: h);
      if (!mounted) return;
      if (parties.statusCode == 200 && products.statusCode == 200) {
        final List<dynamic> all = jsonDecode(parties.body);
        setState(() {
          _customers = all.where((p) => p["party_type"] == "customer").toList();
          _products = jsonDecode(products.body);
        });
      } else {
        setState(() {
          _error = "কাস্টমার বা প্রোডাক্টের তালিকা আনা যায়নি";
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

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _delivery ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _delivery = d;
      });
    }
  }

  Widget _sumLine(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerId == null || _productId == null) {
      setState(() {
        _error = "কাস্টমার ও মডেল বেছে নিন";
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/advance-orders"),
        headers: _headers(widget.token),
        body: jsonEncode({
          "customer_id": _customerId,
          "product_id": _productId,
          "color": _colorC.text.trim().isEmpty ? null : _colorC.text.trim(),
          "agreed_price": _total,
          "quantity": _qty,
          "unit_price": _unitPrice,
          "expected_delivery_date": _delivery == null ? null : _fmtDate(_delivery!),
          "notes": _notesC.text.trim().isEmpty ? null : _notesC.text.trim(),
          "advance_amount": _adv,
          "payment_mode": _mode,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("অগ্রিম অর্ডার সংরক্ষণ হয়েছে")),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = _detail(res, "সংরক্ষণ করা যায়নি");
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
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("নতুন অগ্রিম অর্ডার")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FormWrap(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "কাস্টমার",
                        border: OutlineInputBorder(),
                      ),
                      items: _customers
                          .map<DropdownMenuItem<int>>((c) => DropdownMenuItem<int>(
                                value: c["id"],
                                child: Text("${c["name"]}${c["phone"] != null ? ' (${c["phone"]})' : ''}"),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _customerId = v),
                      validator: (v) => v == null ? "কাস্টমার বেছে নিন" : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _productId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "বাইকের মডেল",
                        border: OutlineInputBorder(),
                      ),
                      items: _products
                          .map<DropdownMenuItem<int>>((p) => DropdownMenuItem<int>(
                                value: p["id"],
                                child: Text("${p["model_name"]}"),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _productId = v;
                          // দাম ফাঁকা থাকলে তালিকা মূল্য বসিয়ে দেওয়া
                          if (_priceC.text.trim().isEmpty) {
                            final p = _products.firstWhere((x) => x["id"] == v, orElse: () => null);
                            if (p != null && p["unit_price"] != null) {
                              _priceC.text = "${p["unit_price"]}";
                            }
                          }
                        });
                      },
                      validator: (v) => v == null ? "মডেল বেছে নিন" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _colorC,
                      decoration: const InputDecoration(
                        labelText: "রঙ (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _qtyC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "কত ইউনিট গাড়ির অর্ডার",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 1) return "কমপক্ষে ১ ইউনিট দিন";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "প্রতি ইউনিটের দাম (টাকা)",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) return "সঠিক মূল্য দিন";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _advanceC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "এখন কত অগ্রিম নিচ্ছেন (টাকা)",
                        helperText: "পরে আরও অগ্রিম নেওয়া যাবে",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final a = int.tryParse((v ?? '').trim());
                        if (a == null || a < 0) return "সঠিক পরিমাণ দিন (না নিলে ০)";
                        if (_total > 0 && a > _total) return "অগ্রিম মোট মূল্যের বেশি হতে পারে না";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        children: [
                          _sumLine("$_qty ইউনিট × ${_money(_unitPrice)}", _money(_total)),
                          _sumLine("এখন অগ্রিম", _money(_adv)),
                          const Divider(),
                          _sumLine("ডেলিভারিতে বাকি", _money(_total - _adv), bold: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _mode,
                      decoration: const InputDecoration(
                        labelText: "অগ্রিম কীভাবে নিলেন",
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: "cash", child: Text("নগদ (ক্যাশ)")),
                        DropdownMenuItem(value: "bank", child: Text("ব্যাংক")),
                      ],
                      onChanged: (v) => setState(() => _mode = v ?? "cash"),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 18),
                            label: Text(_delivery == null
                                ? "ডেলিভারির তারিখ (ঐচ্ছিক)"
                                : "ডেলিভারি: ${_fmtDate(_delivery!)}"),
                            onPressed: _pickDate,
                          ),
                        ),
                        if (_delivery != null)
                          IconButton(
                            tooltip: "তারিখ মুছুন",
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _delivery = null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesC,
                      decoration: const InputDecoration(
                        labelText: "মন্তব্য (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text("অর্ডার সংরক্ষণ করুন", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------
// অর্ডারের বিস্তারিত: অগ্রিম নেওয়া / ডেলিভারি / বাতিল / এডিট
// ---------------------------------------------------------------
class AdvanceOrderDetailScreen extends StatefulWidget {
  final String token;
  final int orderId;

  const AdvanceOrderDetailScreen({super.key, required this.token, required this.orderId});

  @override
  State<AdvanceOrderDetailScreen> createState() => _AdvanceOrderDetailScreenState();
}

class _AdvanceOrderDetailScreenState extends State<AdvanceOrderDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _o;

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
      final res = await http.get(
        Uri.parse("$apiBaseUrl/advance-orders/${widget.orderId}"),
        headers: _headers(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _o = Map<String, dynamic>.from(jsonDecode(res.body));
        });
      } else {
        setState(() {
          _error = _detail(res, "অর্ডার আনা যায়নি");
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ---- অগ্রিম নেওয়া ----
  Future<void> _addPayment() async {
    final o = _o!;
    final maxMore = (o["agreed_price"] as num) - (o["advance_held"] as num);
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    String mode = "cash";
    String? err;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("অগ্রিম জমা নিন"),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("আর সর্বোচ্চ নেওয়া যাবে: ${_money(maxMore)}"),
                const SizedBox(height: 12),
                TextField(
                  controller: amountC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "পরিমাণ (টাকা)", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: "কীভাবে নিলেন", border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: "cash", child: Text("নগদ (ক্যাশ)")),
                    DropdownMenuItem(value: "bank", child: Text("ব্যাংক")),
                  ],
                  onChanged: (v) => setD(() => mode = v ?? "cash"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteC,
                  decoration: const InputDecoration(labelText: "মন্তব্য (ঐচ্ছিক)", border: OutlineInputBorder()),
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("বাতিল")),
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
                          Uri.parse("$apiBaseUrl/advance-orders/${widget.orderId}/payments"),
                          headers: _headers(widget.token),
                          body: jsonEncode({
                            "amount": a,
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
              child: const Text("জমা নিন"),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _snack("অগ্রিম জমা হয়েছে");
      _load();
    }
  }

  // ---- বাতিল ----
  Future<void> _cancelOrder() async {
    final o = _o!;
    final held = (o["advance_held"] as num).toInt();
    final refundC = TextEditingController(text: "$held");
    final noteC = TextEditingController();
    String mode = "cash";
    String? err;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("অর্ডার বাতিল"),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("এখন জমা আছে: ${_money(held)}"),
                if (held > 0) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: refundC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "কত টাকা ফেরত দিচ্ছেন",
                      helperText: "বাকিটা দোকানের আয় হিসেবে রাখা হবে",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: "কীভাবে ফেরত দিচ্ছেন", border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: "cash", child: Text("নগদ (ক্যাশ)")),
                      DropdownMenuItem(value: "bank", child: Text("ব্যাংক")),
                    ],
                    onChanged: (v) => setD(() => mode = v ?? "cash"),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: noteC,
                  decoration: const InputDecoration(labelText: "কারণ (ঐচ্ছিক)", border: OutlineInputBorder()),
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("ফিরে যান")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: busy
                  ? null
                  : () async {
                      final r = held > 0 ? int.tryParse(refundC.text.trim()) : 0;
                      if (r == null || r < 0 || r > held) {
                        setD(() => err = "ফেরত ০ থেকে ${_money(held)}-এর মধ্যে হতে হবে");
                        return;
                      }
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        final res = await http.post(
                          Uri.parse("$apiBaseUrl/advance-orders/${widget.orderId}/cancel"),
                          headers: _headers(widget.token),
                          body: jsonEncode({
                            "refund_amount": r,
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
                            err = _detail(res, "বাতিল করা যায়নি");
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
              child: const Text("অর্ডার বাতিল করুন", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _snack("অর্ডার বাতিল হয়েছে");
      _load();
    }
  }

  // ---- এডিট ----
  Future<void> _edit() async {
    final o = _o!;
    final priceC = TextEditingController(text: "${o["agreed_price"]}");
    final colorC = TextEditingController(text: "${o["color"] ?? ''}");
    final notesC = TextEditingController(text: "${o["notes"] ?? ''}");
    DateTime? delivery = o["expected_delivery_date"] != null
        ? DateTime.tryParse("${o["expected_delivery_date"]}")
        : null;
    String? err;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("অর্ডার এডিট"),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: priceC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "মোট চুক্তির মূল্য", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: colorC,
                    decoration: const InputDecoration(labelText: "রঙ", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(delivery == null ? "ডেলিভারির তারিখ" : _fmtDate(delivery!)),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: delivery ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (d != null) setD(() => delivery = d);
                          },
                        ),
                      ),
                      if (delivery != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setD(() => delivery = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesC,
                    decoration: const InputDecoration(labelText: "মন্তব্য", border: OutlineInputBorder()),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("বাতিল")),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final p = int.tryParse(priceC.text.trim());
                      if (p == null || p <= 0) {
                        setD(() => err = "সঠিক মূল্য দিন");
                        return;
                      }
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        final res = await http.patch(
                          Uri.parse("$apiBaseUrl/advance-orders/${widget.orderId}"),
                          headers: _headers(widget.token),
                          body: jsonEncode({
                            "agreed_price": p,
                            "color": colorC.text.trim().isEmpty ? null : colorC.text.trim(),
                            "expected_delivery_date": delivery == null ? null : _fmtDate(delivery!),
                            "notes": notesC.text.trim().isEmpty ? null : notesC.text.trim(),
                          }),
                        );
                        if (!ctx.mounted) return;
                        if (res.statusCode == 200) {
                          Navigator.of(ctx).pop(true);
                        } else {
                          setD(() {
                            busy = false;
                            err = _detail(res, "আপডেট করা যায়নি");
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
      _snack("আপডেট হয়েছে");
      _load();
    }
  }

  // ---- ডেলিভারি ----
  Future<void> _deliver() async {
    final done = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdvanceDeliverScreen(token: widget.token, order: _o!),
      ),
    );
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final isOpen = o != null && o["status"] == "open";

    return Scaffold(
      appBar: AppBar(
        title: Text("অগ্রিম অর্ডার #${widget.orderId}"),
        actions: [
          if (isOpen)
            IconButton(tooltip: "এডিট", icon: const Icon(Icons.edit), onPressed: _edit),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || o == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error ?? "অর্ডার পাওয়া যায়নি", style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text("আবার চেষ্টা করুন")),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    "${o["customer_name"] ?? '-'}",
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    _statusLabel["${o["status"]}"] ?? "${o["status"]}",
                                    style: const TextStyle(color: Colors.black87),
                                  ),
                                  backgroundColor: _statusColor("${o["status"]}").withValues(alpha: 0.2),
                                ),
                              ],
                            ),
                            if (o["customer_phone"] != null) Text("ফোন: ${o["customer_phone"]}"),
                            const SizedBox(height: 8),
                            Text(
                              "${o["brand"] ?? ''} ${o["model"] ?? ''}"
                              "${o["color"] != null ? ' (${o["color"]})' : ''}",
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text("ইউনিট: ${o["quantity"] ?? 1} টি"
                                "${o["unit_price"] != null ? ' × ${_money(o["unit_price"])}' : ''}"),
                            Text("মোট চুক্তির মূল্য: ${_money(o["agreed_price"])}"),
                            Text("জমা অগ্রিম: ${_money(o["advance_held"])}"),
                            if (isOpen)
                              Text(
                                "ডেলিভারিতে বাকি: ${_money(o["balance"])}",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            const SizedBox(height: 4),
                            Text("অর্ডারের তারিখ: ${o["order_date"] ?? '-'}"),
                            Text(
                              "ডেলিভারির তারিখ: ${o["expected_delivery_date"] ?? '-'}"
                              "${o["overdue"] == true ? '  ⚠ দেরি হয়ে গেছে' : ''}",
                              style: TextStyle(color: o["overdue"] == true ? Colors.red.shade700 : null),
                            ),
                            if (o["notes"] != null) Text("মন্তব্য: ${o["notes"]}"),
                          ],
                        ),
                      ),
                    ),
                    if (isOpen) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _addPayment,
                            icon: const Icon(Icons.payments),
                            label: const Text("অগ্রিম জমা নিন"),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: _deliver,
                            icon: const Icon(Icons.two_wheeler, color: Colors.white),
                            label: const Text("ডেলিভারি দিন (বিক্রয়)", style: TextStyle(color: Colors.white)),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            onPressed: _cancelOrder,
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text("অর্ডার বাতিল"),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text("লেনদেনের তালিকা", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    if ((o["payments"] as List).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text("এখনো কোনো অগ্রিম নেওয়া হয়নি"),
                      )
                    else
                      ...(o["payments"] as List).map((p) {
                        final isIn = p["kind"] == "payment";
                        return Card(
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              isIn ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isIn ? Colors.green : Colors.orange,
                            ),
                            title: Text("${p["label"]} — ${_money(p["amount"])}"),
                            subtitle: Text(
                              "${p["date"] ?? ''}"
                              "${p["payment_mode"] == 'cash' ? ' | নগদ' : p["payment_mode"] == 'bank' ? ' | ব্যাংক' : ''}"
                              "${p["note"] != null ? '\n${p["note"]}' : ''}",
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}

// ---------------------------------------------------------------
// ডেলিভারি: বাইক বেছে বিক্রয় সম্পন্ন, অগ্রিম নিজে থেকে বাদ যায়
// ---------------------------------------------------------------
class AdvanceDeliverScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> order;

  const AdvanceDeliverScreen({super.key, required this.token, required this.order});

  @override
  State<AdvanceDeliverScreen> createState() => _AdvanceDeliverScreenState();
}

class _AdvanceDeliverScreenState extends State<AdvanceDeliverScreen> {
  late final TextEditingController _priceC;
  late final TextEditingController _payC;
  List<dynamic> _units = [];
  int? _unitId;
  String _mode = "cash";

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  int get _held => (widget.order["advance_held"] as num).toInt();
  int get _price => int.tryParse(_priceC.text.trim()) ?? 0;
  int get _remaining => (_price - _held) < 0 ? 0 : (_price - _held);
  int get _pay => int.tryParse(_payC.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    _priceC = TextEditingController(text: "${widget.order["agreed_price"]}");
    final rem = (widget.order["agreed_price"] as num).toInt() - _held;
    _payC = TextEditingController(text: "${rem < 0 ? 0 : rem}");
    _loadUnits();
  }

  @override
  void dispose() {
    _priceC.dispose();
    _payC.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/units?status=in_stock"),
        headers: _headers(widget.token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final List<dynamic> all = jsonDecode(res.body);
        setState(() {
          _units = all.where((u) => u["product_id"] == widget.order["product_id"]).toList();
        });
      } else {
        setState(() {
          _error = _detail(res, "স্টক তালিকা আনা যায়নি");
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

  Future<void> _submit() async {
    if (_unitId == null) {
      setState(() => _error = "কোন বাইকটা দিচ্ছেন তা বেছে নিন");
      return;
    }
    if (_price <= 0) {
      setState(() => _error = "সঠিক বিক্রয় মূল্য দিন");
      return;
    }
    if (_held > _price) {
      setState(() => _error = "জমা অগ্রিম বিক্রয় মূল্যের চেয়ে বেশি হতে পারে না");
      return;
    }
    if (_pay < 0 || _pay > _remaining) {
      setState(() => _error = "এখন নেওয়া টাকা ০ থেকে ${_money(_remaining)}-এর মধ্যে হতে হবে");
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/advance-orders/${widget.order["id"]}/deliver"),
        headers: _headers(widget.token),
        body: jsonEncode({
          "unit_id": _unitId,
          "sold_price": _price,
          "pay_now": _pay,
          "payment_mode": _mode,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final due = (data["due"] as num).toInt();
        final price = (data["price"] as num).toInt();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InvoiceScreen(
              invoiceTitle: "বিক্রয় ইনভয়েস",
              invoiceNumber: "${data["voucher_id"]}",
              date: DateTime.now(),
              partyName: "${widget.order["customer_name"] ?? ''}",
              partyPhone: widget.order["customer_phone"],
              paymentMode: due > 0 ? "due" : "cash",
              totalAmount: price,
              items: [
                InvoiceItem(
                  description:
                      "${data["model"] ?? ''} (চেসিস: ${data["chassis_no"]}, ইঞ্জিন: ${data["engine_no"]})",
                  qty: 1,
                  unit: "pcs",
                  unitPrice: price,
                  total: price,
                ),
              ],
            ),
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = _detail(res, "ডেলিভারি সম্পন্ন করা যায়নি");
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
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final stayDue = _remaining - _pay;

    return Scaffold(
      appBar: AppBar(title: const Text("ডেলিভারি দিন")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${o["customer_name"]}",
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        Text("${o["brand"] ?? ''} ${o["model"] ?? ''}"
                            "${o["color"] != null ? ' (রঙ: ${o["color"]})' : ''}"
                            " — ${o["quantity"] ?? 1} ইউনিট"),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text("কোন বাইকটা দিচ্ছেন (স্টকে থাকা একই মডেল)",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (_units.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      "এই মডেলের কোনো বাইক এখন স্টকে নেই। আগে বাইক ক্রয় এন্ট্রি দিন।",
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                else
                  ..._units.map(
                    (u) => RadioListTile<int>(
                      value: u["id"] as int,
                      groupValue: _unitId,
                      onChanged: (v) => setState(() => _unitId = v),
                      title: Text("চেসিস: ${u["chassis_no"]}"),
                      subtitle: Text("ইঞ্জিন: ${u["engine_no"]} | রঙ: ${u["color"] ?? '-'}"),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _priceC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "বিক্রয় মূল্য (টাকা)",
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "জমা অগ্রিম বাদ: ${_money(_held)}\n"
                    "এখন নিতে হবে (বাকি): ${_money(_remaining)}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _payC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "এখন কত টাকা নিলেন",
                    helperText: "কম নিলে বাকিটা কাস্টমারের বাকি খাতায় উঠবে",
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _mode,
                  decoration: const InputDecoration(
                    labelText: "কীভাবে নিলেন",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: "cash", child: Text("নগদ (ক্যাশ)")),
                    DropdownMenuItem(value: "bank", child: Text("ব্যাংক")),
                  ],
                  onChanged: (v) => setState(() => _mode = v ?? "cash"),
                ),
                const SizedBox(height: 8),
                Text(
                  stayDue > 0
                      ? "কাস্টমারের বাকি থাকবে: ${_money(stayDue)}"
                      : "পুরো টাকা পরিশোধ হবে, কোনো বাকি থাকবে না",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: stayDue > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: (_submitting || _units.isEmpty) ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text("ডেলিভারি নিশ্চিত করুন",
                            style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
              ],
            ),
    );
  }
}