# -*- coding: utf-8 -*-
"""
বিনিয়োগকারীর নোট/হিসাবের ব্যাকএন্ড বদল নিজে থেকে বসায়।
ব্যবহার (PowerShell-এ, backend ফোল্ডারে ঢুকে, venv চালু করে):
    python apply_investors.py
অথবা: python apply_investors.py D:\\apps\\showroom-erp\\backend
কিছু বদলানোর আগে models.py.bak ও main.py.bak নামে ব্যাকআপ রাখে।
"""
import os
import re
import shutil
import sys
import py_compile

MODEL_CODE = '''

# ---------------------------------------------------------------
# ব্যবসায় যারা বিনিয়োগ করেছেন তাদের নোট ও হিসাব (ক্যাশ/ব্যাংকের হিসাবে প্রভাব ফেলে না)
# ---------------------------------------------------------------
class Investor(Base):
    __tablename__ = "investors"
    id = Column(Integer, primary_key=True)
    name = Column(String(150), nullable=False)
    phone = Column(String(30))
    address = Column(String(255))
    note = Column(String(500))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class InvestmentEntry(Base):
    __tablename__ = "investment_entries"
    id = Column(Integer, primary_key=True)
    investor_id = Column(Integer, ForeignKey("investors.id"), nullable=False)
    entry_type = Column(String(10), nullable=False)  # invest, profit, withdraw
    amount = Column(Integer, nullable=False)
    entry_date = Column(Date, nullable=False)
    mode = Column(String(10), default="cash")  # cash, bank, other
    note = Column(String(500))
    created_by = Column(String(50))
    created_at = Column(DateTime, default=datetime.utcnow)
'''

MAIN_CODE = '''


# ---------------------------------------------------------------
# বিনিয়োগকারী: কে কত টাকা দিয়েছেন, কত লাভ/রিটার্ন পেয়েছেন, কত মূল টাকা ফেরত নিয়েছেন
# শুধু অ্যাডমিন দেখতে ও বদলাতে পারবেন। এই হিসাব ক্যাশ/ব্যাংক একাউন্টে প্রভাব ফেলে না।
# ---------------------------------------------------------------
def require_admin_only(user):
    role_name = (user.role.name if getattr(user, "role", None) else "") or ""
    if role_name.strip().lower() != "admin":
        raise HTTPException(status_code=403, detail="শুধু অ্যাডমিন বিনিয়োগের তথ্য দেখতে ও বদলাতে পারবেন")


class InvestorCreate(BaseModel):
    name: str
    phone: str | None = None
    address: str | None = None
    note: str | None = None


class InvestorEntryCreate(BaseModel):
    entry_type: str  # invest | profit | withdraw
    amount: int
    entry_date: date | None = None
    mode: str = "cash"
    note: str | None = None


def investor_totals(db: Session):
    rows = (
        db.query(
            InvestmentEntry.investor_id,
            InvestmentEntry.entry_type,
            func.coalesce(func.sum(InvestmentEntry.amount), 0),
        )
        .group_by(InvestmentEntry.investor_id, InvestmentEntry.entry_type)
        .all()
    )
    totals = {}
    for iid, typ, s in rows:
        totals.setdefault(iid, {"invest": 0, "profit": 0, "withdraw": 0})[typ] = int(s)
    return totals


def investor_dict(inv, totals):
    t = totals.get(inv.id, {"invest": 0, "profit": 0, "withdraw": 0})
    return {
        "id": inv.id,
        "name": inv.name,
        "phone": inv.phone,
        "address": inv.address,
        "note": inv.note,
        "invested": t["invest"],
        "profit_paid": t["profit"],
        "withdrawn": t["withdraw"],
        "principal_balance": t["invest"] - t["withdraw"],
    }


@app.get("/investors")
def list_investors(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    require_admin_only(current_user)
    totals = investor_totals(db)
    rows = db.query(Investor).filter(Investor.is_active.isnot(False)).order_by(Investor.name).all()
    return [investor_dict(i, totals) for i in rows]


@app.post("/investors")
def create_investor(payload: InvestorCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    require_admin_only(current_user)
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="নাম লিখুন")
    inv = Investor(
        name=name,
        phone=(payload.phone or "").strip() or None,
        address=(payload.address or "").strip() or None,
        note=(payload.note or "").strip() or None,
    )
    db.add(inv)
    db.commit()
    db.refresh(inv)
    return investor_dict(inv, {})


@app.get("/investors/{investor_id}")
def get_investor(investor_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    require_admin_only(current_user)
    inv = db.query(Investor).filter(Investor.id == investor_id).first()
    if not inv:
        raise HTTPException(status_code=404, detail="বিনিয়োগকারী পাওয়া যায়নি")
    entries = (
        db.query(InvestmentEntry)
        .filter(InvestmentEntry.investor_id == investor_id)
        .order_by(InvestmentEntry.entry_date.desc(), InvestmentEntry.id.desc())
        .all()
    )
    data = investor_dict(inv, investor_totals(db))
    data["entries"] = [
        {
            "id": e.id,
            "entry_type": e.entry_type,
            "amount": e.amount,
            "entry_date": e.entry_date.isoformat() if e.entry_date else None,
            "mode": e.mode,
            "note": e.note,
            "created_by": e.created_by,
        }
        for e in entries
    ]
    return data


@app.patch("/investors/{investor_id}")
def update_investor(investor_id: int, payload: InvestorCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    require_admin_only(current_user)
    inv = db.query(Investor).filter(Investor.id == investor_id).first()
    if not inv:
        raise HTTPException(status_code=404, detail="বিনিয়োগকারী পাওয়া যায়নি")
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="নাম লিখুন")
    inv.name = name
    inv.phone = (payload.phone or "").strip() or None
    inv.address = (payload.address or "").strip() or None
    inv.note = (payload.note or "").strip() or None
    db.commit()
    return {"ok": True}


@app.delete("/investors/{investor_id}")
def delete_investor(investor_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    require_admin_only(current_user)
    inv = db.query(Investor).filter(Investor.id == investor_id).first()
    if not inv:
        raise HTTPException(status_code=404, detail="বিনিয়োগকারী পাওয়া যায়নি")
    has_entries = db.query(InvestmentEntry).filter(InvestmentEntry.investor_id == investor_id).first()
    if has_entries:
        raise HTTPException(status_code=400, detail="এর লেনদেন আছে, তাই মোছা যাবে না। আগে লেনদেনগুলো মুছুন")
    db.delete(inv)
    db.commit()
    return {"ok": True}


@app.post("/investors/{investor_id}/entries")
def add_investor_entry(investor_id: int, payload: InvestorEntryCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    require_admin_only(current_user)
    inv = db.query(Investor).filter(Investor.id == investor_id).first()
    if not inv:
        raise HTTPException(status_code=404, detail="বিনিয়োগকারী পাওয়া যায়নি")
    if payload.entry_type not in ("invest", "profit", "withdraw"):
        raise HTTPException(status_code=400, detail="লেনদেনের ধরন অবৈধ")
    if payload.amount <= 0:
        raise HTTPException(status_code=400, detail="টাকার পরিমাণ ০-এর বেশি হতে হবে")
    if payload.mode not in ("cash", "bank", "other"):
        raise HTTPException(status_code=400, detail="পেমেন্টের ধরন অবৈধ")

    if payload.entry_type == "withdraw":
        t = investor_totals(db).get(investor_id, {"invest": 0, "profit": 0, "withdraw": 0})
        principal = t["invest"] - t["withdraw"]
        if payload.amount > principal:
            raise HTTPException(status_code=400, detail=f"ফেরত দেওয়া যাবে সর্বোচ্চ ৳{principal} (বাকি মূল বিনিয়োগ)")

    entry = InvestmentEntry(
        investor_id=investor_id,
        entry_type=payload.entry_type,
        amount=payload.amount,
        entry_date=payload.entry_date or date.today(),
        mode=payload.mode,
        note=(payload.note or "").strip() or None,
        created_by=current_user.username,
    )
    db.add(entry)
    db.commit()
    return {"ok": True, "id": entry.id}


@app.delete("/investor-entries/{entry_id}")
def delete_investor_entry(entry_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    require_admin_only(current_user)
    entry = db.query(InvestmentEntry).filter(InvestmentEntry.id == entry_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="লেনদেন পাওয়া যায়নি")
    if entry.entry_type == "invest":
        t = investor_totals(db).get(entry.investor_id, {"invest": 0, "profit": 0, "withdraw": 0})
        if t["invest"] - entry.amount < t["withdraw"]:
            raise HTTPException(status_code=400, detail="এই বিনিয়োগ মুছলে ফেরত দেওয়া টাকার হিসাব মিলবে না। আগে ফেরতের এন্ট্রি মুছুন")
    db.delete(entry)
    db.commit()
    return {"ok": True}
'''


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    models_p = os.path.join(folder, "models.py")
    main_p = os.path.join(folder, "main.py")
    for p in (models_p, main_p):
        if not os.path.isfile(p):
            print("[ত্রুটি] ফাইল পাওয়া যায়নি:", p)
            print("backend ফোল্ডারে ঢুকে চালান, অথবা ফোল্ডারের পথ দিন।")
            sys.exit(1)

    models_s = read(models_p)
    main_s = read(main_p)
    crlf = "\r\n" in main_s

    m = re.search(r"from models import \((.*?)\)", main_s, re.S)
    if not m:
        print("[ত্রুটি] main.py-তে 'from models import ( ... )' অংশ পাওয়া যায়নি। কিছু বদলানো হয়নি।")
        sys.exit(1)
    head = main_s.split("app = FastAPI")[0]
    for needed in ("func", "date"):
        if needed not in head:
            print(f"[ত্রুটি] main.py-তে '{needed}' ইম্পোর্ট পাওয়া যায়নি। কিছু বদলানো হয়নি।")
            sys.exit(1)
    if "Date" not in models_s:
        print("[ত্রুটি] models.py-তে Date ইম্পোর্ট পাওয়া যায়নি। কিছু বদলানো হয়নি।")
        sys.exit(1)

    new_models = models_s
    new_main = main_s
    done = []

    if "class Investor(" not in models_s:
        new_models = models_s.rstrip() + "\n" + MODEL_CODE
        done.append("models.py: Investor ও InvestmentEntry টেবিল যোগ হলো")
    else:
        print("models.py-তে Investor আগেই আছে, বাদ দিলাম")

    body = m.group(1)
    missing = [n for n in ("Investor", "InvestmentEntry") if not re.search(r"\b%s\b" % n, body)]
    if missing:
        b = body.rstrip()
        if not b.endswith(","):
            b += ","
        for n in missing:
            b += "\n    %s," % n
        b += "\n"
        new_main = new_main[: m.start(1)] + b + new_main[m.end(1):]
        done.append("main.py: ইম্পোর্ট যোগ হলো: " + ", ".join(missing))

    if "def list_investors" not in new_main:
        new_main = new_main.rstrip() + "\n" + MAIN_CODE
        done.append("main.py: বিনিয়োগকারীর এন্ডপয়েন্টগুলো যোগ হলো")
    else:
        print("main.py-তে বিনিয়োগের কোড আগেই আছে, বাদ দিলাম")

    if not done:
        print("কিছু করার নেই, সবই আগে থেকে বসানো আছে।")
        return

    if crlf:
        new_main = new_main.replace("\r\n", "\n").replace("\n", "\r\n")

    shutil.copyfile(models_p, models_p + ".bak")
    shutil.copyfile(main_p, main_p + ".bak")
    write(models_p, new_models)
    write(main_p, new_main)
    try:
        py_compile.compile(models_p, doraise=True)
        py_compile.compile(main_p, doraise=True)
    except py_compile.PyCompileError as e:
        shutil.copyfile(models_p + ".bak", models_p)
        shutil.copyfile(main_p + ".bak", main_p)
        print("[ত্রুটি] বদলের পর সিনট্যাক্স এরর এসেছে, সব আগের অবস্থায় ফিরিয়ে দিয়েছি:")
        print(e)
        sys.exit(1)

    print("সফল! যা যা হলো:")
    for d in done:
        print("  -", d)
    print("ব্যাকআপ: models.py.bak, main.py.bak")
    print("এখন ব্যাকএন্ড আবার চালু করুন (--reload থাকলে নিজেই হবে)।")


if __name__ == "__main__":
    main()
