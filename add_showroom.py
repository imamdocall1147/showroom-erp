"""
একবার চালান (venv চালু অবস্থায়, backend ফোল্ডারে):  python add_showroom.py
দুবার চালালেও ক্ষতি নেই।

কাজ:
 1. units-এ decoration_cost / registration_cost কলাম
 2. accounts ও users-এ branch_id কলাম
 3. দ্বিতীয় শোরুম (CNG অটো রিক্সা) ও তার একটি গোডাউন তৈরি
 4. এতদিনের সব একাউন্ট ও অগ্রিম অর্ডার প্রথম (বাইক) শোরুমে বসানো
 5. সাপ্লায়ার-অর্ডারের টেবিল (supplier_orders) ও units.supplier_order_id কলাম
"""
from sqlalchemy import text, inspect
from database import engine
from models import Base

NEW_BRANCH_NAME = "CNG অটো রিক্সা শোরুম"
NEW_WAREHOUSE_NAME = "CNG শোরুম গোডাউন"
FIRST_BRANCH_NAME_IF_MISSING = "বাইক শোরুম"
COMPANY_NAME_IF_MISSING = "Imam Motors"

COLUMNS = [
    ("units", "decoration_cost", "INTEGER DEFAULT 0"),
    ("units", "registration_cost", "INTEGER DEFAULT 0"),
    ("accounts", "branch_id", "INTEGER REFERENCES branches(id)"),
    ("users", "branch_id", "INTEGER REFERENCES branches(id)"),
    ("advance_orders", "branch_id", "INTEGER REFERENCES branches(id)"),
    ("units", "supplier_order_id", "INTEGER REFERENCES supplier_orders(id)"),
]

# নতুন টেবিল (supplier_orders) আগে তৈরি; পুরনো টেবিলে হাত দেয় না
Base.metadata.create_all(bind=engine)

insp = inspect(engine)
with engine.begin() as conn:
    # ১. কলাম
    for table, col, ddl in COLUMNS:
        existing = [c["name"] for c in insp.get_columns(table)]
        if col in existing:
            print(f"আগেই আছে: {table}.{col}")
        else:
            conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {col} {ddl}"))
            print(f"যোগ হয়েছে: {table}.{col}")

    # ২. কোম্পানি ও প্রথম শোরুম
    company_id = conn.execute(text("SELECT id FROM companies ORDER BY id LIMIT 1")).scalar()
    if company_id is None:
        company_id = conn.execute(
            text("INSERT INTO companies (name, created_at) VALUES (:n, NOW()) RETURNING id"),
            {"n": COMPANY_NAME_IF_MISSING},
        ).scalar()
        print(f"কোম্পানি তৈরি: {COMPANY_NAME_IF_MISSING}")

    first_branch_id = conn.execute(text("SELECT id FROM branches ORDER BY id LIMIT 1")).scalar()
    if first_branch_id is None:
        first_branch_id = conn.execute(
            text("INSERT INTO branches (company_id, name, is_active, created_at) "
                 "VALUES (:c, :n, TRUE, NOW()) RETURNING id"),
            {"c": company_id, "n": FIRST_BRANCH_NAME_IF_MISSING},
        ).scalar()
        print(f"প্রথম শোরুম তৈরি: {FIRST_BRANCH_NAME_IF_MISSING}")

    # ৩. দ্বিতীয় শোরুম
    new_branch_id = conn.execute(
        text("SELECT id FROM branches WHERE name = :n"), {"n": NEW_BRANCH_NAME}
    ).scalar()
    if new_branch_id is None:
        new_branch_id = conn.execute(
            text("INSERT INTO branches (company_id, name, is_active, created_at) "
                 "VALUES (:c, :n, TRUE, NOW()) RETURNING id"),
            {"c": company_id, "n": NEW_BRANCH_NAME},
        ).scalar()
        print(f"নতুন শোরুম তৈরি: {NEW_BRANCH_NAME} (id={new_branch_id})")
    else:
        print(f"শোরুম আগেই আছে: {NEW_BRANCH_NAME} (id={new_branch_id})")

    has_wh = conn.execute(
        text("SELECT id FROM warehouses WHERE branch_id = :b LIMIT 1"), {"b": new_branch_id}
    ).scalar()
    if has_wh is None:
        conn.execute(
            text("INSERT INTO warehouses (branch_id, name, is_active, created_at) "
                 "VALUES (:b, :n, TRUE, NOW())"),
            {"b": new_branch_id, "n": NEW_WAREHOUSE_NAME},
        )
        print(f"গোডাউন তৈরি: {NEW_WAREHOUSE_NAME}")

    # ৪. পুরনো একাউন্ট প্রথম শোরুমে
    res = conn.execute(
        text("UPDATE accounts SET branch_id = :b WHERE branch_id IS NULL"), {"b": first_branch_id}
    )
    print(f"{res.rowcount}টি পুরনো একাউন্ট প্রথম শোরুমে বসানো হয়েছে (শোরুম id={first_branch_id})")

    res = conn.execute(
        text("UPDATE advance_orders SET branch_id = :b WHERE branch_id IS NULL"), {"b": first_branch_id}
    )
    print(f"{res.rowcount}টি পুরনো অগ্রিম অর্ডার প্রথম শোরুমে বসানো হয়েছে")

print("শেষ। এবার backend চালান।")