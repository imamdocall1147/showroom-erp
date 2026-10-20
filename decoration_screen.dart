import 'package:flutter/material.dart';
import 'main.dart';
import 'invoice_screen.dart';
import 'sync_service.dart';
import 'app_theme.dart';

/// বাইক বিক্রয় ছাড়া আলাদাভাবে ডেকোরেশনের টাকা নেওয়ার এন্ট্রি।
class DecorationIncomeScreen extends StatefulWidget {
  final String token;

  const DecorationIncomeScreen({super.key, required this.token});

  @override
  State<DecorationIncomeScreen> createState() => _DecorationIncomeScreenState();
}

class _DecorationIncomeScreenState extends State<DecorationIncomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  List<dynamic> _customers = [];
  int? _selectedCustomerId;
  String _paymentMode = "cash";

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final res = await SyncService().getList("/parties", widget.token);
      if (!mounted) return;
      if (res["data"] != null) {
        final List<dynamic> all = res["data"];
        setState(() {
          _customers = all.where((p) => p["party_type"] == "customer").toList();
        });
      } else {
        setState(() {
          _errorMessage = "কাস্টমার তালিকা আনা যায়নি";
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_paymentMode == "due" && _selectedCustomerId == null) {
      setState(() {
        _errorMessage = "বাকিতে হলে কাস্টমার বেছে নিন";
      });
      return;
    }

    final amount = int.parse(_amountController.text.trim());
    final note = _noteController.text.trim();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await SyncService().apiCall(
        method: "POST",
        endpoint: "/decoration-income",
        body: {
          "amount": amount,
          "customer_id": _selectedCustomerId,
          "payment_mode": _paymentMode,
          "note": note.isEmpty ? null : note,
        },
        token: widget.token,
        description: "ডেকোরেশন আয়: ৳$amount",
      );

      if (!mounted) return;

      if (result["offline"] == true) {
        Navigator.of(context).pop("offline");
        return;
      }

      if (result["error"] == true) {
        setState(() {
          _errorMessage = result["message"] ?? "এন্ট্রি করা যায়নি";
        });
        return;
      }

      final data = result["data"];
      final voucherId = data is Map ? data["voucher_id"] : null;
      final customer = _customers.firstWhere(
        (c) => c["id"] == _selectedCustomerId,
        orElse: () => null,
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => InvoiceScreen(
            invoiceTitle: "ডেকোরেশন ইনভয়েস",
            invoiceNumber: "${voucherId ?? '-'}",
            date: DateTime.now(),
            partyName: customer != null ? customer["name"] : "নগদ কাস্টমার",
            partyPhone: customer != null ? customer["phone"] : null,
            paymentMode: _paymentMode,
            totalAmount: amount,
            items: [
              InvoiceItem(
                description: note.isEmpty ? "ডেকোরেশন খরচ" : "ডেকোরেশন: $note",
                qty: 1,
                unit: "pcs",
                unitPrice: amount,
                total: amount,
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text("ডেকোরেশন আয় (বাইক বিক্রয় ছাড়া)")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FormWrap(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int?>(
                      initialValue: _selectedCustomerId,
                      decoration: const InputDecoration(
                        labelText: "কাস্টমার (নগদে হলে ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text("— কাস্টমার ছাড়া —"),
                        ),
                        ..._customers.map<DropdownMenuItem<int?>>((c) {
                          return DropdownMenuItem<int?>(
                            value: c["id"],
                            child: Text("${c["name"]}"),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCustomerId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: "ডেকোরেশনের টাকা",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final n = int.tryParse((value ?? '').trim());
                        if (n == null || n <= 0) return "সঠিক টাকার পরিমাণ দিন";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: "বিবরণ (ঐচ্ছিক, যেমন: স্টিকার, ক্রোম কিট)",
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
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text("আয় যোগ করুন", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}