"""
পার্টনার (সেল সেন্টার) ভিত্তিক অগ্রিমের হিসাব ও সাপ্লায়ারের (রানার) ডেলিভারির হিসাব।

নিয়ম:
  * প্রতিটা সেল সেন্টারের (শোরুমের) "Supplier Advances" একাউন্ট আলাদা, তাই দুই পার্টনারের জমা আলাদা থাকে।
  * গাড়ি ডেলিভারি নেওয়ার সময় ক্রয় "বাকি" ধরলে সেটা Accounts Payable-এ ওঠে।
  * গাড়ি বিক্রি হলে সেই সেন্টারের অগ্রিম থেকে গাড়ির ক্রয়মূল্য কাটা হয়:
        Dr Accounts Payable (সাপ্লায়ার)  /  Cr Supplier Advances (সাপ্লায়ার)
    অগ্রিম কম পড়লে যতটুকু আছে ততটুকু কাটে, বাকিটা পাওনা থেকে যায়। পরে অগ্রিম জমা দিলে বাকিটা কাটে।
  * বিক্রি যে পথেই হোক (সরাসরি বিক্রয় বা অগ্রিম অর্ডারের ডেলিভারি), হিসাব দেখার সময় কাটা নিজে মিলে যায়।

  GET /partner-ledger?supplier_id=   : পার্টনার/সেন্টার অনুযায়ী জমা, কাটা, ব্যালান্স ও লেনদেন
  GET /supplier-deliveries?supplier_id= : অর্ডার, পাওয়া, পাওয়া বাকি, মাসওয়ারি ও দৈনিক ডেলিভারি
"""
from collections import OrderedDict, defaultdict
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from database import get_db
from models import Account, Branch, Party, SupplierOrder, Unit, Voucher, VoucherEntry, Warehouse

ADV = "Supplier Advances"
PAY = "Accounts Payable"
LOCAL = timedelta(hours=6)  # ডাটাবেসে সময় UTC, বাংলাদেশ = UTC+6


# ---------------------------------------------------------------
# খাঁটি হিসাবের ফাংশন (ডাটাবেস ছাড়া, তাই সহজে পরীক্ষা করা যায়)
# ---------------------------------------------------------------
def plan_settlement(sold_units, payable_by_ref, applied_by_ref, balance):
    """
    sold_units    : [(unit_id, chassis_no)] বিক্রির ক্রমে
    payable_by_ref: {chassis: ক্রয়ের সময় সাপ্লায়ারের কাছে বাকি রাখা টাকা}
    applied_by_ref: {chassis: আগেই অগ্রিম থেকে কাটা টাকা}
    balance       : সাপ্লায়ারের কাছে জমা থাকা অগ্রিম
    ফেরত: [(unit_id, chassis, কাটার পরিমাণ)]
    """
    plan = []
    for uid, chassis in sold_units:
        if balance <= 0:
            break
        need = int(payable_by_ref.get(chassis, 0)) - int(applied_by_ref.get(chassis, 0))
        if need <= 0:
            continue
        amt = min(need, int(balance))
        plan.append((uid, chassis, amt))
        balance -= amt
    return plan


def month_key(dt):
    return (dt + LOCAL).strftime("%Y-%m") if dt else "-"


def monthly_summary(order_rows):
    """order_rows: [(order_date, qty, received, status)] -> মাসওয়ারি সারাংশ (নতুন মাস আগে)"""
    months = OrderedDict()
    for order_date, qty, got, status in sorted(order_rows, key=lambda r: (r[0] is None, r[0]), reverse=True):
        if status == "cancelled":
            continue
        key = month_key(order_date)
        m = months.setdefault(key, {"month": key, "orders": 0, "ordered": 0, "received": 0, "remaining": 0})
        m["orders"] += 1
        m["ordered"] += int(qty)
        m["received"] += int(min(got, qty))
        if status == "open":
            m["remaining"] += max(int(qty) - int(got), 0)
    return list(months.values())


def daily_summary(unit_rows, branch_names):
    """unit_rows: [(purchase_date, branch_id)] -> [{date, branch, count}] (নতুন দিন আগে)"""
    counts = defaultdict(int)
    for dt, branch_id in unit_rows:
        if not dt:
            continue
        counts[((dt + LOCAL).strftime("%Y-%m-%d"), branch_id)] += 1
    rows = [
        {"date": d, "branch_id": b, "branch": branch_names.get(b), "count": c}
        for (d, b), c in counts.items()
    ]
    rows.sort(key=lambda r: (r["date"], r["branch_id"] or 0), reverse=True)
    return rows


# ---------------------------------------------------------------
# অগ্রিম কাটা (বিক্রির সময়)
# ---------------------------------------------------------------
def _first_account(db: Session, name: str, branch_id):
    return (
        db.query(Account)
        .filter(Account.name == name, Account.branch_id == branch_id)
        .order_by(Account.id)
        .first()
    )


def settle_sold_units(db: Session, supplier_id, branch_id):
    """এই সেন্টারের বিক্রি হওয়া গাড়ির দাম সাপ্লায়ারের অগ্রিম থেকে কাটে। কয়টা কাটা হলো তা ফেরত দেয়।"""
    if not supplier_id or not branch_id:
        return 0
    adv = _first_account(db, ADV, branch_id)
    pay = _first_account(db, PAY, branch_id)
    if not adv or not pay:
        return 0

    dep, ded = (
        db.query(
            func.coalesce(func.sum(VoucherEntry.debit), 0),
            func.coalesce(func.sum(VoucherEntry.credit), 0),
        )
        .filter(VoucherEntry.account_id == adv.id, VoucherEntry.party_id == supplier_id)
        .one()
    )
    balance = int(dep) - int(ded)
    if balance <= 0:
        return 0

    payable_rows = (
        db.query(Voucher.reference, func.coalesce(func.sum(VoucherEntry.credit), 0))
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .filter(
            Voucher.voucher_type == "purchase",
            VoucherEntry.account_id == pay.id,
            VoucherEntry.party_id == supplier_id,
        )
        .group_by(Voucher.reference)
        .all()
    )
    payable = {ref: int(v) for ref, v in payable_rows if ref}

    applied_rows = (
        db.query(Voucher.reference, func.coalesce(func.sum(VoucherEntry.credit), 0))
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .filter(
            Voucher.voucher_type == "advance_apply",
            VoucherEntry.account_id == adv.id,
            VoucherEntry.party_id == supplier_id,
        )
        .group_by(Voucher.reference)
        .all()
    )
    applied = {ref: int(v) for ref, v in applied_rows if ref}

    units = (
        db.query(Unit)
        .join(Warehouse, Unit.warehouse_id == Warehouse.id)
        .filter(
            Unit.status == "sold",
            Unit.supplier_id == supplier_id,
            Warehouse.branch_id == branch_id,
        )
        .order_by(Unit.sold_date, Unit.id)
        .all()
    )
    plan = plan_settlement([(u.id, u.chassis_no) for u in units], payable, applied, balance)
    if not plan:
        return 0

    by_id = {u.id: u for u in units}
    for uid, chassis, amt in plan:
        u = by_id[uid]
        # নারেশনের "Unit #<id> (" অংশ বাইক মোছার সময় ভাউচার খুঁজতে কাজে লাগে — বদলাবেন না
        v = Voucher(
            voucher_type="advance_apply",
            narration=f"Unit #{u.id} ({u.chassis_no}) বিক্রয়ে অগ্রিম থেকে কাটা",
            reference=u.chassis_no,
            voucher_date=u.sold_date or datetime.utcnow(),
        )
        db.add(v)
        db.flush()
        db.add(VoucherEntry(voucher_id=v.id, account_id=pay.id, party_id=supplier_id, debit=amt, credit=0))
        db.add(VoucherEntry(voucher_id=v.id, account_id=adv.id, party_id=supplier_id, debit=0, credit=amt))
    db.commit()
    return len(plan)


def settle_unit_advance(db: Session, unit):
    """একটা গাড়ি বিক্রির পরপর ডাকা হয়"""
    wh = unit.warehouse
    if unit.supplier_id and wh and wh.branch_id:
        return settle_sold_units(db, unit.supplier_id, wh.branch_id)
    return 0


def settle_scope(db: Session, branch_id=None):
    """সব (বা একটা) সেন্টারের সব সাপ্লায়ারের জন্য কাটা মিলিয়ে নেয়"""
    branch_ids = [branch_id] if branch_id else [b.id for b in db.query(Branch).all()]
    supplier_ids = [
        r[0]
        for r in db.query(Unit.supplier_id)
        .filter(Unit.status == "sold", Unit.supplier_id.isnot(None))
        .distinct()
        .all()
    ]
    n = 0
    for b in branch_ids:
        for s in supplier_ids:
            n += settle_sold_units(db, s, b)
    return n


# ---------------------------------------------------------------
# হিসাব তৈরি
# ---------------------------------------------------------------
def _branch_ledger(db: Session, supplier_id, branch):
    adv = _first_account(db, ADV, branch.id)
    entries = []
    deposits_total = 0
    deducted_total = 0

    if adv:
        rows = (
            db.query(VoucherEntry, Voucher)
            .join(Voucher, Voucher.id == VoucherEntry.voucher_id)
            .filter(VoucherEntry.account_id == adv.id, VoucherEntry.party_id == supplier_id)
            .order_by(Voucher.voucher_date.desc(), VoucherEntry.id.desc())
            .all()
        )
        deposit_voucher_ids = [v.id for e, v in rows if (e.debit or 0) > 0]
        modes = {}
        if deposit_voucher_ids:
            mrows = (
                db.query(VoucherEntry.voucher_id, Account.name)
                .join(Account, Account.id == VoucherEntry.account_id)
                .filter(
                    VoucherEntry.voucher_id.in_(deposit_voucher_ids),
                    Account.name.in_(["Cash", "Bank"]),
                    VoucherEntry.credit > 0,
                )
                .all()
            )
            modes = {vid: name for vid, name in mrows}

        for e, v in rows:
            dep = int(e.debit or 0)
            ded = int(e.credit or 0)
            day = (v.voucher_date + LOCAL).strftime("%Y-%m-%d") if v.voucher_date else None
            if dep > 0:
                deposits_total += dep
                entries.append({
                    "date": day,
                    "kind": "deposit",
                    "amount": dep,
                    "mode": {"Cash": "নগদ", "Bank": "ব্যাংক"}.get(modes.get(v.id)),
                    "note": v.narration,
                })
            if ded > 0:
                deducted_total += ded
                entries.append({
                    "date": day,
                    "kind": "deduct",
                    "amount": ded,
                    "mode": None,
                    "note": v.narration,
                })

    sold_units = 0
    stock_units = 0
    stock_cost = 0
    stats = (
        db.query(Unit.status, func.count(Unit.id), func.coalesce(func.sum(Unit.purchase_price), 0))
        .join(Warehouse, Unit.warehouse_id == Warehouse.id)
        .filter(Unit.supplier_id == supplier_id, Warehouse.branch_id == branch.id)
        .group_by(Unit.status)
        .all()
    )
    for st, cnt, total in stats:
        if st == "sold":
            sold_units = int(cnt)
        elif st == "in_stock":
            stock_units = int(cnt)
            stock_cost = int(total)

    return {
        "branch_id": branch.id,
        "branch_name": branch.name,
        "deposits_total": deposits_total,
        "deducted_total": deducted_total,
        "balance": deposits_total - deducted_total,
        "sold_units": sold_units,
        "stock_units": stock_units,
        "stock_cost": stock_cost,
        "entries": entries[:300],
    }


def build_partner_router(get_current_user):
    router = APIRouter()

    def scope_branches(db: Session, user):
        active = getattr(user, "active_branch_id", None)
        q = db.query(Branch)
        if active:
            q = q.filter(Branch.id == active)
        elif user.branch_id:
            q = q.filter(Branch.id == user.branch_id)
        return q.order_by(Branch.id).all()

    def get_supplier(db: Session, supplier_id: int):
        supplier = db.query(Party).filter(Party.id == supplier_id).first()
        if not supplier or supplier.party_type != "supplier":
            raise HTTPException(status_code=404, detail="সাপ্লায়ার পাওয়া যায়নি")
        return supplier

    @router.get("/partner-ledger")
    def partner_ledger(
        supplier_id: int,
        db: Session = Depends(get_db),
        current_user=Depends(get_current_user),
    ):
        supplier = get_supplier(db, supplier_id)
        branches = scope_branches(db, current_user)
        result = []
        for b in branches:
            settle_sold_units(db, supplier_id, b.id)
            result.append(_branch_ledger(db, supplier_id, b))
        return {"supplier_id": supplier.id, "supplier_name": supplier.name, "branches": result}

    @router.get("/supplier-deliveries")
    def supplier_deliveries(
        supplier_id: int,
        db: Session = Depends(get_db),
        current_user=Depends(get_current_user),
    ):
        supplier = get_supplier(db, supplier_id)
        branches = scope_branches(db, current_user)
        branch_ids = [b.id for b in branches]
        branch_names = {b.id: b.name for b in branches}

        orders = (
            db.query(SupplierOrder)
            .filter(SupplierOrder.supplier_id == supplier_id, SupplierOrder.branch_id.in_(branch_ids))
            .order_by(SupplierOrder.id.desc())
            .all()
        )
        received = dict(
            db.query(Unit.supplier_order_id, func.count(Unit.id))
            .filter(Unit.supplier_order_id.isnot(None))
            .group_by(Unit.supplier_order_id)
            .all()
        )
        order_rows = []
        order_list = []
        for o in orders:
            got = int(received.get(o.id, 0))
            order_rows.append((o.order_date, o.qty, got, o.status))
            if o.status == "open":
                order_list.append({
                    "id": o.id,
                    "branch": branch_names.get(o.branch_id),
                    "date": (o.order_date + LOCAL).strftime("%Y-%m-%d") if o.order_date else None,
                    "qty": o.qty,
                    "received": got,
                    "remaining": max(o.qty - got, 0),
                    "unit_price": o.unit_price,
                    "expected_date": o.expected_date.isoformat() if o.expected_date else None,
                })

        months = monthly_summary(order_rows)
        totals = {
            "ordered": sum(m["ordered"] for m in months),
            "received": sum(m["received"] for m in months),
            "remaining": sum(m["remaining"] for m in months),
        }

        since = datetime.utcnow() - timedelta(days=90)
        unit_rows = (
            db.query(Unit.purchase_date, Warehouse.branch_id)
            .join(Warehouse, Unit.warehouse_id == Warehouse.id)
            .filter(
                Unit.supplier_id == supplier_id,
                Warehouse.branch_id.in_(branch_ids),
                Unit.purchase_date >= since,
            )
            .all()
        )
        daily = daily_summary([(d, b) for d, b in unit_rows], branch_names)

        return {
            "supplier_id": supplier.id,
            "supplier_name": supplier.name,
            "totals": totals,
            "months": months,
            "open_orders": order_list,
            "daily": daily[:200],
        }

    return router
