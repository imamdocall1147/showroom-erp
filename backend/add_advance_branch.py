from sqlalchemy import text, inspect
from database import engine

insp = inspect(engine)
if not insp.has_table("advance_orders"):
    print("advance_orders টেবিল নেই; সার্ভার চালু করলেই তৈরি হবে")
else:
    cols = [c["name"] for c in insp.get_columns("advance_orders")]
    with engine.begin() as conn:
        if "branch_id" not in cols:
            conn.execute(text("ALTER TABLE advance_orders ADD COLUMN branch_id INTEGER REFERENCES branches(id)"))
        first = conn.execute(text("SELECT MIN(id) FROM branches")).scalar()
        conn.execute(text("UPDATE advance_orders SET branch_id = :b WHERE branch_id IS NULL"), {"b": first})
    print("হয়েছে")