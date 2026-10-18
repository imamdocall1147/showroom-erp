import 'package:flutter/material.dart';

// ---------------------------------------------------------------
// অ্যাপের রং ও নাম এক জায়গায়। এখানে বদলালে পুরো অ্যাপের চেহারা বদলে যাবে।
// ---------------------------------------------------------------
const String kAppName = "Imam Motors";
const Color kBrandColor = Color(0xFF1E5AA8); // মূল রং (নীল)
const Color kSidebarColor = Color(0xFF0E1A2E); // বাঁ পাশের মেনুর গাঢ় রং
const Color kPageColor = Color(0xFFF3F5F9); // পেজের পেছনের হালকা রং
const Color kBorderColor = Color(0xFFE3E7EF);
const Color kTextDark = Color(0xFF1B2433);

/// লাখ-কোটি গ্রুপিংসহ টাকা: ৳12,34,567
String formatTaka(num n) {
  final digits = n.abs().round().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = "${parts.join(',')},$last3";
  }
  return "${n < 0 ? '-' : ''}৳$grouped";
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandColor,
    brightness: Brightness.light,
  );

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kPageColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: kTextDark,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: kTextDark,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kBorderColor),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(kBorderColor),
      enabledBorder: border(kBorderColor),
      disabledBorder: border(kBorderColor),
      focusedBorder: border(scheme.primary, 1.8),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 1.8),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: buttonShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: buttonShape,
        side: const BorderSide(color: kBorderColor),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: buttonShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: kBorderColor)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w500),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: const DividerThemeData(color: kBorderColor, space: 1, thickness: 1),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}

// ---------------------------------------------------------------
// পুনর্ব্যবহারযোগ্য উইজেট
// ---------------------------------------------------------------

/// গোল লোগো (বাইক আইকনসহ)
class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFD6E4F7)],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Icon(Icons.two_wheeler, size: size * 0.58, color: kBrandColor),
    );
  }
}

/// ফর্ম পেজের জন্য: বড় স্ক্রিনে ফর্ম মাঝখানে সীমিত প্রস্থে থাকে
class FormWrap extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const FormWrap({super.key, required this.child, this.maxWidth = 680});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

/// একটা সংখ্যার কার্ড (আইকন + শিরোনাম + মান)
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = kBrandColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// কার্ডগুলো স্ক্রিনের প্রস্থ অনুযায়ী সারিতে সাজায়
class StatGrid extends StatelessWidget {
  final List<StatCard> cards;

  const StatGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final count = cards.length;
        final cols = w >= 720 ? (count > 4 ? 4 : count) : (w >= 460 ? 2 : 1);
        const gap = 12.0;
        final itemW = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: itemW, child: card),
          ],
        );
      },
    );
  }
}

/// তালিকা ফাঁকা থাকলে দেখানোর জন্য
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.black26),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.black54, fontSize: 15)),
        ],
      ),
    );
  }
}