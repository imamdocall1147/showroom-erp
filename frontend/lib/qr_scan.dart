import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// QR কোড স্ক্যান করে লেখা (যেমন চেসিস নম্বর) ফেরত দেয়। বাতিল করলে null।
/// • ফোন/ট্যাবলেটের অ্যাপে (ও ওয়েবে): ক্যামেরা দিয়ে স্ক্যান
/// • পিসির উইন্ডোজ অ্যাপে ক্যামেরা স্ক্যান নেই: হ্যান্ড স্ক্যানার দিয়ে চেসিস ঘরে সরাসরি স্ক্যান করুন
Future<String?> scanChassisQr(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _ScanDialog(),
  );
}

bool get _cameraSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

class _ScanDialog extends StatefulWidget {
  const _ScanDialog();

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  bool _done = false;

  void _finish(String value) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("QR স্ক্যান করুন"),
      content: SizedBox(
        width: 380,
        child: _cameraSupported
            ? SizedBox(
                height: 280,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: MobileScanner(
                    onDetect: (capture) {
                      for (final b in capture.barcodes) {
                        final v = b.rawValue?.trim();
                        if (v != null && v.isNotEmpty) {
                          _finish(v);
                          break;
                        }
                      }
                    },
                  ),
                ),
              )
            : Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "পিসির উইন্ডোজ অ্যাপে ক্যামেরা স্ক্যান নেই।\n\n"
                  "হ্যান্ড (USB) স্ক্যানার থাকলে এই বাক্স বন্ধ করে চেসিস নম্বরের ঘরে ক্লিক করুন, "
                  "তারপর স্ক্যান করুন। নম্বর নিজে থেকে বসে যাবে।\n\n"
                  "ফোনের অ্যাপে (APK) এই বাটন ক্যামেরা খুলবে।",
                  style: TextStyle(fontSize: 13),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text("বন্ধ করুন"),
        ),
      ],
    );
  }
}
