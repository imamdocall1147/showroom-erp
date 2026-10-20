import 'package:flutter/material.dart';
import 'sync_service.dart';
import 'supplier_quick_add.dart';
import 'reports_screen.dart';

/// কোম্পানি/সাপ্লায়ারকে (যেমন রানার) গাড়ী ক্রয়ের অগ্রিম দেওয়া এবং কার কাছে কত অগ্রিম জমা আছে দেখা।
/// অগ্রিম একবারে বা কিস্তিতে (পার্ট বাই পার্ট) যতবার খুশি দেওয়া যায়, প্রতিবার আগের জমার সাথে যোগ হয়।
/// অগ্রিম পরে "নতুন বাইক ক্রয়" ফর্মে ইউনিটের মূল্য থেকে কাটা যায়।
class SupplierAdvanceScreen extends StatefulWidget {
  final String token;

  const SupplierAdvanceScreen({super.key, required this.token});

  @override
  State<SupplierAdvanceScreen> createState() => _SupplierAdvanceScreenState();
}

class _SupplierAdvanceScreenState extends State<SupplierAdvanceScreen> {
  bool _loading = true;
  String? _error;
  bool _fromCache = false;
  List<dynamic> _balances = [];
  List<dynamic> _suppliers = [];

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
      final adv = await sync.getList("/supplier-advances", widget.token);
      final parties = await sync.getList("/parties", widget.token);
      if (!mounted) return;
      if (adv["data"] != null && parties["data"] != null) {
        final List<dynamic> all = parties["data"];
        setState(() {
          _balances = List<dynamic>.from(adv["data"]);
          _suppliers = all.where((p) => p["party_type"] == "supplier").toList();
          _fromCache = adv["fromCache"] == true;
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

  /// তালিকার কার্ড থেকে সাপ্লায়ারের আইডি বের করা
  int? _idForBalance(Map b) {
    final direct = b["supplier_id"] ?? b["party_id"];
    if (direct is int) return direct;
    final m = _suppliers.where((s) => "${s["name"]}" == "${b["supplier_name"]}");
    return m.isNotEmpty ? m.first["id"] as int : null;
  }

  num _advanceOf(int? supplierId) {
    if (supplierId == null) return 0;
    for (final b in _balances) {
      if (_idForBalance(b as Map) == supplierId) {
        return b["advance_balance"] as num;
      }
    }
    return 0;
  }

  Future<void> _openPayDialog({int? presetSupplierId}) async {
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    int? supplierId = presetSupplierId;
    String mode = "cash";
    String? err;
    bool busy = false;

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final current = _advanceOf(supplierId);
          final entered = int.tryParse(amountC.text.trim()) ?? 0;

          return AlertDialog(
            title: const Text("সাপ্লায়ারকে অগ্রিম দিন"),
            content: SizedBox(
              width: 420,
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
                        onPressed: busy
                            ? null
                            : () async {
                                final created = await showAddSupplierDialog(ctx, widget.token);
                                if (created == null) return;
                                if (created["offline"] == true) {
                                  _snack("ইন্টারনেট নেই — সাপ্লায়ার পরে যোগ হবে, তখন তালিকা রিফ্রেশ করুন",
                                      color: Colors.orange);
                                  return;
                                }
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
                    if (supplierId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          "এখন জমা আছে: ${_money(current)}",
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    TextField(
                      controller: amountC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "এখন কত টাকা দিচ্ছেন",
                        helperText: "একবারে বা কিস্তিতে — যতবার খুশি দিতে পারবেন",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setD(() {}),
                    ),
                    if (supplierId != null && entered > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "দেওয়ার পর মোট অগ্রিম জমা হবে: ${_money(current + entered)}",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteC,
                      decoration: const InputDecoration(
                        labelText: "বিবরণ (ঐচ্ছিক, যেমন: ১০টা বাইকের ২য় কিস্তি)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      dense: true,
                      title: const Text("নগদ (Cash) থেকে"),
                      value: "cash",
                      groupValue: mode,
                      onChanged: (v) => setD(() {
                        mode = v!;
                      }),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      title: const Text("ব্যাংক থেকে"),
                      value: "bank",
                      groupValue: mode,
                      onChanged: (v) => setD(() {
                        mode = v!;
                      }),
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
                        final amount = int.tryParse(amountC.text.trim());
                        if (supplierId == null) {
                          setD(() {
                            err = "সাপ্লায়ার বেছে নিন";
                          });
                          return;
                        }
                        if (amount == null || amount <= 0) {
                          setD(() {
                            err = "সঠিক টাকার পরিমাণ দিন";
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
                            endpoint: "/supplier-advances",
                            body: {
                              "supplier_id": supplierId,
                              "amount": amount,
                              "payment_mode": mode,
                              "narration": noteC.text.trim().isEmpty ? null : noteC.text.trim(),
                            },
                            token: widget.token,
                            description: "সাপ্লায়ার অগ্রিম: ৳$amount",
                          );
                          if (res["offline"] == true) {
                            if (ctx.mounted) Navigator.of(ctx).pop("offline");
                          } else if (res["error"] == true) {
                            setD(() {
                              busy = false;
                              err = res["message"] ?? "অগ্রিম দেওয়া যায়নি";
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
                    : const Text("অগ্রিম দিন"),
              ),
            ],
          );
        },
      ),
    );

    amountC.dispose();
    noteC.dispose();

    if (result == true) {
      _snack("অগ্রিম দেওয়া হয়েছে", color: Colors.green);
      _load();
    } else if (result == "offline") {
      _snack("ইন্টারনেট নেই — এন্ট্রিটা পরে সিঙ্ক হবে", color: Colors.orange);
    }
  }

  @override
  Widget build(BuildContext context) {
    num total = 0;
    for (final b in _balances) {
      total += (b["advance_balance"] as num);
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
              color: const Color(0xFF7C4DDB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("সাপ্লায়ারদের কাছে মোট অগ্রিম জমা",
                          style: TextStyle(color: Colors.white70)),
                      Text(
                        _money(total),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              "আরও অগ্রিম দিতে নিচের কোনো সাপ্লায়ারে ট্যাপ করুন",
              style: TextStyle(color: Colors.black54, fontSize: 12.5),
            ),
          ),
          if (_balances.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text("কোনো সাপ্লায়ারের কাছে অগ্রিম জমা নেই")),
            ),
          for (final b in _balances)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: () => _openPayDialog(presetSupplierId: _idForBalance(b as Map)),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE6DAFB),
                  child: Icon(Icons.local_shipping, color: Color(0xFF7C4DDB)),
                ),
                title: Text("${b["supplier_name"] ?? '-'}",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text("${b["phone"] ?? ''}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _money(b["advance_balance"] as num),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.add_circle_outline, color: Color(0xFF7C4DDB)),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("সাপ্লায়ার অগ্রিম"),
        actions: [
          ReportsIconButton(
            token: widget.token,
            title: "সাপ্লায়ার রিপোর্ট",
            onlyKeys: const {'purchase_due', 'payable', 'supplier_purchase'},
          ),
          IconButton(
            tooltip: "রিফ্রেশ",
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPayDialog(),
        icon: const Icon(Icons.add),
        label: const Text("অগ্রিম দিন"),
      ),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}
