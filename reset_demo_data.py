"""
ডেমো লেনদেন মুছে সিস্টেম নতুন করে শুরুর স্ক্রিপ্ট (শুধু PostgreSQL)।

ব্যবহার (backend ফোল্ডারে, main.py যেখানে আছে সেখানে):
  1) python reset_demo_data.py             -> শুধু দেখায় কী কী মুছবে (কিছুই মোছে না)
  2) python reset_demo_data.py --execute   -> CSV ব্যাকআপ নিয়ে, নিশ্চিত করলে মোছে

মোছার আগে অবশ্যই পুরো ডাটাবেসের ব্যাকআপ নিন (pg_dump)। ব্যাকএন্ড সার্ভার বন্ধ রাখুন।
"""
import csv
import os
import sys
from datetime import datetime

from dotenv import load_dotenv

load_dotenv()

from sqlalchemy import inspect, text  # noqa: E402

# ---------------------------------------------------------------
# কী মুছবে, কী থাকবে। দরকারে এখানে বদলান।
# ---------------------------------------------------------------
# ডেমো লেনদেন: ভাউচার (হিসাবের এন্ট্রি), বিক্রয়-ক্রয়, অগ্রিম অর্ডার, বাইকের স্টক (BRTA তথ্যসহ)
DELETE_TABLES = [
    "voucher_entries",
    "vouchers",
    "advance_payments",
    "advance_orders",
    "supplier_orders",
    "units",
]

# ডেমো কাস্টমার ও সাপ্লায়ার মুছবেন? (True = সব কাস্টমার-সাপ্লায়ার মুছে যাবে)
DELETE_PARTIES = True

# স্পেয়ার পার্টসের তালিকা ও স্টকও মুছবেন? (ডেমো পার্টস থাকলে True করুন)
DELETE_SPARE_PARTS = False

# যে টেবিলের নামে এই শব্দ আছে সেটাও মুছবে (যেমন অনুমোদনের অনুরোধের টেবিল)
AUTO_DELETE_WORD = "approval"

# নাম জানা আছে এমন আরও টেবিল মুছতে চাইলে এখানে লিখুন, যেমন ["my_table"]
EXTRA_DELETE = ["change_requests"]

# সেটআপ: এগুলো থাকবে (ইউজার, রোল, কোম্পানি, শোরুম, গোডাউন, ব্র্যান্ড, মডেল, এলাকা, হিসাবের একাউন্ট)
KEEP_TABLES = [
    "roles", "users", "companies", "branches", "warehouses",
    "brands", "products", "areas", "accounts",
]

CONFIRM_WORD = "YES-DELETE"


def quote(engine, name):
    return engine.dialect.identifier_preparer.quote(name)


def count_rows(engine, name):
    with engine.connect() as conn:
        return conn.execute(text(f"SELECT COUNT(*) FROM {quote(engine, name)}")).scalar()


def make_plan(engine):
    """(মুছবে, থাকবে, অজানা) তিনটা তালিকা"""
    insp = inspect(engine)
    existing = set(insp.get_table_names())

    delete = [t for t in DELETE_TABLES if t in existing]
    if DELETE_PARTIES and "parties" in existing:
        delete.append("parties")
    if DELETE_SPARE_PARTS and "spare_parts" in existing:
        delete.append("spare_parts")
    for t in EXTRA_DELETE:
        if t in existing and t not in delete:
            delete.append(t)

    keep = [t for t in KEEP_TABLES if t in existing]
    if not DELETE_PARTIES and "parties" in existing:
        keep.append("parties")
    if not DELETE_SPARE_PARTS and "spare_parts" in existing:
        keep.append("spare_parts")

    for t in sorted(existing):
        if t in delete or t in keep:
            continue
        if AUTO_DELETE_WORD and AUTO_DELETE_WORD in t.lower():
            delete.append(t)

    unknown = sorted(existing - set(delete) - set(keep))
    return delete, keep, unknown


def find_blockers(engine, delete, others):
    """যেসব টেবিল থাকবে অথচ মুছতে যাওয়া টেবিলের সাথে জোড়া (foreign key), তাদের তালিকা"""
    insp = inspect(engine)
    blockers = []
    for t in others:
        for fk in insp.get_foreign_keys(t):
            if fk.get("referred_table") in delete:
                blockers.append((t, fk["referred_table"]))
    return blockers


def backup_to_csv(engine, tables, folder):
    os.makedirs(folder, exist_ok=True)
    with engine.connect() as conn:
        for t in tables:
            result = conn.execute(text(f"SELECT * FROM {quote(engine, t)}"))
            with open(os.path.join(folder, f"{t}.csv"), "w", newline="", encoding="utf-8-sig") as f:
                w = csv.writer(f)
                w.writerow(list(result.keys()))
                for row in result:
                    w.writerow(list(row))


def main():
    from database import engine

    execute = "--execute" in sys.argv

    if engine.dialect.name != "postgresql":
        print("এই স্ক্রিপ্ট শুধু PostgreSQL-এর জন্য। আপনার ডাটাবেস:", engine.dialect.name)
        return

    print("ডাটাবেস:", engine.url.render_as_string(hide_password=True))
    print()

    delete, keep, unknown = make_plan(engine)

    print("=== মুছে যাবে (সব সারি) ===")
    total = 0
    for t in delete:
        n = count_rows(engine, t)
        total += n
        print(f"  {t:<24} {n} সারি")
    print(f"  মোট: {total} সারি")

    print("\n=== থাকবে (সেটআপ) ===")
    for t in keep:
        print(f"  {t:<24} {count_rows(engine, t)} সারি")

    if unknown:
        print("\n=== অজানা টেবিল (মুছবে না, একবার দেখে নিন) ===")
        for t in unknown:
            print(f"  {t:<24} {count_rows(engine, t)} সারি")
        print("  এর কোনোটা ডেমো লেনদেনের হলে EXTRA_DELETE তালিকায় নাম যোগ করুন।")

    blockers = find_blockers(engine, delete, keep + unknown)
    if blockers:
        print("\n!!! সমস্যা: এই টেবিলগুলো মুছতে যাওয়া টেবিলের সাথে জোড়া, তাই মোছা যাবে না:")
        for t, ref in blockers:
            print(f"  {t} -> {ref}")
        print("  এগুলো ডেমো লেনদেনের হলে EXTRA_DELETE-এ নাম দিন, নইলে DELETE_TABLES/DELETE_PARTIES ঠিক করুন।")
        return

    if not execute:
        print("\nএটা শুধু পূর্বদর্শন ছিল, কিছু মোছা হয়নি।")
        print("সব ঠিক থাকলে চালান:  python reset_demo_data.py --execute")
        return

    print("\nসতর্কতা: এই কাজ ফেরানো যায় না। আগে pg_dump দিয়ে পুরো ডাটাবেসের ব্যাকআপ নিয়েছেন তো?")
    print(f"নিশ্চিত হলে হুবহু লিখুন: {CONFIRM_WORD}")
    answer = input("> ").strip()
    if answer != CONFIRM_WORD:
        print("বাতিল করা হলো, কিছু মোছা হয়নি।")
        return

    folder = "backup_demo_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    print(f"মুছতে যাওয়া ডেটার CSV ব্যাকআপ হচ্ছে: {folder}/")
    backup_to_csv(engine, delete, folder)

    names = ", ".join(quote(engine, t) for t in delete)
    try:
        with engine.begin() as conn:
            conn.execute(text(f"TRUNCATE TABLE {names} RESTART IDENTITY"))
    except Exception as e:
        print("\nমোছা যায়নি (কিছুই বদলায়নি):")
        print(e)
        return

    print("\nমোছা সম্পন্ন। এখন যাচাই:")
    for t in delete:
        print(f"  {t:<24} {count_rows(engine, t)} সারি")
    print("\nইনভয়েস/ভাউচার নম্বর এখন আবার ১ থেকে শুরু হবে।")
    print("এরপর ব্যাকএন্ড চালু করে অ্যাপ থেকে লগইন করুন।")


if __name__ == "__main__":
    main()