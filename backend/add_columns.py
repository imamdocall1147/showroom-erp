from sqlalchemy import text, inspect
from database import engine

COLUMNS = [
    ("units", "decoration_cost", "INTEGER DEFAULT 0"),
    ("units", "registration_cost", "INTEGER DEFAULT 0"),
]

insp = inspect(engine)
with engine.begin() as conn:
    for table, col, ddl in COLUMNS:
        existing = [c["name"] for c in insp.get_columns(table)]
        if col in existing:
            print(f"আগেই আছে: {table}.{col}")
        else:
            conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {col} {ddl}"))
            print(f"যোগ হয়েছে: {table}.{col}")