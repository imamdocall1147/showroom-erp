import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'app_theme.dart';

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

/// স্টকের একটা বাইকের চেসিস, ইঞ্জিন, রঙ, বছর ও গোডাউন এডিট।
/// ক্রয় মূল্য ও মডেল এখান থেকে বদলায় না (ওগুলো হিসাবের ভাউচারের সাথে বাঁধা)।
class EditUnitScreen extends StatefulWidget {
  final String token;
  final int unitId;

  const EditUnitScreen({super.key, required this.token, required this.unitId});

  @override
  State<EditUnitScreen> createState() => _EditUnitScreenState();
}

class _EditUnitScreenState extends State<EditUnitScreen> {
  final _formKey = GlobalKey<FormState>();
  final _chassisController = TextEditingController();
  final _engineController = TextEditingController();
  final _colorController = TextEditingController();
  final _yearController = TextEditingController();

  List<dynamic> _warehouses = [];
  int? _selectedWarehouseId;
  Map<String, dynamic> _unit = {};

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _loadError;

  Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chassisController.dispose();
    _engineController.dispose();
    _colorController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final unitRes = await http.get(
        Uri.parse("$apiBaseUrl/units/${widget.unitId}"),
        headers: _headers,
      );
      final whRes = await http.get(
        Uri.parse("$apiBaseUrl/warehouses"),
        headers: _headers,
      );
      if (!mounted) return;
      if (unitRes.statusCode != 200) {
        setState(() {
          _loadError = _msgFrom(unitRes, "বাইকের তথ্য আনা যায়নি");
        });
        return;
      }
      final unit = Map<String, dynamic>.from(jsonDecode(unitRes.body));
      setState(() {
        _unit = unit;
        _chassisController.text = "${unit["chassis_no"] ?? ''}";
        _engineController.text = "${unit["engine_no"] ?? ''}";
        _colorController.text = "${unit["color"] ?? ''}";
        _yearController.text = "${unit["year"] ?? ''}";
        _selectedWarehouseId = unit["warehouse_id"] as int?;
        if (whRes.statusCode == 200) {
          _warehouses = jsonDecode(whRes.body);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = "সার্ভারের সাথে সংযোগ করা যায়নি";
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

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final color = _colorController.text.trim();
    final year = _yearController.text.trim();
    final body = <String, dynamic>{
      "chassis_no": _chassisController.text.trim(),
      "engine_no": _engineController.text.trim(),
      "color": color.isEmpty ? null : color,
      "year": year.isEmpty ? null : year,
      "warehouse_id": _selectedWarehouseId,
    };

    try {
      final response = await http.patch(
        Uri.parse("$apiBaseUrl/units/${widget.unitId}"),
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
      appBar: AppBar(title: const Text("স্টক এডিট")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_loadError!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text("আবার চেষ্টা করুন"),
                      ),
                    ],
                  ),
                )
              : FormWrap(
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
                            "ক্রয় মূল্য: ৳${_unit["purchase_price"] ?? '-'} "
                            "(মূল্য ও মডেল এখান থেকে বদলায় না, কারণ সেটা হিসাবের ভাউচারের সাথে যুক্ত)",
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _chassisController,
                          decoration: const InputDecoration(
                            labelText: "চেসিস নম্বর",
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? "চেসিস নম্বর দিন"
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _engineController,
                          decoration: const InputDecoration(
                            labelText: "ইঞ্জিন নম্বর",
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? "ইঞ্জিন নম্বর দিন"
                              : null,
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
                                : const Text("সংরক্ষণ করুন",
                                    style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}