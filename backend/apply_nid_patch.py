"""
NID নম্বর যোগ করার স্বয়ংক্রিয় প্যাচ।

কীভাবে চালাবেন:
  1. FastAPI সার্ভার বন্ধ করুন (Ctrl+C)।
  2. এই ফাইলটা main.py-র পাশের ফোল্ডারে রাখুন (যেখানে models.py ও database.py আছে)।
  3. ওই ফোল্ডারে টার্মিনাল খুলে চালান:   python apply_nid_patch.py
  4. FastAPI সার্ভার আবার চালু করুন।

এটা যা করে:
  - main.py ও models.py-র ব্যাকআপ রাখে (main.py.bak, models.py.bak)
  - models.py-র Party ক্লাসে nid_no কলাম যোগ করে
  - main.py-তে NID যাচাই, নতুন কাস্টমারে NID সংরক্ষণ ও PATCH /parties/{id} এডিট এন্ডপয়েন্ট যোগ করে
  - ডাটাবেসের parties টেবিলে nid_no কলাম যোগ করে
দুইবার চালালেও ক্ষতি নেই; যা আগেই হয়ে গেছে তা বাদ দিয়ে যায়।
"""
import shutil
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

CLEAN_NID_AND_CREATE = '''def clean_nid(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip().replace(" ", "")
    value = value.translate(str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789"))
    if value == "":
        return None
    if not value.isdigit() or len(value) not in (10, 13, 17):
        raise HTTPException(status_code=400, detail="NID নম্বর ১০, ১৩ বা ১৭ অঙ্কের সংখ্যা হতে হবে")
    return value


class PartyCreate(BaseModel):
    name: str
    party_type: str
    phone: str | None = None
    address: str | None = None
    area_id: int | None = None
    nid_no: str | None = None
'''

PARTY_UPDATE = '''class PartyUpdate(BaseModel):
    name: str | None = None
    phone: str | None = None
    address: str | None = None
    area_id: int | None = None
    nid_no: str | None = None


@app.patch("/parties/{party_id}")
def update_party(party_id: int, payload: PartyUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    party = db.query(Party).filter(Party.id == party_id).first()
    if not party:
        raise HTTPException(status_code=404, detail="পার্টি পাওয়া যায়নি")
    data = payload.dict(exclude_unset=True)
    if "nid_no" in data:
        party.nid_no = clean_nid(data["nid_no"])
    if data.get("name"):
        party.name = data["name"]
    for field in ("phone", "address", "area_id"):
        if field in data:
            setattr(party, field, data[field])
    db.commit()
    db.refresh(party)
    return party


'''


def patch_models(s):
    if "nid_no" in s:
        return s, "models.py: nid_no আগেই আছে, বাদ দিলাম"
    start = s.find("class Party(Base):")
    if start < 0:
        raise RuntimeError("models.py-তে 'class Party(Base):' পাওয়া যায়নি")
    marker = "    phone = Column(String(30))\n"
    pos = s.find(marker, start)
    if pos < 0:
        raise RuntimeError("Party ক্লাসে 'phone = Column(String(30))' লাইন পাওয়া যায়নি")
    pos += len(marker)
    s = s[:pos] + "    nid_no = Column(String(30), nullable=True)\n" + s[pos:]
    return s, "models.py: nid_no কলাম যোগ হয়েছে"


def patch_main(s):
    notes = []

    if "def clean_nid" in s:
        notes.append("main.py: clean_nid আগেই আছে, বাদ দিলাম")
    else:
        old = '''class PartyCreate(BaseModel):
    name: str
    party_type: str
    phone: str | None = None
    address: str | None = None
    area_id: int | None = None
'''
        if s.count(old) != 1:
            raise RuntimeError("main.py-তে PartyCreate ক্লাস হুবহু মেলেনি (হয়তো আপনি বদলেছেন)")
        s = s.replace(old, CLEAN_NID_AND_CREATE)
        notes.append("main.py: clean_nid ও PartyCreate-তে nid_no যোগ হয়েছে")

    if "nid_no=clean_nid(payload.nid_no)" in s:
        notes.append("main.py: create_party-তে NID আগেই আছে, বাদ দিলাম")
    else:
        old = "        area_id=payload.area_id,\n    )\n    db.add(party)"
        if s.count(old) != 1:
            raise RuntimeError("main.py-তে create_party-র Party(...) অংশ মেলেনি")
        s = s.replace(
            old,
            "        area_id=payload.area_id,\n        nid_no=clean_nid(payload.nid_no),\n    )\n    db.add(party)",
        )
        notes.append("main.py: create_party-তে NID সংরক্ষণ যোগ হয়েছে")

    if "def update_party" in s:
        notes.append("main.py: update_party আগেই আছে, বাদ দিলাম")
    else:
        marker = '@app.get("/parties")\n'
        if s.count(marker) != 1:
            raise RuntimeError('main.py-তে @app.get("/parties") লাইন মেলেনি')
        s = s.replace(marker, PARTY_UPDATE + marker)
        notes.append("main.py: PATCH /parties/{id} এডিট এন্ডপয়েন্ট যোগ হয়েছে")

    return s, notes


def add_db_column():
    from sqlalchemy import inspect, text
    from database import engine

    cols = [c["name"] for c in inspect(engine).get_columns("parties")]
    if "nid_no" in cols:
        return "ডাটাবেস: nid_no কলাম আগেই আছে, বাদ দিলাম"
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE parties ADD COLUMN nid_no VARCHAR(30)"))
    return "ডাটাবেস: parties টেবিলে nid_no কলাম যোগ হয়েছে"


def main():
    for name in ("models.py", "main.py"):
        try:
            open(name, encoding="utf-8").close()
        except FileNotFoundError:
            print(f"{name} পাওয়া যায়নি। এই ফাইলটা main.py-র পাশের ফোল্ডারে রেখে চালান।")
            return

    models = open("models.py", encoding="utf-8").read()
    main_py = open("main.py", encoding="utf-8").read()

    try:
        new_models, m1 = patch_models(models)
        new_main, m2 = patch_main(main_py)
    except RuntimeError as e:
        print("থামলাম, কোনো ফাইল বদলাইনি:", e)
        return

    shutil.copy("models.py", "models.py.bak")
    shutil.copy("main.py", "main.py.bak")
    open("models.py", "w", encoding="utf-8").write(new_models)
    open("main.py", "w", encoding="utf-8").write(new_main)

    print(m1)
    for line in m2:
        print(line)

    try:
        print(add_db_column())
    except Exception as e:
        print("ডাটাবেসে কলাম যোগ করা যায়নি:", e)
        print("এই SQL টা আপনার ডাটাবেস টুলে নিজে চালান:")
        print("    ALTER TABLE parties ADD COLUMN nid_no VARCHAR(30);")

    print("\nশেষ। এবার FastAPI সার্ভার আবার চালু করুন।")


if __name__ == "__main__":
    main()