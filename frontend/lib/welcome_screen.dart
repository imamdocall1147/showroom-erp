import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart';
import 'app_theme.dart';

/// লগইনের পর এই পেজ দেখায়। কয়েক সেকেন্ড পর নিজে থেকে মূল অ্যাপে ঢোকে,
/// চাইলে "প্রবেশ করুন" বাটনে চেপে সাথে সাথে ঢোকা যায়।
class WelcomeScreen extends StatefulWidget {
  final String token;
  final String role;
  final List<Map<String, dynamic>> branches;
  final int branchId;
  final bool canViewAll;

  const WelcomeScreen({
    super.key,
    required this.token,
    required this.role,
    this.branches = const [],
    this.branchId = 0,
    this.canViewAll = false,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Timer? _timer;
  bool _went = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 3000), _enter);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _enter() {
    if (_went || !mounted) return;
    _went = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AppShell(
          token: widget.token,
          role: widget.role,
          branches: widget.branches,
          branchId: widget.branchId,
          canViewAll: widget.canViewAll,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kSidebarColor, kBrandColor],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(size: 96),
                  const SizedBox(height: 28),
                  const Text(
                    "Welcome to",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "IMAM MOTORS",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "শোরুম ম্যানেজমেন্ট সিস্টেম",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.role,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: kBrandColor,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                      ),
                      onPressed: _enter,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text("প্রবেশ করুন", style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}