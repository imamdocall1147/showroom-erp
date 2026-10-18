import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'reports_screen.dart';

class PayablesScreen extends StatefulWidget {
  final String token;

  const PayablesScreen({super.key, required this.token});

  @override
  State<PayablesScreen> createState() => _PayablesScreenState();
}

class _PayablesScreenState extends State<PayablesScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _loadPayables();
  }

  Future<void> _loadPayables() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse("$apiBaseUrl/reports/payables-by-party"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _suppliers = data["suppliers"];
        });
      } else {
        setState(() {
          _errorMessage = "তালিকা আনতে সমস্যা হয়েছে";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "সার্ভারের সাথে সংযোগ করা যায়নি";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openPay(Map<String, dynamic> supplier) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PaySupplierScreen(token: widget.token, supplier: supplier),
      ),
    );
    if (result == true) {
      _loadPayables();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("পরিশোধ সফল হয়েছে")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("সরবরাহকারীর পাওনা"),
        actions: [
          ReportsIconButton(
            token: widget.token,
            title: "ক্রয় রিপোর্ট",
            groups: const ['Purchase'],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPayables,
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
                          onPressed: _loadPayables,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    ),
                  )
                : _suppliers.isEmpty
                    ? const Center(child: Text("কোনো পাওনা নেই"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _suppliers.length,
                        itemBuilder: (context, index) {
                          final supplier = _suppliers[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => _openPay(supplier),
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.shade100,
                                child: const Icon(Icons.local_shipping, color: Colors.orange),
                              ),
                              title: Text(
                                supplier["supplier_name"] ?? "",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                "এলাকা: ${supplier['area'] ?? '-'} | "
                                "ফোন: ${supplier['phone'] ?? '-'}",
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "৳${supplier['payable_amount']}",
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                                  ),
                                  const Icon(Icons.chevron_right, color: Colors.grey),
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

class PaySupplierScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> supplier;

  const PaySupplierScreen({super.key, required this.token, required this.supplier});

  @override
  State<PaySupplierScreen> createState() => _PaySupplierScreenState();
}

class _PaySupplierScreenState extends State<PaySupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _narrationController = TextEditingController();
  String _paymentMode = "cash";
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/supplier-payments"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode({
          "amount": int.parse(_amountController.text.trim()),
          "supplier_id": widget.supplier["supplier_id"],
          "payment_mode": _paymentMode,
          "narration": _narrationController.text.trim().isEmpty
              ? null
              : _narrationController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _errorMessage = data["detail"] ?? "পরিশোধ করা যায়নি";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "সার্ভারের সাথে সংযোগ করা যায়নি";
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("সরবরাহকারীকে পরিশোধ")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.supplier["supplier_name"] ?? "",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "বর্তমান পাওনা: ৳${widget.supplier['payable_amount']}",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: "পরিশোধের পরিমাণ",
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return "পরিমাণ দিন";
                  if (int.tryParse(value.trim()) == null) return "সঠিক সংখ্যা দিন";
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _narrationController,
                decoration: const InputDecoration(
                  labelText: "মন্তব্য (ঐচ্ছিক)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text("পেমেন্ট মোড", style: TextStyle(fontWeight: FontWeight.bold)),
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
                title: const Text("ব্যাংক (Bank)"),
                value: "bank",
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
                  onPressed: _isSubmitting ? null : _submitPayment,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          "পরিশোধ নিশ্চিত করুন",
                          style: TextStyle(fontSize: 16, color: Colors.white),
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