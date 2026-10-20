import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';

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

const Map<String, String> _fieldLabels = {
  "name": "নাম",
  "location": "ঠিকানা",
  "branch_id": "শাখা (আইডি)",
  "brand_id": "ব্র্যান্ড (আইডি)",
  "model_name": "মডেলের নাম",
  "category": "ক্যাটাগরি",
  "unit_price": "মূল্য",
  "is_active": "সক্রিয়",
  "address": "ঠিকানা",
  "phone": "ফোন",
  "unit": "একক",
  "warehouse_id": "গোডাউন (আইডি)",
  "purchase_price": "ক্রয় মূল্য",
  "sale_price": "বিক্রয় মূল্য",
  "chassis_no": "চেসিস নম্বর",
  "engine_no": "ইঞ্জিন নম্বর",
  "color": "রঙ",
  "year": "বছর",
};

/// চিপের লেখার রঙ — সব চিপে স্পষ্ট দেখাবে
const TextStyle _chipTextStyle = TextStyle(color: Colors.black87);

/// ডাটাবেসে UTC সময় থাকে, বাংলাদেশের সময় (+৬) করে দেখায়
String _formatTime(String? iso) {
  if (iso == null) return "-";
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final bd = t.add(const Duration(hours: 6));
  String two(int n) => n.toString().padLeft(2, '0');
  return "${two(bd.day)}/${two(bd.month)}/${bd.year} ${two(bd.hour)}:${two(bd.minute)}";
}

class ApprovalScreen extends StatefulWidget {
  final String token;

  const ApprovalScreen({super.key, required this.token});

  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _requests = [];
  bool _showAll = false;
  int? _busyId;

  Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

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
      final response = await http.get(
        Uri.parse("$apiBaseUrl/change-requests?status=${_showAll ? 'all' : 'pending'}"),
        headers: _headers,
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _requests = jsonDecode(response.body);
        });
      } else {
        setState(() {
          _errorMessage = _msgFrom(response, "তালিকা আনতে সমস্যা হয়েছে");
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

  Future<void> _approve(Map<String, dynamic> req) async {
    final isDelete = req["action"] == "delete";
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("অনুমোদন দেবেন?"),
        content: Text(
          "${req["summary"]}\n\n"
          "${isDelete ? 'অনুমোদন দিলে তথ্যটি স্থায়ীভাবে মুছে যাবে।' : 'অনুমোদন দিলে পরিবর্তনটি এখনই কার্যকর হবে।'}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("না"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("অনুমোদন দিন", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busyId = req["id"] as int?;
    });
    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/change-requests/${req["id"]}/approve"),
        headers: _headers,
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        _snack(_msgFrom(response, "অনুমোদন করা হয়েছে"), color: Colors.green);
        _load();
      } else {
        _snack(_msgFrom(response, "অনুমোদন করা যায়নি"), color: Colors.red);
      }
    } catch (e) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _busyId = null;
        });
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> req) async {
    final noteController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("অনুরোধ বাতিল করবেন?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${req["summary"]}"),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: "কারণ (ঐচ্ছিক)",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("ফিরে যান"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("বাতিল করুন", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    final note = noteController.text.trim();
    noteController.dispose();
    if (ok != true) return;

    setState(() {
      _busyId = req["id"] as int?;
    });
    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/change-requests/${req["id"]}/reject"),
        headers: _headers,
        body: jsonEncode({"note": note.isEmpty ? null : note}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        _snack("অনুরোধ বাতিল করা হয়েছে");
        _load();
      } else {
        _snack(_msgFrom(response, "বাতিল করা যায়নি"), color: Colors.red);
      }
    } catch (e) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _busyId = null;
        });
      }
    }
  }

  Widget _statusChip(String status) {
    switch (status) {
      case "approved":
        return const Chip(
          label: Text("অনুমোদিত", style: _chipTextStyle),
          backgroundColor: Color(0xFFD9F2E3),
          visualDensity: VisualDensity.compact,
        );
      case "rejected":
        return const Chip(
          label: Text("বাতিল", style: _chipTextStyle),
          backgroundColor: Color(0xFFFDECEC),
          visualDensity: VisualDensity.compact,
        );
      default:
        return const Chip(
          label: Text("অপেক্ষায়", style: _chipTextStyle),
          backgroundColor: Color(0xFFFFF1D6),
          visualDensity: VisualDensity.compact,
        );
    }
  }

  Widget _card(Map<String, dynamic> req) {
    final changes = req["changes"] is Map
        ? Map<String, dynamic>.from(req["changes"])
        : <String, dynamic>{};
    final isPending = req["status"] == "pending";
    final isDelete = req["action"] == "delete";
    final busy = _busyId == req["id"];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isDelete ? Icons.delete_outline : Icons.edit_outlined,
                  color: isDelete ? Colors.red : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${req["summary"]}",
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                _statusChip("${req["status"]}"),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "অনুরোধকারী: ${req["requested_by_name"] ?? '-'}  |  ${_formatTime(req["requested_at"])}",
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            if (!isDelete && changes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text("যা বদলাতে চান:",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...changes.entries.map(
                (e) => Text(
                  "• ${_fieldLabels[e.key] ?? e.key}: ${e.value ?? '(খালি)'}",
                ),
              ),
            ],
            if (!isPending) ...[
              const SizedBox(height: 8),
              Text(
                "সিদ্ধান্ত: ${req["decided_by_name"] ?? '-'}  |  ${_formatTime(req["decided_at"])}"
                "${(req["decision_note"] ?? '').toString().isEmpty ? '' : '\nকারণ: ${req["decision_note"]}'}",
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : () => _reject(req),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text("বাতিল"),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: busy ? null : () => _approve(req),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text("অনুমোদন",
                            style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("অনুমোদন"),
        actions: [
          IconButton(
            tooltip: "রিফ্রেশ",
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text("অপেক্ষায়", style: _chipTextStyle),
                  backgroundColor: Colors.white,
                  selectedColor: const Color(0xFFE3DDF7),
                  selected: !_showAll,
                  onSelected: (_) {
                    setState(() {
                      _showAll = false;
                    });
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("সব", style: _chipTextStyle),
                  backgroundColor: Colors.white,
                  selectedColor: const Color(0xFFE3DDF7),
                  selected: _showAll,
                  onSelected: (_) {
                    setState(() {
                      _showAll = true;
                    });
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
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
                                onPressed: _load,
                                child: const Text("আবার চেষ্টা করুন"),
                              ),
                            ],
                          ),
                        )
                      : _requests.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(child: Text("কোনো অনুরোধ নেই")),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _requests.length,
                              itemBuilder: (context, index) => _card(
                                  Map<String, dynamic>.from(_requests[index])),
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
