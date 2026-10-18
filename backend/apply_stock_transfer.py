# -*- coding: utf-8 -*-
"""
স্টক ট্রান্সফারের ব্যাকএন্ড বদল নিজে থেকে বসায়।
ব্যবহার (PowerShell-এ, backend ফোল্ডারে ঢুকে):
    python apply_stock_transfer.py
অথবা অন্য ফোল্ডার থেকে:
    python apply_stock_transfer.py D:\\apps\\showroom-erp\\backend
কিছু বদলানোর আগে models.py.bak ও main.py.bak নামে ব্যাকআপ রাখে।
"""
import os
import re
import shutil
import sys
import py_compile

MODEL_CODE = '''

# ---------------------------------------------------------------
# এক শোরুম/গোডাউন থেকে আরেক শোরুম/গোডাউনে গাড়ী পাঠানোর ইতিহাস
# ---------------------------------------------------------------
class StockTransfer(Base):
    __tablename__ = "stock_transfers"
    id = Column(Integer, primary_key=True)
    batch_no = Column(Integer, nullable=False)  # একসাথে পাঠানো গাড়ীগুলোর একই নম্বর
    unit_id = Column(Integer, ForeignKey("units.id"), nullable=False)
    from_warehouse_id = Column(Integer, ForeignKey("warehouses.id"), nullable=True)
    to_warehouse_id = Column(Integer, ForeignKey("warehouses.id"), nullable=False)
    from_branch_id = Column(Integer, ForeignKey("branches.id"), nullable=True)
    to_branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    transfer_date = Column(DateTime, default=datetime.utcnow)
    by_user = Column(String(50))
    note = Column(String(255))
'''

MAIN_CODE = '''


# ---------------------------------------------------------------
# স্টক ট্রান্সফার: এক শোরুম থেকে অন্য শোরুমে গাড়ী পাঠানো
# গাড়ীর গোডাউন বদলে গেলে বিক্রয় ও হিসাব নিজে থেকে নতুন শোরুমে যায়।
# ---------------------------------------------------------------
class UnitTransferRequest(BaseModel):
    unit_ids: list[int]
    to_warehouse_id: int
    note: str | None = None


@app.get("/transfer-targets")
def transfer_targets(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """গাড়ী পাঠানোর গন্তব্য: সব শোরুমের সব গোডাউন"""
    branch_names = {b.id: b.name for b in db.query(Branch).all()}
    rows = db.query(Warehouse).order_by(Warehouse.branch_id, Warehouse.id).all()
    return [
        {
            "id": w.id,
            "name": w.name,
            "branch_id": w.branch_id,
            "branch_name": branch_names.get(w.branch_id),
        }
        for w in rows
        if w.is_active is not False
    ]


@app.post("/units/transfer")
def transfer_units(payload: UnitTransferRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    ids = list(dict.fromkeys(payload.unit_ids))
    if not ids:
        raise HTTPException(status_code=400, detail="অন্তত একটা গাড়ী বেছে নিন")

    dest = db.query(Warehouse).filter(Warehouse.id == payload.to_warehouse_id).first()
    if not dest:
        raise HTTPException(status_code=404, detail="গন্তব্য গোডাউন পাওয়া যায়নি")

    bid = scope_branch(current_user)
    units = db.query(Unit).filter(Unit.id.in_(ids)).all()
    if len(units) != len(ids):
        raise HTTPException(status_code=404, detail="কিছু গাড়ী পাওয়া যায়নি")

    for u in units:
        src = u.warehouse
        if u.status != "in_stock":
            raise HTTPException(status_code=400, detail=f"{u.chassis_no} এখন স্টকে নেই (বিক্রি হয়ে গেছে)")
        if bid and (not src or src.branch_id != bid):
            raise HTTPException(status_code=400, detail=f"{u.chassis_no} অন্য শোরুমের গাড়ী")
        if u.warehouse_id == dest.id:
            raise HTTPException(status_code=400, detail=f"{u.chassis_no} আগে থেকেই এই গোডাউনে আছে")

    batch_no = (db.query(func.max(StockTransfer.batch_no)).scalar() or 0) + 1
    note = (payload.note or "").strip() or None
    for u in units:
        src = u.warehouse
        db.add(StockTransfer(
            batch_no=batch_no,
            unit_id=u.id,
            from_warehouse_id=u.warehouse_id,
            to_warehouse_id=dest.id,
            from_branch_id=src.branch_id if src else None,
            to_branch_id=dest.branch_id,
            by_user=current_user.username,
            note=note,
        ))
        u.warehouse_id = dest.id
    db.commit()
    return {"batch_no": batch_no, "count": len(units), "to_warehouse": dest.name}


@app.get("/stock-transfers")
def list_stock_transfers(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    q = db.query(StockTransfer)
    if bid:
        q = q.filter(or_(StockTransfer.from_branch_id == bid, StockTransfer.to_branch_id == bid))
    rows = q.order_by(StockTransfer.id.desc()).limit(300).all()
    if not rows:
        return []

    units = {u.id: u for u in db.query(Unit).filter(Unit.id.in_([r.unit_id for r in rows])).all()}
    warehouses = {w.id: w for w in db.query(Warehouse).all()}
    branch_names = {b.id: b.name for b in db.query(Branch).all()}
    local = timedelta(hours=6)  # ডাটাবেসে সময় UTC, বাংলাদেশ = UTC+6

    result = []
    for r in rows:
        u = units.get(r.unit_id)
        fw = warehouses.get(r.from_warehouse_id)
        tw = warehouses.get(r.to_warehouse_id)
        result.append({
            "id": r.id,
            "batch_no": r.batch_no,
            "unit_id": r.unit_id,
            "chassis_no": u.chassis_no if u else None,
            "engine_no": u.engine_no if u else None,
            "model": u.product.model_name if u and u.product else None,
            "brand": u.product.brand.name if u and u.product and u.product.brand else None,
            "color": u.color if u else None,
            "from_branch": branch_names.get(r.from_branch_id),
            "from_warehouse": fw.name if fw else None,
            "to_branch": branch_names.get(r.to_branch_id),
            "to_warehouse": tw.name if tw else None,
            "date": (r.transfer_date + local).strftime("%Y-%m-%d %H:%M") if r.transfer_date else None,
            "by_user": r.by_user,
            "note": r.note,
        })
    return result
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

    # --- যাচাই (কিছু বদলানোর আগে) ---
    m = re.search(r"from models import \((.*?)\)", main_s, re.S)
    if not m:
        print("[ত্রুটি] main.py-তে 'from models import ( ... )' অংশ পাওয়া যায়নি। কিছু বদলানো হয়নি।")
        sys.exit(1)
    for needed in ("func", "or_", "timedelta"):
        if needed not in main_s.split("app = FastAPI")[0]:
            print(f"[ত্রুটি] main.py-তে '{needed}' ইম্পোর্ট পাওয়া যায়নি। কিছু বদলানো হয়নি।")
            sys.exit(1)

    new_models = models_s
    new_main = main_s
    done = []

    if "class StockTransfer" not in models_s:
        new_models = models_s.rstrip() + "\n" + MODEL_CODE
        done.append("models.py: StockTransfer টেবিল যোগ হলো")
    else:
        print("models.py-তে StockTransfer আগেই আছে, বাদ দিলাম")

    if "StockTransfer" not in m.group(1):
        body = m.group(1).rstrip()
        if not body.endswith(","):
            body += ","
        body += "\n    StockTransfer,\n"
        new_main = new_main[: m.start(1)] + body + new_main[m.end(1):]
        done.append("main.py: StockTransfer ইম্পোর্ট যোগ হলো")

    if "def transfer_units" not in new_main:
        new_main = new_main.rstrip() + "\n" + MAIN_CODE
        done.append("main.py: ট্রান্সফারের তিনটা এন্ডপয়েন্ট যোগ হলো")
    else:
        print("main.py-তে ট্রান্সফারের কোড আগেই আছে, বাদ দিলাম")

    if not done:
        print("কিছু করার নেই, সবই আগে থেকে বসানো আছে।")
        return

    if crlf:
        new_main = new_main.replace("\r\n", "\n").replace("\n", "\r\n")

    # ব্যাকআপ, তারপর লেখা, তারপর সিনট্যাক্স পরীক্ষা
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
