import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'app_theme.dart';

/// বাংলা অঙ্ক ইংরেজিতে বদলে সংখ্যা বের করে (ভুল হলে null)
int? _toIntOrNull(String s) {
  const bn = '০১২৩৪৫৬৭৮৯';
  final buf = StringBuffer();
  for (final ch in s.replaceAll(',', '').replaceAll(' ', '').split('')) {
    final i = bn.indexOf(ch);
    buf.write(i >= 0 ? '$i' : ch);
  }
  return int.tryParse(buf.toString());
}

// ---------------------------------------------------------------
// প্রোডাক্ট মডেলের তালিকা
// ---------------------------------------------------------------
class ProductListScreen extends StatefulWidget {
  final String token;

  const ProductListScreen({super.key, required this.token});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _products = [];
  Map<int, String> _brandNames = {};

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final headers = {"Authorization": "Bearer ${widget.token}"};
      final response =
          await http.get(Uri.parse("$apiBaseUrl/products"), headers: headers);

      // ব্র্যান্ডের নাম দেখানোর জন্য (না পেলে "-" দেখাবে)
      try {
        final brandRes =
            await http.get(Uri.parse("$apiBaseUrl/brands"), headers: headers);
        if (brandRes.statusCode == 200) {
          final List<dynamic> list = jsonDecode(brandRes.body);
          _brandNames = {for (final b in list) b["id"] as int: "${b["name"]}"};
        }
      } catch (_) {}

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _products = jsonDecode(response.body);
        });
      } else {
        setState(() {
          _errorMessage = "তালিকা আনতে সমস্যা হয়েছে";
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
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openAddProduct() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddProductScreen(token: widget.token),
      ),
    );
    if (result == true) {
      _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("প্রোডাক্ট মডেল যোগ হয়েছে")),
      );
    }
  }

  Future<void> _openEditProduct(Map<String, dynamic> product) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            AddProductScreen(token: widget.token, product: product),
      ),
    );
    if (result == true) {
      _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("প্রোডাক্ট মডেল আপডেট হয়েছে")),
      );
    } else if (result == "pending") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে"),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("মডেল মুছবেন?"),
        content: Text("\"${product["model_name"]}\" স্থায়ীভাবে মুছে যাবে।"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("না"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("হ্যাঁ, মুছুন",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final response = await http.delete(
        Uri.parse("$apiBaseUrl/products/${product["id"]}"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        _loadProducts();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("প্রোডাক্ট মডেল মুছে ফেলা হয়েছে")),
        );
      } else if (response.statusCode == 202) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে"),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        String msg = "মুছা যায়নি";
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data["detail"] is String) msg = data["detail"];
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("সার্ভারের সাথে সংযোগ করা যায়নি"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("প্রোডাক্ট মডেল")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddProduct,
        icon: const Icon(Icons.add),
        label: const Text("নতুন মডেল"),
      ),
      body: RefreshIndicator(
        onRefresh: _loadProducts,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage!,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadProducts,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    ),
                  )
                : _products.isEmpty
                    ? const Center(child: Text("কোনো প্রোডাক্ট মডেল নেই"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final p = _products[index];
                          final brand = _brandNames[p["brand_id"]] ?? "-";
                          final price = p["unit_price"];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => _openEditProduct(
                                  Map<String, dynamic>.from(p)),
                              leading: const CircleAvatar(
                                child: Icon(Icons.two_wheeler),
                              ),
                              title: Text(
                                "$brand ${p["model_name"] ?? ''}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                "ক্যাটাগরি: ${p["category"] ?? '-'}\n"
                                "মূল্য: ${price == null ? '-' : '৳$price'}",
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: "এডিট",
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _openEditProduct(
                                        Map<String, dynamic>.from(p)),
                                  ),
                                  IconButton(
                                    tooltip: "মুছুন",
                                    icon: const Icon(Icons.delete_outline,
                                        size: 22, color: Colors.red),
                                    onPressed: () => _deleteProduct(
                                        Map<String, dynamic>.from(p)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// নতুন প্রোডাক্ট মডেল যোগ করার ফর্ম
// ---------------------------------------------------------------
/// product দিলে এডিট মোড, না দিলে নতুন যোগ করার ফর্ম
class AddProductScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? product;

  const AddProductScreen({super.key, required this.token, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _modelController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();

  List<dynamic> _brands = [];
  int? _selectedBrandId;

  bool _isLoadingBrands = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _modelController.text = "${p["model_name"] ?? ''}";
      _categoryController.text = "${p["category"] ?? ''}";
      _priceController.text = p["unit_price"] == null ? "" : "${p["unit_price"]}";
      _selectedBrandId = p["brand_id"] as int?;
    }
    _loadBrands();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadBrands() async {
    setState(() {
      _isLoadingBrands = true;
    });
    try {
      final response =
          await http.get(Uri.parse("$apiBaseUrl/brands"), headers: _headers);
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _brands = jsonDecode(response.body);
        });
      }
    } catch (e) {
      // ব্র্যান্ড তালিকা না এলেও নতুন ব্র্যান্ড যোগ করার বাটন থাকছে
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBrands = false;
        });
      }
    }
  }

  Future<void> _addBrandDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("নতুন ব্র্যান্ড"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "ব্র্যান্ডের নাম (যেমন: Bajaj)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("বাতিল"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text("যোগ করুন"),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/brands"),
        headers: _headers,
        body: jsonEncode({"name": name}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final created = jsonDecode(response.body);
        await _loadBrands();
        if (!mounted) return;
        setState(() {
          _selectedBrandId = created["id"] as int?;
        });
      } else {
        setState(() {
          _errorMessage =
              "ব্র্যান্ড যোগ করা যায়নি (নামটি আগে থেকেই থাকতে পারে)";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "সার্ভারের সাথে সংযোগ করা যায়নি";
      });
    }
  }

  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final category = _categoryController.text.trim();
    final body = <String, dynamic>{
      "brand_id": _selectedBrandId,
      "model_name": _modelController.text.trim(),
      "category": category.isEmpty ? null : category,
      "unit_price": _toIntOrNull(_priceController.text),
    };

    try {
      final response = _isEdit
          ? await http.patch(
              Uri.parse("$apiBaseUrl/products/${widget.product!["id"]}"),
              headers: _headers,
              body: jsonEncode(body),
            )
          : await http.post(
              Uri.parse("$apiBaseUrl/products"),
              headers: _headers,
              body: jsonEncode(body),
            );

      if (!mounted) return;
      if (response.statusCode == 200) {
        Navigator.of(context).pop(true);
      } else if (response.statusCode == 202) {
        Navigator.of(context).pop("pending");
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _errorMessage =
              data["detail"] is String ? data["detail"] : "যোগ করা যায়নি";
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
      appBar: AppBar(
          title: Text(_isEdit ? "প্রোডাক্ট মডেল এডিট" : "নতুন প্রোডাক্ট মডেল")),
      body: _isLoadingBrands
          ? const Center(child: CircularProgressIndicator())
          : FormWrap(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(_selectedBrandId),
                            initialValue: _selectedBrandId,
                            decoration: const InputDecoration(
                              labelText: "ব্র্যান্ড",
                              border: OutlineInputBorder(),
                            ),
                            items: _brands.map<DropdownMenuItem<int>>((b) {
                              return DropdownMenuItem<int>(
                                value: b["id"],
                                child: Text("${b["name"]}"),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedBrandId = value;
                              });
                            },
                            validator: (value) =>
                                value == null ? "ব্র্যান্ড বাছাই করুন" : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _addBrandDialog,
                            icon: const Icon(Icons.add),
                            label: const Text("ব্র্যান্ড"),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: "মডেলের নাম (যেমন: Pulsar 150)",
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? "মডেলের নাম দিন"
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        labelText: "ক্যাটাগরি (ঐচ্ছিক, যেমন: 150cc)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: "মূল্য (ঐচ্ছিক)",
                        prefixText: "৳ ",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        return _toIntOrNull(value) == null
                            ? "সঠিক সংখ্যা দিন"
                            : null;
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
                        onPressed: _isSubmitting ? null : _submitProduct,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_isEdit ? "সংরক্ষণ করুন" : "যোগ করুন",
                                style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}