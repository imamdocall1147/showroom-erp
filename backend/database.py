import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv
load_dotenv()
DATABASE_URL = (os.getenv("DATABASE_URL") or "").strip().strip('"').strip("'")
if DATABASE_URL.startswith("DATABASE_URL="):
    DATABASE_URL = DATABASE_URL.split("=", 1)[1].strip()

if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

if not DATABASE_URL.startswith(("postgresql://", "sqlite")):
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