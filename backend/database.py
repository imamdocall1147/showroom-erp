from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv
import os

DATABASE_URL = os.getenv("DATABASE_URL")

# যদি Render থেকে আসা ইউআরএল শুধু postgresql:// দিয়ে শুরু হয়, তবে তা স্বয়ংক্রিয়ভাবে psycopg2 ড্রাইভার যুক্ত করে নেবে
if DATABASE_URL and DATABASE_URL.startswith("postgresql://"):
   DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+psycopg2://", 1)

 engine = create_engine(DATABASE_URL)

load_dotenv()

SessionLocal = sessionmaker(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()