"""
পার্টনার (সেল সেন্টার) অগ্রিম ও রানারের ডেলিভারির হিসাব বসানোর প্যাচ।

backend ফোল্ডারে (যেখানে main.py আছে) এই ফাইল আর partner_ledger.py রেখে চালান:
    .\\venv\\Scripts\\python.exe apply_partner_ledger.py --check   (শুধু দেখায়, কিছু বদলায় না)
    .\\venv\\Scripts\\python.exe apply_partner_ledger.py           (বদল বসায়, ব্যাকআপ রাখে)

যা করে:
  1) backend/main.py : বিক্রির সময় সাপ্লায়ারের অগ্রিম থেকে গাড়ির দাম কাটা, নতুন হিসাবের পথ চালু
  2) frontend/lib/trade_screens.dart : ক্রয় ফর্মে সাপ্লায়ার বাছলে "বাকি" নিজে বাছা হয়, লেখা পরিষ্কার
  3) frontend/lib/main.dart : মেনুতে "পার্টনার ও রানার হিসাব" (ঐচ্ছিক ফাইল)
ডাটাবেসে কোনো কলাম বা টেবিল যোগ হয় না। প্রতিটা ফাইলের পুরনো কপি থাকে: <ফাইল>.bak_partner
কোনো ফাইলে মিল না পেলে কিছুই বদলায় না।
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FRONT = os.path.normpath(os.path.join(HERE, "..", "frontend", "lib"))


def after(literal, new_lines, marker):
    """যে লাইনে literal আছে (ঠিক একটা লাইন), তার নিচে নতুন লাইন বসায়"""
    return ("after", literal, new_lines, marker)


def before_regex(pattern, new_lines, marker):
    return ("before_regex", pattern, new_lines, marker)


def replace(literal, new_text, marker):
    return ("replace", literal, new_text, marker)


FILES = [
    # (পথ, আবশ্যক কি না, বদলের তালিকা)
    (
        os.path.join(HERE, "main.py"),
        True,
        [
            after(
                "from advance_orders import build_advance_router",
                ["from partner_ledger import build_partner_router, settle_scope, settle_unit_advance"],
                "from partner_ledger import",
            ),
            after(
                "app.include_router(build_advance_router(get_current_user))",
                ["", "app.include_router(build_partner_router(get_current_user))"],
                "build_partner_router(get_current_user)",
            ),
            before_regex(
                r"(?P<indent>[ \t]*)customer = db\.query\(Party\)\.filter\(Party\.id == payload\.customer_id\)\.first\(\)\s*\n\s*if customer:\s*\n\s*if due_amount > 0:",
                [
                    "# বিক্রির সময় সাপ্লায়ারের অগ্রিম থেকে গাড়ির দাম কাটা (পার্টনারের হিসাব)",
                    "try:",
                    "    settle_unit_advance(db, unit)",
                    "except Exception:",
                    "    db.rollback()",
                    "",
                ],
                "settle_unit_advance(db, unit)",
            ),
            before_regex(
                r"(?P<indent>[ \t]*)balances = supplier_advance_balances\(db, bid\)",
                [
                    "try:",
                    "    settle_scope(db, bid)",
                    "except Exception:",
                    "    db.rollback()",
                ],
                "settle_scope(db, bid)",
            ),
        ],
    ),
    (
        os.path.join(FRONT, "trade_screens.dart"),
        True,
        [
            after(
                "_selectedOrderId = null;",
                ['if (value != null) _paymentMode = "due";'],
                '_paymentMode = "due";',
            ),
            replace(
                'labelText: "অগ্রিম থেকে কাটবেন (টাকা)",',
                'labelText: "অগ্রিম থেকে কাটবেন (সাধারণত ০ রাখুন, বিক্রির সময় নিজে কাটবে)",',
                "সাধারণত ০ রাখুন",
            ),
            replace(
                'title: const Text("বাকি (Due)"),',
                'title: const Text("বাকি / বিক্রির সময় অগ্রিম থেকে কাটবে"),',
                "বাকি / বিক্রির সময়",
            ),
        ],
    ),
    (
        os.path.join(FRONT, "main.dart"),
        False,
        [
            after(
                "import 'supplier_order_screen.dart';",
                ["import 'partner_ledger_screen.dart';"],
                "import 'partner_ledger_screen.dart';",
            ),
            after(
                "(t) => SupplierOrderScreen(token: t)),",
                [
                    '_MenuItem(Icons.groups_outlined, "পার্টনার ও রানার হিসাব",',
                    "    (t) => PartnerLedgerScreen(token: t)),",
                ],
                "PartnerLedgerScreen(token: t)",
            ),
        ],
    ),
]


def apply_edits(text, edits):
    """(নতুন_লেখা, বার্তার তালিকা) অথবা (None, ত্রুটির বার্তা)"""
    msgs = []
    for kind, key, new, marker in edits:
        if marker in text:
            msgs.append("  - আগে থেকেই করা আছে, বাদ")
            continue

        if kind == "after":
            lines = text.split("\n")
            idx = [i for i, ln in enumerate(lines) if key in ln]
            if len(idx) != 1:
                return None, f"এই লাইনটা ঠিক একবার পাওয়া উচিত ছিল, পাওয়া গেছে {len(idx)} বার: {key[:70]}"
            i = idx[0]
            indent = re.match(r"[ \t]*", lines[i]).group(0)
            ins = [(indent + ln) if ln.strip() else ln for ln in new]
            lines[i + 1:i + 1] = ins
            text = "\n".join(lines)
            msgs.append("  - যোগ হলো: " + new[0][:60])

        elif kind == "before_regex":
            found = list(re.finditer(key, text))
            if len(found) != 1:
                return None, f"ফর্মের জায়গাটা ঠিক একবার পাওয়া উচিত ছিল, পাওয়া গেছে {len(found)} বার"
            m = found[0]
            indent = m.group("indent")
            block = "\n".join((indent + ln) if ln.strip() else ln for ln in new) + "\n"
            text = text[:m.start()] + block + text[m.start():]
            msgs.append("  - ফর্মে নতুন ঘর যোগ হলো")

        elif kind == "replace":
            if text.count(key) != 1:
                return None, f"এই লেখাটা ঠিক একবার পাওয়া উচিত ছিল, পাওয়া গেছে {text.count(key)} বার: {key[:70]}"
            text = text.replace(key, new)
            msgs.append("  - বদলানো হলো: " + key[:50])

    return text, msgs


def read_file(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        raw = f.read()
    crlf = "\r\n" in raw
    return raw.replace("\r\n", "\n"), crlf


def write_file(path, text, crlf):
    if crlf:
        text = text.replace("\n", "\r\n")
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def main():
    check_only = "--check" in sys.argv
    plan = []
    problems = []

    print("=== ফাইল পরীক্ষা ===")
    for path, required, edits in FILES:
        name = os.path.relpath(path, os.path.join(HERE, ".."))
        if not os.path.exists(path):
            if required:
                problems.append(f"{name}: ফাইল পাওয়া যায়নি")
                print(f"[ত্রুটি] {name}: ফাইল নেই")
            else:
                print(f"[বাদ]   {name}: ফাইল নেই, এটা ঐচ্ছিক")
            continue
        text, crlf = read_file(path)
        new_text, msgs = apply_edits(text, edits)
        if new_text is None:
            if required:
                problems.append(f"{name}: {msgs}")
                print(f"[ত্রুটি] {name}: {msgs}")
            else:
                print(f"[বাদ]   {name}: মিল পাওয়া যায়নি, এই ফাইলে কিছু বদলাবে না (ঐচ্ছিক)")
                print(f"        কারণ: {msgs}")
            continue
        print(f"[ঠিক]   {name}")
        for m in msgs:
            print(m)
        plan.append((path, text, new_text, crlf))

    if problems:
        print("\nকোনো ফাইল বদলানো হয়নি। উপরের ত্রুটি ঠিক করে বা আমাকে পাঠিয়ে আবার চালান।")
        return

    if check_only:
        print("\nএটা শুধু পরীক্ষা ছিল। বদল বসাতে --check ছাড়া চালান।")
        return

    print("\n=== বদল বসানো হচ্ছে ===")
    for path, old, new, crlf in plan:
        if old == new:
            continue
        shutil.copyfile(path, path + ".bak_partner")
        write_file(path, new, crlf)
        print("লেখা হলো:", os.path.relpath(path, os.path.join(HERE, "..")))

    print("\nসম্পন্ন। এখন ব্যাকএন্ড আবার চালু করুন এবং অ্যাপ নতুন করে চালান। ডাটাবেসে কিছু বদলাতে হয়নি।")


if __name__ == "__main__":
    main()
