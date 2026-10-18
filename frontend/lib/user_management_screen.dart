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

const List<String> _commonRoles = ["admin", "manager", "staff", "accountant"];

class UserManagementScreen extends StatefulWidget {
  final String token;

  const UserManagementScreen({super.key, required this.token});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _users = [];

  Map<String, String> get _headers => {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      };

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await http.get(
        Uri.parse("$apiBaseUrl/users"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );
      if (response.statusCode == 200) {
        setState(() {
          _users = jsonDecode(response.body);
        });
      } else {
        setState(() {
          _errorMessage = "ইউজার তালিকা আনতে সমস্যা হয়েছে";
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

  Future<void> _openAddUser() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddUserScreen(token: widget.token),
      ),
    );
    if (result == true) {
      _loadUsers();
      _snack("ইউজার সফলভাবে তৈরি হয়েছে");
    }
  }

  Future<void> _openEditUser(Map<String, dynamic> user) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditUserScreen(token: widget.token, user: user),
      ),
    );
    if (result == true) {
      _loadUsers();
      _snack("ইউজারের তথ্য আপডেট হয়েছে");
    } else if (result == "relogin") {
      // নিজের ইউজার আইডি বদলালে পুরনো টোকেন অচল, তাই আবার লগইন করতে হয়
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ইউজার আইডি বদলেছে, নতুন আইডি দিয়ে আবার লগইন করুন")),
      );
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final controller = TextEditingController();
    bool obscure = true;
    final newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text("${user["full_name"] ?? user["username"]} — নতুন পাসওয়ার্ড"),
          content: TextField(
            controller: controller,
            obscureText: obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: "নতুন পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)",
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setLocal(() => obscure = !obscure),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("বাতিল"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text("পাসওয়ার্ড বদলান"),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (newPassword == null) return;
    if (newPassword.length < 6) {
      _snack("কমপক্ষে ৬ অক্ষরের পাসওয়ার্ড দিন", color: Colors.red);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/users/${user["id"]}/reset-password"),
        headers: _headers,
        body: jsonEncode({"new_password": newPassword}),
      );
      if (response.statusCode == 200) {
        _snack("পাসওয়ার্ড বদলানো হয়েছে", color: Colors.green);
      } else {
        _snack(_msgFrom(response, "পাসওয়ার্ড বদলানো যায়নি"), color: Colors.red);
      }
    } catch (e) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ইউজার মুছবেন?"),
        content: Text("\"${user["full_name"] ?? user["username"]}\" স্থায়ীভাবে মুছে যাবে।"),
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
        Uri.parse("$apiBaseUrl/users/${user["id"]}"),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        _loadUsers();
        _snack("ইউজার মুছে ফেলা হয়েছে");
      } else {
        _snack(_msgFrom(response, "মুছা যায়নি"), color: Colors.red);
      }
    } catch (e) {
      _snack("সার্ভারের সাথে সংযোগ করা যায়নি", color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ইউজার ম্যানেজমেন্ট")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddUser,
        icon: const Icon(Icons.person_add),
        label: const Text("নতুন ইউজার"),
      ),
      body: RefreshIndicator(
        onRefresh: _loadUsers,
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
                          onPressed: _loadUsers,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    ),
                  )
                : _users.isEmpty
                    ? const Center(child: Text("কোনো ইউজার নেই"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = Map<String, dynamic>.from(_users[index]);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => _openEditUser(user),
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.shade100,
                                child: const Icon(Icons.person, color: Colors.blue),
                              ),
                              title: Text(
                                user["full_name"] ?? "",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                "ইউজারনেম: ${user['username']} | রোল: ${user['role'] ?? '-'}",
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: "আরও",
                                onSelected: (value) {
                                  if (value == "edit") _openEditUser(user);
                                  if (value == "password") _resetPassword(user);
                                  if (value == "delete") _deleteUser(user);
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: "edit",
                                    child: ListTile(
                                      leading: Icon(Icons.edit),
                                      title: Text("এডিট (আইডি/নাম/রোল)"),
                                      dense: true,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: "password",
                                    child: ListTile(
                                      leading: Icon(Icons.lock_reset),
                                      title: Text("পাসওয়ার্ড বদলান"),
                                      dense: true,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: "delete",
                                    child: ListTile(
                                      leading: Icon(Icons.delete_outline, color: Colors.red),
                                      title: Text("মুছুন", style: TextStyle(color: Colors.red)),
                                      dense: true,
                                    ),
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

class AddUserScreen extends StatefulWidget {
  final String token;

  const AddUserScreen({super.key, required this.token});

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _customRoleController = TextEditingController();

  String _selectedRole = "staff";
  bool _useCustomRole = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _customRoleController.dispose();
    super.dispose();
  }

  Future<void> _submitUser() async {
    if (!_formKey.currentState!.validate()) return;

    final roleName = _useCustomRole ? _customRoleController.text.trim() : _selectedRole;
    if (roleName.isEmpty) {
      setState(() {
        _errorMessage = "রোল দিন";
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/users/register"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode({
          "username": _usernameController.text.trim(),
          "password": _passwordController.text,
          "full_name": _fullNameController.text.trim(),
          "role_name": roleName,
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _errorMessage = _msgFrom(response, "ইউজার তৈরি করা যায়নি");
        });
      }
    } catch (e) {
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
      appBar: AppBar(title: const Text("নতুন ইউজার তৈরি")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: "পূর্ণ নাম",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? "নাম দিন" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: "ইউজারনেম",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? "ইউজারনেম দিন" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return "পাসওয়ার্ড দিন";
                  if (value.length < 6) return "কমপক্ষে ৬ অক্ষরের পাসওয়ার্ড দিন";
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text("রোল", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _commonRoles.map((role) {
                  return ChoiceChip(
                    label: Text(role),
                    selected: !_useCustomRole && _selectedRole == role,
                    onSelected: (selected) {
                      setState(() {
                        _useCustomRole = false;
                        _selectedRole = role;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _useCustomRole,
                    onChanged: (value) {
                      setState(() {
                        _useCustomRole = value ?? false;
                      });
                    },
                  ),
                  const Text("অন্য রোল লিখুন"),
                ],
              ),
              if (_useCustomRole)
                TextFormField(
                  controller: _customRoleController,
                  decoration: const InputDecoration(
                    labelText: "রোলের নাম",
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
                  onPressed: _isSubmitting ? null : _submitUser,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text("তৈরি করুন", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ইউজারের ইউজার আইডি, নাম ও রোল এডিট (শুধু অ্যাডমিন)
class EditUserScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const EditUserScreen({super.key, required this.token, required this.user});

  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _customRoleController = TextEditingController();

  String _selectedRole = "staff";
  bool _useCustomRole = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController.text = "${widget.user["username"] ?? ''}";
    _fullNameController.text = "${widget.user["full_name"] ?? ''}";
    final role = "${widget.user["role"] ?? ''}";
    if (_commonRoles.contains(role)) {
      _selectedRole = role;
    } else if (role.isNotEmpty) {
      _useCustomRole = true;
      _customRoleController.text = role;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _customRoleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final roleName = _useCustomRole ? _customRoleController.text.trim() : _selectedRole;
    if (roleName.isEmpty) {
      setState(() {
        _errorMessage = "রোল দিন";
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await http.patch(
        Uri.parse("$apiBaseUrl/users/${widget.user["id"]}"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode({
          "username": _usernameController.text.trim(),
          "full_name": _fullNameController.text.trim(),
          "role_name": roleName,
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        bool relogin = false;
        try {
          final data = jsonDecode(response.body);
          relogin = data is Map && data["relogin_required"] == true;
        } catch (_) {}
        Navigator.of(context).pop(relogin ? "relogin" : true);
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
      appBar: AppBar(title: const Text("ইউজার এডিট")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: "পূর্ণ নাম",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? "নাম দিন" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: "ইউজার আইডি (ইউজারনেম)",
                  helperText: "বদলালে ওই ইউজারকে নতুন আইডি দিয়ে আবার লগইন করতে হবে",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? "ইউজার আইডি দিন" : null,
              ),
              const SizedBox(height: 16),
              const Text("রোল", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _commonRoles.map((role) {
                  return ChoiceChip(
                    label: Text(role),
                    selected: !_useCustomRole && _selectedRole == role,
                    onSelected: (selected) {
                      setState(() {
                        _useCustomRole = false;
                        _selectedRole = role;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _useCustomRole,
                    onChanged: (value) {
                      setState(() {
                        _useCustomRole = value ?? false;
                      });
                    },
                  ),
                  const Text("অন্য রোল লিখুন"),
                ],
              ),
              if (_useCustomRole)
                TextFormField(
                  controller: _customRoleController,
                  decoration: const InputDecoration(
                    labelText: "রোলের নাম",
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
                      : const Text("সংরক্ষণ করুন", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}