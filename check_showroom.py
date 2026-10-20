from sqlalchemy import text, inspect
from database import engine

insp = inspect(engine)

def has_col(table, col):
    return insp.has_table(table) and col in [c["name"] for c in insp.get_columns(table)]

print("accounts.branch_id        :", "আছে" if has_col("accounts", "branch_id") else "নেই")
print("users.branch_id           :", "আছে" if has_col("users", "branch_id") else "নেই")
print("units.decoration_cost     :", "আছে" if has_col("units", "decoration_cost") else "নেই")
print("units.registration_cost   :", "আছে" if has_col("units", "registration_cost") else "নেই")
print("advance_orders.branch_id  :", "আছে" if has_col("advance_orders", "branch_id") else "নেই")

with engine.connect() as conn:
    print("\nশোরুমের তালিকা:")
    for r in conn.execute(text("SELECT id, name FROM branches ORDER BY id")):
        print("  ", r[0], r[1])
    print("\nগোডাউনের তালিকা:")
    for r in conn.execute(text("SELECT id, name, branch_id FROM warehouses ORDER BY id")):
        print("  ", r[0], r[1], "(শোরুম id:", r[2], ")")