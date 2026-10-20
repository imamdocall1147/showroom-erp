# -*- coding: utf-8 -*-
"""
বাইক ক্রয়ে "গেট পাস নম্বর" যোগ করার ব্যাকএন্ড বদল নিজে থেকে বসায়।

ব্যবহার (আগে চলমান ব্যাকএন্ড বন্ধ করুন, তারপর PowerShell-এ backend ফোল্ডারে ঢুকে):
    python apply_gate_pass.py
অথবা অন্য ফোল্ডার থেকে:
    python apply_gate_pass.py D:\\apps\\showroom-erp\\backend

যা করে:
  1. models.py  : Unit টেবিলে gate_pass_no কলাম
  2. main.py    : ক্রয়ের অনুরোধে gate_pass_no নেওয়া ও সেভ করা,
                  "গাড়ী খুঁজুন" ও স্টক রিপোর্টের ফলাফলে gate_pass_no দেখানো
  3. ডাটাবেস   : units টেবিলে gate_pass_no কলাম যোগ (ALTER TABLE)
কিছু বদলানোর আগে models.py.gp.bak ও main.py.gp.bak নামে ব্যাকআপ রাখে।
"""
import os
import shutil
import sys
import py_compile


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


def replace_once(text, anchor, new, label):
    n = text.count(anchor)
    if n != 1:
        print(f"[ত্রুটি] '{label}' জায়গাটা ঠিকমতো পাওয়া যায়নি (পাওয়া গেছে {n} বার)। কিছু বদলানো হয়নি।")
        print("সম্ভবত ফাইলটা আগে বদলানো হয়েছে। এই মেসেজটা সহ আমাকে জানান।")
        sys.exit(1)
    return text.replace(anchor, new)


MODEL_ANCHOR = "    brta_notes = Column(String, nullable=True)\n"
MODEL_NEW = (
    MODEL_ANCHOR
    + "\n    # গেট পাস নম্বর (কোম্পানি থেকে গাড়ী ছাড়ানোর সময়ের নম্বর)\n"
    + "    gate_pass_no = Column(String(50), nullable=True)\n"
)

MAIN_EDITS = [
    (
        "UnitPurchaseCreate ক্লাস",
        "class UnitPurchaseCreate(BaseModel):\n",
        "class UnitPurchaseCreate(BaseModel):\n"
        "    gate_pass_no: str | None = None  # গেট পাস নম্বর (ঐচ্ছিক)\n",
    ),
    (
        "ক্রয়ে Unit তৈরির অংশ",
        "        supplier_order_id=order.id if order else None,\n",
        "        supplier_order_id=order.id if order else None,\n"
        '        gate_pass_no=(payload.gate_pass_no or "").strip() or None,\n',
    ),
    (
        "গাড়ী খুঁজুনের ফলাফল",
        '            "year": u.year,\n',
        '            "year": u.year,\n'
        '            "gate_pass_no": u.gate_pass_no,\n',
    ),
    (
        "স্টক রিপোর্ট",
        '            "color": u.color,\n'
        '            "warehouse": u.warehouse.name if u.warehouse else None,\n'
        '            "purchase_price": u.purchase_price,\n',
        '            "color": u.color,\n'
        '            "gate_pass_no": u.gate_pass_no,\n'
        '            "warehouse": u.warehouse.name if u.warehouse else None,\n'
        '            "purchase_price": u.purchase_price,\n',
    ),
]

SQL = "ALTER TABLE units ADD COLUMN gate_pass_no VARCHAR(50)"


def add_db_column(folder):
    sys.path.insert(0, folder)
    os.chdir(folder)
    try:
        from sqlalchemy import inspect, text
        from database import engine

        cols = [c["name"] for c in inspect(engine).get_columns("units")]
        if "gate_pass_no" in cols:
            print("ডাটাবেসে gate_pass_no কলাম আগেই আছে, বাদ দিলাম")
            return True
        with engine.begin() as conn:
            conn.execute(text(SQL))
        print("ডাটাবেস: units টেবিলে gate_pass_no কলাম যোগ হলো")
        return True
    except Exception as e:
        print("[সতর্কতা] ডাটাবেসে কলাম যোগ করা যায়নি:", e)
        print("এই SQL-টা নিজে চালাতে হবে:  " + SQL + ";")
        return False


def main():
    folder = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
    models_p = os.path.join(folder, "models.py")
    main_p = os.path.join(folder, "main.py")
    for p in (models_p, main_p):
        if not os.path.isfile(p):
            print("[ত্রুটি] ফাইল পাওয়া যায়নি:", p)
            print("backend ফোল্ডারে ঢুকে চালান, অথবা ফোল্ডারের পথ দিন।")
            sys.exit(1)

    models_s, models_crlf = read(models_p)
    main_s, main_crlf = read(main_p)
    new_models, new_main = models_s, main_s
    done = []

    if "gate_pass_no" in models_s:
        print("models.py-তে gate_pass_no আগেই আছে, বাদ দিলাম")
    else:
        new_models = replace_once(models_s, MODEL_ANCHOR, MODEL_NEW, "Unit মডেলের BRTA অংশ")
        done.append("models.py: Unit-এ gate_pass_no কলাম যোগ হলো")

    if "gate_pass_no" in main_s:
        print("main.py-তে gate_pass_no আগেই আছে, বাদ দিলাম")
    else:
        for label, anchor, new in MAIN_EDITS:
            new_main = replace_once(new_main, anchor, new, label)
        done.append("main.py: ক্রয়, গাড়ী খুঁজুন ও স্টক রিপোর্টে gate_pass_no যোগ হলো")

    if done:
        shutil.copyfile(models_p, models_p + ".gp.bak")
        shutil.copyfile(main_p, main_p + ".gp.bak")
        write(models_p, new_models, models_crlf)
        write(main_p, new_main, main_crlf)
        try:
            py_compile.compile(models_p, doraise=True)
            py_compile.compile(main_p, doraise=True)
        except py_compile.PyCompileError as e:
            shutil.copyfile(models_p + ".gp.bak", models_p)
            shutil.copyfile(main_p + ".gp.bak", main_p)
            print("[ত্রুটি] বদলের পর সিনট্যাক্স এরর এসেছে, সব আগের অবস্থায় ফিরিয়ে দিয়েছি:")
            print(e)
            sys.exit(1)

    db_ok = add_db_column(folder)

    print()
    print("সম্পন্ন:")
    for d in done:
        print("  -", d)
    if done:
        print("ব্যাকআপ: models.py.gp.bak, main.py.gp.bak")
    if db_ok:
        print("এখন ব্যাকএন্ড চালু করুন।")
    else:
        print("আগে উপরের SQL চালিয়ে কলাম যোগ করুন, তারপর ব্যাকএন্ড চালু করুন।")


if __name__ == "__main__":
    main()