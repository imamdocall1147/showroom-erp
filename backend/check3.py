from sqlalchemy import text
from database import engine

with engine.connect() as conn:
    print("শোরুম 2-তে কী কী বাঁধা:")
    print("  গোডাউন:", conn.execute(text("SELECT COUNT(*) FROM warehouses WHERE branch_id=2")).scalar())
    print("  একাউন্ট:", conn.execute(text("SELECT COUNT(*) FROM accounts WHERE branch_id=2")).scalar())
    print("  ইউজার:", conn.execute(text("SELECT COUNT(*) FROM users WHERE branch_id=2")).scalar())
    print("\nস্পেয়ার পার্টস (গোডাউন অনুযায়ী):")
    for r in conn.execute(text("SELECT warehouse_id, COUNT(*) FROM spare_parts GROUP BY warehouse_id")):
        print("  গোডাউন id", r[0], "->", r[1], "টি")
    print("\nভাউচার এন্ট্রি (একাউন্টের শোরুম অনুযায়ী):")
    for r in conn.execute(text(
        "SELECT a.branch_id, COUNT(*) FROM voucher_entries e JOIN accounts a ON a.id=e.account_id GROUP BY a.branch_id"
    )):
        print("  শোরুম id", r[0], "->", r[1], "টি এন্ট্রি")