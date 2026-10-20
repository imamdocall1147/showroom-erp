import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'invoice_screen.dart';
import 'sync_service.dart';

const String _offlineSnackText = "ইন্টারনেট নেই — এন্ট্রিটা পরে সিঙ্ক হবে";

String _msgFrom(http.Response response, String fallback) {
  try {
    final data = jsonDecode(response.body);
    if (data is Map) {
      if (data["detail"] is String) return data["detail"];
      if (data["message"] is String) return data["message"];
    }
  } catch (_) {}
  return fallback;
}

class SparePartsScreen extends StatefulWidget {
  final String token;

  const SparePartsScreen({super.key, required this.token});

  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  bool _isLoading = true;
  bool _fromCache = false;
  String? _errorMessage;
  List<dynamic> _parts = [];

  @override
  void initState() {
    super.initState();
    _loadParts();
  }

  Future<void> _loadParts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await SyncService().getList("/spare-parts", widget.token);
      if (res["data"] != null) {
        setState(() {
          _parts = res["data"];
          _fromCache = res["fromCache"] == true;
        });
      } else {
        setState(() {
          _errorMessage = "তালিকা আনতে সমস্যা হয়েছে";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "তালিকা লোড করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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

  void _showOfflineSnack() {
    _snack(_offlineSnackText, color: Colors.orange);
  }

  Future<void> _openAddPart() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddSparePartScreen(token: widget.token),
      ),
    );
    if (result == true) {
      _loadParts();
      _snack("পার্টস সফলভাবে যোগ হয়েছে");
    } else if (result == "offline") {
      _showOfflineSnack();
    }
  }

  Future<void> _openPartAction(Map<String, dynamic> part) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SparePartActionScreen(token: widget.token, part: part),
      ),
    );
    if (result == true) {
      _loadParts();
    } else if (result == "offline") {
      _showOfflineSnack();
    }
  }

  Future<void> _openEditPart(Map<String, dynamic> part) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditSparePartScreen(token: widget.token, part: part),
      ),
    );
    if (result == true) {
      _loadParts();
      _snack("পার্টসের তথ্য আপডেট হয়েছে");
    } else if (result == "pending") {
      _snack("অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে", color: Colors.orange);
    }
  }

  Future<void> _deletePart(Map<String, dynamic> part) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("পার্টস মুছবেন?"),
        content: Text("\"${part["name"]}\" স্থায়ীভাবে মুছে যাবে।"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("না"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("হ্যাঁ, মুছুন", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final response = await http.delete(
        Uri.parse("$apiBaseUrl/spare-parts/${part["id"]}"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );
      if (response.statusCode == 200) {
        _loadParts();
        _snack("পার্টস মুছে ফেলা হয়েছে");
      } else if (response.statusCode == 202) {
        _snack(_msgFrom(response, "অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে"),
            color: Colors.orange);
      } else {
        _snack(_msgFrom(response, "মুছা যায়নি"), color: Colors.red);
      }
    } catch (e) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("স্পেয়ার পার্টস"),
        actions: [
          IconButton(
            tooltip: "রিফ্রেশ",
            icon: const Icon(Icons.refresh),
            onPressed: _loadParts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddPart,
        icon: const Icon(Icons.add),
        label: const Text("নতুন পার্টস"),
      ),
      body: Column(
        children: [
          if (_fromCache && !_isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade100,
              child: const Text(
                "অফলাইন — সর্বশেষ সংরক্ষিত তালিকা দেখানো হচ্ছে (স্টক সংখ্যা পুরনো হতে পারে)",
                style: TextStyle(fontSize: 13),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadParts,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _loadParts,
                                child: const Text("আবার চেষ্টা করুন"),
                              ),
                            ],
                          ),
                        )
                      : _parts.isEmpty
                          ? const Center(child: Text("কোনো পার্টস নেই"))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _parts.length,
                              itemBuilder: (context, index) {
                                final part = _parts[index];
                                final qty = part["stock_qty"] as int;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    onTap: () => _openPartAction(part),
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          qty > 0 ? Colors.green.shade100 : Colors.red.shade100,
                                      child: Icon(
                                        Icons.settings,
                                        color: qty > 0 ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    title: Text(
                                      part["name"] ?? "",
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      "স্টক: $qty ${part['unit']} | বিক্রয় মূল্য: ৳${part['sale_price']}",
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      tooltip: "আরও",
                                      onSelected: (value) {
                                        final p = Map<String, dynamic>.from(part);
                                        if (value == "edit") _openEditPart(p);
                                        if (value == "delete") _deletePart(p);
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: "edit",
                                          child: ListTile(
                                            leading: Icon(Icons.edit),
                                            title: Text("তথ্য এডিট"),
                                            dense: true,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: "delete",
                                          child: ListTile(
                                            leading: Icon(Icons.delete_outline, color: Colors.red),
                                            title: Text("মুছুন", style: TextStyle(color: Colors.red)),
                                            dense: true,
                                          ),
                                        ),
                                      ],
                                    ),
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

class AddSparePartScreen extends StatefulWidget {
  final String token;

  const AddSparePartScreen({super.key, required this.token});

  @override
  State<AddSparePartScreen> createState() => _AddSparePartScreenState();
}

class _AddSparePartScreenState extends State<AddSparePartScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _unitController = TextEditingController(text: "pcs");
  final _purchasePriceController = TextEditingController();
  final _salePriceController = TextEditingController();

  List<dynamic> _warehouses = [];
  int? _selectedWarehouseId;

  bool _isLoadingWarehouses = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _isLoadingWarehouses = true;
    });
    try {
      final res = await SyncService().getList("/warehouses", widget.token);
      if (res["data"] != null) {
        setState(() {
          _warehouses = res["data"];
        });
      } else {
        setState(() {
          _errorMessage =
              "গোডাউন তালিকা আনা যায়নি। একবার ইন্টারনেট/ব্যাকএন্ড চালু অবস্থায় অ্যাপ খুলুন।";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "গোডাউন তালিকা লোড করা যায়নি";
      });
    } finally {
      setState(() {
        _isLoadingWarehouses = false;
      });
    }
  }

  Future<void> _submitPart() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWarehouseId == null) {
      setState(() {
        _errorMessage = "গোডাউন বেছে নিন";
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await SyncService().apiCall(
        method: "POST",
        endpoint: "/spare-parts",
        body: {
          "name": _nameController.text.trim(),
          "unit": _unitController.text.trim().isEmpty ? "pcs" : _unitController.text.trim(),
          "warehouse_id": _selectedWarehouseId,
          "purchase_price": int.tryParse(_purchasePriceController.text.trim()) ?? 0,
          "sale_price": int.tryParse(_salePriceController.text.trim()) ?? 0,
        },
        token: widget.token,
        description: "নতুন পার্টস: ${_nameController.text.trim()}",
      );

      if (!mounted) return;

      if (result["offline"] == true) {
        Navigator.of(context).pop("offline");
      } else if (result["error"] == true) {
        setState(() {
          _errorMessage = result["message"];
        });
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "যোগ করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("নতুন স্পেয়ার পার্টস")),
      body: _isLoadingWarehouses
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: "পার্টসের নাম",
                        hintText: "যেমন: Brake Shoe, Clutch Plate",
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? "নাম দিন" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _unitController,
                      decoration: const InputDecoration(
                        labelText: "একক (pcs, liter ইত্যাদি)",
                        border: OutlineInputBorder(),
                      ),
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
                    TextFormField(
                      controller: _purchasePriceController,
                      decoration: const InputDecoration(
                        labelText: "ক্রয় মূল্য (প্রতি একক)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _salePriceController,
                      decoration: const InputDecoration(
                        labelText: "বিক্রয় মূল্য (প্রতি একক)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
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
                        onPressed: _isSubmitting ? null : _submitPart,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text("যোগ করুন", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// পার্টসের নাম, একক, গোডাউন ও দাম এডিট (স্টকের সংখ্যা বদলায় না, সেটা ক্রয়/বিক্রয় দিয়ে হয়)
class EditSparePartScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> part;

  const EditSparePartScreen({super.key, required this.token, required this.part});

  @override
  State<EditSparePartScreen> createState() => _EditSparePartScreenState();
}

class _EditSparePartScreenState extends State<EditSparePartScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _unitController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _salePriceController = TextEditingController();

  List<dynamic> _warehouses = [];
  int? _selectedWarehouseId;

  bool _isLoadingWarehouses = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.part;
    _nameController.text = "${p["name"] ?? ''}";
    _unitController.text = "${p["unit"] ?? 'pcs'}";
    _purchasePriceController.text = "${p["purchase_price"] ?? 0}";
    _salePriceController.text = "${p["sale_price"] ?? 0}";
    _selectedWarehouseId = p["warehouse_id"] as int?;
    _loadWarehouses();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    try {
      final res = await SyncService().getList("/warehouses", widget.token);
      if (res["data"] != null && mounted) {
        setState(() {
          _warehouses = res["data"];
        });
      }
    } catch (e) {
      // তালিকা না এলেও নাম/দাম এডিট করা যাবে
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWarehouses = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final body = <String, dynamic>{
      "name": _nameController.text.trim(),
      "unit": _unitController.text.trim().isEmpty ? "pcs" : _unitController.text.trim(),
      "warehouse_id": _selectedWarehouseId,
      "purchase_price": int.tryParse(_purchasePriceController.text.trim()) ?? 0,
      "sale_price": int.tryParse(_salePriceController.text.trim()) ?? 0,
    };

    try {
      final response = await http.patch(
        Uri.parse("$apiBaseUrl/spare-parts/${widget.part["id"]}"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode(body),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        Navigator.of(context).pop(true);
      } else if (response.statusCode == 202) {
        Navigator.of(context).pop("pending");
      } else {
        setState(() {
          _errorMessage = _msgFrom(response, "আপডেট করা যায়নি");
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("পার্টস এডিট")),
      body: _isLoadingWarehouses
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "বর্তমান স্টক: ${widget.part["stock_qty"]} ${widget.part["unit"]} "
                        "(স্টকের সংখ্যা এখান থেকে বদলায় না, ক্রয়/বিক্রয় থেকে বদলায়)",
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: "পার্টসের নাম",
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? "নাম দিন" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _unitController,
                      decoration: const InputDecoration(
                        labelText: "একক (pcs, liter ইত্যাদি)",
                        border: OutlineInputBorder(),
                      ),
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
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _purchasePriceController,
                      decoration: const InputDecoration(
                        labelText: "ক্রয় মূল্য (প্রতি একক)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _salePriceController,
                      decoration: const InputDecoration(
                        labelText: "বিক্রয় মূল্য (প্রতি একক)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
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
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
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
            ),
    );
  }
}

class SparePartActionScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> part;

  const SparePartActionScreen({super.key, required this.token, required this.part});

  @override
  State<SparePartActionScreen> createState() => _SparePartActionScreenState();
}

class _SparePartActionScreenState extends State<SparePartActionScreen> {
  final _restockController = TextEditingController();
  final _sellQtyController = TextEditingController();
  String _sellPaymentMode = "cash";
  String _restockPaymentMode = "cash";

  List<dynamic> _customers = [];
  List<dynamic> _suppliers = [];
  int? _selectedCustomerId;
  int? _selectedSupplierId;
  bool _isLoadingParties = true;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    setState(() {
      _isLoadingParties = true;
    });
    try {
      final res = await SyncService().getList("/parties", widget.token);
      if (res["data"] != null) {
        final List<dynamic> allParties = res["data"];
        setState(() {
          _customers = allParties.where((p) => p["party_type"] == "customer").toList();
          _suppliers = allParties.where((p) => p["party_type"] == "supplier").toList();
        });
      }
    } catch (e) {
      // তালিকা আনতে ব্যর্থ হলেও নগদ লেনদেন চালিয়ে যাওয়া যাবে
    } finally {
      setState(() {
        _isLoadingParties = false;
      });
    }
  }

  Future<void> _restock() async {
    final qty = int.tryParse(_restockController.text.trim());
    if (qty == null || qty <= 0) {
      setState(() {
        _errorMessage = "সঠিক পরিমাণ দিন";
      });
      return;
    }
    if (_restockPaymentMode == "due" && _selectedSupplierId == null) {
      setState(() {
        _errorMessage = "বাকিতে ক্রয় করতে সাপ্লায়ার বেছে নিন";
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await SyncService().apiCall(
        method: "POST",
        endpoint: "/spare-parts/${widget.part['id']}/restock",
        body: {
          "qty": qty,
          "payment_mode": _restockPaymentMode,
          "supplier_id": _restockPaymentMode == "due" ? _selectedSupplierId : null,
        },
        token: widget.token,
        description: "পার্টস স্টক বাড়ানো: ${widget.part['name']} × $qty",
      );

      if (!mounted) return;

      if (result["offline"] == true) {
        Navigator.of(context).pop("offline");
      } else if (result["error"] == true) {
        setState(() {
          _errorMessage = result["message"];
        });
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "স্টক বাড়ানো যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _sell() async {
    final qty = int.tryParse(_sellQtyController.text.trim());
    if (qty == null || qty <= 0) {
      setState(() {
        _errorMessage = "সঠিক পরিমাণ দিন";
      });
      return;
    }
    if (_sellPaymentMode == "due" && _selectedCustomerId == null) {
      setState(() {
        _errorMessage = "বাকিতে বিক্রি করতে কাস্টমার বেছে নিন";
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await SyncService().apiCall(
        method: "POST",
        endpoint: "/spare-parts/${widget.part['id']}/sell",
        body: {
          "qty": qty,
          "payment_mode": _sellPaymentMode,
          "customer_id": _selectedCustomerId,
        },
        token: widget.token,
        description: "পার্টস বিক্রয়: ${widget.part['name']} × $qty",
      );

      if (!mounted) return;

      if (result["offline"] == true) {
        // অফলাইনে ভাউচার নম্বর পাওয়া যায় না, তাই ইনভয়েস সিঙ্কের পর
        Navigator.of(context).pop("offline");
        return;
      }
      if (result["error"] == true) {
        setState(() {
          _errorMessage = result["message"];
        });
        return;
      }

      final data = result["data"];
      final voucherId = data["voucher_id"];
      final totalSale = data["total_sale"];
      final unitPrice = qty > 0 ? (totalSale / qty).round() : totalSale;
      final customer = _customers.firstWhere(
        (c) => c["id"] == _selectedCustomerId,
        orElse: () => null,
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => InvoiceScreen(
            invoiceTitle: "স্পেয়ার পার্টস বিক্রয় ইনভয়েস",
            invoiceNumber: "$voucherId",
            date: DateTime.now(),
            partyName: customer != null ? customer["name"] : "",
            partyPhone: customer != null ? customer["phone"] : null,
            paymentMode: _sellPaymentMode,
            totalAmount: totalSale,
            items: [
              InvoiceItem(
                description: widget.part["name"] ?? "",
                qty: qty,
                unit: widget.part["unit"] ?? "pcs",
                unitPrice: unitPrice,
                total: totalSale,
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = "বিক্রি করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.part["name"] ?? "")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
                      "বর্তমান স্টক: ${widget.part['stock_qty']} ${widget.part['unit']}",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text("ক্রয় মূল্য: ৳${widget.part['purchase_price']} | বিক্রয় মূল্য: ৳${widget.part['sale_price']}"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text("স্টক বাড়ান (ক্রয়)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _restockController,
              decoration: const InputDecoration(
                labelText: "পরিমাণ",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            const Text("পেমেন্ট মোড", style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile<String>(
              title: const Text("নগদ (Cash)"),
              value: "cash",
              groupValue: _restockPaymentMode,
              onChanged: (value) {
                setState(() {
                  _restockPaymentMode = value!;
                });
              },
            ),
            RadioListTile<String>(
              title: const Text("বাকি (Due)"),
              value: "due",
              groupValue: _restockPaymentMode,
              onChanged: (value) {
                setState(() {
                  _restockPaymentMode = value!;
                });
              },
            ),
            if (_restockPaymentMode == "due") ...[
              const SizedBox(height: 8),
              _isLoadingParties
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
                      initialValue: _selectedSupplierId,
                      decoration: const InputDecoration(
                        labelText: "সাপ্লায়ার",
                        border: OutlineInputBorder(),
                      ),
                      items: _suppliers.map<DropdownMenuItem<int>>((s) {
                        return DropdownMenuItem<int>(
                          value: s["id"],
                          child: Text("${s["name"]}"),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedSupplierId = value;
                        });
                      },
                    ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _restock,
                child: const Text("স্টকে যোগ করুন"),
              ),
            ),
            const SizedBox(height: 32),
            const Text("বিক্রয়", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _sellQtyController,
              decoration: const InputDecoration(
                labelText: "পরিমাণ",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              title: const Text("নগদ (Cash)"),
              value: "cash",
              groupValue: _sellPaymentMode,
              onChanged: (value) {
                setState(() {
                  _sellPaymentMode = value!;
                });
              },
            ),
            RadioListTile<String>(
              title: const Text("বাকি (Due)"),
              value: "due",
              groupValue: _sellPaymentMode,
              onChanged: (value) {
                setState(() {
                  _sellPaymentMode = value!;
                });
              },
            ),
            if (_sellPaymentMode == "due") ...[
              const SizedBox(height: 8),
              _isLoadingParties
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
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
                    ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _sell,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text("বিক্রয় নিশ্চিত করুন", style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}