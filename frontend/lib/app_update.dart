import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart' show apiBaseUrl;

bool _checked = false;

/// ফোনের (Android) অ্যাপ খোলার সময় সার্ভারে নতুন ভার্সন আছে কিনা দেখে।
/// থাকলে "আপডেট করুন" জানালা দেখায়। প্রতিবার অ্যাপ চালুতে একবারই দেখে।
/// পিসিতে কিছু করে না (পিসির অ্যাপ setup_erp.bat দিয়ে নতুন করে বানাতে হয়)।
Future<void> checkForAppUpdate(BuildContext context) async {
  if (_checked || kIsWeb || !Platform.isAndroid) return;
  _checked = true;
  try {
    final info = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;

    final res = await http
        .get(Uri.parse("$apiBaseUrl/app/version"))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return;

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final latest = ((data["build"] ?? 0) as num).toInt();
    final name = "${data["name"] ?? ''}";
    if (latest <= current) return;
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("নতুন আপডেট আছে"),
        content: Text(
          "অ্যাপের নতুন ভার্সন${name.isEmpty ? '' : ' ($name)'} পাওয়া গেছে।\n\n"
          "\"আপডেট করুন\" চাপলে ফাইলটা নামবে। নামা শেষে ফাইলটা খুলে \"ইনস্টল\" চাপুন।",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("পরে"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(
                Uri.parse("$apiBaseUrl/app/download"),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text("আপডেট করুন"),
          ),
        ],
      ),
    );
  } catch (_) {
    // সার্ভারে সংযোগ না থাকলে বা কিছু ভুল হলে চুপচাপ বাদ
  }
}