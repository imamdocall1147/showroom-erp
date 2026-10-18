import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';
import 'app_theme.dart';
import 'party_screen.dart';
import 'receivable_screen.dart';
import 'expense_screen.dart';
import 'accounts_screen.dart';
import 'reports_screen.dart';
import 'trade_screens.dart';

class DashboardScreen extends StatefulWidget {
  final String token;

  const DashboardScreen({super.key, required this.token});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse("$apiBaseUrl/reports/dashboard"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _data = jsonDecode(response.body);
        });
      } else {
        setState(() {
          _errorMessage = "ড্যাশবোর্ড তথ্য আনতে সমস্যা হয়েছে";
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

  String _fmt(dynamic v) {
    final n = (v is num) ? v : (num.tryParse("$v") ?? 0);
    final neg = n < 0;
    final s = n.abs().round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return neg ? "-$b" : b.toString();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _loadDashboard();
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  Widget _welcome() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE3EEFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E3F3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.trending_up, color: Colors.green, size: 34),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("স্বাগতম!",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kBrandColor)),
                Text("আপনার ব্যবসা এখন আরও সহজ, আরও স্মার্ট।"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpis(double width) {
    final cards = [
      _kpiCard("সর্বমোট আয়", "৳ ${_fmt(_data!['total_revenue'])}", Icons.trending_up,
          const Color(0xFF16B364)),
      _kpiCard("বিক্রিত বাইক", "${_data!['total_units_sold']} টি", Icons.two_wheeler,
          const Color(0xFF1E6BFF)),
      _kpiCard("মোট বাকি (পাওনা)", "৳ ${_fmt(_data!['total_receivables'])}", Icons.receipt_long,
          const Color(0xFFFF9F0A)),
      _kpiCard("মোট দেনা", "৳ ${_fmt(_data!['total_payables'])}", Icons.local_shipping,
          const Color(0xFFF2454F)),
      _kpiCard("স্টকের মূল্য (বাইক + পার্টস)", "৳ ${_fmt(_data!['stock_value'])}", Icons.inventory_2,
          const Color(0xFF7C4DDB)),
    ];

    if (width >= 1000) {
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    final each = width >= 560 ? (width - 12) / 2 : width;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final c in cards) SizedBox(width: each, child: c)],
    );
  }

  Widget _panel({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E3F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: kBrandColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: kBrandColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _chartPanel() {
    final List<dynamic> all = _data!['daily_sales'] ?? [];
    final recent = all.length > 7 ? all.sublist(all.length - 7) : all;

    Widget body;
    if (recent.isEmpty) {
      body = const SizedBox(
        height: 200,
        child: Center(child: Text("এখনো কোনো বিক্রয় ডাটা নেই")),
      );
    } else {
      final values = recent.map<double>((e) => (e['amount'] as num).toDouble()).toList();
      final labels = recent.map<String>((e) {
        final parts = "${e['date']}".split("-");
        return parts.length == 3 ? "${parts[2]}/${parts[1]}" : "${e['date']}";
      }).toList();
      body = SizedBox(
        height: 220,
        child: CustomPaint(
          size: Size.infinite,
          painter: _BarChartPainter(values, labels, _fmt),
        ),
      );
    }

    return _panel(title: "সাম্প্রতিক বিক্রয় (শেষ ৭ দিন)", icon: Icons.bar_chart, child: body);
  }

  Widget _quickButton(String label, IconData icon, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: fg, size: 28),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickPanel() {
    final buttons = [
      _quickButton("নতুন বাইক ক্রয়", Icons.shopping_bag, const Color(0xFFFFE8B8),
          const Color(0xFFFF9F0A), () => _open(PurchaseScreen(token: widget.token))),
      _quickButton("কাস্টমার / সাপ্লায়ার", Icons.groups, const Color(0xFFE6DAFB),
          const Color(0xFF7C4DDB), () => _open(PartyListScreen(token: widget.token))),
      _quickButton("বাকি আদায়", Icons.payments, const Color(0xFFFFD6DA),
          const Color(0xFFF2454F), () => _open(ReceivablesScreen(token: widget.token))),
      _quickButton("দোকান খরচ", Icons.receipt_long, const Color(0xFFC9F2D8),
          const Color(0xFF16B364), () => _open(ExpenseScreen(token: widget.token))),
      _quickButton("একাউন্ট ব্যালান্স", Icons.account_balance_wallet, const Color(0xFFD6E6FF),
          const Color(0xFF1E6BFF), () => _open(AccountsScreen(token: widget.token))),
      _quickButton("রিপোর্ট দেখুন", Icons.bar_chart, const Color(0xFFCDF1F0),
          const Color(0xFF0E9AA7), () => _open(ReportsHomeScreen(token: widget.token))),
    ];

    return _panel(
      title: "দ্রুত কাজ (Quick Access)",
      icon: Icons.flash_on,
      child: Column(
        children: [
          for (int r = 0; r < 3; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: buttons[r * 2]),
                  const SizedBox(width: 8),
                  Expanded(child: buttons[r * 2 + 1]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(double width) {
    final chart = _chartPanel();
    final quick = _quickPanel();

    Widget lower;
    if (width >= 900) {
      lower = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: chart),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: quick),
        ],
      );
    } else {
      lower = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [chart, const SizedBox(height: 12), quick],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _welcome(),
        const SizedBox(height: 14),
        _kpis(width),
        const SizedBox(height: 14),
        lower,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FC),
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
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
                          onPressed: _loadDashboard,
                          child: const Text("আবার চেষ্টা করুন"),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final inner = constraints.maxWidth - 32;
                      return ExcludeSemantics(
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          child: _content(inner),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// বার চার্ট (বাইরের প্যাকেজ ছাড়া)
// ---------------------------------------------------------------
class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final String Function(dynamic) fmt;

  _BarChartPainter(this.values, this.labels, this.fmt);

  void _text(Canvas c, String t, Offset o, {bool right = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: const TextStyle(fontSize: 11, color: Colors.black87)),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx = o.dx;
    if (right) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(c, Offset(dx, o.dy - tp.height / 2));
  }

  double _niceStep(double maxV) {
    if (maxV <= 0) return 1000;
    final raw = maxV / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final norm = raw / mag;
    final f = norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10));
    return f * mag;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;

    const left = 64.0;
    const bottom = 24.0;
    final chartW = size.width - left;
    final chartH = size.height - bottom;

    final maxV = values.reduce(math.max);
    final step = _niceStep(maxV);
    final top = maxV <= 0 ? step : (maxV / step).ceil() * step;
    final lines = (top / step).round();

    final grid = Paint()
      ..color = const Color(0xFFE3E9F3)
      ..strokeWidth = 1;
    for (int i = 0; i <= lines; i++) {
      final v = step * i;
      final y = chartH - (v / top) * chartH;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      _text(canvas, fmt(v), Offset(left - 6, y), right: true);
    }

    final slot = chartW / values.length;
    final barW = math.min(slot * 0.5, 48.0);
    final paint = Paint()..color = const Color(0xFF1E6BFF);
    for (int i = 0; i < values.length; i++) {
      final h = (values[i] / top) * chartH;
      final x = left + slot * i + (slot - barW) / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, chartH - h, barW, h),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        paint,
      );
      if (i < labels.length) {
        _text(canvas, labels[i], Offset(left + slot * i + slot / 2, chartH + 14), center: true);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.values != values || old.labels != labels;
}