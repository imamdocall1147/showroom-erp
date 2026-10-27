"""
রিপোর্ট ডেটা: GET /report-data/{key}

Flutter অ্যাপের "রিপোর্ট" মেনু এই এন্ডপয়েন্ট ডাকে। উত্তরের ফরম্যাট:
{
  "columns": [{"key": "...", "label": "...", "type": "text|number|money|percent|date"}],
  "rows":    [{...}],
  "totals":  {"<column key>": <যোগফল>}
}

শোরুম: টোকেনে থাকা সক্রিয় শোরুম (current_user.active_branch_id) অনুযায়ী সব রিপোর্ট ছাঁকা হয়।
সক্রিয় শোরুম না থাকলে (সব শোরুম মোড) দুই শোরুমের যোগফল দেখায়।

main.py-তে যোগ করতে হবে (get_current_user লেখার পরে):
    from backend.report_data import build_router
    app.include_router(build_router(get_current_user))
"""
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.models import (
    Account, Area, Branch, Brand, Party, Product, SparePart, Unit, Voucher,
    VoucherEntry, Warehouse,
)

# ডাটাবেসে সময় UTC-তে জমা হয় (datetime.utcnow)। বাংলাদেশ = UTC+6।
# "আজকের" রিপোর্ট ঠিক রাখতে তারিখের সীমা ও দেখানো তারিখে এই ব্যবধান ধরা হয়।
LOCAL_OFFSET = timedelta(hours=6)

TYPE_LABEL = {
    "sale": "বিক্রয়",
    "purchase": "ক্রয়",
    "payment": "পেমেন্ট",
    "receipt": "আদায়",
    "advance": "অগ্রিম",
}
MODE_LABEL = {"cash": "নগদ", "due": "বাকি"}


# ---------------------------------------------------------------
# সাধারণ সাহায্যকারী
# ---------------------------------------------------------------
def col(key, label, type="text"):
    return {"key": key, "label": label, "type": type}


def out(columns, rows, totals=None):
    return {"columns": columns, "rows": rows, "totals": totals or {}}


def message(text):
    return out([col("msg", "বার্তা")], [{"msg": text}])


def n(v):
    return int(v or 0)


def ldate(dt):
    """UTC datetime -> বাংলাদেশের তারিখ (YYYY-MM-DD)"""
    return (dt + LOCAL_OFFSET).strftime("%Y-%m-%d") if dt else None


def has(text, needle):
    """needle ফাঁকা হলে true, নইলে text-এর ভেতরে আছে কিনা (ছোট/বড় হাতের পার্থক্য নেই)"""
    if not needle:
        return True
    return needle.lower() in (text or "").lower()


def parse_day(s, name):
    if not s:
        return None
    try:
        return datetime.strptime(s, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail=f"{name} তারিখ YYYY-MM-DD ফরম্যাটে হতে হবে")


def totals_of(rows, keys):
    return {k: sum(n(r.get(k)) for r in rows) for k in keys}


class Filters:
    def __init__(self, **kw):
        self.from_ = None
        self.to = None
        self.customer_id = None
        self.supplier_id = None
        self.product_id = None
        self.warehouse_id = None
        self.brand = None
        self.category = None
        self.payment_mode = None
        self.area = None
        self.account = None
        self.q = None
        self.days = None
        self.branch_id = None  # সক্রিয় শোরুম (None = সব শোরুম)
        for k, v in kw.items():
            setattr(self, k, v)
        self.d_from = parse_day(self.from_, "from")
        self.d_to = parse_day(self.to, "to")

    @property
    def start(self):
        """UTC সীমা (অন্তর্ভুক্ত)"""
        return self.d_from - LOCAL_OFFSET if self.d_from else None

    @property
    def end(self):
        """UTC সীমা (বাদ)"""
        return self.d_to + timedelta(days=1) - LOCAL_OFFSET if self.d_to else None

    def int_days(self, default):
        try:
            d = int(self.days) if self.days not in (None, "") else default
        except ValueError:
            d = default
        return max(d, 0)


def scope_only(f):
    """তারিখ/অন্য ফিল্টার ছাড়া, শুধু শোরুমের সীমা (এখনকার ব্যালান্সের জন্য)"""
    return Filters(branch_id=f.branch_id)


def in_range(dt, f):
    if not dt:
        return False
    if f.start and dt < f.start:
        return False
    if f.end and dt >= f.end:
        return False
    return True


class Maps:
    """ছোট টেবিলগুলো একবারে মেমোরিতে নিয়ে নেয়, যাতে প্রতি সারিতে আলাদা কোয়েরি না লাগে"""

    def __init__(self, db):
        self.parties = {x.id: x for x in db.query(Party).all()}
        self.products = {x.id: x for x in db.query(Product).all()}
        self.brands = {x.id: x for x in db.query(Brand).all()}
        self.warehouses = {x.id: x for x in db.query(Warehouse).all()}
        self.areas = {x.id: x for x in db.query(Area).all()}
        self.branches = {x.id: x for x in db.query(Branch).all()}

    def party(self, pid):
        x = self.parties.get(pid)
        return x.name if x else None

    def phone(self, pid):
        x = self.parties.get(pid)
        return x.phone if x else None

    def nid(self, pid):
        x = self.parties.get(pid)
        return getattr(x, "nid_no", None) if x else None

    def area_name(self, pid):
        x = self.parties.get(pid)
        a = self.areas.get(x.area_id) if x and x.area_id else None
        return a.name if a else None

    def model(self, prod):
        x = self.products.get(prod)
        return x.model_name if x else None

    def brand_name(self, prod):
        x = self.products.get(prod)
        b = self.brands.get(x.brand_id) if x else None
        return b.name if b else None

    def category(self, prod):
        x = self.products.get(prod)
        return x.category if x else None

    def wh(self, wid):
        x = self.warehouses.get(wid)
        return x.name if x else None

    def wh_ids(self, branch_id):
        """একটা শোরুমের সব গোডাউনের id"""
        return [w.id for w in self.warehouses.values() if w.branch_id == branch_id]

    def branch_name(self, bid):
        x = self.branches.get(bid)
        return x.name if x else None


def product_ok(f, m, product_id):
    return has(m.brand_name(product_id), f.brand) and has(m.category(product_id), f.category)


# ---------------------------------------------------------------
# শোরুম অনুযায়ী ছাঁকা
# ---------------------------------------------------------------
def scope_units(q, f, m):
    if f.branch_id:
        q = q.filter(Unit.warehouse_id.in_(m.wh_ids(f.branch_id)))
    return q


def acc_query(db, f):
    q = db.query(Account)
    if f.branch_id:
        q = q.filter(Account.branch_id == f.branch_id)
    return q


def acc_ids(db, f, name=None, types=None):
    q = acc_query(db, f)
    if name:
        q = q.filter(Account.name == name)
    if types:
        q = q.filter(Account.account_type.in_(types))
    return [a.id for a in q.all()]


def acc_label(a, f, m):
    """সব শোরুম মোডে একাউন্টের নামের সাথে শোরুমের নামও দেখায়"""
    if not f.branch_id and a.branch_id and m.branch_name(a.branch_id):
        return f"{a.name} — {m.branch_name(a.branch_id)}"
    return a.name


def unit_vouchers(db, vtype, due_account):
    """চেসিস নম্বর -> {voucher_id, date, mode}। due_account ব্যবহার হলে mode = 'due'"""
    rows = (
        db.query(Voucher.id, Voucher.reference, Voucher.voucher_date, Account.name)
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .join(Account, Account.id == VoucherEntry.account_id)
        .filter(Voucher.voucher_type == vtype)
        .all()
    )
    result = {}
    for vid, ref, vdate, aname in rows:
        info = result.setdefault(ref, {"voucher_id": vid, "date": vdate, "mode": "cash"})
        if aname == due_account:
            info["mode"] = "due"
    return result


def party_balances(db, f, account_name, side):
    """পার্টি-ভিত্তিক ব্যালান্স। side='debit' হলে ডেবিট-ক্রেডিট, নইলে ক্রেডিট-ডেবিট"""
    ids = acc_ids(db, f, name=account_name)
    if not ids:
        return {}
    rows = (
        db.query(
            VoucherEntry.party_id,
            func.coalesce(func.sum(VoucherEntry.debit), 0),
            func.coalesce(func.sum(VoucherEntry.credit), 0),
        )
        .filter(VoucherEntry.account_id.in_(ids), VoucherEntry.party_id.isnot(None))
        .group_by(VoucherEntry.party_id)
        .all()
    )
    result = {}
    for pid, d, c in rows:
        d, c = n(d), n(c)
        result[pid] = (d - c) if side == "debit" else (c - d)
    return result


def entries_sum(db, f, *conds):
    """শর্ত মেলানো ভাউচার এন্ট্রির (মোট ডেবিট, মোট ক্রেডিট, সংখ্যা), তারিখ ও শোরুমের সীমাসহ"""
    q = (
        db.query(
            func.coalesce(func.sum(VoucherEntry.debit), 0),
            func.coalesce(func.sum(VoucherEntry.credit), 0),
            func.count(VoucherEntry.id),
        )
        .join(Voucher, Voucher.id == VoucherEntry.voucher_id)
        .join(Account, Account.id == VoucherEntry.account_id)
    )
    for c in conds:
        q = q.filter(c)
    if f.branch_id:
        q = q.filter(Account.branch_id == f.branch_id)
    if f.start:
        q = q.filter(Voucher.voucher_date >= f.start)
    if f.end:
        q = q.filter(Voucher.voucher_date < f.end)
    d, c, cnt = q.one()
    return n(d), n(c), n(cnt)


def balance_by_type(db, f, types):
    d, c, _ = entries_sum(db, scope_only(f), Account.account_type.in_(types))
    return d - c


def stock_value_now(db, f, m):
    units = scope_units(db.query(Unit).filter(Unit.status == "in_stock"), f, m).all()
    value = sum(n(u.purchase_price) for u in units)
    pq = db.query(SparePart)
    if f.branch_id:
        pq = pq.filter(SparePart.warehouse_id.in_(m.wh_ids(f.branch_id)))
    value += sum(n(p.stock_qty) * n(p.purchase_price) for p in pq.all())
    return value


# ---------------------------------------------------------------
# স্টক
# ---------------------------------------------------------------
STOCK_COLS = [
    col("chassis", "চেসিস নম্বর"),
    col("engine", "ইঞ্জিন নম্বর"),
    col("model", "মডেল"),
    col("brand", "ব্র্যান্ড"),
    col("color", "রঙ"),
    col("warehouse", "গোডাউন"),
    col("purchase_date", "ক্রয়ের তারিখ", "date"),
    col("age", "স্টকে কত দিন", "number"),
    col("price", "ক্রয় মূল্য", "money"),
]


def stock_unit_rows(db, f, m):
    q = scope_units(db.query(Unit).filter(Unit.status == "in_stock"), f, m)
    if f.warehouse_id:
        q = q.filter(Unit.warehouse_id == f.warehouse_id)
    if f.product_id:
        q = q.filter(Unit.product_id == f.product_id)
    now = datetime.utcnow()
    rows = []
    for u in q.order_by(Unit.purchase_date).all():
        if not product_ok(f, m, u.product_id):
            continue
        if f.q and f.q.lower() not in f"{u.chassis_no} {u.engine_no}".lower():
            continue
        rows.append({
            "chassis": u.chassis_no,
            "engine": u.engine_no,
            "model": m.model(u.product_id),
            "brand": m.brand_name(u.product_id),
            "category": m.category(u.product_id),
            "color": u.color,
            "warehouse": m.wh(u.warehouse_id),
            "purchase_date": ldate(u.purchase_date),
            "age": (now - u.purchase_date).days if u.purchase_date else 0,
            "price": n(u.purchase_price),
        })
    return rows


def stock_totals(rows):
    # প্রথম কলামের (চেসিস) ঘরে সংখ্যা দেখানো হয়, তাই টেবিলের নিচের সারিতে "মোট N টি বাইক" আসে
    totals = totals_of(rows, ["price"])
    totals["chassis"] = f"মোট {len(rows)} টি বাইক"
    return totals


def r_current_stock(db, f, m):
    rows = stock_unit_rows(db, f, m)
    return out(STOCK_COLS, rows, stock_totals(rows))


def r_dead_stock(db, f, m):
    days = f.int_days(90)
    rows = [r for r in stock_unit_rows(db, f, m) if r["age"] >= days]
    rows.sort(key=lambda r: -r["age"])
    return out(STOCK_COLS, rows, stock_totals(rows))


def spare_parts_for(db, f, m):
    """ফিল্টারে প্রোডাক্ট/ব্র্যান্ড/ক্যাটেগরি/সার্চ থাকলে স্পেয়ার পার্টস বাদ"""
    if f.product_id or f.brand or f.category or f.q:
        return []
    q = db.query(SparePart)
    if f.branch_id:
        q = q.filter(SparePart.warehouse_id.in_(m.wh_ids(f.branch_id)))
    if f.warehouse_id:
        q = q.filter(SparePart.warehouse_id == f.warehouse_id)
    return [p for p in q.all() if n(p.stock_qty) > 0]


def r_stock_valuation(db, f, m):
    groups = {}
    for r in stock_unit_rows(db, f, m):
        key = ("bike", r["warehouse"], r["model"])
        g = groups.setdefault(key, {
            "warehouse": r["warehouse"], "model": r["model"], "brand": r["brand"],
            "category": r["category"], "qty": 0, "value": 0,
        })
        g["qty"] += 1
        g["value"] += r["price"]
    for p in spare_parts_for(db, f, m):
        groups[("part", p.id)] = {
            "warehouse": m.wh(p.warehouse_id), "model": p.name, "brand": "—",
            "category": "স্পেয়ার পার্টস", "qty": n(p.stock_qty),
            "value": n(p.stock_qty) * n(p.purchase_price),
        }
    rows = sorted(groups.values(), key=lambda r: -r["value"])
    cols = [
        col("warehouse", "গোডাউন"), col("model", "মডেল/পার্টস"), col("brand", "ব্র্যান্ড"),
        col("category", "ক্যাটেগরি"), col("qty", "সংখ্যা", "number"), col("value", "মোট মূল্য", "money"),
    ]
    return out(cols, rows, totals_of(rows, ["qty", "value"]))


def r_warehouse_stock(db, f, m):
    data = {}

    def bucket(name):
        return data.setdefault(name, {"warehouse": name, "bikes": 0, "bike_value": 0, "parts_value": 0})

    for r in stock_unit_rows(db, f, m):
        g = bucket(r["warehouse"])
        g["bikes"] += 1
        g["bike_value"] += r["price"]
    for p in spare_parts_for(db, f, m):
        bucket(m.wh(p.warehouse_id))["parts_value"] += n(p.stock_qty) * n(p.purchase_price)
    rows = list(data.values())
    for r in rows:
        r["total_value"] = r["bike_value"] + r["parts_value"]
    rows.sort(key=lambda r: -r["total_value"])
    cols = [
        col("warehouse", "শোরুম/গোডাউন"), col("bikes", "বাইক (সংখ্যা)", "number"),
        col("bike_value", "বাইকের মূল্য", "money"), col("parts_value", "স্পেয়ার পার্টসের মূল্য", "money"),
        col("total_value", "মোট মূল্য", "money"),
    ]
    return out(cols, rows, totals_of(rows, ["bikes", "bike_value", "parts_value", "total_value"]))


def r_out_of_stock(db, f, m):
    counts = dict(
        scope_units(
            db.query(Unit.product_id, func.count(Unit.id)).filter(Unit.status == "in_stock"), f, m
        )
        .group_by(Unit.product_id)
        .all()
    )
    # প্রোডাক্টের তালিকা দুই শোরুমে এক, তাই শোরুম বাছা থাকলে শুধু সেই শোরুমে
    # আগে যে মডেলের লেনদেন হয়েছে সেগুলোই দেখানো হয়
    known = None
    if f.branch_id:
        known = {pid for (pid,) in scope_units(db.query(Unit.product_id), f, m).distinct().all()}
    rows = []
    for p in m.products.values():
        if p.is_active is False:
            continue
        if known is not None and p.id not in known:
            continue
        if f.product_id and p.id != f.product_id:
            continue
        if not product_ok(f, m, p.id):
            continue
        if counts.get(p.id, 0) == 0:
            rows.append({
                "model": p.model_name, "brand": m.brand_name(p.id),
                "category": p.category, "unit_price": p.unit_price,
            })
    cols = [col("model", "মডেল"), col("brand", "ব্র্যান্ড"), col("category", "ক্যাটেগরি"),
            col("unit_price", "তালিকা মূল্য", "money")]
    return out(cols, rows)


def movement_rows(db, f, m, default_days):
    days = f.int_days(default_days)
    since = datetime.utcnow() - timedelta(days=days)

    sq = scope_units(db.query(Unit).filter(Unit.status == "sold", Unit.sold_date >= since), f, m)
    if f.warehouse_id:
        sq = sq.filter(Unit.warehouse_id == f.warehouse_id)
    sold = {}
    for u in sq.all():
        g = sold.setdefault(u.product_id, [0, 0])
        g[0] += 1
        g[1] += n(u.sold_price)

    tq = scope_units(
        db.query(Unit.product_id, func.count(Unit.id)).filter(Unit.status == "in_stock"), f, m
    )
    if f.warehouse_id:
        tq = tq.filter(Unit.warehouse_id == f.warehouse_id)
    in_stock = dict(tq.group_by(Unit.product_id).all())

    rows = []
    for pid in set(sold) | set(in_stock):
        if f.product_id and pid != f.product_id:
            continue
        if not product_ok(f, m, pid):
            continue
        rows.append({
            "model": m.model(pid), "brand": m.brand_name(pid),
            "sold_qty": sold.get(pid, [0, 0])[0],
            "sold_amount": sold.get(pid, [0, 0])[1],
            "stock_qty": in_stock.get(pid, 0),
        })
    cols = [
        col("model", "মডেল"), col("brand", "ব্র্যান্ড"),
        col("sold_qty", f"গত {days} দিনে বিক্রি", "number"),
        col("sold_amount", "বিক্রয় মূল্য", "money"),
        col("stock_qty", "এখন স্টকে", "number"),
    ]
    return cols, rows


def r_fast_moving(db, f, m):
    cols, rows = movement_rows(db, f, m, 30)
    rows = [r for r in rows if r["sold_qty"] > 0]
    rows.sort(key=lambda r: -r["sold_qty"])
    return out(cols, rows, totals_of(rows, ["sold_qty", "sold_amount", "stock_qty"]))


def r_slow_moving(db, f, m):
    cols, rows = movement_rows(db, f, m, 60)
    rows = [r for r in rows if r["stock_qty"] > 0]
    rows.sort(key=lambda r: r["sold_qty"])
    return out(cols, rows, totals_of(rows, ["sold_qty", "sold_amount", "stock_qty"]))


def r_stock_in_out(db, f, m):
    q = scope_units(db.query(Unit), f, m)
    if f.warehouse_id:
        q = q.filter(Unit.warehouse_id == f.warehouse_id)
    if f.product_id:
        q = q.filter(Unit.product_id == f.product_id)
    events = []
    for u in q.all():
        if not product_ok(f, m, u.product_id):
            continue
        if in_range(u.purchase_date, f):
            events.append((u.purchase_date, "স্টকে এসেছে", u, m.party(u.supplier_id) or "নগদ ক্রয়", n(u.purchase_price)))
        if u.sold_date and in_range(u.sold_date, f):
            events.append((u.sold_date, "বিক্রি হয়েছে", u, m.party(u.customer_id), n(u.sold_price)))
    events.sort(key=lambda e: e[0])
    rows = [{
        "date": ldate(dt), "type": kind, "model": m.model(u.product_id),
        "brand": m.brand_name(u.product_id), "chassis": u.chassis_no,
        "warehouse": m.wh(u.warehouse_id), "party": party, "amount": amount,
    } for dt, kind, u, party, amount in events]
    cols = [
        col("date", "তারিখ", "date"), col("type", "ধরন"), col("model", "মডেল"),
        col("brand", "ব্র্যান্ড"), col("chassis", "চেসিস নম্বর"), col("warehouse", "গোডাউন"),
        col("party", "সাপ্লায়ার/কাস্টমার"), col("amount", "মূল্য", "money"),
    ]
    return out(cols, rows)


# ---------------------------------------------------------------
# বিক্রয় ও ক্রয়
# ---------------------------------------------------------------
def sales_rows(db, f, m):
    q = scope_units(db.query(Unit).filter(Unit.status == "sold", Unit.sold_date.isnot(None)), f, m)
    if f.start:
        q = q.filter(Unit.sold_date >= f.start)
    if f.end:
        q = q.filter(Unit.sold_date < f.end)
    if f.warehouse_id:
        q = q.filter(Unit.warehouse_id == f.warehouse_id)
    if f.customer_id:
        q = q.filter(Unit.customer_id == f.customer_id)
    if f.product_id:
        q = q.filter(Unit.product_id == f.product_id)

    vmap = unit_vouchers(db, "sale", "Accounts Receivable")
    rows = []
    for u in q.order_by(Unit.sold_date).all():
        if not product_ok(f, m, u.product_id):
            continue
        v = vmap.get(u.chassis_no, {})
        mode = v.get("mode")
        if f.payment_mode and mode != f.payment_mode:
            continue
        sold = n(u.sold_price)
        rows.append({
            "date": ldate(u.sold_date),
            "invoice": str(v["voucher_id"]) if v.get("voucher_id") else "-",
            "customer": m.party(u.customer_id) or "—",
            "model": m.model(u.product_id),
            "brand": m.brand_name(u.product_id),
            "category": m.category(u.product_id),
            "chassis": u.chassis_no,
            "warehouse": m.wh(u.warehouse_id),
            "payment": MODE_LABEL.get(mode, "—"),
            "sold_price": sold,
            "purchase_price": n(u.purchase_price),
            "profit": sold - n(u.purchase_price),
        })
    return rows


SALES_COLS = [
    col("date", "তারিখ", "date"), col("invoice", "ইনভয়েস নং"), col("customer", "কাস্টমার"),
    col("model", "মডেল"), col("brand", "ব্র্যান্ড"), col("chassis", "চেসিস নম্বর"),
    col("warehouse", "শোরুম/গোডাউন"), col("payment", "পেমেন্ট"),
    col("sold_price", "বিক্রয় মূল্য", "money"), col("purchase_price", "ক্রয় মূল্য", "money"),
    col("profit", "লাভ", "money"),
]
SALES_SUMS = [("sold_price", "বিক্রয় মূল্য"), ("purchase_price", "ক্রয় মূল্য"), ("profit", "লাভ")]


def grouped(rows, field, label, sums):
    g = {}
    for r in rows:
        k = r.get(field) or "—"
        x = g.setdefault(k, {"name": k, "qty": 0, **{key: 0 for key, _ in sums}})
        x["qty"] += 1
        for key, _ in sums:
            x[key] += n(r.get(key))
    first_sum = sums[0][0]
    items = sorted(g.values(), key=lambda x: -x[first_sum])
    cols = [col("name", label), col("qty", "সংখ্যা", "number")] + [col(k, l, "money") for k, l in sums]
    return out(cols, items, totals_of(items, ["qty"] + [k for k, _ in sums]))


def sales_detail(db, f, m):
    rows = sales_rows(db, f, m)
    return out(SALES_COLS, rows, totals_of(rows, ["sold_price", "purchase_price", "profit"]))


def sales_group(field, label):
    def fn(db, f, m):
        return grouped(sales_rows(db, f, m), field, label, SALES_SUMS)
    return fn


def purchase_rows(db, f, m):
    q = scope_units(db.query(Unit), f, m)
    if f.start:
        q = q.filter(Unit.purchase_date >= f.start)
    if f.end:
        q = q.filter(Unit.purchase_date < f.end)
    if f.warehouse_id:
        q = q.filter(Unit.warehouse_id == f.warehouse_id)
    if f.supplier_id:
        q = q.filter(Unit.supplier_id == f.supplier_id)
    if f.product_id:
        q = q.filter(Unit.product_id == f.product_id)

    vmap = unit_vouchers(db, "purchase", "Accounts Payable")
    rows = []
    for u in q.order_by(Unit.purchase_date).all():
        if not product_ok(f, m, u.product_id):
            continue
        v = vmap.get(u.chassis_no, {})
        mode = v.get("mode")
        if f.payment_mode and mode != f.payment_mode:
            continue
        rows.append({
            "date": ldate(u.purchase_date),
            "voucher": str(v["voucher_id"]) if v.get("voucher_id") else "-",
            "supplier": m.party(u.supplier_id) or "নগদ ক্রয়",
            "model": m.model(u.product_id),
            "brand": m.brand_name(u.product_id),
            "category": m.category(u.product_id),
            "chassis": u.chassis_no,
            "engine": u.engine_no,
            "warehouse": m.wh(u.warehouse_id),
            "payment": MODE_LABEL.get(mode, "—"),
            "price": n(u.purchase_price),
        })
    return rows


PURCHASE_COLS = [
    col("date", "তারিখ", "date"), col("voucher", "ভাউচার নং"), col("supplier", "সাপ্লায়ার"),
    col("model", "মডেল"), col("brand", "ব্র্যান্ড"), col("chassis", "চেসিস নম্বর"),
    col("engine", "ইঞ্জিন নম্বর"), col("warehouse", "গোডাউন"), col("payment", "পেমেন্ট"),
    col("price", "ক্রয় মূল্য", "money"),
]
PURCHASE_SUMS = [("price", "ক্রয় মূল্য")]


def purchase_detail(db, f, m):
    rows = purchase_rows(db, f, m)
    return out(PURCHASE_COLS, rows, totals_of(rows, ["price"]))


def purchase_group(field, label):
    def fn(db, f, m):
        return grouped(purchase_rows(db, f, m), field, label, PURCHASE_SUMS)
    return fn


# ---------------------------------------------------------------
# কাস্টমার ও বাকি
# ---------------------------------------------------------------
def r_customer_due(db, f, m):
    rows = []
    for pid, due in party_balances(db, f, "Accounts Receivable", "debit").items():
        if due == 0 or pid not in m.parties:
            continue
        if f.customer_id and pid != f.customer_id:
            continue
        if not has(m.area_name(pid), f.area):
            continue
        rows.append({"customer": m.party(pid), "phone": m.phone(pid), "nid": m.nid(pid),
                     "area": m.area_name(pid) or "—", "due": due})
    rows.sort(key=lambda r: -r["due"])
    cols = [col("customer", "কাস্টমার"), col("nid", "NID নম্বর"), col("phone", "ফোন"),
            col("area", "এলাকা"), col("due", "বাকি", "money")]
    return out(cols, rows, totals_of(rows, ["due"]))


def r_area_due(db, f, m):
    g = {}
    for pid, due in party_balances(db, f, "Accounts Receivable", "debit").items():
        if due == 0 or pid not in m.parties:
            continue
        area = m.area_name(pid) or "এলাকা ঠিক করা নেই"
        if not has(area, f.area):
            continue
        x = g.setdefault(area, {"area": area, "customers": 0, "due": 0})
        x["customers"] += 1
        x["due"] += due
    rows = sorted(g.values(), key=lambda r: -r["due"])
    cols = [col("area", "এলাকা"), col("customers", "বাকি আছে এমন কাস্টমার", "number"),
            col("due", "মোট বাকি", "money")]
    return out(cols, rows, totals_of(rows, ["customers", "due"]))


def r_payable(db, f, m):
    rows = []
    for pid, due in party_balances(db, f, "Accounts Payable", "credit").items():
        if due == 0 or pid not in m.parties:
            continue
        if f.supplier_id and pid != f.supplier_id:
            continue
        rows.append({"supplier": m.party(pid), "phone": m.phone(pid),
                     "area": m.area_name(pid) or "—", "due": due})
    rows.sort(key=lambda r: -r["due"])
    cols = [col("supplier", "সাপ্লায়ার"), col("phone", "ফোন"), col("area", "এলাকা"),
            col("due", "পাওনা", "money")]
    return out(cols, rows, totals_of(rows, ["due"]))


def ledger(db, f, account_ids, party_id, debit_label, credit_label, with_voucher_type=True):
    """একটা (বা কয়েকটা) একাউন্টের খতিয়ান, আগের জের ও চলতি ব্যালান্সসহ"""
    q = (
        db.query(Voucher.voucher_date, Voucher.id, Voucher.voucher_type, Voucher.narration,
                 VoucherEntry.debit, VoucherEntry.credit)
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .filter(VoucherEntry.account_id.in_(account_ids))
    )
    if party_id:
        q = q.filter(VoucherEntry.party_id == party_id)
    q = q.order_by(Voucher.voucher_date, VoucherEntry.id)

    opening = 0
    inside = []
    for vdate, vid, vtype, narr, d, c in q.all():
        d, c = n(d), n(c)
        if f.start and vdate < f.start:
            opening += d - c
        elif f.end and vdate >= f.end:
            continue
        else:
            inside.append((vdate, vid, vtype, narr, d, c))

    rows = []
    if f.d_from:
        rows.append({"date": f.d_from.strftime("%Y-%m-%d"), "voucher": "", "type": "আগের জের",
                     "narration": "", "debit": None, "credit": None, "balance": opening})
    balance = opening
    for vdate, vid, vtype, narr, d, c in inside:
        balance += d - c
        rows.append({"date": ldate(vdate), "voucher": str(vid), "type": TYPE_LABEL.get(vtype, vtype),
                     "narration": narr or "", "debit": d, "credit": c, "balance": balance})
    cols = [
        col("date", "তারিখ", "date"), col("voucher", "ভাউচার নং"), col("type", "ধরন"),
        col("narration", "বিবরণ"), col("debit", debit_label, "money"),
        col("credit", credit_label, "money"), col("balance", "ব্যালান্স", "money"),
    ]
    totals = {"debit": sum(r[4] for r in inside), "credit": sum(r[5] for r in inside)}
    return out(cols, rows, totals)


def r_customer_ledger(db, f, m):
    if not f.customer_id:
        return message("কাস্টমার বেছে নিন")
    ids = acc_ids(db, f, name="Accounts Receivable")
    if not ids:
        return message("এখনো কোনো বাকির লেনদেন নেই")
    return ledger(db, f, ids, f.customer_id, "বাকি বেড়েছে", "জমা")


def r_customer_payments(db, f, m):
    """কোন কাস্টমার কত তারিখে কত টাকা দিয়েছেন — তারিখ অনুযায়ী, প্রতিবারের পর কত বাকি থাকল সহ"""
    ids = acc_ids(db, f, name="Accounts Receivable")
    if not ids:
        return message("এখনো কোনো বাকির লেনদেন নেই")
    q = (
        db.query(Voucher.voucher_date, Voucher.id, Voucher.voucher_type, Voucher.narration,
                 VoucherEntry.party_id, VoucherEntry.debit, VoucherEntry.credit)
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .filter(VoucherEntry.account_id.in_(ids), VoucherEntry.party_id.isnot(None))
        .order_by(Voucher.voucher_date, VoucherEntry.id)
    )

    # সব লেনদেন তারিখ ধরে ধরে চালিয়ে প্রত্যেক কাস্টমারের চলতি বাকি ও মোট জমা হিসাব রাখা হয়
    balance = {}
    paid_total = {}
    found = []
    for vdate, vid, vtype, narr, pid, d, c in q.all():
        d, c = n(d), n(c)
        balance[pid] = balance.get(pid, 0) + d - c
        if c > 0 and vtype == "receipt":
            paid_total[pid] = paid_total.get(pid, 0) + c
            if f.customer_id and pid != f.customer_id:
                continue
            if not in_range(vdate, f):
                continue
            found.append((vdate, vid, narr, pid, c, balance[pid], paid_total[pid]))

    # কোন মাধ্যমে (ক্যাশ/ব্যাংক) টাকা এসেছে
    methods = {}
    vids = [r[1] for r in found]
    if vids:
        for vid, aname in (
            db.query(VoucherEntry.voucher_id, Account.name)
            .join(Account, Account.id == VoucherEntry.account_id)
            .filter(VoucherEntry.voucher_id.in_(vids), VoucherEntry.debit > 0)
            .all()
        ):
            methods[vid] = aname

    rows = [{
        "date": ldate(vdate), "voucher": str(vid), "customer": m.party(pid) or "—",
        "phone": m.phone(pid), "method": methods.get(vid, "—"), "amount": credit,
        "balance_after": bal, "paid_total": paid, "narration": narr or "",
    } for vdate, vid, narr, pid, credit, bal, paid in found]
    cols = [
        col("date", "তারিখ", "date"), col("customer", "কাস্টমার"), col("phone", "ফোন"),
        col("amount", "জমা দিয়েছেন", "money"), col("balance_after", "এরপর বাকি", "money"),
        col("paid_total", "এ পর্যন্ত মোট জমা", "money"), col("method", "মাধ্যম"),
        col("voucher", "ভাউচার নং"), col("narration", "বিবরণ"),
    ]
    return out(cols, rows, totals_of(rows, ["amount"]))


def r_overdue(db, f, m):
    """FIFO: জমার টাকা সবচেয়ে পুরনো বাকি থেকে কাটা হয়; যে বাকি এখনো আছে তার বয়সই 'ওভারডিউ'"""
    days = f.int_days(30)
    ids = acc_ids(db, f, name="Accounts Receivable")
    if not ids:
        return out([], [])
    entries = {}
    q = (
        db.query(VoucherEntry.party_id, Voucher.voucher_date, VoucherEntry.debit, VoucherEntry.credit)
        .join(Voucher, Voucher.id == VoucherEntry.voucher_id)
        .filter(VoucherEntry.account_id.in_(ids), VoucherEntry.party_id.isnot(None))
        .order_by(Voucher.voucher_date, VoucherEntry.id)
    )
    for pid, vdate, d, c in q.all():
        entries.setdefault(pid, []).append((vdate, n(d), n(c)))

    now = datetime.utcnow()
    rows = []
    for pid, items in entries.items():
        if f.customer_id and pid != f.customer_id:
            continue
        credit_left = sum(c for _, _, c in items)
        due = sum(d for _, d, _ in items) - credit_left
        if due <= 0:
            continue
        oldest = None
        for vdate, d, _ in items:
            if d <= 0:
                continue
            if credit_left >= d:
                credit_left -= d
            else:
                oldest = vdate
                break
        if oldest is None:
            continue
        age = (now - oldest).days
        if age < days:
            continue
        rows.append({
            "customer": m.party(pid), "phone": m.phone(pid), "nid": m.nid(pid),
            "area": m.area_name(pid) or "—",
            "due": due, "oldest": ldate(oldest), "overdue_days": age,
        })
    rows.sort(key=lambda r: -r["overdue_days"])
    cols = [col("customer", "কাস্টমার"), col("nid", "NID নম্বর"), col("phone", "ফোন"),
            col("area", "এলাকা"),
            col("due", "বাকি", "money"), col("oldest", "সবচেয়ে পুরনো বাকির তারিখ", "date"),
            col("overdue_days", "কত দিন বাকি", "number")]
    return out(cols, rows, totals_of(rows, ["due"]))


def r_customer_summary(db, f, m):
    sales = {}
    for r in sales_rows(db, f, m):
        x = sales.setdefault(r["customer"], {"qty": 0, "amount": 0})
        x["qty"] += 1
        x["amount"] += r["sold_price"]
    dues = party_balances(db, f, "Accounts Receivable", "debit")
    rows = []
    names = set(sales)
    for pid, due in dues.items():
        if due != 0 and pid in m.parties:
            if f.customer_id and pid != f.customer_id:
                continue
            names.add(m.party(pid))
    by_name = {p.name: p.id for p in m.parties.values()}
    for name in names:
        pid = by_name.get(name)
        if f.customer_id and pid != f.customer_id:
            continue
        s = sales.get(name, {"qty": 0, "amount": 0})
        rows.append({
            "customer": name, "phone": m.phone(pid), "nid": m.nid(pid),
            "area": m.area_name(pid) or "—",
            "qty": s["qty"], "amount": s["amount"], "due": dues.get(pid, 0),
        })
    rows.sort(key=lambda r: -r["amount"])
    cols = [col("customer", "কাস্টমার"), col("nid", "NID নম্বর"), col("phone", "ফোন"),
            col("area", "এলাকা"),
            col("qty", "বাইক কিনেছেন", "number"), col("amount", "মোট বিক্রয়", "money"),
            col("due", "এখনকার বাকি", "money")]
    return out(cols, rows, totals_of(rows, ["qty", "amount", "due"]))


# ---------------------------------------------------------------
# একাউন্টস
# ---------------------------------------------------------------
def r_cash_book(db, f, m):
    ids = acc_ids(db, f, name="Cash")
    if not ids:
        return message("ক্যাশ একাউন্টে এখনো কোনো লেনদেন নেই")
    return ledger(db, f, ids, None, "জমা (ক্যাশে এসেছে)", "খরচ (ক্যাশ থেকে গেছে)")


def r_bank_transactions(db, f, m):
    accs = [a for a in acc_query(db, f).filter(Account.account_type == "bank").all()
            if has(a.name, f.account)]
    if not accs:
        return message("ব্যাংক একাউন্টে এখনো কোনো লেনদেন নেই")
    return ledger(db, f, [a.id for a in accs], None, "জমা", "উত্তোলন/পেমেন্ট")


def expense_rows(db, f):
    q = (
        db.query(Voucher.voucher_date, Voucher.id, Account.name, Voucher.narration,
                 VoucherEntry.debit, VoucherEntry.credit)
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .join(Account, Account.id == VoucherEntry.account_id)
        .filter(Account.account_type == "expense", Account.name != "Inventory Purchase")
    )
    if f.branch_id:
        q = q.filter(Account.branch_id == f.branch_id)
    if f.start:
        q = q.filter(Voucher.voucher_date >= f.start)
    if f.end:
        q = q.filter(Voucher.voucher_date < f.end)
    rows = []
    for vdate, vid, aname, narr, d, c in q.order_by(Voucher.voucher_date, VoucherEntry.id).all():
        if not has(aname, f.category):
            continue
        rows.append({"date": ldate(vdate), "voucher": str(vid), "category": aname,
                     "narration": narr or "", "amount": n(d) - n(c)})
    return rows


def r_expense(db, f, m):
    rows = expense_rows(db, f)
    cols = [col("date", "তারিখ", "date"), col("voucher", "ভাউচার নং"), col("category", "খাত"),
            col("narration", "বিবরণ"), col("amount", "খরচ", "money")]
    return out(cols, rows, totals_of(rows, ["amount"]))


def r_expense_by_category(db, f, m):
    g = {}
    for r in expense_rows(db, f):
        x = g.setdefault(r["category"], {"category": r["category"], "count": 0, "amount": 0})
        x["count"] += 1
        x["amount"] += r["amount"]
    rows = sorted(g.values(), key=lambda r: -r["amount"])
    cols = [col("category", "খাত"), col("count", "সংখ্যা", "number"), col("amount", "মোট খরচ", "money")]
    return out(cols, rows, totals_of(rows, ["count", "amount"]))


def r_income(db, f, m):
    q = (
        db.query(Voucher.voucher_date, Voucher.id, Account.name, Voucher.narration,
                 VoucherEntry.debit, VoucherEntry.credit)
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .join(Account, Account.id == VoucherEntry.account_id)
        .filter(Account.account_type == "income")
    )
    if f.branch_id:
        q = q.filter(Account.branch_id == f.branch_id)
    if f.start:
        q = q.filter(Voucher.voucher_date >= f.start)
    if f.end:
        q = q.filter(Voucher.voucher_date < f.end)
    rows = [{
        "date": ldate(vdate), "voucher": str(vid), "source": aname,
        "narration": narr or "", "amount": n(c) - n(d),
    } for vdate, vid, aname, narr, d, c in q.order_by(Voucher.voucher_date, VoucherEntry.id).all()]
    cols = [col("date", "তারিখ", "date"), col("voucher", "ভাউচার নং"), col("source", "খাত"),
            col("narration", "বিবরণ"), col("amount", "আয়", "money")]
    return out(cols, rows, totals_of(rows, ["amount"]))


def r_cash_flow(db, f, m):
    ids = acc_ids(db, f, types=["cash", "bank"])
    if not ids:
        return message("ক্যাশ/ব্যাংকে এখনো কোনো লেনদেন নেই")
    q = (
        db.query(Voucher.voucher_date, VoucherEntry.debit, VoucherEntry.credit)
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .filter(VoucherEntry.account_id.in_(ids))
    )
    if f.start:
        q = q.filter(Voucher.voucher_date >= f.start)
    if f.end:
        q = q.filter(Voucher.voucher_date < f.end)
    days = {}
    for vdate, d, c in q.all():
        x = days.setdefault(ldate(vdate), {"date": ldate(vdate), "inflow": 0, "outflow": 0})
        x["inflow"] += n(d)
        x["outflow"] += n(c)
    rows = sorted(days.values(), key=lambda r: r["date"])
    for r in rows:
        r["net"] = r["inflow"] - r["outflow"]
    cols = [col("date", "তারিখ", "date"), col("inflow", "টাকা এসেছে", "money"),
            col("outflow", "টাকা গেছে", "money"), col("net", "নিট", "money")]
    return out(cols, rows, totals_of(rows, ["inflow", "outflow", "net"]))


def r_bank_balance(db, f, m):
    accs = acc_query(db, f).filter(Account.account_type == "bank").all()
    if not accs:
        return message("ব্যাংক একাউন্ট এখনো তৈরি হয়নি (ব্যাংকে পেমেন্ট/জমা হলে নিজে থেকে তৈরি হয়)")
    rows = []
    for a in accs:
        d, c, _ = entries_sum(db, Filters(), VoucherEntry.account_id == a.id)
        rows.append({"account": acc_label(a, f, m), "debit": d, "credit": c, "balance": d - c})
    cols = [col("account", "একাউন্ট"), col("debit", "মোট জমা", "money"),
            col("credit", "মোট উত্তোলন", "money"), col("balance", "ব্যালান্স", "money")]
    return out(cols, rows, totals_of(rows, ["debit", "credit", "balance"]))


def r_cash_bank_position(db, f, m):
    rows = []
    for a in acc_query(db, f).filter(Account.account_type.in_(["cash", "bank"])).all():
        d, c, _ = entries_sum(db, Filters(), VoucherEntry.account_id == a.id)
        rows.append({"account": acc_label(a, f, m), "kind": "ক্যাশ" if a.account_type == "cash" else "ব্যাংক",
                     "balance": d - c})
    cols = [col("account", "একাউন্ট"), col("kind", "ধরন"), col("balance", "ব্যালান্স", "money")]
    return out(cols, rows, totals_of(rows, ["balance"]))


# ---------------------------------------------------------------
# ম্যানেজমেন্ট
# ---------------------------------------------------------------
def r_business_summary(db, f, m):
    sf = scope_only(f)

    sales = sales_rows(db, f, m)
    sold = sum(r["sold_price"] for r in sales)
    cost = sum(r["purchase_price"] for r in sales)
    cash_sales = sum(r["sold_price"] for r in sales if r["payment"] == MODE_LABEL["cash"])
    profit = sold - cost

    d, c, _ = entries_sum(db, f, Account.name == "Spare Parts Income")
    parts_income = c - d
    d, c, _ = entries_sum(db, f, Account.name == "Commission Income")
    commission_income = c - d

    bikes = purchase_rows(db, Filters(from_=f.from_, to=f.to, branch_id=f.branch_id), m)
    bike_purchase = sum(r["price"] for r in bikes)
    d, c, _ = entries_sum(db, f, Account.name == "Inventory Purchase")
    parts_purchase = max((d - c) - bike_purchase, 0)

    d, c, cnt = entries_sum(db, f, Account.name == "Accounts Receivable", Voucher.voucher_type == "receipt")
    collected, receipts = c, cnt

    exp = expense_rows(db, f)
    expenses = sum(r["amount"] for r in exp)

    rd, rc, _ = entries_sum(db, sf, Account.name == "Accounts Receivable")
    pd, pc, _ = entries_sum(db, sf, Account.name == "Accounts Payable")
    ad, ac, _ = entries_sum(db, sf, Account.name == "Customer Advances")

    rows = [
        {"label": "বাইক বিক্রয়", "count": len(sales), "amount": sold},
        {"label": "বিক্রীত বাইকের ক্রয় মূল্য", "count": None, "amount": cost},
        {"label": "বাইক বিক্রয়ে লাভ", "count": None, "amount": profit},
        {"label": "স্পেয়ার পার্টস বিক্রয়", "count": None, "amount": parts_income},
        {"label": "কোম্পানি থেকে প্রাপ্ত কমিশন", "count": None, "amount": commission_income},
        {"label": "বাইক ক্রয়", "count": len(bikes), "amount": bike_purchase},
        {"label": "স্পেয়ার পার্টস ক্রয়", "count": None, "amount": parts_purchase},
        {"label": "নগদ বিক্রয়", "count": None, "amount": cash_sales},
        {"label": "বাকি আদায়", "count": receipts, "amount": collected},
        {"label": "মোট কালেকশন (নগদ বিক্রয় + বাকি আদায়)", "count": None, "amount": cash_sales + collected},
        {"label": "দোকান খরচ", "count": len(exp), "amount": expenses},
        {"label": "আনুমানিক নিট লাভ (স্পেয়ার পার্টসের ক্রয় খরচ ধরা হয়নি)", "count": None,
        "amount": profit + parts_income + commission_income - expenses},
        {"label": "— এখনকার অবস্থা (আজ পর্যন্ত) —", "count": None, "amount": None},
        {"label": "ক্যাশ ব্যালান্স", "count": None, "amount": balance_by_type(db, f, ["cash"])},
        {"label": "ব্যাংক ব্যালান্স", "count": None, "amount": balance_by_type(db, f, ["bank"])},
        {"label": "কাস্টমারের কাছে বাকি", "count": None, "amount": rd - rc},
        {"label": "সাপ্লায়ারের পাওনা", "count": None, "amount": pc - pd},
        {"label": "কাস্টমারের অগ্রিম জমা (ডেলিভারির অপেক্ষায়)", "count": None, "amount": ac - ad},
        {"label": "মোট স্টকের মূল্য", "count": None, "amount": stock_value_now(db, f, m)},
    ]
    cols = [col("label", "বিষয়"), col("count", "সংখ্যা", "number"), col("amount", "পরিমাণ", "money")]
    return out(cols, rows)


def r_profit_loss(db, f, m):
    sales = sales_rows(db, f, m)
    sold = sum(r["sold_price"] for r in sales)
    cost = sum(r["purchase_price"] for r in sales)
    d, c, _ = entries_sum(db, f, Account.name == "Spare Parts Income")
    parts_income = c - d
    d, c, _ = entries_sum(db, f, Account.name == "Commission Income")
    commission_income = c - d
    expenses = sum(r["amount"] for r in expense_rows(db, f))
    rows = [
        {"label": "বাইক বিক্রয় (আয়)", "amount": sold},
        {"label": "(−) বিক্রীত বাইকের ক্রয় মূল্য", "amount": cost},
        {"label": "বাইক বিক্রয়ে মোট লাভ", "amount": sold - cost},
        {"label": "(+) স্পেয়ার পার্টস বিক্রয় (ক্রয় খরচ হিসাবে নেই)", "amount": parts_income},
        {"label": "(+) কোম্পানি থেকে প্রাপ্ত কমিশন", "amount": commission_income},
        {"label": "মোট আয়", "amount": sold - cost + parts_income + commission_income},
        {"label": "(−) দোকান খরচ", "amount": expenses},
        {"label": "নিট লাভ", "amount": sold - cost + parts_income + commission_income - expenses},
    ]
    return out([col("label", "বিবরণ"), col("amount", "টাকা", "money")], rows)


def r_showroom_performance(db, f, m):
    data = {}

    def bucket(name):
        return data.setdefault(name, {"warehouse": name, "sold_qty": 0, "sales": 0, "cost": 0,
                                      "profit": 0, "stock_qty": 0, "stock_value": 0})

    for r in sales_rows(db, f, m):
        g = bucket(r["warehouse"])
        g["sold_qty"] += 1
        g["sales"] += r["sold_price"]
        g["cost"] += r["purchase_price"]
        g["profit"] += r["profit"]
    for r in stock_unit_rows(db, Filters(warehouse_id=f.warehouse_id, branch_id=f.branch_id), m):
        g = bucket(r["warehouse"])
        g["stock_qty"] += 1
        g["stock_value"] += r["price"]
    rows = sorted(data.values(), key=lambda r: -r["sales"])
    cols = [
        col("warehouse", "শোরুম/গোডাউন"), col("sold_qty", "বিক্রি (সংখ্যা)", "number"),
        col("sales", "বিক্রয়", "money"), col("cost", "ক্রয় মূল্য", "money"), col("profit", "লাভ", "money"),
        col("stock_qty", "স্টকে (সংখ্যা)", "number"), col("stock_value", "স্টকের মূল্য", "money"),
    ]
    return out(cols, rows, totals_of(rows, ["sold_qty", "sales", "cost", "profit", "stock_qty", "stock_value"]))


def r_business_growth(db, f, m):
    today = datetime.utcnow() + LOCAL_OFFSET
    start = f.d_from or datetime(today.year, 1, 1)
    end = f.d_to or today
    months = []
    y, mo = start.year, start.month
    while (y, mo) <= (end.year, end.month) and len(months) < 60:
        months.append((y, mo))
        mo += 1
        if mo > 12:
            mo, y = 1, y + 1
    buckets = {k: {"sales": 0, "cost": 0, "purchase": 0, "expense": 0} for k in months}

    g = Filters(from_=start.strftime("%Y-%m-%d"), to=end.strftime("%Y-%m-%d"), branch_id=f.branch_id)

    def add(date_str, field, amount):
        key = (int(date_str[:4]), int(date_str[5:7]))
        if key in buckets:
            buckets[key][field] += amount

    for r in sales_rows(db, g, m):
        add(r["date"], "sales", r["sold_price"])
        add(r["date"], "cost", r["purchase_price"])
    for r in purchase_rows(db, g, m):
        add(r["date"], "purchase", r["price"])
    for r in expense_rows(db, g):
        add(r["date"], "expense", r["amount"])

    rows = []
    prev = None
    for key in months:
        b = buckets[key]
        growth = None
        if prev:
            growth = round((b["sales"] - prev) * 100.0 / prev, 1)
        rows.append({
            "month": f"{key[0]}-{key[1]:02d}", "sales": b["sales"], "purchase": b["purchase"],
            "expense": b["expense"], "profit": b["sales"] - b["cost"] - b["expense"], "growth": growth,
        })
        prev = b["sales"] or None
    cols = [
        col("month", "মাস"), col("sales", "বিক্রয়", "money"), col("purchase", "ক্রয়", "money"),
        col("expense", "খরচ", "money"), col("profit", "লাভ (বিক্রয় − ক্রয় মূল্য − খরচ)", "money"),
        col("growth", "আগের মাসের তুলনায় বিক্রয় বৃদ্ধি", "percent"),
    ]
    return out(cols, rows, totals_of(rows, ["sales", "purchase", "expense", "profit"]))


def r_advance_orders(db, f, m):
    try:
        from backend.models import AdvanceOrder, AdvancePayment  # noqa: F401
    except ImportError:
        return message("অগ্রিম অর্ডার এখনো চালু করা হয়নি")
    q = db.query(AdvanceOrder)
    if f.branch_id:
        q = q.filter(AdvanceOrder.branch_id == f.branch_id)
    if f.start:
        q = q.filter(AdvanceOrder.order_date >= f.start)
    if f.end:
        q = q.filter(AdvanceOrder.order_date < f.end)
    if f.customer_id:
        q = q.filter(AdvanceOrder.customer_id == f.customer_id)
    if f.product_id:
        q = q.filter(AdvanceOrder.product_id == f.product_id)
    orders = q.order_by(AdvanceOrder.order_date, AdvanceOrder.id).all()

    sums = {}
    if orders:
        for oid, kind, total in (
            db.query(AdvancePayment.order_id, AdvancePayment.kind, func.coalesce(func.sum(AdvancePayment.amount), 0))
            .filter(AdvancePayment.order_id.in_([o.id for o in orders]))
            .group_by(AdvancePayment.order_id, AdvancePayment.kind)
            .all()
        ):
            sums.setdefault(oid, {})[kind] = n(total)

    status_label = {"open": "চলমান", "delivered": "ডেলিভারি হয়েছে", "cancelled": "বাতিল"}
    rows = []
    for o in orders:
        s_ = sums.get(o.id, {})
        held = s_.get("payment", 0) - s_.get("refund", 0) - s_.get("forfeit", 0) - s_.get("applied", 0)
        rows.append({
            "date": ldate(o.order_date), "customer": m.party(o.customer_id) or "—",
            "phone": m.phone(o.customer_id), "model": m.model(o.product_id), "color": o.color,
            "price": n(o.agreed_price), "paid": s_.get("payment", 0),
            "held": held if o.status == "open" else 0,
            "balance": max(n(o.agreed_price) - held, 0) if o.status == "open" else 0,
            "delivery": o.expected_delivery_date.isoformat() if o.expected_delivery_date else None,
            "status": status_label.get(o.status, o.status),
        })
    cols = [
        col("date", "অর্ডারের তারিখ", "date"), col("customer", "কাস্টমার"), col("phone", "ফোন"),
        col("model", "মডেল"), col("color", "রঙ"), col("price", "চুক্তির মূল্য", "money"),
        col("paid", "মোট অগ্রিম নেওয়া", "money"), col("held", "এখন জমা আছে", "money"),
        col("balance", "ডেলিভারিতে বাকি", "money"), col("delivery", "ডেলিভারির তারিখ", "date"),
        col("status", "অবস্থা"),
    ]
    return out(cols, rows, totals_of(rows, ["price", "paid", "held", "balance"]))


# ---------------------------------------------------------------
# যেসব রিপোর্টের ডেটা এখনো সংরক্ষণ হয় না
# ---------------------------------------------------------------
def unsupported(text):
    def fn(db, f, m):
        return message(text)
    return fn


REPORTS = {
    # ম্যানেজমেন্ট
    "daily_business_summary": r_business_summary,
    "monthly_business_summary": r_business_summary,
    "yearly_business_summary": r_business_summary,
    "showroom_performance": r_showroom_performance,
    "profit_loss": r_profit_loss,
    "cash_bank_position": r_cash_bank_position,
    "business_growth": r_business_growth,
    # বিক্রয়
    "daily_sales": sales_detail,
    "monthly_sales": sales_detail,
    "invoice_sales": sales_detail,
    "showroom_sales": sales_group("warehouse", "শোরুম/গোডাউন"),
    "product_sales": sales_group("model", "মডেল"),
    "category_sales": sales_group("category", "ক্যাটেগরি"),
    "brand_sales": sales_group("brand", "ব্র্যান্ড"),
    "customer_sales": sales_group("customer", "কাস্টমার"),
    "payment_method_sales": sales_group("payment", "পেমেন্ট মাধ্যম"),
    "salesperson_sales": unsupported("কে বিক্রি করেছেন তা এখন সংরক্ষণ হয় না (বিক্রয়ে ইউজার আইডি নেই)। সেটা যোগ হলে এই রিপোর্ট চালু হবে।"),
    "sales_return": unsupported("বিক্রয় ফেরত রেকর্ড করার ব্যবস্থা এখনো নেই।"),
    "discount_report": unsupported("বিক্রয়ে ছাড় আলাদাভাবে সংরক্ষণ হয় না।"),
    # ক্রয়
    "daily_purchase": purchase_detail,
    "monthly_purchase": purchase_detail,
    "supplier_purchase": purchase_group("supplier", "সাপ্লায়ার"),
    "product_purchase": purchase_group("model", "মডেল"),
    "purchase_due": r_payable,
    "purchase_return": unsupported("ক্রয় ফেরত রেকর্ড করার ব্যবস্থা এখনো নেই।"),
    # স্টক
    "current_stock": r_current_stock,
    "serial_stock": r_current_stock,
    "stock_valuation": r_stock_valuation,
    "showroom_stock": r_warehouse_stock,
    "warehouse_stock": r_warehouse_stock,
    "out_of_stock": r_out_of_stock,
    "dead_stock": r_dead_stock,
    "fast_moving": r_fast_moving,
    "slow_moving": r_slow_moving,
    "stock_in_out": r_stock_in_out,
    "stock_transfer": r_stock_transfer,
    "product_movement": r_stock_in_out,
    "low_stock": unsupported("প্রোডাক্টের সর্বনিম্ন স্টক সীমা ঠিক করা নেই। সীমা যোগ করলে এই রিপোর্ট চালু হবে।"),
    "stock_adjustment": unsupported("স্টক সমন্বয় রেকর্ড করার ব্যবস্থা এখনো নেই।"),
    # কাস্টমার ও বাকি
    "customer_due": r_customer_due,
    "customer_ledger": r_customer_ledger,
    "area_due": r_area_due,
    "customer_payment_history": r_customer_payments,
    "overdue_customers": r_overdue,
    "customer_sales_due_summary": r_customer_summary,
    "advance_orders": r_advance_orders,
    # একাউন্টস
    "daily_cash_book": r_cash_book,
    "bank_transactions": r_bank_transactions,
    "income_report": r_income,
    "expense_report": r_expense,
    "expense_by_category": r_expense_by_category,
    "receivable": r_customer_due,
    "payable": r_payable,
    "cash_flow": r_cash_flow,
    "bank_balance": r_bank_balance,
}
# ---------------------------------------------------------------
# রিপোর্টের উপরে দেখানোর সারসংক্ষেপ (মোট কত বাইক / কত জন কাস্টমার ইত্যাদি)
# ---------------------------------------------------------------
BIKE_ROW_REPORTS = {
    "daily_sales", "monthly_sales", "invoice_sales",
    "daily_purchase", "monthly_purchase",
    "current_stock", "serial_stock", "dead_stock",
}
BIKE_QTY_REPORTS = {
    "showroom_sales", "product_sales", "category_sales", "brand_sales",
    "customer_sales", "payment_method_sales",
    "supplier_purchase", "product_purchase",
}


def add_summary(key, result):
    cols = result.get("columns") or []
    rows = result.get("rows") or []
    totals = result.get("totals") or {}
    if not rows or (cols and cols[0].get("key") == "msg"):
        return result
    cnt = len(rows)
    text = None
    if key in BIKE_ROW_REPORTS:
        text = f"মোট {cnt} টি বাইক"
    elif key in BIKE_QTY_REPORTS:
        text = f"মোট {n(totals.get('qty'))} টি বাইক"
    elif key in ("showroom_stock", "warehouse_stock"):
        text = f"মোট {n(totals.get('bikes'))} টি বাইক স্টকে আছে"
    elif key == "stock_valuation":
        bikes = sum(n(r.get("qty")) for r in rows if r.get("category") != "স্পেয়ার পার্টস")
        text = f"মোট {bikes} টি বাইক স্টকে আছে"
    elif key in ("fast_moving", "slow_moving"):
        text = f"মোট বিক্রি {n(totals.get('sold_qty'))} টি, এখন স্টকে {n(totals.get('stock_qty'))} টি"
    elif key in ("stock_in_out", "product_movement"):
        came = sum(1 for r in rows if r.get("type") == "স্টকে এসেছে")
        sold = sum(1 for r in rows if r.get("type") == "বিক্রি হয়েছে")
        text = f"স্টকে এসেছে {came} টি, বিক্রি হয়েছে {sold} টি"
    elif key == "out_of_stock":
        text = f"{cnt} টি মডেল স্টকে নেই"
    elif key in ("customer_due", "receivable", "overdue_customers"):
        text = f"মোট {cnt} জন কাস্টমারের বাকি আছে"
    elif key == "area_due":
        text = f"মোট {n(totals.get('customers'))} জন কাস্টমারের বাকি আছে"
    elif key == "customer_sales_due_summary":
        text = f"{cnt} জন কাস্টমার, মোট {n(totals.get('qty'))} টি বাইক বিক্রয়"
    elif key in ("payable", "purchase_due"):
        text = f"মোট {cnt} জন সাপ্লায়ারের পাওনা আছে"
    elif key == "customer_payment_history":
        text = f"মোট {cnt} বার জমা"
    elif key == "advance_orders":
        text = f"মোট {cnt} টি অগ্রিম অর্ডার"
    if text:
        result["summary"] = text
    return result
def r_stock_transfers(db, f, m):
    from sqlalchemy import or_
    from backend.models import StockTransfer

    q = db.query(StockTransfer)
    if f.branch_id:
        q = q.filter(or_(StockTransfer.from_branch_id == f.branch_id,
                         StockTransfer.to_branch_id == f.branch_id))
    if f.start:
        q = q.filter(StockTransfer.transfer_date >= f.start)
    if f.end:
        q = q.filter(StockTransfer.transfer_date < f.end)
    if f.warehouse_id:
        q = q.filter(or_(StockTransfer.from_warehouse_id == f.warehouse_id,
                         StockTransfer.to_warehouse_id == f.warehouse_id))
    transfers = q.order_by(StockTransfer.transfer_date, StockTransfer.id).all()

    units = {}
    if transfers:
        ids = [t.unit_id for t in transfers]
        units = {u.id: u for u in db.query(Unit).filter(Unit.id.in_(ids)).all()}

    rows = []
    for t in transfers:
        u = units.get(t.unit_id)
        pid = u.product_id if u else None
        if f.product_id and pid != f.product_id:
            continue
        if (f.brand or f.category) and (pid is None or not product_ok(f, m, pid)):
            continue
        if f.q and (not u or f.q.lower() not in f"{u.chassis_no} {u.engine_no}".lower()):
            continue
        rows.append({
            "date": (t.transfer_date + LOCAL_OFFSET).strftime("%Y-%m-%d %H:%M") if t.transfer_date else None,
            "batch": f"#{t.batch_no}",
            "chassis": u.chassis_no if u else "—",
            "engine": u.engine_no if u else "—",
            "model": m.model(pid) if pid else None,
            "brand": m.brand_name(pid) if pid else None,
            "from_branch": m.branch_name(t.from_branch_id),
            "from_wh": m.wh(t.from_warehouse_id),
            "to_branch": m.branch_name(t.to_branch_id),
            "to_wh": m.wh(t.to_warehouse_id),
            "by_user": t.by_user,
            "note": t.note or "",
        })

    cols = [
        col("date", "তারিখ ও সময়"), col("batch", "ব্যাচ নং"),
        col("chassis", "চেসিস নম্বর"), col("engine", "ইঞ্জিন নম্বর"),
        col("model", "মডেল"), col("brand", "ব্র্যান্ড"),
        col("from_branch", "কোন শোরুম থেকে"), col("from_wh", "কোন গোডাউন থেকে"),
        col("to_branch", "কোন শোরুমে"), col("to_wh", "কোন গোডাউনে"),
        col("by_user", "কে পাঠিয়েছেন"), col("note", "মন্তব্য"),
    ]
    result = out(cols, rows, {"date": f"মোট {len(rows)} টি বাইক"} if rows else {})
    if rows:
        batches = len({r["batch"] for r in rows})
        result["summary"] = f"মোট {len(rows)} টি বাইক ট্রান্সফার ({batches} ব্যাচে)"
    return result

def build_router(get_current_user):
    router = APIRouter()

    @router.get("/report-data/{key}")
    def report_data(
        key: str,
        from_: str | None = Query(None, alias="from"),
        to: str | None = None,
        customer_id: int | None = None,
        supplier_id: int | None = None,
        product_id: int | None = None,
        warehouse_id: int | None = None,
        brand: str | None = None,
        category: str | None = None,
        payment_mode: str | None = None,
        area: str | None = None,
        account: str | None = None,
        q: str | None = None,
        days: str | None = None,
        db: Session = Depends(get_db),
        current_user=Depends(get_current_user),
    ):
        handler = REPORTS.get(key)
        if handler is None:
            raise HTTPException(status_code=404, detail="এই নামে কোনো রিপোর্ট নেই")
        f = Filters(
            from_=from_, to=to, customer_id=customer_id, supplier_id=supplier_id,
            product_id=product_id, warehouse_id=warehouse_id, brand=brand, category=category,
            payment_mode=payment_mode, area=area, account=account, q=q, days=days,
            branch_id=getattr(current_user, "active_branch_id", None),
        )
        return add_summary(key, handler(db, f, Maps(db)))

    return router