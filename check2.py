from sqlalchemy import text
from database import engine

with engine.connect() as conn:
    print("শোরুম অনুযায়ী একাউন্ট:")
    for r in conn.execute(text("SELECT branch_id, COUNT(*) FROM accounts GROUP BY branch_id ORDER BY branch_id")):
        print("  শোরুম id", r[0], "->", r[1], "টি একাউন্ট")
    print("\nইউজার:")
    for r in conn.execute(text("SELECT id, username, branch_id FROM users ORDER BY id")):
        print("  ", r)
    print("\nশোরুমের বিস্তারিত:")
    for r in conn.execute(text("SELECT id, name, company_id, address FROM branches ORDER BY id")):
        print("  ", r)
    print("\nবাইক (গোডাউন অনুযায়ী):")
    for r in conn.execute(text("SELECT warehouse_id, COUNT(*) FROM units GROUP BY warehouse_id")):
        print("  গোডাউন id", r[0], "->", r[1], "টি বাইক")