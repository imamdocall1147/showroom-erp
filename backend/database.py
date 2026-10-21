import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv

load_dotenv()

raw_url = os.getenv("DATABASE_URL") or ""

DATABASE_URL = raw_url.strip().strip('"').strip("'")
if "DATABASE_URL=" in DATABASE_URL:
    DATABASE_URL = DATABASE_URL.split("DATABASE_URL=")[-1].strip()

for prefix in ("postgresql+psycopg2://", "postgresql://", "postgres://"):
    if DATABASE_URL.startswith(prefix):
        DATABASE_URL = "postgresql+psycopg2://" + DATABASE_URL[len(prefix):]
        break

if not DATABASE_URL.startswith(("postgresql+psycopg2://", "sqlite")):
    raise RuntimeError(
        "DATABASE_URL ভুল: শুরুর অংশ = %r, দৈর্ঘ্য = %d"
        % (DATABASE_URL[:8], len(DATABASE_URL))
    )

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()