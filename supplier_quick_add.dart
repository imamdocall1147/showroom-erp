import 'package:flutter/material.dart';
import 'sync_service.dart';

/// অগ্রিম/অর্ডারের ফর্ম থেকেই নতুন সাপ্লায়ার (কোম্পানি) যোগ করার ছোট ডায়ালগ।
/// সফল হলে {"id": ..., "name": ...} ফেরত দেয়। ইন্টারনেট না থাকলে {"offline": true}।
/// বাতিল করলে null।
Future<Map<String, dynamic>?> showAddSupplierDialog(
  BuildContext context,
  String token,
) async {
  final nameC = TextEditingController();
  final phoneC = TextEditingController();
  String? err;
  bool busy = false;

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text("নতুন সাপ্লায়ার / কোম্পানি"),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(
                  labelText: "কোম্পানির নাম",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: phoneC,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "ফোন (ঐচ্ছিক)",
                  border: OutlineInputBorder(),
                ),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(ctx).pop(null),
            child: const Text("বাতিল"),
          ),
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    final name = nameC.text.trim();
                    final phone = phoneC.text.trim();
                    if (name.isEmpty) {
                      setD(() {
                        err = "কোম্পানির নাম লিখুন";
                      });
                      return;
                    }
                    setD(() {
                      busy = true;
                      err = null;
                    });
                    try {
                      final res = await SyncService().apiCall(
                        method: "POST",
                        endpoint: "/parties",
                        body: {
                          "name": name,
                          "phone": phone.isEmpty ? null : phone,
                          "party_type": "supplier",
                        },
                        token: token,
                        description: "নতুন সাপ্লায়ার: $name",
                      );
                      if (res["offline"] == true) {
                        if (ctx.mounted) Navigator.of(ctx).pop({"offline": true});
                      } else if (res["error"] == true) {
                        setD(() {
                          busy = false;
                          err = res["message"] ?? "সাপ্লায়ার যোগ করা যায়নি";
                        });
                      } else {
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop({
                            "id": res["id"],
                            "name": name,
                          });
                        }
                      }
                    } catch (e) {
                      setD(() {
                        busy = false;
                        err = "সার্ভারের সাথে সংযোগ করা যায়নি";
                      });
                    }
                  },
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text("যোগ করুন"),
          ),
        ],
      ),
    ),
  );

  nameC.dispose();
  phoneC.dispose();
  return result;
}
