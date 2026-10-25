"""
অগ্রিম অর্ডার ও অগ্রিম পেমেন্ট।

শোরুম: প্রতিটি অর্ডার একটি শোরুমের (AdvanceOrder.branch_id)। অগ্রিম, ডেলিভারি ও বাতিলের সব
ভাউচার ওই শোরুমের নিজস্ব একাউন্টে যায়। ডেলিভারির বাইক অবশ্যই একই শোরুমের স্টকের হতে হবে।

হিসাবের নিয়ম:
- অগ্রিম নেওয়া:  ডেবিট ক্যাশ/ব্যাংক,  ক্রেডিট "Customer Advances" (দায়, কাস্টমারের নামে)
- ডেলিভারি (বিক্রয়): ক্রেডিট "Sales Income";  ডেবিট "Customer Advances" (অগ্রিম সমন্বয়),
                      ডেবিট ক্যাশ/ব্যাংক (ডেলিভারির সময় নেওয়া টাকা),
                      ডেবিট "Accounts Receivable" (যা বাকি থাকল)
  ভাউচারের reference = বাইকের চেসিস নম্বর, তাই বিক্রয়ের সব রিপোর্টে এটা আপনা থেকেই আসে।
- বাতিল: ডেবিট "Customer Advances";  ক্রেডিট ক্যাশ/ব্যাংক (ফেরত),
         ক্রেডিট "Advance Forfeiture Income" (দোকান যা রেখে দিল)
"""
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.models import (
    Account, AdvanceOrder, AdvancePayment, Brand, Party, Product, Unit,
    Voucher, VoucherEntry,
)
from backend.sms_service import send_sms

LOCAL_OFFSET = timedelta(hours=6)  # বাংলাদেশ = UTC+6, ডাটাবেসে সময় UTC-তে
ADVANCE_ACCOUNT = "Customer Advances"
FORFEIT_ACCOUNT = "Advance Forfeiture Income"
KIND_LABEL = {
    "payment": "অগ্রিম জমা",
    "refund": "ফেরত দেওয়া",
    "forfeit": "দোকানে রাখা (বাজেয়াপ্ত)",
    "applied": "বিক্রয়ে সমন্বয়",
}


def local_date_str(dt):
    return (dt + LOCAL_OFFSET).strftime("%Y-%m-%d") if dt else None


def active_branch(user):
    """সক্রিয় শোরুম (None = সব শোরুম)"""
    return getattr(user, "active_branch_id", None)


def get_or_create_account(db: Session, name: str, account_type: str, branch_id: int | None) -> Account:
    q = db.query(Account).filter(Account.name == name)
    if branch_id is not None:
        q = q.filter(Account.branch_id == branch_id)
    account = q.order_by(Account.id).first()
    if not account:
        account = Account(name=name, account_type=account_type, branch_id=branch_id)
        db.add(account)
        db.flush()
    return account


def money_account(db: Session, mode: str, branch_id: int | None) -> Account:
    if mode == "cash":
        return get_or_create_account(db, "Cash", "cash", branch_id)
    if mode == "bank":
        return get_or_create_account(db, "Bank", "bank", branch_id)
    raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'bank' হতে হবে")


def sums_for(db: Session, order_ids=None):
    q = (
        db.query(AdvancePayment.order_id, AdvancePayment.kind,
                 func.coalesce(func.sum(AdvancePayment.amount), 0))
        .group_by(AdvancePayment.order_id, AdvancePayment.kind)
    )
    if order_ids is not None:
        q = q.filter(AdvancePayment.order_id.in_(order_ids))
    result = {}
    for oid, kind, total in q.all():
        result.setdefault(oid, {})[kind] = int(total or 0)
    return result


def held_of(s: dict) -> int:
    """এখনো দোকানের কাছে জমা থাকা অগ্রিম"""
    return (s.get("payment", 0) - s.get("refund", 0)
            - s.get("forfeit", 0) - s.get("applied", 0))


class Lookups:
    def __init__(self, db: Session):
        self.parties = {x.id: x for x in db.query(Party).all()}
        self.products = {x.id: x for x in db.query(Product).all()}
        self.brands = {x.id: x for x in db.query(Brand).all()}


def order_dict(o: AdvanceOrder, sums: dict, lk: Lookups) -> dict:
    s = sums.get(o.id, {})
    held = held_of(s)
    cust = lk.parties.get(o.customer_id)
    prod = lk.products.get(o.product_id)
    brand = lk.brands.get(prod.brand_id) if prod else None
    today = (datetime.utcnow() + LOCAL_OFFSET).date()
    return {
        "id": o.id,
        "branch_id": o.branch_id,
        "customer_id": o.customer_id,
        "customer_name": cust.name if cust else None,
        "customer_phone": cust.phone if cust else None,
        "customer_address": cust.address if cust else None,
        "product_id": o.product_id,
        "model": prod.model_name if prod else None,
        "brand": brand.name if brand else None,
        "color": o.color,
        "agreed_price": o.agreed_price,
        "advance_paid": s.get("payment", 0),
        "advance_held": held,
        "balance": max(o.agreed_price - held, 0) if o.status == "open" else 0,
        "order_date": local_date_str(o.order_date),
        "expected_delivery_date": o.expected_delivery_date.isoformat() if o.expected_delivery_date else None,
        "status": o.status,
        "notes": o.notes,
        "unit_id": o.unit_id,
        "overdue": bool(o.status == "open" and o.expected_delivery_date and o.expected_delivery_date < today),
    }


def detail_dict(db: Session, o: AdvanceOrder) -> dict:
    d = order_dict(o, sums_for(db, [o.id]), Lookups(db))
    pays = (
        db.query(AdvancePayment)
        .filter(AdvancePayment.order_id == o.id)
        .order_by(AdvancePayment.payment_date, AdvancePayment.id)
        .all()
    )
    d["payments"] = [{
        "id": p.id, "kind": p.kind, "label": KIND_LABEL.get(p.kind, p.kind),
        "amount": p.amount, "payment_mode": p.payment_mode,
        "date": local_date_str(p.payment_date), "note": p.note,
    } for p in pays]
    return d


def get_order(db: Session, order_id: int, user) -> AdvanceOrder:
    o = db.query(AdvanceOrder).filter(AdvanceOrder.id == order_id).first()
    if not o:
        raise HTTPException(status_code=404, detail="অর্ডার পাওয়া যায়নি")
    bid = active_branch(user)
    if bid and o.branch_id != bid:
        raise HTTPException(status_code=404, detail="অর্ডার পাওয়া যায়নি (এটি অন্য শোরুমের)")
    return o


def require_open(o: AdvanceOrder):
    if o.status != "open":
        raise HTTPException(status_code=400, detail="এই অর্ডার আর চলমান নেই")


def receive_advance(db: Session, order: AdvanceOrder, amount: int, mode: str, note: str | None):
    money = money_account(db, mode, order.branch_id)
    adv = get_or_create_account(db, ADVANCE_ACCOUNT, "advance", order.branch_id)
    voucher = Voucher(
        voucher_type="advance",
        narration=note or f"অগ্রিম অর্ডার #{order.id} — অগ্রিম গ্রহণ",
        reference=f"adv-{order.id}",
    )
    db.add(voucher)
    db.flush()
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=money.id, party_id=order.customer_id,
                        debit=amount, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=adv.id, party_id=order.customer_id,
                        debit=0, credit=amount))
    db.add(AdvancePayment(order_id=order.id, kind="payment", amount=amount, payment_mode=mode,
                          voucher_id=voucher.id, note=note))
    return voucher


class AdvanceOrderCreate(BaseModel):
    customer_id: int
    product_id: int
    color: str | None = None
    agreed_price: int
    expected_delivery_date: date | None = None
    notes: str | None = None
    advance_amount: int = 0
    payment_mode: str = "cash"


class AdvanceOrderUpdate(BaseModel):
    agreed_price: int | None = None
    color: str | None = None
    expected_delivery_date: date | None = None
    notes: str | None = None


class AdvancePay(BaseModel):
    amount: int
    payment_mode: str = "cash"
    note: str | None = None


class AdvanceDeliver(BaseModel):
    unit_id: int
    sold_price: int | None = None
    pay_now: int = 0
    payment_mode: str = "cash"


class AdvanceCancel(BaseModel):
    refund_amount: int | None = None  # None হলে পুরো অগ্রিম ফেরত
    payment_mode: str = "cash"
    note: str | None = None


def build_advance_router(get_current_user):
    router = APIRouter()

    @router.post("/advance-orders")
    def create_order(payload: AdvanceOrderCreate, db: Session = Depends(get_db),
                     current_user=Depends(get_current_user)):
        branch_id = active_branch(current_user)
        if not branch_id:
            raise HTTPException(status_code=400, detail="অগ্রিম অর্ডার নিতে আগে একটি নির্দিষ্ট শোরুম বেছে নিন")

        customer = db.query(Party).filter(Party.id == payload.customer_id).first()
        if not customer or customer.party_type != "customer":
            raise HTTPException(status_code=404, detail="কাস্টমার পাওয়া যায়নি")
        if not db.query(Product).filter(Product.id == payload.product_id).first():
            raise HTTPException(status_code=404, detail="প্রোডাক্ট পাওয়া যায়নি")
        if payload.agreed_price <= 0:
            raise HTTPException(status_code=400, detail="মূল্য শূন্যের বেশি হতে হবে")
        if payload.advance_amount < 0 or payload.advance_amount > payload.agreed_price:
            raise HTTPException(status_code=400, detail="অগ্রিম মূল্যের বেশি বা ঋণাত্মক হতে পারে না")

        order = AdvanceOrder(
            customer_id=payload.customer_id,
            product_id=payload.product_id,
            color=(payload.color or "").strip() or None,
            agreed_price=payload.agreed_price,
            expected_delivery_date=payload.expected_delivery_date,
            notes=(payload.notes or "").strip() or None,
            status="open",
            branch_id=branch_id,
        )
        db.add(order)
        db.flush()
        if payload.advance_amount > 0:
            receive_advance(db, order, payload.advance_amount, payload.payment_mode, "প্রথম অগ্রিম")
        db.commit()
        db.refresh(order)
        return detail_dict(db, order)

    @router.get("/advance-orders")
    def list_orders(status: str | None = None, customer_id: int | None = None,
                    db: Session = Depends(get_db), current_user=Depends(get_current_user)):
        q = db.query(AdvanceOrder)
        bid = active_branch(current_user)
        if bid:
            q = q.filter(AdvanceOrder.branch_id == bid)
        if status:
            q = q.filter(AdvanceOrder.status == status)
        if customer_id:
            q = q.filter(AdvanceOrder.customer_id == customer_id)
        orders = q.order_by(AdvanceOrder.expected_delivery_date.is_(None),
                            AdvanceOrder.expected_delivery_date, AdvanceOrder.id.desc()).all()
        sums = sums_for(db, [o.id for o in orders]) if orders else {}
        lk = Lookups(db)
        return [order_dict(o, sums, lk) for o in orders]

    @router.get("/advance-orders/{order_id}")
    def get_one(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
        return detail_dict(db, get_order(db, order_id, current_user))

    @router.patch("/advance-orders/{order_id}")
    def update_order(order_id: int, payload: AdvanceOrderUpdate, db: Session = Depends(get_db),
                     current_user=Depends(get_current_user)):
        order = get_order(db, order_id, current_user)
        require_open(order)
        data = payload.dict(exclude_unset=True)
        if data.get("agreed_price") is not None:
            held = held_of(sums_for(db, [order.id]).get(order.id, {}))
            if data["agreed_price"] <= 0 or data["agreed_price"] < held:
                raise HTTPException(status_code=400, detail="মূল্য শূন্য বা এখন পর্যন্ত জমা অগ্রিমের চেয়ে কম হতে পারে না")
            order.agreed_price = data["agreed_price"]
        if "color" in data:
            order.color = (data["color"] or "").strip() or None
        if "expected_delivery_date" in data:
            order.expected_delivery_date = data["expected_delivery_date"]
        if "notes" in data:
            order.notes = (data["notes"] or "").strip() or None
        db.commit()
        db.refresh(order)
        return detail_dict(db, order)

    @router.post("/advance-orders/{order_id}/payments")
    def add_payment(order_id: int, payload: AdvancePay, db: Session = Depends(get_db),
                    current_user=Depends(get_current_user)):
        order = get_order(db, order_id, current_user)
        require_open(order)
        if payload.amount <= 0:
            raise HTTPException(status_code=400, detail="পরিমাণ শূন্যের বেশি হতে হবে")
        held = held_of(sums_for(db, [order.id]).get(order.id, {}))
        if held + payload.amount > order.agreed_price:
            raise HTTPException(
                status_code=400,
                detail=f"মোট অগ্রিম অর্ডারের মূল্যের বেশি হতে পারে না (আর সর্বোচ্চ ৳{order.agreed_price - held} নেওয়া যাবে)",
            )
        receive_advance(db, order, payload.amount, payload.payment_mode, (payload.note or "").strip() or None)
        db.commit()
        db.refresh(order)
        return detail_dict(db, order)

    @router.post("/advance-orders/{order_id}/deliver")
    def deliver(order_id: int, payload: AdvanceDeliver, db: Session = Depends(get_db),
                current_user=Depends(get_current_user)):
        order = get_order(db, order_id, current_user)
        require_open(order)

        unit = db.query(Unit).filter(Unit.id == payload.unit_id).first()
        if not unit:
            raise HTTPException(status_code=404, detail="ইউনিট পাওয়া যায়নি")
        if unit.status != "in_stock":
            raise HTTPException(status_code=400, detail="এই বাইক স্টকে নেই")
        if unit.product_id != order.product_id:
            raise HTTPException(status_code=400, detail="বাইকের মডেল অর্ডারের মডেলের সঙ্গে মেলেনি")
        unit_branch = unit.warehouse.branch_id if unit.warehouse else None
        if unit_branch != order.branch_id:
            raise HTTPException(status_code=400, detail="এই বাইক অন্য শোরুমের স্টকে — অর্ডারের শোরুমের বাইক দিন")

        branch_id = order.branch_id

        price = payload.sold_price if payload.sold_price is not None else order.agreed_price
        if price <= 0:
            raise HTTPException(status_code=400, detail="বিক্রয় মূল্য শূন্যের বেশি হতে হবে")

        held = held_of(sums_for(db, [order.id]).get(order.id, {}))
        if held > price:
            raise HTTPException(status_code=400, detail="জমা অগ্রিম বিক্রয় মূল্যের চেয়ে বেশি — আগে মূল্য ঠিক করুন")
        remaining = price - held
        if payload.pay_now < 0 or payload.pay_now > remaining:
            raise HTTPException(status_code=400, detail=f"এখন নেওয়া টাকা ০ থেকে ৳{remaining}-এর মধ্যে হতে হবে")
        due = remaining - payload.pay_now

        unit.status = "sold"
        unit.sold_price = price
        unit.sold_date = datetime.utcnow()
        unit.customer_id = order.customer_id

        voucher = Voucher(
            voucher_type="sale",
            narration=f"Unit #{unit.id} ({unit.chassis_no}) বিক্রয় — অগ্রিম অর্ডার #{order.id}",
            reference=unit.chassis_no,
        )
        db.add(voucher)
        db.flush()

        income = get_or_create_account(db, "Sales Income", "income", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=income.id, debit=0, credit=price))
        if held > 0:
            adv = get_or_create_account(db, ADVANCE_ACCOUNT, "advance", branch_id)
            db.add(VoucherEntry(voucher_id=voucher.id, account_id=adv.id,
                                party_id=order.customer_id, debit=held, credit=0))
            db.add(AdvancePayment(order_id=order.id, kind="applied", amount=held, payment_mode="adjust",
                                  voucher_id=voucher.id, note=f"বিক্রয় ভাউচার #{voucher.id}-এ সমন্বয়"))
        if payload.pay_now > 0:
            money = money_account(db, payload.payment_mode, branch_id)
            db.add(VoucherEntry(voucher_id=voucher.id, account_id=money.id,
                                party_id=order.customer_id, debit=payload.pay_now, credit=0))
        if due > 0:
            receivable = get_or_create_account(db, "Accounts Receivable", "receivable", branch_id)
            db.add(VoucherEntry(voucher_id=voucher.id, account_id=receivable.id,
                                party_id=order.customer_id, debit=due, credit=0))

        order.status = "delivered"
        order.unit_id = unit.id
        db.commit()

        customer = db.query(Party).filter(Party.id == order.customer_id).first()
        if customer:
            try:
                send_sms(
                    customer.phone,
                    f"প্রিয় {customer.name}, আপনার বাইক ডেলিভারি সম্পন্ন হয়েছে। মূল্য: ৳{price}, "
                    f"অগ্রিম: ৳{held}, বাকি: ৳{due}। ধন্যবাদ — Showroom ERP",
                )
            except Exception:
                pass

        prod = db.query(Product).filter(Product.id == unit.product_id).first()
        return {
            "voucher_id": voucher.id,
            "price": price,
            "advance_applied": held,
            "paid_now": payload.pay_now,
            "due": due,
            "chassis_no": unit.chassis_no,
            "engine_no": unit.engine_no,
            "model": prod.model_name if prod else None,
            "order": detail_dict(db, order),
        }

    @router.post("/advance-orders/{order_id}/cancel")
    def cancel(order_id: int, payload: AdvanceCancel, db: Session = Depends(get_db),
               current_user=Depends(get_current_user)):
        order = get_order(db, order_id, current_user)
        require_open(order)
        held = held_of(sums_for(db, [order.id]).get(order.id, {}))
        refund = held if payload.refund_amount is None else payload.refund_amount
        if refund < 0 or refund > held:
            raise HTTPException(status_code=400, detail=f"ফেরতের পরিমাণ ০ থেকে ৳{held}-এর মধ্যে হতে হবে")
        forfeited = held - refund

        if held > 0:
            adv = get_or_create_account(db, ADVANCE_ACCOUNT, "advance", order.branch_id)
            voucher = Voucher(
                voucher_type="advance",
                narration=(payload.note or "").strip() or f"অগ্রিম অর্ডার #{order.id} বাতিল",
                reference=f"adv-{order.id}",
            )
            db.add(voucher)
            db.flush()
            db.add(VoucherEntry(voucher_id=voucher.id, account_id=adv.id,
                                party_id=order.customer_id, debit=held, credit=0))
            if refund > 0:
                money = money_account(db, payload.payment_mode, order.branch_id)
                db.add(VoucherEntry(voucher_id=voucher.id, account_id=money.id,
                                    party_id=order.customer_id, debit=0, credit=refund))
                db.add(AdvancePayment(order_id=order.id, kind="refund", amount=refund,
                                      payment_mode=payload.payment_mode, voucher_id=voucher.id,
                                      note=(payload.note or "").strip() or None))
            if forfeited > 0:
                income = get_or_create_account(db, FORFEIT_ACCOUNT, "income", order.branch_id)
                db.add(VoucherEntry(voucher_id=voucher.id, account_id=income.id, debit=0, credit=forfeited))
                db.add(AdvancePayment(order_id=order.id, kind="forfeit", amount=forfeited,
                                      payment_mode="adjust", voucher_id=voucher.id,
                                      note=(payload.note or "").strip() or None))

        order.status = "cancelled"
        db.commit()
        db.refresh(order)
        return detail_dict(db, order)

    return router