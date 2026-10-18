import 'package:flutter/material.dart';
import 'sync_service.dart';
import 'reports_screen.dart';

class ExpenseScreen extends StatefulWidget {
  final String token;

  const ExpenseScreen({super.key, required this.token});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _narrationController = TextEditingController();
  String _paymentMode = "cash";

  bool _isSubmitting = false;
  String? _errorMessage;

  final List<String> _commonCategories = [
    "দোকান ভাড়া",
    "বিদ্যুৎ বিল",
    "স্টাফ বেতন",
    "চা-নাস্তা",
    "যাতায়াত খরচ",
  ];

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final amount = int.parse(_amountController.text.trim());
    final category = _categoryController.text.trim();

    try {
      final result = await SyncService().apiCall(
        method: "POST",
        endpoint: "/payments",
        body: {
          "amount": amount,
          "expense_account_name": category,
          "payment_mode": _paymentMode,
          "narration": _narrationController.text.trim().isEmpty
              ? null
              : _narrationController.text.trim(),
        },
        token: widget.token,
        description: "খরচ: $category ৳$amount",
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
        _errorMessage = "পেমেন্ট করা যায়নি";
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
        title: const Text("দোকান খরচ"),
        actions: [
          ReportsIconButton(
            token: widget.token,
            title: "খরচের রিপোর্ট",
            onlyKeys: const {'expense_report', 'expense_by_category'},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: "খরচের খাত",
                  hintText: "যেমন: দোকান ভাড়া, বিদ্যুৎ বিল",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? "খরচের খাত লিখুন" : null,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _commonCategories.map((cat) {
                  return ActionChip(
                    label: Text(cat, style: const TextStyle(color: Colors.black87)),
                    backgroundColor: Colors.white,
                    onPressed: () {
                      setState(() {
                        _categoryController.text = cat;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: "টাকার পরিমাণ",
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          "খরচ যোগ করুন",
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