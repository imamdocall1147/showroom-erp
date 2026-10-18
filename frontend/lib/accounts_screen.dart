import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'reports_screen.dart';

class AccountsScreen extends StatefulWidget {
  final String token;

  const AccountsScreen({super.key, required this.token});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _accountsWithBalance = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final accountsRes = await http.get(
        Uri.parse("$apiBaseUrl/accounts"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );

      if (accountsRes.statusCode != 200) {
        setState(() {
          _errorMessage = "অ্যাকাউন্ট তালিকা আনতে সমস্যা হয়েছে";
        });
        return;
      }

      final List<dynamic> accounts = jsonDecode(accountsRes.body);
      List<Map<String, dynamic>> result = [];

      // প্রতিটা অ্যাকাউন্টের ব্যালান্স আলাদাভাবে আনা হচ্ছে
      for (final account in accounts) {
        final balanceRes = await http.get(
          Uri.parse("$apiBaseUrl/accounts/${account['id']}/balance"),
          headers: {"Authorization": "Bearer ${widget.token}"},
        );
        if (balanceRes.statusCode == 200) {
          final balanceData = jsonDecode(balanceRes.body);
          result.add({
            "id": account["id"],
            "name": account["name"],
            "account_type": account["account_type"],
            "balance": balanceData["balance"],
          });
        }
      }

      setState(() {
        _accountsWithBalance = result;
      });
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

  IconData _iconForType(String type) {
    switch (type) {
      case "cash":
        return Icons.payments;
      case "bank":
        return Icons.account_balance;
      case "income":
        return Icons.trending_up;
      case "expense":
        return Icons.trending_down;
      case "receivable":
        return Icons.request_page;
      case "payable":
        return Icons.request_quote;
      default:
        return Icons.account_balance_wallet;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case "cash":
      case "bank":
        return Colors.green;
      case "income":
        return Colors.blue;
      case "expense":
        return Colors.red;
      case "receivable":
        return Colors.orange;
      case "payable":
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case "cash":
        return "নগদ";
      case "bank":
        return "ব্যাংক";
      case "income":
        return "আয়";
      case "expense":
        return "খরচ";
      case "receivable":
        return "প্রাপ্য (বাকি)";
      case "payable":
        return "পরিশোধযোগ্য";
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cashAndBank = _accountsWithBalance
        .where((a) => a["account_type"] == "cash" || a["account_type"] == "bank")
        .toList();
    final totalCashBank = cashAndBank.fold<int>(0, (sum, a) => sum + (a["balance"] as int));

    return Scaffold(
      appBar: AppBar(
        title: const Text("একাউন্ট ব্যালান্স"),
        actions: [
          ReportsIconButton(
            token: widget.token,
            title: "হিসাবের রিপোর্ট",
            groups: const ['Accounts'],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAccounts,
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
                          onPressed: _loadAccounts,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Card(
                        color: Colors.green.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "হাতে থাকা মোট টাকা (নগদ + ব্যাংক)",
                                style: TextStyle(fontSize: 13, color: Colors.black54),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "৳$totalCashBank",
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "সব অ্যাকাউন্ট",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (_accountsWithBalance.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text("কোনো অ্যাকাউন্ট নেই")),
                        )
                      else
                        ..._accountsWithBalance.map((account) {
                          final type = account["account_type"] as String;
                          final balance = account["balance"] as int;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _colorForType(type).withValues(alpha: 0.15),
                                child: Icon(_iconForType(type), color: _colorForType(type)),
                              ),
                              title: Text(
                                account["name"],
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(_labelForType(type)),
                              trailing: Text(
                                "৳$balance",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: balance < 0 ? Colors.red : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
      ),
    );
  }
}