import 'package:flutter/material.dart';
import 'main.dart';
import 'invoice_screen.dart';
import 'sync_service.dart';
import 'app_theme.dart';
import 'qr_scan.dart';

// ---------------------------------------------------------------
// বাইক ক্রয়: সাপ্লায়ারকে আগে দেওয়া অগ্রিম থেকে কাটা যায়, বাকিটা নগদ বা বাকি
// ---------------------------------------------------------------
class PurchaseScreen extends StatefulWidget {
  final String token;

  const PurchaseScreen({super.key, required this.token});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  DateTime _entryDate = DateTime.now();
  final _formKey = GlobalKey<FormState>();
  final _chassisController = TextEditingController();
  final _engineController = TextEditingController();
  final _gatePassController = TextEditingController();
  final _colorController = TextEditingController();
  final _yearController = TextEditingController();
  final _priceController = TextEditingController();
  final _advanceController = TextEditingController(text: "0");

  List<dynamic> _products = [];
  List<dynamic> _warehouses = [];
  List<dynamic> _suppliers = [];
  List<dynamic> _advances = [];
  List<dynamic> _orders = [];
  int? _selectedOrderId;
  int? _selectedProductId;
  int? _selectedWarehouseId;
  int? _selectedSupplierId;
  String _paymentMode = "cash";

  bool _isLoadingLists = true;
  bool _usingCachedLists = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  int _numOf(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int get _price => _numOf(_priceController);

  /// বেছে নেওয়া সাপ্লায়ারের কাছে এখনো যত অগ্রিম জমা আছে
  int get _availableAdvance {
    if (_selectedSupplierId == null) return 0;
    for (final a in _advances) {
      if (a["supplier_id"] == _selectedSupplierId) {
        return (a["advance_balance"] as num).toInt();
      }
    }
    return 0;
  }

  /// বেছে নেওয়া সাপ্লায়ারের চলমান অর্ডারগুলো (এখনো ইউনিট আসা বাকি আছে এমন)
  List<dynamic> get _ordersForSupplier {
    if (_selectedSupplierId == null) return [];
    return _orders
        .where((o) => o["supplier_id"] == _selectedSupplierId && (o["remaining"] as num) > 0)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
  }

  @override
  void dispose() {
    _chassisController.dispose();
    _engineController.dispose();
    _gatePassController.dispose();
    _colorController.dispose();
    _yearController.dispose();
    _priceController.dispose();
    _advanceController.dispose();
    super.dispose();
  }

  Future<void> _loadDropdownData() async {
    setState(() {
      _isLoadingLists = true;
    });
    try {
      final sync = SyncService();
      final productsRes = await sync.getList("/products", widget.token);
      final warehousesRes = await sync.getList("/warehouses", widget.token);
      final partiesRes = await sync.getList("/parties", widget.token);
      Map<String, dynamic>? advancesRes;
      try {
        advancesRes = await sync.getList("/supplier-advances", widget.token);
      } catch (_) {
        advancesRes = null;
      }
      Map<String, dynamic>? ordersRes;
      try {
        ordersRes = await sync.getList("/supplier-orders?status=open", widget.token);
      } catch (_) {
        ordersRes = null;
      }
      if (!mounted) return;

      if (productsRes["data"] != null &&
          warehousesRes["data"] != null &&
          partiesRes["data"] != null) {
        final List<dynamic> allParties = partiesRes["data"];
        setState(() {
          _orders = (ordersRes != null && ordersRes["data"] != null)
              ? List<dynamic>.from(ordersRes["data"])
              : [];
          _products = productsRes["data"];
          _warehouses = warehousesRes["data"];
          _suppliers = allParties.where((p) => p["party_type"] == "supplier").toList();
          _advances = (advancesRes != null && advancesRes["data"] != null)
              ? List<dynamic>.from(advancesRes["data"])
              : [];
          _usingCachedLists = productsRes["fromCache"] == true ||
              warehousesRes["fromCache"] == true ||
              partiesRes["fromCache"] == true;
        });
      } else {
        setState(() {
          _errorMessage =
              "প্রোডাক্ট বা গোডাউন তালিকা আনা যায়নি। একবার ইন্টারনেট/ব্যাকএন্ড চালু অবস্থায় অ্যাপ খুলুন।";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "তালিকা লোড করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLists = false;
        });
      }
    }
  }

  Future<void> _submitPurchase() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null || _selectedWarehouseId == null) {
      setState(() {
        _errorMessage = "প্রোডাক্ট ও গোডাউন বেছে নিন";
      });
      return;
    }
    if (_paymentMode == "due" && _selectedSupplierId == null) {
      setState(() {
        _errorMessage = "বাকিতে ক্রয়ের জন্য সাপ্লায়ার বেছে নিন";
      });
      return;
    }

    final price = _price;
    final advance = _numOf(_advanceController);
    if (advance < 0 || advance > price) {
      setState(() {
        _errorMessage = "অগ্রিম থেকে কাটার পরিমাণ ০ থেকে ক্রয় মূল্যের মধ্যে হতে হবে";
      });
      return;
    }
    if (advance > _availableAdvance) {
      setState(() {
        _errorMessage = "এই সাপ্লায়ারের অগ্রিম আছে মাত্র ৳$_availableAdvance";
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final body = {
      "product_id": _selectedProductId,
      "warehouse_id": _selectedWarehouseId,
      "chassis_no": _chassisController.text.trim(),
      "engine_no": _engineController.text.trim(),
      "color": _colorController.text.trim().isEmpty ? null : _colorController.text.trim(),
      "year": _yearController.text.trim().isEmpty ? null : _yearController.text.trim(),
      "purchase_price": price,
      "payment_mode": _paymentMode,
      "supplier_id": _selectedSupplierId,
      "advance_used": advance,
      "order_id": _selectedOrderId,
      "purchase_date": _fmtYmd(_entryDate),
      "gate_pass_no": _gatePassController.text.trim().isEmpty
          ? null
          : _gatePassController.text.trim(),
    };

    try {
      final result = await SyncService().apiCall(
        method: "POST",
        endpoint: "/units/purchase",
        body: body,
        token: widget.token,
        description: "বাইক ক্রয়: ${_chassisController.text.trim()}",
      );

      if (!mounted) return;

      if (result["offline"] == true) {
        Navigator.of(context).pop("offline");
      } else if (result["error"] == true) {
        setState(() {
          _errorMessage = result["message"];
        });
      } else {
        final data = result["data"];
        String voucher = "-";
        if (data is Map && data["voucher_id"] != null) {
          voucher = "${data["voucher_id"]}";
        }
        final product = _products.firstWhere(
          (p) => p["id"] == _selectedProductId,
          orElse: () => null,
        );
        final supplier = _selectedSupplierId != null
            ? _suppliers.firstWhere(
                (s) => s["id"] == _selectedSupplierId,
                orElse: () => null,
              )
            : null;

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => InvoiceScreen(
              invoiceTitle: "ক্রয় ইনভয়েস",
              invoiceNumber: voucher,
              date: _entryDate,
              partyName: supplier != null ? supplier["name"] : "নগদ ক্রয়",
              partyPhone: supplier != null ? supplier["phone"] : null,
              paymentMode: _paymentMode,
              totalAmount: price,
              partyLabel: "সাপ্লায়ার",
              partySignatureLabel: "বিক্রেতার স্বাক্ষর",
              items: [
                InvoiceItem(
                  description:
                      "${product != null ? product['model_name'] : ''} (চেসিস: ${_chassisController.text.trim()}, ইঞ্জিন: ${_engineController.text.trim()})",
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
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "সার্ভারের সাথে সংযোগ করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _sumRow(String label, int amount, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text("৳$amount", style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableAdvance;
    final advance = _numOf(_advanceController);

    return Scaffold(
      appBar: AppBar(title: const Text("নতুন বাইক ক্রয় এন্ট্রি")),
      body: _isLoadingLists
          ? const Center(child: CircularProgressIndicator())
          : FormWrap(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_usingCachedLists) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "অফলাইন — ডিভাইসে সংরক্ষিত তালিকা ব্যবহার হচ্ছে। এন্ট্রি ইন্টারনেট ফিরলে সিঙ্ক হবে।",
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    DropdownButtonFormField<int>(
                      key: ValueKey("product-$_selectedProductId"),
                      initialValue: _selectedProductId,
                      decoration: const InputDecoration(
                        labelText: "প্রোডাক্ট (মডেল)",
                        border: OutlineInputBorder(),
                      ),
                      items: _products.map<DropdownMenuItem<int>>((p) {
                        return DropdownMenuItem<int>(
                          value: p["id"],
                          child: Text("${p["model_name"]}"),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedProductId = value;
                        });
                      },
                      validator: (value) => value == null ? "প্রোডাক্ট বেছে নিন" : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedWarehouseId,
                      decoration: const InputDecoration(
                        labelText: "গোডাউন",
                        border: OutlineInputBorder(),
                      ),
                      items: _warehouses.map<DropdownMenuItem<int>>((w) {
                        return DropdownMenuItem<int>(
                          value: w["id"],
                          child: Text("${w["name"]}"),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedWarehouseId = value;
                        });
                      },
                      validator: (value) => value == null ? "গোডাউন বেছে নিন" : null,
                    ),
                    const SizedBox(height: 16),
                    buildEntryDateField(context, _entryDate, (d) => setState(() => _entryDate = d), "ক্রয়ের তারিখ"),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _chassisController,
                       decoration: InputDecoration(
                        labelText: "চেসিস নম্বর",
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: "QR স্ক্যান করে চেসিস নম্বর বসান",
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () async {
                            final code = await scanChassisQr(context);
                            if (code != null && code.isNotEmpty) {
                              setState(() {
                                _chassisController.text = code;
                              });
                            }
                          },
                        ),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? "চেসিস নম্বর দিন" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _engineController,
                      decoration: const InputDecoration(
                        labelText: "ইঞ্জিন নম্বর",
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? "ইঞ্জিন নম্বর দিন" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _gatePassController,
                      decoration: const InputDecoration(
                        labelText: "গেট পাস নম্বর (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _colorController,
                      decoration: const InputDecoration(
                        labelText: "রঙ (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _yearController,
                      decoration: const InputDecoration(
                        labelText: "বছর (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: "ক্রয় মূল্য (টাকা)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return "ক্রয় মূল্য দিন";
                        if (int.tryParse(value.trim()) == null) return "সঠিক সংখ্যা দিন";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      initialValue: _selectedSupplierId,
                      decoration: const InputDecoration(
                        labelText: "সাপ্লায়ার / কোম্পানি (বাকি বা অগ্রিমের জন্য দরকার)",
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text("— নগদ ক্রয় (সাপ্লায়ার ছাড়া) —"),
                        ),
                        ..._suppliers.map<DropdownMenuItem<int?>>((s) {
                          return DropdownMenuItem<int?>(
                            value: s["id"],
                            child: Text("${s["name"]}"),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedSupplierId = value;
                          _selectedOrderId = null;
                          _advanceController.text = "0";
                        });
                      },
                    ),
                    if (_ordersForSupplier.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        key: ValueKey("order-$_selectedSupplierId-$_selectedOrderId"),
                        initialValue: _selectedOrderId,
                        decoration: const InputDecoration(
                          labelText: "অর্ডার থেকে (ঐচ্ছিক) — বাছলে মডেল ও দাম নিজে বসে যাবে",
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text("— অর্ডার ছাড়া —"),
                          ),
                          ..._ordersForSupplier.map<DropdownMenuItem<int?>>((o) {
                            return DropdownMenuItem<int?>(
                              value: o["id"],
                              child: Text(
                                "${o["model"]} — আসা বাকি ${o["remaining"]} টি × ৳${o["unit_price"]}",
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedOrderId = value;
                            if (value != null) {
                              final o = _orders.firstWhere(
                                (x) => x["id"] == value,
                                orElse: () => null,
                              );
                              if (o != null) {
                                _selectedProductId = o["product_id"];
                                _priceController.text = "${o["unit_price"]}";
                              }
                            }
                          });
                        },
                      ),
                    ],
                    if (available > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          "এই সাপ্লায়ারের কাছে আপনার অগ্রিম জমা আছে: ৳$available",
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _advanceController,
                        decoration: InputDecoration(
                          labelText: "অগ্রিম থেকে কাটবেন (টাকা)",
                          border: const OutlineInputBorder(),
                          suffix: TextButton(
                            onPressed: () {
                              final fill = _price > 0 && _price < available ? _price : available;
                              setState(() {
                                _advanceController.text = "$fill";
                              });
                            },
                            child: const Text("সবটা"),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty) return null;
                          final n = int.tryParse(v);
                          if (n == null || n < 0) return "সঠিক সংখ্যা দিন";
                          if (n > available) return "অগ্রিম আছে মাত্র ৳$available";
                          return null;
                        },
                      ),
                      if (advance > 0) ...[
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
                              _sumRow("ক্রয় মূল্য", _price),
                              _sumRow("অগ্রিম থেকে কাটা", advance),
                              const Divider(),
                              _sumRow("বাকি অংশ (নিচের পেমেন্ট মোডে)", _price - advance, bold: true),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    const Text("পেমেন্ট মোড (অগ্রিম বাদে বাকি অংশের জন্য)",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    RadioListTile<String>(
                      title: const Text("নগদ (Cash)"),
                      value: "cash",
                      groupValue: _paymentMode,
                      onChanged: (value) {
                        setState(() {
                          _paymentMode = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text("বাকি (Due)"),
                      value: "due",
                      groupValue: _paymentMode,
                      onChanged: (value) {
                        setState(() {
                          _paymentMode = value!;
                        });
                      },
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitPurchase,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text("স্টকে যোগ করুন", style: TextStyle(fontSize: 16)),
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
// বাইক বিক্রয়: নগদ, বাকি, অথবা কিছু জমা নিয়ে বাকিটা বাকি
// ---------------------------------------------------------------
class SellScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> unit;

  const SellScreen({super.key, required this.token, required this.unit});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  DateTime _entryDate = DateTime.now();
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _priceController;
  final _decorationController = TextEditingController(text: "0");
  final _registrationController = TextEditingController(text: "0");
  final _paidController = TextEditingController(text: "0");

  List<dynamic> _customers = [];
  int? _selectedCustomerId;
  String _paymentMode = "cash";

  bool _isLoadingCustomers = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  int _numOf(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// মোট বিক্রয় মূল্য = বাইক + ডেকোরেশন + রেজিস্ট্রেশন
  int get _totalPrice =>
      _numOf(_priceController) + _numOf(_decorationController) + _numOf(_registrationController);

  /// বাকিতে বিক্রয়ে এখন যত টাকা জমা নেওয়া হচ্ছে
  int get _paidNow => _paymentMode == "due" ? _numOf(_paidController) : _totalPrice;

  int get _dueAmount => _totalPrice - _paidNow;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.unit["purchase_price"]?.toString() ?? "",
    );
    _loadCustomers();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _decorationController.dispose();
    _registrationController.dispose();
    _paidController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoadingCustomers = true;
    });
    try {
      final res = await SyncService().getList("/parties", widget.token);
      if (!mounted) return;
      if (res["data"] != null) {
        final List<dynamic> allParties = res["data"];
        setState(() {
          _customers = allParties.where((p) => p["party_type"] == "customer").toList();
        });
      } else {
        setState(() {
          _errorMessage =
              "কাস্টমার তালিকা আনা যায়নি। একবার ইন্টারনেট/ব্যাকএন্ড চালু অবস্থায় অ্যাপ খুলুন।";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "সার্ভারের সাথে সংযোগ করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCustomers = false;
        });
      }
    }
  }

  Future<void> _submitSell() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      setState(() {
        _errorMessage = "কাস্টমার বেছে নিন";
      });
      return;
    }
    if (_paymentMode == "due") {
      final paid = _numOf(_paidController);
      if (paid < 0 || paid >= _totalPrice) {
        setState(() {
          _errorMessage = "জমা মোট মূল্যের কম হতে হবে। পুরো টাকা নিলে 'নগদ' বেছে নিন";
        });
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await SyncService().apiCall(
        method: "POST",
        endpoint: "/units/${widget.unit['unit_id']}/sell",
        body: {
          "sold_price": int.parse(_priceController.text.trim()),
          "decoration_cost": _numOf(_decorationController),
          "registration_cost": _numOf(_registrationController),
          "customer_id": _selectedCustomerId,
          "payment_mode": _paymentMode,
          "paid_amount": _paymentMode == "due" ? _numOf(_paidController) : null,
          "sale_date": _fmtYmd(_entryDate),
        },
        token: widget.token,
        description: "বাইক বিক্রয়: ${widget.unit['chassis_no']}",
      );

      if (!mounted) return;

            if (result["offline"] == true) {
        // অফলাইনে ভাউচার নম্বর পাওয়া যায় না, তাই ইনভয়েস সিঙ্কের পর
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "জমা ৳$_paidNow, বাকি ৳$_dueAmount (সিঙ্কের পর ইনভয়েস হবে)",
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        Navigator.of(context).pop("offline");
        return;
      }

      if (result["error"] != true) {
        final data = result["data"];
        final voucherId = data["voucher_id"];
        final soldPrice = int.parse(_priceController.text.trim());
        final decoration = _numOf(_decorationController);
        final registration = _numOf(_registrationController);
        final grandTotal = soldPrice + decoration + registration;
        final customer = _customers.firstWhere(
          (c) => c["id"] == _selectedCustomerId,
          orElse: () => null,
        );

        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => InvoiceScreen(
              invoiceTitle: "বিক্রয় ইনভয়েস",
              invoiceNumber: "$voucherId",
              date: _entryDate,
              partyName: customer != null ? customer["name"] : "",
              partyPhone: customer != null ? customer["phone"] : null,
              paymentMode: _paymentMode,
              totalAmount: grandTotal,
              paidAmount: _paymentMode == "due" ? _numOf(_paidController) : null,
              items: [
                InvoiceItem(
                  description:
                      "${widget.unit['brand'] ?? ''} ${widget.unit['model'] ?? ''} (চেসিস: ${widget.unit['chassis_no']})",
                  qty: 1,
                  unit: "pcs",
                  unitPrice: soldPrice,
                  total: soldPrice,
                ),
                if (decoration > 0)
                  InvoiceItem(
                    description: "ডেকোরেশন খরচ",
                    qty: 1,
                    unit: "pcs",
                    unitPrice: decoration,
                    total: decoration,
                  ),
                if (registration > 0)
                  InvoiceItem(
                    description: "রেজিস্ট্রেশন খরচ",
                    qty: 1,
                    unit: "pcs",
                    unitPrice: registration,
                    total: registration,
                  ),
              ],
            ),
          ),
        );
        if (!mounted) return;
                final paidNow = _paymentMode == "due" ? _numOf(_paidController) : grandTotal;
        final dueNow = grandTotal - paidNow;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dueNow > 0
                  ? "বিক্রয় সম্পন্ন। জমা ৳$paidNow, বাকি ৳$dueNow"
                  : "বিক্রয় সম্পন্ন। পুরো টাকা পরিশোধিত",
            ),
            backgroundColor: dueNow > 0 ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _errorMessage = result["message"] ?? "বিক্রি করা যায়নি";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "সার্ভারের সাথে সংযোগ করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _sumRow(String label, int amount, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text("৳$amount", style: style),
        ],
      ),
    );
  }

  String? _optionalAmountValidator(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < 0) return "সঠিক সংখ্যা দিন";
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("বাইক বিক্রয়")),
      body: _isLoadingCustomers
          ? const Center(child: CircularProgressIndicator())
          : FormWrap(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${widget.unit['brand'] ?? ''} ${widget.unit['model'] ?? ''}",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text("চেসিস: ${widget.unit['chassis_no']}"),
                            Text("ইঞ্জিন: ${widget.unit['engine_no']}"),
                            Text("ক্রয় মূল্য: ৳${widget.unit['purchase_price']}"),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedCustomerId,
                      decoration: const InputDecoration(
                        labelText: "কাস্টমার",
                        border: OutlineInputBorder(),
                      ),
                      items: _customers.map<DropdownMenuItem<int>>((c) {
                        return DropdownMenuItem<int>(
                          value: c["id"],
                          child: Text("${c["name"]}"),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCustomerId = value;
                        });
                      },
                      validator: (value) => value == null ? "কাস্টমার বেছে নিন" : null,
                    ),
                    const SizedBox(height: 16),
                    buildEntryDateField(context, _entryDate, (d) => setState(() => _entryDate = d), "বিক্রয়ের তারিখ"),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: "বাইকের বিক্রয় মূল্য (টাকা)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return "বিক্রয় মূল্য দিন";
                        if (int.tryParse(value.trim()) == null) return "সঠিক সংখ্যা দিন";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _decorationController,
                      decoration: const InputDecoration(
                        labelText: "ডেকোরেশন খরচ (টাকা)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      validator: _optionalAmountValidator,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _registrationController,
                      decoration: const InputDecoration(
                        labelText: "রেজিস্ট্রেশন খরচ (টাকা)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      validator: _optionalAmountValidator,
                    ),
                    const SizedBox(height: 16),
                    const Text("পেমেন্ট মোড", style: TextStyle(fontWeight: FontWeight.bold)),
                    RadioListTile<String>(
                      title: const Text("নগদ (পুরো টাকা এখন পেয়েছি)"),
                      value: "cash",
                      groupValue: _paymentMode,
                      onChanged: (value) {
                        setState(() {
                          _paymentMode = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text("বাকি (কিছু জমা নিয়ে বাকিটা বাকি, বা পুরোটাই বাকি)"),
                      value: "due",
                      groupValue: _paymentMode,
                      onChanged: (value) {
                        setState(() {
                          _paymentMode = value!;
                        });
                      },
                    ),
                    if (_paymentMode == "due") ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _paidController,
                        decoration: const InputDecoration(
                          labelText: "এখন জমা নিচ্ছেন (টাকা) — পুরোটা বাকি হলে ০",
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty) return null;
                          final n = int.tryParse(v);
                          if (n == null || n < 0) return "সঠিক সংখ্যা দিন";
                          if (n >= _totalPrice) return "জমা মোট মূল্যের কম হতে হবে";
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        children: [
                          _sumRow("বাইকের মূল্য", _numOf(_priceController)),
                          _sumRow("ডেকোরেশন খরচ", _numOf(_decorationController)),
                          _sumRow("রেজিস্ট্রেশন খরচ", _numOf(_registrationController)),
                          const Divider(),
                          _sumRow("মোট বিক্রয় মূল্য", _totalPrice, bold: true),
                          if (_paymentMode == "due") ...[
                            const Divider(),
                            _sumRow("এখন জমা", _paidNow),
                            _sumRow("বাকি থাকবে", _dueAmount, bold: true),
                            
                          ],
                        ],
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitSell,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                "বিক্রয় নিশ্চিত করুন (৳$_totalPrice)",
                                style: const TextStyle(fontSize: 16, color: Colors.white),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

String _fmtYmd(DateTime d) =>
    "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

Widget buildEntryDateField(BuildContext context, DateTime value,
    ValueChanged<DateTime> onChanged, String label) {
  return InkWell(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (picked != null) onChanged(picked);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today),
      ),
      child: Text(_fmtYmd(value)),
    ),
  );
}
