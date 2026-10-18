import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'sync_service.dart';
import 'reports_screen.dart';

class ReceivablesScreen extends StatefulWidget {
  final String token;

  const ReceivablesScreen({super.key, required this.token});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  bool _isLoading = true;
  bool _fromCache = false;
  String? _errorMessage;
  List<dynamic> _customers = [];
  int? _sendingReminderFor;

  @override
  void initState() {
    super.initState();
    _loadReceivables();
  }

  Future<void> _loadReceivables() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await SyncService()
          .getList("/reports/receivables-by-party", widget.token);
      if (res["data"] != null) {
        setState(() {
          _customers = res["data"]["customers"];
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

  Future<void> _openCollect(Map<String, dynamic> customer) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CollectPaymentScreen(token: widget.token, customer: customer),
      ),
    );
    if (result == true) {
      _loadReceivables();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("আদায় সফল হয়েছে")),
        );
      }
    } else if (result == "offline") {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ইন্টারনেট নেই — আদায়ের এন্ট্রি পরে সিঙ্ক হবে"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _sendReminder(Map<String, dynamic> customer) async {
    final customerId = customer["customer_id"];
    setState(() {
      _sendingReminderFor = customerId;
    });

    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/parties/$customerId/send-due-reminder"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("রিমাইন্ডার পাঠানো হয়েছে")),
        );
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data["detail"] ?? "রিমাইন্ডার পাঠানো যায়নি")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("রিমাইন্ডার পাঠাতে সার্ভারের সংযোগ লাগে")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingReminderFor = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("বাকির তালিকা ও আদায়"),
        actions: [
          ReportsIconButton(
            token: widget.token,
            title: "বাকির রিপোর্ট",
            groups: const ['Customer'],
          ),
          IconButton(
            tooltip: "রিফ্রেশ",
            icon: const Icon(Icons.refresh),
            onPressed: _loadReceivables,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_fromCache && !_isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade100,
              child: const Text(
                "অফলাইন — সর্বশেষ সংরক্ষিত তালিকা (বাকির অঙ্ক পুরনো হতে পারে)",
                style: TextStyle(fontSize: 13),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadReceivables,
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
                                onPressed: _loadReceivables,
                                child: const Text("আবার চেষ্টা করুন"),
                              ),
                            ],
                          ),
                        )
                      : _customers.isEmpty
                          ? const Center(child: Text("কোনো বাকি নেই"))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _customers.length,
                              itemBuilder: (context, index) {
                                final customer = _customers[index];
                                final isSending = _sendingReminderFor == customer["customer_id"];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ListTile(
                                            onTap: () => _openCollect(customer),
                                            leading: const CircleAvatar(
                                              child: Icon(Icons.person),
                                            ),
                                            title: Text(
                                              customer["customer_name"] ?? "",
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            subtitle: Text(
                                              "এলাকা: ${customer['area'] ?? '-'} | "
                                              "ফোন: ${customer['phone'] ?? '-'}",
                                            ),
                                            trailing: Text(
                                              "৳${customer['due_amount']}",
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold, color: Colors.red),
                                            ),
                                          ),
                                        ),
                                        isSending
                                            ? const Padding(
                                                padding: EdgeInsets.only(right: 16),
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                              )
                                            : IconButton(
                                                icon: const Icon(Icons.sms, color: Colors.blue),
                                                tooltip: "SMS রিমাইন্ডার পাঠান",
                                                onPressed: () => _sendReminder(customer),
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

class CollectPaymentScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> customer;

  const CollectPaymentScreen({super.key, required this.token, required this.customer});

  @override
  State<CollectPaymentScreen> createState() => _CollectPaymentScreenState();
}

class _CollectPaymentScreenState extends State<CollectPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _narrationController = TextEditingController();
  String _paymentMode = "cash";
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submitReceipt() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final amount = int.parse(_amountController.text.trim());

    try {
      final result = await SyncService().apiCall(
        method: "POST",
        endpoint: "/receipts",
        body: {
          "amount": amount,
          "customer_id": widget.customer["customer_id"],
          "payment_mode": _paymentMode,
          "narration": _narrationController.text.trim().isEmpty
              ? null
              : _narrationController.text.trim(),
        },
        token: widget.token,
        description: "বাকি আদায়: ${widget.customer['customer_name']} ৳$amount",
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
        _errorMessage = "আদায় করা যায়নি";
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
      appBar: AppBar(title: const Text("বাকি আদায়")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
                        widget.customer["customer_name"] ?? "",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "বর্তমান বাকি: ৳${widget.customer['due_amount']}",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: "আদায়কৃত টাকার পরিমাণ",
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
                  onPressed: _isSubmitting ? null : _submitReceipt,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          "আদায় নিশ্চিত করুন",
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