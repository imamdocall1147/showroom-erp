import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'app_theme.dart';

/// লগইন করা ইউজার নিজের পাসওয়ার্ড বদলানোর স্ক্রিন
class MyAccountScreen extends StatefulWidget {
  final String token;
  final String role;

  const MyAccountScreen({super.key, required this.token, required this.role});

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse("$apiBaseUrl/users/me/change-password"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode({
          "old_password": _oldController.text,
          "new_password": _newController.text,
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        _oldController.clear();
        _newController.clear();
        _confirmController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("পাসওয়ার্ড সফলভাবে বদলানো হয়েছে"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        String msg = "পাসওয়ার্ড বদলানো যায়নি";
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data["detail"] is String) msg = data["detail"];
        } catch (_) {}
        setState(() {
          _errorMessage = msg;
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
      appBar: AppBar(title: const Text("আমার একাউন্ট")),
      body: FormWrap(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_user, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text("রোল: ${widget.role}"),
                ],
              ),
              const SizedBox(height: 20),
              const Text("পাসওয়ার্ড পরিবর্তন",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _oldController,
                obscureText: _obscureOld,
                decoration: InputDecoration(
                  labelText: "বর্তমান পাসওয়ার্ড",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureOld ? Icons.visibility : Icons.visibility_off),
                    onPressed: () {
                      setState(() {
                        _obscureOld = !_obscureOld;
                      });
                    },
                  ),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? "বর্তমান পাসওয়ার্ড দিন" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newController,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: "নতুন পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
                    onPressed: () {
                      setState(() {
                        _obscureNew = !_obscureNew;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return "কমপক্ষে ৬ অক্ষরের পাসওয়ার্ড দিন";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscureNew,
                decoration: const InputDecoration(
                  labelText: "নতুন পাসওয়ার্ড আবার লিখুন",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value != _newController.text ? "দুটি পাসওয়ার্ড মিলছে না" : null,
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
                      : const Text("পাসওয়ার্ড বদলান", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}