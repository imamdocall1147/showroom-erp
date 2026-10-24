import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';

String _t2(int n) => n.toString().padLeft(2, '0');
String _fd(DateTime d) => "${d.year}-${_t2(d.month)}-${_t2(d.day)}";

class SaleEditListScreen extends StatefulWidget {
  final String token;
  const SaleEditListScreen({super.key, required this.token});

  @override
  State<SaleEditListScreen> createState() => _SaleEditListScreenState();
}

class _SaleEditListScreenState extends State<SaleEditListScreen> {
  final _searchC = TextEditingController();
  bool _loading = true;
  String? _error;
  List<dynamic> _sales = [];

  Map<String, String> get _h => {"Authorization": "Bearer ${widget.token}"};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse("$apiBaseUrl/sales")
          .replace(queryParameters: {"q": _searchC.text.trim()});
      final res = await http.get(uri, headers: _h);
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _sales = jsonDecode(utf8.decode(res.bodyBytes));
        });
      } else {
        setState(() {
          _error = "বিক্রয়ের তালিকা আনা যায়নি";
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

  Future<void> _open(Map<String, dynamic> sale) async {
    final ok = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleEditForm(token: widget.token, sale: sale),
      ),
    );
    if (ok == true) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ইনভয়েস আপডেট হয়েছে"), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("বিক্রয় ইনভয়েস এডিট")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchC,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: "চেসিস, ইঞ্জিন বা কাস্টমারের নাম দিয়ে খুঁজুন",
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _load,
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : _sales.isEmpty
                        ? const Center(child: Text("কোনো বিক্রয় পাওয়া যায়নি"))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _sales.length,
                            itemBuilder: (context, i) {
                              final s = Map<String, dynamic>.from(_sales[i] as Map);
                              final due = (s["due"] ?? 0) as num;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  onTap: () => _open(s),
                                  title: Text(
                                    "${s['brand'] ?? ''} ${s['model'] ?? ''}".trim(),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    "চেসিস: ${s['chassis_no']}\n"
                                    "কাস্টমার: ${s['customer_name'] ?? '-'}  |  তারিখ: ${s['sale_date'] ?? '-'}",
                                  ),
                                  isThreeLine: true,
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("৳${s['total']}",
                                          style: const TextStyle(fontWeight: FontWeight.w800)),
                                      if (due > 0)
                                        Text("বাকি ৳$due",
                                            style: const TextStyle(color: Colors.red, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class SaleEditForm extends StatefulWidget {
  final String token;
  final Map<String, dynamic> sale;
  const SaleEditForm({super.key, required this.token, required this.sale});

  @override
  State<SaleEditForm> createState() => _SaleEditFormState();
}

class _SaleEditFormState extends State<SaleEditForm> {
  final _priceC = TextEditingController();
  final _decoC = TextEditingController();
  final _regC = TextEditingController();
  final _paidC = TextEditingController();

  List<dynamic> _customers = [];
  List<dynamic> _partners = [];
  int? _customerId;
  int? _partnerId;
  DateTime? _date;
  bool _saving = false;
  String? _error;

  Map<String, String> get _h => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

  @override
  void initState() {
    super.initState();
    final s = widget.sale;
    _priceC.text = "${s['sold_price'] ?? 0}";
    _decoC.text = "${s['decoration_cost'] ?? 0}";
    _regC.text = "${s['registration_cost'] ?? 0}";
    _paidC.text = "${s['paid'] ?? 0}";
    _customerId = s["customer_id"] as int?;
    _partnerId = s["partner_id"] as int?;
    _date = DateTime.tryParse("${s['sale_date'] ?? ''}");
    _loadLists();
  }

  @override
  void dispose() {
    _priceC.dispose();
    _decoC.dispose();
    _regC.dispose();
    _paidC.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    try {
      final r = await http.get(Uri.parse("$apiBaseUrl/parties"), headers: _h);
      if (r.statusCode == 200 && mounted) {
        final all = jsonDecode(utf8.decode(r.bodyBytes)) as List;
        setState(() {
          _customers = all.where((p) => p["party_type"] == "customer").toList();
        });
      }
    } catch (_) {}
    try {
      final r = await http.get(Uri.parse("$apiBaseUrl/partners"), headers: _h);
      if (r.statusCode == 200 && mounted) {
        setState(() {
          _partners = jsonDecode(utf8.decode(r.bodyBytes));
        });
      }
    } catch (_) {}
  }

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  int get _total => _n(_priceC) + _n(_decoC) + _n(_regC);
  int get _due => _total - _n(_paidC);

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() {
        _date = d;
      });
    }
  }

  Future<void> _save() async {
    if (_customerId == null) {
      setState(() {
        _error = "কাস্টমার বাছুন";
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await http.put(
        Uri.parse("$apiBaseUrl/units/${widget.sale['unit_id']}/sale"),
        headers: _h,
        body: jsonEncode({
          "customer_id": _customerId,
          "sold_price": _n(_priceC),
          "decoration_cost": _n(_decoC),
          "registration_cost": _n(_regC),
          "paid_amount": _n(_paidC),
          "sale_date": _date == null ? null : _fd(_date!),
          "partner_id": _partnerId,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.of(context).pop(true);
      } else {
        String msg = "সংরক্ষণ করা যায়নি";
        try {
          final d = jsonDecode(utf8.decode(res.bodyBytes));
          if (d is Map && d["detail"] is String) msg = d["detail"];
        } catch (_) {}
        setState(() {
          _error = msg;
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
          _saving = false;
        });
      }
    }
  }

  Widget _num(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;
    final custIds = _customers.map((c) => c["id"] as int).toSet();
    return Scaffold(
      appBar: AppBar(title: const Text("ইনভয়েস এডিট")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  "${s['brand'] ?? ''} ${s['model'] ?? ''}\n"
                  "চেসিস: ${s['chassis_no']}\nইঞ্জিন: ${s['engine_no']}\n"
                  "ইনভয়েস/ভাউচার নং: ${s['invoice_no'] ?? '-'}",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: (_customerId != null && custIds.contains(_customerId)) ? _customerId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: "কাস্টমার", border: OutlineInputBorder()),
              items: _customers
                  .map<DropdownMenuItem<int>>((c) => DropdownMenuItem<int>(
                        value: c["id"] as int,
                        child: Text("${c["name"]}${(c["phone"] ?? '').toString().isEmpty ? '' : ' (${c["phone"]})'}",
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _customerId = v;
              }),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(_date == null ? "বিক্রয়ের তারিখ বাছুন" : "তারিখ: ${_fd(_date!)}"),
              onPressed: _pickDate,
            ),
            const SizedBox(height: 16),
            _num("বাইকের মূল্য", _priceC),
            const SizedBox(height: 12),
            _num("ডেকোরেশন খরচ", _decoC),
            const SizedBox(height: 12),
            _num("রেজিস্ট্রেশন খরচ", _regC),
            const SizedBox(height: 12),
            _num("এখন জমা (অগ্রিম)", _paidC),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "সর্বমোট: ৳$_total     জমা: ৳${_n(_paidC)}     বাকি: ৳$_due",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _due < 0 ? Colors.red : Colors.black87,
                  ),
                ),
              ),
            ),
            if (_partners.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _partners.any((p) => p["id"] == _partnerId) ? _partnerId : null,
                decoration: const InputDecoration(labelText: "কোন পার্টনারের বিক্রয়", border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text("কেউ না")),
                  ..._partners.map<DropdownMenuItem<int>>((p) => DropdownMenuItem<int>(
                        value: p["id"] as int,
                        child: Text("${p["name"]}"),
                      )),
                ],
                onChanged: (v) => setState(() {
                  _partnerId = v;
                }),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving || _due < 0 ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text("সংরক্ষণ করুন", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}