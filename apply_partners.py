# -*- coding: utf-8 -*-
"""
পার্টনার হিসাব + কাস্টমারের নতুন ঘর (পিতার নাম, রেফারেন্স, তারিখ) + রানারের পাওনা গাড়ীর সারাংশ:
ব্যাকএন্ডের বদল নিজে থেকে বসায়।

ব্যবহার (PowerShell-এ, backend ফোল্ডারে ঢুকে, venv চালু করে):
    python apply_partners.py
অথবা: python apply_partners.py D:\\apps\\showroom-erp\\backend
কিছু বদলানোর আগে models.py.bak ও main.py.bak নামে ব্যাকআপ রাখে।
কোনো জায়গা মিলাতে না পারলে কিছুই বদলায় না।
"""
import os
import re
import shutil
import sys
import py_compile

MODEL_CODE = '''

# ---------------------------------------------------------------
# পার্টনারের আলাদা হিসাব: রানারকে কে কত অগ্রিম দিয়েছেন, কে কত গাড়ী বিক্রি করেছেন
# ---------------------------------------------------------------
class Partner(Base):
    __tablename__ = "partners"
    id = Column(Integer, primary_key=True)
    name = Column(String(150), nullable=False)
    phone = Column(String(30))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class PartnerAdvance(Base):
    __tablename__ = "partner_advances"
    id = Column(Integer, primary_key=True)
    partner_id = Column(Integer, ForeignKey("partners.id"), nullable=False)
    supplier_id = Column(Integer, ForeignKey("parties.id"), nullable=False)  # রানার
    amount = Column(Integer, nullable=False)
    adv_date = Column(Date, nullable=False)
    mode = Column(String(10), default="cash")
    note = Column(String(255))
    voucher_id = Column(Integer, ForeignKey("vouchers.id"), nullable=True)
    created_by = Column(String(50))
    created_at = Column(DateTime, default=datetime.utcnow)


# নতুন ঘর (আগের টেবিলে যোগ; ডাটাবেসে main.py নিজে কলাম বসিয়ে নেয়)
Party.father_name = Column(String(150))      # পিতার নাম
Party.reference = Column(String(100))        # রেফারেন্স
Party.entry_date = Column(Date)              # তারিখ
Unit.sold_by_partner_id = Column(Integer, nullable=True)   # কোন পার্টনার বিক্রি করেছেন
Unit.sale_ref = Column(String(100))          # বিক্রয়ের রেফারেন্স
'''

MIGRATION_CODE = '''

def _ensure_new_columns():
    """আগের টেবিলে নতুন কলাম না থাকলে বসিয়ে নেয় (একবারই কাজ করে)"""
    from sqlalchemy import inspect as _inspect
    wanted = [
        ("parties", "father_name", "VARCHAR(150)"),
        ("parties", "reference", "VARCHAR(100)"),
        ("parties", "entry_date", "DATE"),
        ("units", "sold_by_partner_id", "INTEGER"),
        ("units", "sale_ref", "VARCHAR(100)"),
    ]
    for table, col, typ in wanted:
        try:
            have = {c["name"] for c in _inspect(engine).get_columns(table)}
            if col not in have:
                with engine.begin() as conn:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {col} {typ}"))
        except Exception as e:
            logging.warning("কলাম যোগ করা যায়নি %s.%s: %s", table, col, e)


_ensure_new_columns()
'''

MAIN_CODE = '''


# ---------------------------------------------------------------
# পার্টনারের হিসাব
# দুই পার্টনার আলাদাভাবে রানারকে অগ্রিম দেন। যে পার্টনার গাড়ী বিক্রি করেন, বিক্রয়মূল্য তার হিসাব থেকে বাদ যায়।
# ব্যালান্স = মোট অগ্রিম জমা − নিজের বিক্রি গাড়ীর বিক্রয়মূল্য
# ---------------------------------------------------------------
def _partner_admin(user):
    role_name = (user.role.name if getattr(user, "role", None) else "") or ""
    if role_name.strip().lower() != "admin":
        raise HTTPException(status_code=403, detail="শুধু অ্যাডমিন পার্টনারের হিসাব দেখতে ও বদলাতে পারবেন")


class PartnerCreate(BaseModel):
    name: str
    phone: str | None = None


class PartnerAdvanceCreate(BaseModel):
    supplier_id: int
    amount: int
    adv_date: date | None = None
    payment_mode: str = "cash"
    note: str | None = None


def _partner_totals(db: Session):
    deposits = {
        pid: int(s)
        for pid, s in db.query(PartnerAdvance.partner_id, func.coalesce(func.sum(PartnerAdvance.amount), 0))
        .group_by(PartnerAdvance.partner_id).all()
    }
    sold = {}
    rows = (
        db.query(Unit.sold_by_partner_id, func.count(Unit.id), func.coalesce(func.sum(Unit.sold_price), 0))
        .filter(Unit.sold_by_partner_id.isnot(None), Unit.status == "sold")
        .group_by(Unit.sold_by_partner_id).all()
    )
    for pid, n, v in rows:
        sold[pid] = (int(n), int(v))
    return deposits, sold


def _partner_dict(p, deposits, sold):
    dep = deposits.get(p.id, 0)
    n, val = sold.get(p.id, (0, 0))
    return {
        "id": p.id,
        "name": p.name,
        "phone": p.phone,
        "deposited": dep,
        "units_sold": n,
        "sold_value": val,
        "balance": dep - val,
    }


@app.get("/partners")
def list_partners(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    deposits, sold = _partner_totals(db)
    rows = db.query(Partner).filter(Partner.is_active.isnot(False)).order_by(Partner.id).all()
    return [_partner_dict(p, deposits, sold) for p in rows]


@app.post("/partners")
def create_partner(payload: PartnerCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    _partner_admin(current_user)
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="নাম লিখুন")
    p = Partner(name=name, phone=(payload.phone or "").strip() or None)
    db.add(p)
    db.commit()
    db.refresh(p)
    return _partner_dict(p, {}, {})


@app.get("/partners/{partner_id}")
def get_partner(partner_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    _partner_admin(current_user)
    p = db.query(Partner).filter(Partner.id == partner_id).first()
    if not p:
        raise HTTPException(status_code=404, detail="পার্টনার পাওয়া যায়নি")
    deposits, sold = _partner_totals(db)
    data = _partner_dict(p, deposits, sold)
    suppliers = {s.id: s.name for s in db.query(Party).filter(Party.party_type == "supplier").all()}
    local = timedelta(hours=6)

    entries = []
    for a in db.query(PartnerAdvance).filter(PartnerAdvance.partner_id == partner_id).all():
        entries.append({
            "type": "deposit",
            "date": a.adv_date.isoformat() if a.adv_date else None,
            "amount": a.amount,
            "text": f"অগ্রিম জমা: {suppliers.get(a.supplier_id, '-')} ({'নগদ' if a.mode == 'cash' else 'ব্যাংক'})"
                    + (f" — {a.note}" if a.note else ""),
        })
    units = (
        db.query(Unit)
        .filter(Unit.sold_by_partner_id == partner_id, Unit.status == "sold")
        .all()
    )
    for u in units:
        cust = db.query(Party).filter(Party.id == u.customer_id).first() if u.customer_id else None
        model = u.product.model_name if u.product else ""
        entries.append({
            "type": "sale",
            "date": (u.sold_date + local).strftime("%Y-%m-%d") if u.sold_date else None,
            "amount": u.sold_price or 0,
            "text": f"গাড়ী বিক্রি: {model} {u.chassis_no}" + (f" → {cust.name}" if cust else ""),
        })
    entries.sort(key=lambda e: e["date"] or "", reverse=True)
    data["entries"] = entries
    return data


@app.post("/partners/{partner_id}/advances")
def add_partner_advance(partner_id: int, payload: PartnerAdvanceCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """পার্টনারের পক্ষ থেকে রানারকে অগ্রিম। টাকা ক্যাশ/ব্যাংক থেকে বেরোয় (আগের অগ্রিমের নিয়মেই) এবং পার্টনারের খাতায় জমা হয়।"""
    _partner_admin(current_user)
    partner = db.query(Partner).filter(Partner.id == partner_id).first()
    if not partner:
        raise HTTPException(status_code=404, detail="পার্টনার পাওয়া যায়নি")
    req = SupplierAdvanceRequest(
        supplier_id=payload.supplier_id,
        amount=payload.amount,
        payment_mode=payload.payment_mode,
        narration=(payload.note or "").strip() or f"{partner.name}-এর পক্ষ থেকে রানারকে অগ্রিম",
    )
    res = pay_supplier_advance(req, db, current_user)  # হিসাবের এন্ট্রি, ভুল হলে এখানেই এরর
    adv = PartnerAdvance(
        partner_id=partner_id,
        supplier_id=payload.supplier_id,
        amount=payload.amount,
        adv_date=payload.adv_date or date.today(),
        mode=payload.payment_mode,
        note=(payload.note or "").strip() or None,
        voucher_id=res.get("voucher_id"),
        created_by=current_user.username,
    )
    db.add(adv)
    db.commit()
    return {"ok": True, "voucher_id": res.get("voucher_id")}


@app.get("/runner-summary")
def runner_summary(supplier_id: int | None = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """রানার (সাপ্লায়ার) থেকে কত গাড়ী অর্ডার, কত এসেছে, কত পাওনা। মাস ধরে ও গত ১৪ দিনের ডেলিভারিসহ।"""
    bid = scope_branch(current_user)
    q = db.query(SupplierOrder).filter(SupplierOrder.status != "cancelled")
    if bid:
        q = q.filter(SupplierOrder.branch_id == bid)
    if supplier_id:
        q = q.filter(SupplierOrder.supplier_id == supplier_id)
    orders = q.all()
    ids = [o.id for o in orders]
    units = db.query(Unit).filter(Unit.supplier_order_id.in_(ids)).all() if ids else []

    got = {}
    for u in units:
        got[u.supplier_order_id] = got.get(u.supplier_order_id, 0) + 1

    names = {p.id: p.name for p in db.query(Party).filter(Party.party_type == "supplier").all()}
    per = {}
    monthly = {}
    for o in orders:
        r = got.get(o.id, 0)
        s = per.setdefault(o.supplier_id, {"supplier_id": o.supplier_id, "supplier_name": names.get(o.supplier_id),
                                          "ordered": 0, "received": 0, "pending": 0})
        s["ordered"] += o.qty
        s["received"] += min(r, o.qty) if o.status == "completed" else r
        if o.status == "open":
            s["pending"] += max(o.qty - r, 0)
        m = (o.order_date.strftime("%Y-%m") if o.order_date else "-")
        monthly.setdefault(m, {"month": m, "ordered": 0, "received": 0})["ordered"] += o.qty

    local = timedelta(hours=6)
    recent = {}
    today = (datetime.utcnow() + local).date()
    for u in units:
        if not u.purchase_date:
            continue
        d = (u.purchase_date + local)
        m = d.strftime("%Y-%m")
        monthly.setdefault(m, {"month": m, "ordered": 0, "received": 0})["received"] += 1
        if (today - d.date()).days <= 14:
            recent[d.strftime("%Y-%m-%d")] = recent.get(d.strftime("%Y-%m-%d"), 0) + 1

    return {
        "suppliers": sorted(per.values(), key=lambda x: -x["pending"]),
        "monthly": sorted(monthly.values(), key=lambda x: x["month"], reverse=True),
        "recent_days": [{"date": k, "count": v} for k, v in sorted(recent.items(), reverse=True)],
    }
'''


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)


def once(s, anchor, label):
    if s.count(anchor) != 1:
        print(f"[ত্রুটি] main.py-তে '{label}' ঠিক একবার পাওয়া উচিত ছিল, পাওয়া গেছে {s.count(anchor)} বার। কিছু বদলানো হয়নি।")
        print("  খুঁজছিলাম:", anchor.strip()[:90])
        sys.exit(1)


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    models_p = os.path.join(folder, "models.py")
    main_p = os.path.join(folder, "main.py")
    for p in (models_p, main_p):
        if not os.path.isfile(p):
            print("[ত্রুটি] ফাইল পাওয়া যায়নি:", p)
            sys.exit(1)

    models_s = read(models_p)
    main_s = read(main_p).replace("\r\n", "\n")
    new_models, new_main = models_s, main_s
    done = []

    # ---- যাচাই (কিছু বদলানোর আগে) ----
    already = "class Partner(" in models_s and "def list_partners" in main_s
    m = re.search(r"from models import \((.*?)\)", main_s, re.S)
    if not m:
        print("[ত্রুটি] main.py-তে 'from models import ( ... )' পাওয়া যায়নি।")
        sys.exit(1)
    head = main_s.split("app = FastAPI")[0]
    for needed in ("func", "date", "timedelta", "datetime", "text"):
        if re.search(r"\b%s\b" % needed, head) is None:
            print(f"[ত্রুটি] main.py-তে '{needed}' ইম্পোর্ট পাওয়া যায়নি।")
            sys.exit(1)
    for needed in ("class SupplierAdvanceRequest", "def pay_supplier_advance", "class UnitSellRequest"):
        if needed not in main_s:
            print(f"[ত্রুটি] main.py-তে '{needed}' পাওয়া যায়নি।")
            sys.exit(1)

    A_CREATE = "Base.metadata.create_all(bind=engine)\n"
    A_PAID = "    paid_amount: int | None = None  # বাকিতে বিক্রয়ে এখন যত টাকা জমা নেওয়া হচ্ছে\n"
    A_CUST = "    unit.customer_id = payload.customer_id\n"
    if "_ensure_new_columns" not in main_s:
        once(main_s, A_CREATE, "Base.metadata.create_all(bind=engine)")
    if "partner_id: int | None" not in main_s:
        once(main_s, A_PAID, "paid_amount ... জমা নেওয়া হচ্ছে (UnitSellRequest)")
    if "sold_by_partner_id" not in main_s:
        once(main_s, A_CUST, "unit.customer_id = payload.customer_id (sell_unit)")

    # ---- বদল ----
    if "class Partner(" not in models_s:
        if "Date" not in models_s:
            print("[ত্রুটি] models.py-তে Date ইম্পোর্ট নেই।")
            sys.exit(1)
        new_models = models_s.rstrip() + "\n" + MODEL_CODE
        done.append("models.py: পার্টনার টেবিল ও নতুন কলাম যোগ হলো")

    body = m.group(1)
    missing = [n for n in ("Partner", "PartnerAdvance") if not re.search(r"\b%s\b" % n, body)]
    if missing:
        b = body.rstrip()
        if not b.endswith(","):
            b += ","
        for n in missing:
            b += "\n    %s," % n
        b += "\n"
        new_main = new_main[: m.start(1)] + b + new_main[m.end(1):]
        done.append("main.py: ইম্পোর্ট যোগ হলো: " + ", ".join(missing))

    if "_ensure_new_columns" not in new_main:
        new_main = new_main.replace(A_CREATE, A_CREATE + MIGRATION_CODE, 1)
        done.append("main.py: নতুন কলাম নিজে বসানোর ব্যবস্থা")

    if "partner_id: int | None" not in new_main:
        new_main = new_main.replace(A_PAID, A_PAID + "    partner_id: int | None = None   # কোন পার্টনারের বিক্রয় (তার হিসাব থেকে বাদ যাবে)\n", 1)
        done.append("main.py: বিক্রয়ের অনুরোধে partner_id")

    if "sold_by_partner_id" not in new_main:
        add = (
            "    if payload.partner_id:\n"
            "        if not db.query(Partner).filter(Partner.id == payload.partner_id).first():\n"
            "            raise HTTPException(status_code=404, detail=\"পার্টনার পাওয়া যায়নি\")\n"
            "    unit.sold_by_partner_id = payload.partner_id or None\n"
        )
        new_main = new_main.replace(A_CUST, A_CUST + add, 1)
        done.append("main.py: বিক্রির সময় পার্টনার সংরক্ষণ")

    if "def list_partners" not in new_main:
        new_main = new_main.rstrip() + "\n" + MAIN_CODE
        done.append("main.py: পার্টনার ও রানার-সারাংশের এন্ডপয়েন্টগুলো যোগ হলো")

    if not done:
        print("কিছু করার নেই, সবই আগে থেকে বসানো আছে।")
        return

    original_main = read(main_p)
    crlf = "\r\n" in original_main
    if crlf:
        new_main = new_main.replace("\n", "\r\n")

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
    print("এখন ব্যাকএন্ড আবার চালু করুন। প্রথমবার চালুর সময় ডাটাবেসে নতুন কলাম নিজে বসবে।")


if __name__ == "__main__":
    main()
