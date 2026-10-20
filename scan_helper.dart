import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// ক্যামেরা দিয়ে স্ক্যান শুধু ফোনে (Android/iPhone) চলে। পিসিতে চলে না।
/// পিসিতে USB বারকোড/QR স্ক্যানার লাগালে সেটা কীবোর্ডের মতো লেখা বসিয়ে দেয়, আলাদা কিছু লাগে না।
bool get canScanWithCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// ক্যামেরা খুলে একটা QR বা বারকোড পড়ে, পড়া লেখাটা ফেরত দেয় (বাতিল করলে null)।
Future<String?> scanCodeOnce(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const _ScanPage()),
  );
}

/// চেসিস নম্বরের ঘরে বসানোর স্ক্যান বাটন। পিসিতে কিছু দেখায় না।
/// ব্যবহার: TextField-এর decoration-এ suffixIcon: ChassisScanButton(controller: chassisController)
class ChassisScanButton extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onScanned;

  const ChassisScanButton({super.key, required this.controller, this.onScanned});

  @override
  Widget build(BuildContext context) {
    if (!canScanWithCamera) return const SizedBox.shrink();
    return IconButton(
      tooltip: "QR স্ক্যান করে চেসিস নম্বর বসান",
      icon: const Icon(Icons.qr_code_scanner),
      onPressed: () async {
        final v = await scanCodeOnce(context);
        if (v == null) return;
        controller.text = v;
        controller.selection = TextSelection.collapsed(offset: v.length);
        onScanned?.call();
      },
    );
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final MobileScannerController _c =
      MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("চেসিস QR স্ক্যান"),
        actions: [
          IconButton(
            tooltip: "টর্চ",
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _c.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _c, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: Text(
                "QR বা বারকোড ফ্রেমের ভেতরে ধরুন",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}