import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'app_theme.dart';
import 'reports_screen.dart';

/// বাংলা অঙ্ক ইংরেজিতে বদলে ও ফাঁকা বাদ দিয়ে NID নম্বর পরিষ্কার করে
String _normalizeNid(String s) {
  const bn = '০১২৩৪৫৬৭৮৯';
  final buf = StringBuffer();
  for (final ch in s.replaceAll(' ', '').split('')) {
    final i = bn.indexOf(ch);
    buf.write(i >= 0 ? '$i' : ch);
  }
  return buf.toString();
}

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

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => "${d.year}-${_two(d.month)}-${_two(d.day)}";

class PartyListScreen extends StatefulWidget {
  final String token;

  const PartyListScreen({super.key, required this.token});

  @override
  State<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends State<PartyListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _parties = [];
  Map<int, String> _areaNames = {};
  Map<int, Map<String, dynamic>> _extras = {};
  String _search = "";

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _loadParties() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final headers = {"Authorization": "Bearer ${widget.token}"};
      final response = await http.get(Uri.parse("$apiBaseUrl/parties"), headers: headers);

      // এলাকার নাম দেখানোর জন্য (না পেলে "-" দেখাবে)
      try {
        final areaRes = await http.get(Uri.parse("$apiBaseUrl/areas"), headers: headers);
        if (areaRes.statusCode == 200) {
          final List<dynamic> list = jsonDecode(areaRes.body);
          _areaNames = {for (final a in list) a["id"] as int: "${a["name"]}"};
        }
      } catch (_) {}

      // পিতার নাম, রেফারেন্স, তারিখ (না পেলে এগুলো ছাড়াই তালিকা দেখাবে)
      try {
        final exRes = await http.get(Uri.parse("$apiBaseUrl/parties-extra"), headers: headers);
        if (exRes.statusCode == 200) {
          final List<dynamic> list = jsonDecode(utf8.decode(exRes.bodyBytes));
          _extras = {for (final e in list) e["id"] as int: Map<String, dynamic>.from(e as Map)};
        }
      } catch (_) {}

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _parties = jsonDecode(utf8.decode(response.bodyBytes));
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

  Future<void> _openAddParty() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddPartyScreen(token: widget.token),
      ),
    );
    if (result == true) {
      _loadParties();
    }
  }

  Future<void> _openEditParty(Map<String, dynamic> party) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddPartyScreen(token: widget.token, party: party),
      ),
    );
    if (result == true) {
      _loadParties();
    } else if (result == "pending") {
      _snack("অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে", color: Colors.orange);
    }
  }

  Future<void> _deleteParty(Map<String, dynamic> party) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("মুছবেন?"),
        content: Text("\"${party["name"]}\" স্থায়ীভাবে মুছে যাবে।"),
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
        Uri.parse("$apiBaseUrl/parties/${party["id"]}"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );
      if (response.statusCode == 200) {
        _loadParties();
        _snack("মুছে ফেলা হয়েছে");
      } else if (response.statusCode == 202) {
        _snack(_msgFrom(response, "অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে"),
            color: Colors.orange);
      } else {
        _snack(_msgFrom(response, "মুছা যায়নি"), color: Colors.red);
      }
    } catch (e) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final shown = q.isEmpty
        ? _parties
        : _parties.where((p) {
            final ex = _extras[p["id"]] ?? {};
            final text = "${p['name'] ?? ''} ${p['phone'] ?? ''} ${p['address'] ?? ''} "
                    "${ex['father_name'] ?? ''} ${ex['reference'] ?? ''}"
                .toLowerCase();
            return text.contains(q);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("কাস্টমার ও সাপ্লায়ার"),
        actions: [
          ReportsIconButton(
            token: widget.token,
            title: "বাকির রিপোর্ট",
            groups: const ['Customer'],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddParty,
        icon: const Icon(Icons.add),
        label: const Text("নতুন যোগ করুন"),
      ),
      body: RefreshIndicator(
        onRefresh: _loadParties,
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
                          onPressed: _loadParties,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: "নাম, ফোন, ঠিকানা, পিতার নাম বা রেফারেন্স দিয়ে খুঁজুন",
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() {
                            _search = v;
                          }),
                        ),
                      ),
                      Expanded(
                        child: shown.isEmpty
                            ? const Center(child: Text("কোনো কাস্টমার বা সাপ্লায়ার নেই"))
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: shown.length,
                                itemBuilder: (context, index) {
                                  final party = shown[index];
                                  final isCustomer = party["party_type"] == "customer";
                                  final nid = party["nid_no"];
                                  final areaName = _areaNames[party["area_id"]] ?? "-";
                                  final hasNid = isCustomer && nid != null && "$nid".isNotEmpty;
                                  final ex = _extras[party["id"]] ?? {};
                                  final father = "${ex['father_name'] ?? ''}";
                                  final ref = "${ex['reference'] ?? ''}";
                                  final date = "${ex['entry_date'] ?? ''}";
                                  final extraLine = [
                                    if (father.isNotEmpty) "পিতা: $father",
                                    if (ref.isNotEmpty) "রেফ: $ref",
                                    if (date.isNotEmpty) "তারিখ: $date",
                                  ].join(" | ");
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: ListTile(
                                      onTap: () => _openEditParty(Map<String, dynamic>.from(party)),
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            isCustomer ? Colors.blue.shade100 : Colors.orange.shade100,
                                        child: Icon(
                                          isCustomer ? Icons.person : Icons.local_shipping,
                                          color: isCustomer ? Colors.blue : Colors.orange,
                                        ),
                                      ),
                                      title: Text(
                                        party["name"] ?? "",
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        "${isCustomer ? 'কাস্টমার' : 'সাপ্লায়ার'} | ${party['phone'] ?? '-'}\n"
                                        "এলাকা: $areaName"
                                        "${isCustomer ? '\nNID: ${hasNid ? nid : '-'}' : ''}"
                                        "${extraLine.isNotEmpty ? '\n$extraLine' : ''}",
                                      ),
                                      isThreeLine: true,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: "এডিট",
                                            icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                                            onPressed: () =>
                                                _openEditParty(Map<String, dynamic>.from(party)),
                                          ),
                                          IconButton(
                                            tooltip: "মুছুন",
                                            icon: const Icon(Icons.delete_outline,
                                                size: 22, color: Colors.red),
                                            onPressed: () =>
                                                _deleteParty(Map<String, dynamic>.from(party)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// party দিলে এডিট মোড, না দিলে নতুন যোগ করার ফর্ম
class AddPartyScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? party;

  const AddPartyScreen({super.key, required this.token, this.party});

  @override
  State<AddPartyScreen> createState() => _AddPartyScreenState();
}

class _AddPartyScreenState extends State<AddPartyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _fatherController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _nidController = TextEditingController();
  final _refController = TextEditingController();
  final _openingController = TextEditingController();
  int _origOpening = 0;

  String _partyType = "customer";
  List<dynamic> _areas = [];
  int? _selectedAreaId;
  DateTime? _entryDate;

  bool _isLoadingAreas = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEdit => widget.party != null;

  Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

  @override
  void initState() {
    super.initState();
    final p = widget.party;
    if (p != null) {
      _nameController.text = "${p["name"] ?? ''}";
      _phoneController.text = "${p["phone"] ?? ''}";
      _addressController.text = "${p["address"] ?? ''}";
      _nidController.text = "${p["nid_no"] ?? ''}";
      _partyType = "${p["party_type"] ?? 'customer'}";
      _selectedAreaId = p["area_id"] as int?;
      _loadExtra();
      _loadOpening();
    } else {
      _entryDate = DateTime.now();
    }
    _loadAreas();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fatherController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _nidController.dispose();
    _refController.dispose();
    _openingController.dispose();
    super.dispose();
  }

  Future<void> _loadExtra() async {
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/parties/${widget.party!["id"]}/extra"),
        headers: _headers,
      );
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _fatherController.text = "${d["father_name"] ?? ''}";
          _refController.text = "${d["reference"] ?? ''}";
          _entryDate = d["entry_date"] != null ? DateTime.tryParse("${d["entry_date"]}") : null;
        });
      }
    } catch (_) {
      // না পেলে ঘরগুলো ফাঁকা থাকবে, বাকি তথ্য এডিট করা যাবে
    }
  }

  Future<void> _loadAreas() async {
    setState(() {
      _isLoadingAreas = true;
    });
    try {
      final response = await http.get(
        Uri.parse("$apiBaseUrl/areas"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _areas = jsonDecode(response.body);
        });
      }
    } catch (e) {
      // এলাকা তালিকা না পেলেও ফর্ম ব্যবহার করা যাবে, তাই এখানে আটকানো হচ্ছে না
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAreas = false;
        });
      }
    }
  }
  Future<void> _addAreaDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("নতুন এলাকা"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: "এলাকার নাম"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("বাতিল"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("যোগ করুন"),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty) return;

    // একই নাম আগে থেকে থাকলে নতুন না বানিয়ে সেটাই বেছে নিন
    final existing = _areas.where(
      (a) => "${a["name"]}".toLowerCase() == name.toLowerCase(),
    );
    if (existing.isNotEmpty) {
      setState(() => _selectedAreaId = existing.first["id"] as int?);
      return;
    }

    try {
      final res = await http.post(
        Uri.parse("$apiBaseUrl/areas"),
        headers: _headers,
        body: jsonEncode({"name": name}),
      );
      if (res.statusCode == 200) {
        final created = jsonDecode(utf8.decode(res.bodyBytes));
        await _loadAreas();
        if (!mounted) return;
        setState(() => _selectedAreaId = created["id"] as int?);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_msgFrom(res, "এলাকা যোগ হয়নি (${res.statusCode})"))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("সার্ভারের সাথে সংযোগ করা যায়নি")),
      );
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _entryDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _entryDate = d;
      });
    }
  }

   Future<void> _loadOpening() async {
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/parties/${widget.party!["id"]}/opening-balance"),
        headers: _headers,
      );
      if (res.statusCode == 200 && mounted) {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        final amt = ((d["amount"] ?? 0) as num).toInt();
        setState(() {
          _origOpening = amt;
          _openingController.text = amt > 0 ? "$amt" : "";
        });
      }
    } catch (_) {}
  }

  /// সফল হলে null, না হলে এররের লেখা
  Future<String?> _saveOpening(int partyId) async {
    final txt = _normalizeNid(_openingController.text);
    final amount = txt.isEmpty ? 0 : int.tryParse(txt);
    if (amount == null) return "পূর্বের বকেয়ার অঙ্ক ঠিক নয়";
    if (amount == _origOpening) return null;
    final res = await http.put(
      Uri.parse("$apiBaseUrl/parties/$partyId/opening-balance"),
      headers: _headers,
      body: jsonEncode({
        "amount": amount,
        "balance_date": _entryDate == null ? null : _fmtDate(_entryDate!),
      }),
    );
    if (res.statusCode == 200) return null;
    return _msgFrom(res, "পূর্বের বকেয়া সংরক্ষণ করা যায়নি");
  }
  Future<void> _saveExtra(int partyId) async {
    await http.put(
      Uri.parse("$apiBaseUrl/parties/$partyId/extra"),
      headers: _headers,
      body: jsonEncode({
        "father_name": _fatherController.text.trim(),
        "reference": _refController.text.trim(),
        "entry_date": _entryDate == null ? null : _fmtDate(_entryDate!),
      }),
    );
  }

  Future<void> _submitParty() async {

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final nid = _normalizeNid(_nidController.text);
    final body = <String, dynamic>{
      "name": _nameController.text.trim(),
      "phone": _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      "address": _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      "area_id": _selectedAreaId,
      "nid_no": (_partyType == "customer" && nid.isNotEmpty) ? nid : null,
    };
    if (!_isEdit) {
      body["party_type"] = _partyType;
    }

    try {
      final response = _isEdit
          ? await http.patch(
              Uri.parse("$apiBaseUrl/parties/${widget.party!["id"]}"),
              headers: _headers,
              body: jsonEncode(body),
            )
          : await http.post(
              Uri.parse("$apiBaseUrl/parties"),
              headers: _headers,
              body: jsonEncode(body),
            );

      if (!mounted) return;
      if (response.statusCode == 200) {
        // পিতার নাম, রেফারেন্স ও তারিখ আলাদা ডাকে সংরক্ষণ হয়
        int? id = _isEdit ? widget.party!["id"] as int? : null;
        if (id == null) {
          try {
            id = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)["id"] as int?;
          } catch (_) {}
        }
      if (id != null) {
          try {
            await _saveExtra(id);
          } catch (_) {}
        }
        String? openErr;
        if (id != null && _partyType == "customer") {
          try {
            openErr = await _saveOpening(id);
          } catch (_) {
            openErr = "পূর্বের বকেয়া সংরক্ষণ করা যায়নি";
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(openErr != null
                ? "কাস্টমার সংরক্ষিত হয়েছে, কিন্তু $openErr"
                : (_isEdit ? "সফলভাবে আপডেট হয়েছে" : "সফলভাবে যোগ হয়েছে")),
            backgroundColor: openErr != null ? Colors.orange : null,
          ),
        );
        Navigator.of(context).pop(true);
      } else if (response.statusCode == 202) {
        Navigator.of(context).pop("pending");
      } else {
        setState(() {
          _errorMessage = _msgFrom(
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
      appBar: AppBar(
        title: Text(_isEdit ? "কাস্টমার/সাপ্লায়ার এডিট" : "নতুন কাস্টমার/সাপ্লায়ার"),
      ),
      body: _isLoadingAreas
          ? const Center(child: CircularProgressIndicator())
          : FormWrap(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("ধরন", style: TextStyle(fontWeight: FontWeight.bold)),
                    RadioListTile<String>(
                      title: const Text("কাস্টমার"),
                      value: "customer",
                      groupValue: _partyType,
                      onChanged: _isEdit
                          ? null
                          : (value) {
                              setState(() {
                                _partyType = value!;
                              });
                            },
                    ),
                    RadioListTile<String>(
                      title: const Text("সাপ্লায়ার"),
                      value: "supplier",
                      groupValue: _partyType,
                      onChanged: _isEdit
                          ? null
                          : (value) {
                              setState(() {
                                _partyType = value!;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_entryDate == null ? "তারিখ বাছুন" : "তারিখ: ${_fmtDate(_entryDate!)}"),
                      onPressed: _pickDate,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: "নাম",
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? "নাম দিন" : null,
                    ),
                    if (_partyType == "customer") ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _fatherController,
                        decoration: const InputDecoration(
                          labelText: "পিতার নাম",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: "ফোন নম্বর (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    if (_partyType == "customer") ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nidController,
                        decoration: const InputDecoration(
                          labelText: "NID নম্বর (ঐচ্ছিক)",
                          helperText: "১০, ১৩ বা ১৭ অঙ্কের জাতীয় পরিচয়পত্র নম্বর",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final v = _normalizeNid(value ?? '');
                          if (v.isEmpty) return null;
                          if (!RegExp(r'^\d+$').hasMatch(v) ||
                              ![10, 13, 17].contains(v.length)) {
                            return "NID নম্বর ১০, ১৩ বা ১৭ অঙ্কের সংখ্যা হতে হবে";
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _refController,
                      decoration: const InputDecoration(
                        labelText: "রেফারেন্স (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: "ঠিকানা (ঐচ্ছিক)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                      if (_partyType == "customer") ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _openingController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "পূর্বের বকেয়া (ঐচ্ছিক)",
                          helperText: "হিসাব শুরুর আগে এই কাস্টমারের কাছে যত টাকা পাবেন",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        ),
                        validator: (value) {
                          final t = _normalizeNid(value ?? '');
                          if (t.isEmpty) return null;
                          final n = int.tryParse(t);
                          return (n == null || n < 0) ? "সঠিক অঙ্ক দিন" : null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(_selectedAreaId),
                            initialValue: _selectedAreaId,
                            decoration: const InputDecoration(
                              labelText: "এলাকা (ঐচ্ছিক)",
                              border: OutlineInputBorder(),
                            ),
                            items: _areas.map<DropdownMenuItem<int>>((a) {
                              return DropdownMenuItem<int>(
                                value: a["id"],
                                child: Text("${a["name"]}"),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedAreaId = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: IconButton.filledTonal(
                            icon: const Icon(Icons.add),
                            tooltip: "নতুন এলাকা",
                            onPressed: _addAreaDialog,
                          ),
                        ),
                      ],
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
                        onPressed: _isSubmitting ? null : _submitParty,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
