# -*- coding: utf-8 -*-
"""
"রানার ডেলিভারি" রিপোর্ট যোগ করে (পার্টনারের কোডে হাত দেয় না):
  ব্যাকএন্ড main.py : GET /reports/supplier-deliveries
                      (মাসের অর্ডার, দৈনিক ডেলিভারি, সব চলমান অর্ডারে মোট আসা বাকি)
  অ্যাপ lib         : supplier_delivery_screen.dart কপি + মেনুতে "রানার ডেলিভারি"

ব্যবহার (শুধু এই একটা ফাইলই লাগবে, অ্যাপের স্ক্রিনের কোড এর ভেতরেই আছে; backend ফোল্ডারে ঢুকে):
    python apply_runner_deliveries.py
ফোল্ডার আলাদা হলে (backend, তারপর lib):
    python apply_runner_deliveries.py D:\\apps\\showroom-erp\\backend D:\\apps\\showroom-erp\\frontend\\lib

কিছু বদলানোর আগে main.py.rd.bak ও main.dart.rd.bak নামে ব্যাকআপ রাখে।
"""
import os
import py_compile
import shutil
import sys


def read(path):
    with open(path, "rb") as f:
        raw = f.read()
    crlf = b"\r\n" in raw
    return raw.decode("utf-8-sig").replace("\r\n", "\n"), crlf


def write(path, text, crlf):
    if crlf:
        text = text.replace("\n", "\r\n")
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))


def fail(msg):
    print("[ত্রুটি]", msg, "কিছু বদলানো হয়নি।")
    print("এই মেসেজটা সহ আমাকে জানান।")
    sys.exit(1)


def replace_once(text, anchor, new, label):
    n = text.count(anchor)
    if n != 1:
        fail(f"'{label}' জায়গাটা ঠিকমতো পাওয়া যায়নি (পাওয়া গেছে {n} বার)।")
    return text.replace(anchor, new)


MAIN_CODE = '''


# ---------------------------------------------------------------
# রানার (সাপ্লায়ার) থেকে ডেলিভারির রিপোর্ট
# ---------------------------------------------------------------
@app.get("/reports/supplier-deliveries")
def supplier_deliveries(month: str | None = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """মাসের অর্ডার, দৈনিক গাড়ী পাওয়া, আর সব চলমান অর্ডারে এখনো মোট কত গাড়ী আসা বাকি।
    month = YYYY-MM (না দিলে চলতি মাস)।"""
    bid = scope_branch(current_user)
    local = timedelta(hours=6)  # ডাটাবেসে সময় UTC, বাংলাদেশ = UTC+6

    if month:
        try:
            y, m = [int(x) for x in month.split("-")]
            start = datetime(y, m, 1)
        except Exception:
            raise HTTPException(status_code=400, detail="month অবশ্যই YYYY-MM আকারে দিন (যেমন 2026-10)")
    else:
        now_local = datetime.utcnow() + local
        y, m = now_local.year, now_local.month
        start = datetime(y, m, 1)
    end = datetime(y + (m // 12), (m % 12) + 1, 1)
    start_utc, end_utc = start - local, end - local

    oq = db.query(SupplierOrder)
    if bid:
        oq = oq.filter(SupplierOrder.branch_id == bid)
    month_orders = (
        oq.filter(SupplierOrder.order_date >= start_utc, SupplierOrder.order_date < end_utc)
        .order_by(SupplierOrder.id)
        .all()
    )
    open_orders = oq.filter(SupplierOrder.status == "open").order_by(SupplierOrder.id).all()
    month_rows = supplier_order_dicts(db, month_orders)
    open_rows = supplier_order_dicts(db, open_orders)

    uq = units_query(db, bid).filter(
        Unit.supplier_id.isnot(None),
        Unit.purchase_date >= start_utc,
        Unit.purchase_date < end_utc,
    )
    daily = {}
    for u in uq.all():
        day = (u.purchase_date + local).strftime("%Y-%m-%d")
        daily[day] = daily.get(day, 0) + 1

    return {
        "month": f"{y:04d}-{m:02d}",
        "month_ordered": sum(r["qty"] for r in month_rows if r["status"] != "cancelled"),
        "month_received": sum(r["received"] for r in month_rows),
        "month_orders": month_rows,
        "delivered_in_month": sum(daily.values()),
        "daily_deliveries": [{"date": d, "count": c} for d, c in sorted(daily.items())],
        "open_orders_remaining": sum(r["remaining"] for r in open_rows),
        "open_orders": open_rows,
    }
'''

DART_SCREEN = r'''import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'main.dart' show apiBaseUrl;

/// রানারের কাছ থেকে ডেলিভারি: মাসের অর্ডার, দৈনিক গাড়ী পাওয়া,
/// আর সব চলমান অর্ডারে এখনো কত গাড়ী আসা বাকি।
class SupplierDeliveryScreen extends StatefulWidget {
  final String token;
  const SupplierDeliveryScreen({super.key, required this.token});

  @override
  State<SupplierDeliveryScreen> createState() => _SupplierDeliveryScreenState();
}

class _SupplierDeliveryScreenState extends State<SupplierDeliveryScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  String get _monthKey =>
      "${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}";

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _detail(http.Response res) {
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map && d["detail"] is String) return d["detail"] as String;
    } catch (_) {}
    if (res.statusCode == 401) return "লগইনের মেয়াদ শেষ, আবার লগইন করুন";
    return "সমস্যা হয়েছে (${res.statusCode})";
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(
        Uri.parse("$apiBaseUrl/reports/supplier-deliveries?month=$_monthKey"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _data = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
        });
      } else {
        setState(() {
          _error = _detail(res);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "সার্ভারের সাথে সংযোগ করা যায়নি";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _shift(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  String _statusLabel(String? s) {
    switch (s) {
      case "open":
        return "চলমান";
      case "completed":
        return "সম্পন্ন";
      case "cancelled":
        return "বাতিল";
      default:
        return s ?? "";
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    );
  }

  Widget _orderTile(Map<String, dynamic> o) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text("${o['model'] ?? '-'}  —  ${o['supplier_name'] ?? '-'}",
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          "অর্ডার ${o['qty']} টি  •  পাওয়া ${o['received']} টি  •  বাকি ${o['remaining']} টি\n"
          "অর্ডারের তারিখ: ${o['order_date'] ?? '-'}",
        ),
        trailing: Text(_statusLabel(o["status"] as String?)),
        isThreeLine: true,
      ),
    );
  }

  Widget _content() {
    final d = _data!;
    final monthOrders = List<Map<String, dynamic>>.from(
        (d["month_orders"] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final openOrders = List<Map<String, dynamic>>.from(
        (d["open_orders"] as List).map((e) => Map<String, dynamic>.from(e as Map)));
    final daily = List<Map<String, dynamic>>.from(
        (d["daily_deliveries"] as List).map((e) => Map<String, dynamic>.from(e as Map)));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statBox("এই মাসে অর্ডার", "${d['month_ordered'] ?? 0} টি", Colors.blue.shade700),
              _statBox("এই মাসে গাড়ী পেয়েছেন", "${d['delivered_in_month'] ?? 0} টি", Colors.green.shade700),
              _statBox("সব চলমান অর্ডারে আসা বাকি", "${d['open_orders_remaining'] ?? 0} টি",
                  Colors.orange.shade800),
            ],
          ),
          _sectionTitle("এই মাসের অর্ডার"),
          if (monthOrders.isEmpty)
            const Text("এই মাসে কোনো অর্ডার দেওয়া হয়নি", style: TextStyle(color: Colors.black54)),
          for (final o in monthOrders) _orderTile(o),
          _sectionTitle("দৈনিক ডেলিভারি (রানার থেকে পাওয়া গাড়ী)"),
          if (daily.isEmpty)
            const Text("এই মাসে এখনো কোনো গাড়ী পাওয়া যায়নি", style: TextStyle(color: Colors.black54)),
          for (final row in daily)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_today, size: 18),
                title: Text("${row['date']}"),
                trailing: Text("${row['count']} টি", style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          _sectionTitle("চলমান অর্ডার (এখনো আসা বাকি)"),
          if (openOrders.isEmpty)
            const Text("কোনো চলমান অর্ডার নেই", style: TextStyle(color: Colors.black54)),
          for (final o in openOrders) _orderTile(o),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text("আবার চেষ্টা করুন")),
            ],
          ),
        ),
      );
    } else if (_data == null) {
      body = const SizedBox.shrink();
    } else {
      body = _content();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("রানার ডেলিভারি"),
        actions: [
          IconButton(
            tooltip: "আগের মাস",
            icon: const Icon(Icons.chevron_left),
            onPressed: _loading ? null : () => _shift(-1),
          ),
          Center(
            child: Text(_monthKey, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: "পরের মাস",
            icon: const Icon(Icons.chevron_right),
            onPressed: _loading ? null : () => _shift(1),
          ),
          IconButton(
            tooltip: "রিফ্রেশ",
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: body,
    );
  }
}
'''


MENU_ITEM = (
    '    _MenuItem(Icons.local_shipping, "রানার ডেলিভারি",\n'
    "        (t) => SupplierDeliveryScreen(token: t)),\n"
)
MENU_ANCHOR = '    _MenuItem(Icons.search, "গাড়ী খুঁজুন",\n'


def main():
    backend = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
    if len(sys.argv) > 2:
        lib = os.path.abspath(sys.argv[2])
    else:
        lib = os.path.abspath(os.path.join(backend, "..", "frontend", "lib"))

    main_py = os.path.join(backend, "main.py")
    main_dart = os.path.join(lib, "main.dart")
    screen_dst = os.path.join(lib, "supplier_delivery_screen.dart")

    if not os.path.isfile(main_py):
        print("[ত্রুটি] main.py পাওয়া যায়নি:", main_py)
        print("backend ফোল্ডারে ঢুকে চালান, অথবা ফোল্ডারের পথ দিন।")
        sys.exit(1)
    if not os.path.isfile(main_dart):
        print("[ত্রুটি] Flutter-এর main.dart পাওয়া যায়নি:", main_dart)
        print("দ্বিতীয় আর্গুমেন্টে lib ফোল্ডারের পথ দিন।")
        sys.exit(1)

    py_s, py_crlf = read(main_py)
    dart_s, dart_crlf = read(main_dart)
    new_py, new_dart = py_s, dart_s
    done = []

    # ---- ব্যাকএন্ড ----
    if "/reports/supplier-deliveries" in py_s:
        print("main.py-তে ডেলিভারি রিপোর্ট আগেই আছে, বাদ দিলাম")
    else:
        for needed in ("def supplier_order_dicts", "def units_query", "def scope_branch"):
            if needed not in py_s:
                fail(f"main.py-তে '{needed}' পাওয়া যায়নি।")
        new_py = py_s.rstrip() + "\n" + MAIN_CODE
        done.append("main.py: GET /reports/supplier-deliveries যোগ হলো")

    # ---- অ্যাপ ----
    if "SupplierDeliveryScreen" in dart_s:
        print("main.dart-এ মেনু আগেই আছে, বাদ দিলাম")
    else:
        new_dart = replace_once(
            dart_s,
            "import 'unit_search_screen.dart';\n",
            "import 'unit_search_screen.dart';\nimport 'supplier_delivery_screen.dart';\n",
            "ইম্পোর্ট",
        )
        new_dart = replace_once(new_dart, MENU_ANCHOR, MENU_ITEM + MENU_ANCHOR, 'মেনুর "গাড়ী খুঁজুন" আইটেম')
        done.append("main.dart: 'রানার ডেলিভারি' মেনু যোগ হলো")

    if not done:
        print("কিছু করার নেই, সবই আগে থেকে বসানো আছে।")
        return

    if new_py != py_s:
        shutil.copyfile(main_py, main_py + ".rd.bak")
        write(main_py, new_py, py_crlf)
        try:
            py_compile.compile(main_py, doraise=True)
        except py_compile.PyCompileError as e:
            shutil.copyfile(main_py + ".rd.bak", main_py)
            print("[ত্রুটি] সিনট্যাক্স এরর এসেছে, main.py আগের অবস্থায় ফিরিয়ে দিয়েছি:")
            print(e)
            sys.exit(1)

    if new_dart != dart_s:
        shutil.copyfile(main_dart, main_dart + ".rd.bak")
        write(main_dart, new_dart, dart_crlf)
        if not os.path.isfile(screen_dst):
            with open(screen_dst, "wb") as f:
                f.write(DART_SCREEN.encode("utf-8"))
            done.append("lib: supplier_delivery_screen.dart তৈরি হলো")

    print("সফল! যা যা হলো:")
    for d in done:
        print("  -", d)
    print("ব্যাকআপ: main.py.rd.bak, main.dart.rd.bak")
    print("এখন ব্যাকএন্ড আবার চালু করুন ও অ্যাপ নতুন করে run করুন।")


if __name__ == "__main__":
    main()
