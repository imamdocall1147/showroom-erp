import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'app_theme.dart';

String _errorFrom(http.Response response, String fallback) {
  try {
    final data = jsonDecode(response.body);
    if (data is Map && data["detail"] is String) return data["detail"];
  } catch (_) {}
  return fallback;
}

String _messageFrom(http.Response response, String fallback) {
  try {
    final data = jsonDecode(response.body);
    if (data is Map && data["message"] is String) return data["message"];
  } catch (_) {}
  return fallback;
}

// ---------------------------------------------------------------
// গোডাউনের তালিকা
// ---------------------------------------------------------------
class WarehouseListScreen extends StatefulWidget {
  final String token;

  const WarehouseListScreen({super.key, required this.token});

  @override
  State<WarehouseListScreen> createState() => _WarehouseListScreenState();
}

class _WarehouseListScreenState extends State<WarehouseListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _warehouses = [];
  Map<int, String> _branchNames = {};

  Map<String, String> get _headers => {"Authorization": "Bearer ${widget.token}"};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response =
          await http.get(Uri.parse("$apiBaseUrl/warehouses"), headers: _headers);

      try {
        final branchRes =
            await http.get(Uri.parse("$apiBaseUrl/branches"), headers: _headers);
        if (branchRes.statusCode == 200) {
          final List<dynamic> list = jsonDecode(branchRes.body);
          _branchNames = {for (final b in list) b["id"] as int: "${b["name"]}"};
        }
      } catch (_) {}

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _warehouses = jsonDecode(response.body);
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

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _openForm([Map<String, dynamic>? warehouse]) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            WarehouseFormScreen(token: widget.token, warehouse: warehouse),
      ),
    );
    if (result == true) {
      _load();
      _snack(warehouse == null ? "গোডাউন যোগ হয়েছে" : "গোডাউন আপডেট হয়েছে");
    } else if (result == "pending") {
      _snack("অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে",
          color: Colors.orange);
    }
  }

  Future<void> _delete(Map<String, dynamic> warehouse) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("গোডাউন মুছবেন?"),
        content: Text("\"${warehouse["name"]}\" স্থায়ীভাবে মুছে যাবে।"),
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
        Uri.parse("$apiBaseUrl/warehouses/${warehouse["id"]}"),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        _load();
        _snack("গোডাউন মুছে ফেলা হয়েছে");
      } else if (response.statusCode == 202) {
        _snack(
          _messageFrom(response, "অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে"),
          color: Colors.orange,
        );
      } else {
        _snack(_errorFrom(response, "মুছা যায়নি"), color: Colors.red);
      }
    } catch (e) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("গোডাউন")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text("নতুন গোডাউন"),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
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
                          onPressed: _load,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    ),
                  )
                : _warehouses.isEmpty
                    ? const Center(child: Text("কোনো গোডাউন নেই"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _warehouses.length,
                        itemBuilder: (context, index) {
                          final w = Map<String, dynamic>.from(_warehouses[index]);
                          final branch = _branchNames[w["branch_id"]] ?? "-";
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => _openForm(w),
                              leading: const CircleAvatar(child: Icon(Icons.warehouse)),
                              title: Text(
                                "${w["name"] ?? ''}",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                "শাখা: $branch\nঠিকানা: ${w["location"] ?? '-'}",
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: "এডিট",
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _openForm(w),
                                  ),
                                  IconButton(
                                    tooltip: "মুছুন",
                                    icon: const Icon(Icons.delete_outline,
                                        size: 22, color: Colors.red),
                                    onPressed: () => _delete(w),
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
// গোডাউন যোগ / এডিটের ফর্ম (warehouse দিলে এডিট মোড)
// ---------------------------------------------------------------
class WarehouseFormScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? warehouse;

  const WarehouseFormScreen({super.key, required this.token, this.warehouse});

  @override
  State<WarehouseFormScreen> createState() => _WarehouseFormScreenState();
}

class _WarehouseFormScreenState extends State<WarehouseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();

  List<dynamic> _branches = [];
  int? _selectedBranchId;

  bool _isLoadingBranches = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEdit => widget.warehouse != null;

  Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

  @override
  void initState() {
    super.initState();
    final w = widget.warehouse;
    if (w != null) {
      _nameController.text = "${w["name"] ?? ''}";
      _locationController.text = "${w["location"] ?? ''}";
      _selectedBranchId = w["branch_id"] as int?;
    }
    _loadBranches();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final response =
          await http.get(Uri.parse("$apiBaseUrl/branches"), headers: _headers);
      if (response.statusCode == 200 && mounted) {
        final List<dynamic> list = jsonDecode(response.body);
        setState(() {
          _branches = list;
          // শাখা মাত্র একটা হলে নিজে থেকেই বেছে নেবে
          if (_selectedBranchId == null && list.length == 1) {
            _selectedBranchId = list.first["id"] as int?;
          }
        });
      }
    } catch (e) {
      // তালিকা না এলে নিচে ফর্মে বার্তা দেখাবে
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBranches = false;
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

    final location = _locationController.text.trim();
    final body = <String, dynamic>{
      "branch_id": _selectedBranchId,
      "name": _nameController.text.trim(),
      "location": location.isEmpty ? null : location,
    };

    try {
      final response = _isEdit
          ? await http.patch(
              Uri.parse("$apiBaseUrl/warehouses/${widget.warehouse!["id"]}"),
              headers: _headers,
              body: jsonEncode(body),
            )
          : await http.post(
              Uri.parse("$apiBaseUrl/warehouses"),
              headers: _headers,
              body: jsonEncode(body),
            );

      if (!mounted) return;
      if (response.statusCode == 200) {
        Navigator.of(context).pop(true);
      } else if (response.statusCode == 202) {
        Navigator.of(context).pop("pending");
      } else {
        setState(() {
          _errorMessage = _errorFrom(
              response, _isEdit ? "আপডেট করা যায়নি" : "যোগ করা যায়নি");
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
      appBar: AppBar(title: Text(_isEdit ? "গোডাউন এডিট" : "নতুন গোডাউন")),
      body: _isLoadingBranches
          ? const Center(child: CircularProgressIndicator())
          : FormWrap(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      value: _selectedBranchId,
                      decoration: const InputDecoration(
                        labelText: "শাখা",
                        border: OutlineInputBorder(),
                      ),
                      items: _branches.map<DropdownMenuItem<int>>((b) {
                        return DropdownMenuItem<int>(
                          value: b["id"],
                          child: Text("${b["name"]}"),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedBranchId = value;
                        });
                      },
                      validator: (value) => value == null ? "শাখা বাছাই করুন" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: "গোডাউনের নাম",
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? "গোডাউনের নাম দিন"
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: "ঠিকানা / অবস্থান (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
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
                        onPressed: _isSubmitting ? null : _submit,
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