import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'brta_documents_screen.dart';

const Map<String, String> brtaStatusLabels = {
  "not_started": "শুরু হয়নি",
  "submitted": "জমা দেওয়া হয়েছে",
  "in_process": "প্রক্রিয়াধীন",
  "completed": "সম্পন্ন",
};

Color brtaStatusColor(String? status) {
  switch (status) {
    case "completed":
      return Colors.green;
    case "in_process":
      return Colors.orange;
    case "submitted":
      return Colors.blue;
    default:
      return Colors.grey;
  }
}

class BrtaScreen extends StatefulWidget {
  final String token;

  const BrtaScreen({super.key, required this.token});

  @override
  State<BrtaScreen> createState() => _BrtaScreenState();
}

class _BrtaScreenState extends State<BrtaScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _units = [];

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await http.get(
        Uri.parse("$apiBaseUrl/reports/brta-status"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _units = data["units"];
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

  Future<void> _openUpdate(Map<String, dynamic> unit) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BrtaUpdateScreen(token: widget.token, unit: unit),
      ),
    );
    if (result == true) {
      _loadUnits();
    }
  }

  void _openDocuments(Map<String, dynamic> unit) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BrtaDocumentsScreen(token: widget.token, unit: unit),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BRTA রেজিস্ট্রেশন ট্র্যাকিং")),
      body: RefreshIndicator(
        onRefresh: _loadUnits,
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
                          onPressed: _loadUnits,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    ),
                  )
                : _units.isEmpty
                    ? const Center(child: Text("বিক্রিত কোনো বাইক নেই"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _units.length,
                        itemBuilder: (context, index) {
                          final unit = _units[index];
                          final status = unit["brta_status"] ?? "not_started";
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => _openUpdate(unit),
                              leading: CircleAvatar(
                                backgroundColor: brtaStatusColor(status).withValues(alpha: 0.15),
                                child: Icon(Icons.assignment, color: brtaStatusColor(status)),
                              ),
                              title: Text(
                                "${unit['brand'] ?? ''} ${unit['model'] ?? ''}",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                "চেসিস: ${unit['chassis_no']}\n"
                                "কাস্টমার: ${unit['customer_name'] ?? '-'}"
                                "${unit['brta_reg_no'] != null ? '\nরেজি. নং: ${unit['brta_reg_no']}' : ''}",
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: "BRTA কাগজপত্র তৈরি করুন",
                                    icon: const Icon(Icons.print, color: Colors.blueGrey),
                                    onPressed: () =>
                                        _openDocuments(Map<String, dynamic>.from(unit)),
                                  ),
                                  Chip(
                                    label: Text(
                                      brtaStatusLabels[status] ?? status,
                                      style: const TextStyle(fontSize: 11, color: Colors.white),
                                    ),
                                    backgroundColor: brtaStatusColor(status),
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

class BrtaUpdateScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> unit;

  const BrtaUpdateScreen({super.key, required this.token, required this.unit});

  @override
  State<BrtaUpdateScreen> createState() => _BrtaUpdateScreenState();
}

class _BrtaUpdateScreenState extends State<BrtaUpdateScreen> {
  late String _status;
  late TextEditingController _regNoController;
  late TextEditingController _notesController;
  DateTime? _submissionDate;
  DateTime? _completionDate;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _status = widget.unit["brta_status"] ?? "not_started";
    _regNoController = TextEditingController(text: widget.unit["brta_reg_no"] ?? "");
    _notesController = TextEditingController(text: widget.unit["brta_notes"] ?? "");
    if (widget.unit["brta_submission_date"] != null) {
      _submissionDate = DateTime.tryParse(widget.unit["brta_submission_date"]);
    }
    if (widget.unit["brta_completion_date"] != null) {
      _completionDate = DateTime.tryParse(widget.unit["brta_completion_date"]);
    }
  }

  Future<void> _pickDate(bool isSubmission) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isSubmission) {
          _submissionDate = picked;
        } else {
          _completionDate = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await http.patch(
        Uri.parse("$apiBaseUrl/units/${widget.unit['unit_id']}/brta"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode({
          "brta_status": _status,
          "brta_reg_no": _regNoController.text.trim().isEmpty ? null : _regNoController.text.trim(),
          "brta_submission_date": _submissionDate?.toIso8601String(),
          "brta_completion_date": _completionDate?.toIso8601String(),
          "brta_notes": _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _errorMessage = data["detail"] ?? "আপডেট করা যায়নি";
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

  String _formatDate(DateTime? date) {
    if (date == null) return "নির্বাচন করুন";
    return "${date.day}-${date.month}-${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BRTA আপডেট")),
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
                      "${widget.unit['brand'] ?? ''} ${widget.unit['model'] ?? ''}",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text("চেসিস: ${widget.unit['chassis_no']}"),
                    Text("কাস্টমার: ${widget.unit['customer_name'] ?? '-'}"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.print),
              label: const Text("BRTA কাগজপত্র তৈরি করুন (PDF)"),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => BrtaDocumentsScreen(
                      token: widget.token,
                      unit: widget.unit,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text("স্ট্যাটাস", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: brtaStatusLabels.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _status = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _regNoController,
              decoration: const InputDecoration(
                labelText: "রেজিস্ট্রেশন নম্বর (ঐচ্ছিক)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text("জমা দেওয়ার তারিখ: ${_formatDate(_submissionDate)}")),
                TextButton(
                  onPressed: () => _pickDate(true),
                  child: const Text("বাছাই করুন"),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text("সম্পন্ন হওয়ার তারিখ: ${_formatDate(_completionDate)}")),
                TextButton(
                  onPressed: () => _pickDate(false),
                  child: const Text("বাছাই করুন"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "মন্তব্য (ঐচ্ছিক)",
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text("সেভ করুন", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
