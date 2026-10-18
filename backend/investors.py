"""
ইনভেস্টরদের হিসাব: জমা, উত্তোলন ও লাভ বণ্টনের খাতা।

এই খাতা আলাদা। এটা দোকানের ভাউচার, একাউন্ট ব্যালান্স বা স্টকের হিসাবে কিছু বদলায় না।
শুধু অ্যাডমিন দেখতে ও বদলাতে পারে।

main.py-র একদম শেষে এই দুটো লাইন যোগ করুন:
    from investors import build_investor_router
    app.include_router(build_investor_router(get_db, get_current_user, engine))
"""
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import Boolean, Column, Date, DateTime, ForeignKey, Integer, Numeric, String, func
from sqlalchemy.orm import Session

from models import Base


class Investor(Base):
    __tablename__ = "investors"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(150), nullable=False)
    phone = Column(String(30))
    note = Column(String(300))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class InvestorTxn(Base):
    __tablename__ = "investor_txns"

    id = Column(Integer, primary_key=True, index=True)
    investor_id = Column(Integer, ForeignKey("investors.id"), nullable=False, index=True)
    txn_type = Column(String(20), nullable=False)  # deposit | withdraw | profit
    amount = Column(Numeric(14, 2), nullable=False)
    txn_date = Column(Date, nullable=False)
    note = Column(String(300))
    created_by = Column(String(80))
    created_at = Column(DateTime, default=datetime.utcnow)


class InvestorIn(BaseModel):
    name: str
    phone: Optional[str] = None
    note: Optional[str] = None
    is_active: bool = True


class TxnIn(BaseModel):
    txn_type: str
    amount: float
    txn_date: Optional[date] = None
    note: Optional[str] = None


def build_investor_router(get_db, get_current_user, engine) -> APIRouter:
    # নতুন টেবিল দুটো না থাকলে তৈরি করে (আগের টেবিলে হাত দেয় না)
    Base.metadata.create_all(
        bind=engine, tables=[Investor.__table__, InvestorTxn.__table__]
    )
    router = APIRouter()

    def need_admin(user):
        role = (user.role.name if getattr(user, "role", None) else "") or ""
        if role.strip().lower() != "admin":
            raise HTTPException(status_code=403, detail="শুধু অ্যাডমিন ইনভেস্টরের হিসাব দেখতে বা বদলাতে পারবে")

    def sums(db: Session, investor_id: int = None):
        """{investor_id: {"deposit":x, "withdraw":y, "profit":z}}"""
        q = db.query(
            InvestorTxn.investor_id,
            InvestorTxn.txn_type,
            func.coalesce(func.sum(InvestorTxn.amount), 0),
        )
        if investor_id is not None:
            q = q.filter(InvestorTxn.investor_id == investor_id)
        out = {}
        for iid, t, total in q.group_by(InvestorTxn.investor_id, InvestorTxn.txn_type).all():
            d = out.setdefault(iid, {"deposit": 0.0, "withdraw": 0.0, "profit": 0.0})
            if t in d:
                d[t] = float(total)
        return out

    def summary(inv: Investor, s: dict):
        s = s or {"deposit": 0.0, "withdraw": 0.0, "profit": 0.0}
        return {
            "id": inv.id,
            "name": inv.name,
            "phone": inv.phone,
            "note": inv.note,
            "is_active": bool(inv.is_active),
            "total_deposit": s["deposit"],
            "total_withdraw": s["withdraw"],
            "capital": s["deposit"] - s["withdraw"],
            "total_profit": s["profit"],
        }

    @router.get("/investors")
    def list_investors(db: Session = Depends(get_db), user=Depends(get_current_user)):
        need_admin(user)
        all_sums = sums(db)
        rows = db.query(Investor).order_by(Investor.name).all()
        return [summary(i, all_sums.get(i.id)) for i in rows]

    @router.post("/investors")
    def create_investor(body: InvestorIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
        need_admin(user)
        name = (body.name or "").strip()
        if not name:
            raise HTTPException(status_code=400, detail="ইনভেস্টরের নাম লিখুন")
        inv = Investor(name=name, phone=(body.phone or "").strip() or None,
                       note=(body.note or "").strip() or None, is_active=body.is_active)
        db.add(inv)
        db.commit()
        db.refresh(inv)
        return summary(inv, None)

    @router.put("/investors/{investor_id}")
    def update_investor(investor_id: int, body: InvestorIn,
                        db: Session = Depends(get_db), user=Depends(get_current_user)):
        need_admin(user)
        inv = db.query(Investor).filter(Investor.id == investor_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="ইনভেস্টর পাওয়া যায়নি")
        name = (body.name or "").strip()
        if not name:
            raise HTTPException(status_code=400, detail="ইনভেস্টরের নাম লিখুন")
        inv.name = name
        inv.phone = (body.phone or "").strip() or None
        inv.note = (body.note or "").strip() or None
        inv.is_active = body.is_active
        db.commit()
        return summary(inv, sums(db, inv.id).get(inv.id))

    @router.get("/investors/{investor_id}/ledger")
    def ledger(investor_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
        need_admin(user)
        inv = db.query(Investor).filter(Investor.id == investor_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="ইনভেস্টর পাওয়া যায়নি")
        txns = (
            db.query(InvestorTxn)
            .filter(InvestorTxn.investor_id == investor_id)
            .order_by(InvestorTxn.txn_date, InvestorTxn.id)
            .all()
        )
        capital = 0.0
        rows = []
        for t in txns:
            amt = float(t.amount)
            if t.txn_type == "deposit":
                capital += amt
            elif t.txn_type == "withdraw":
                capital -= amt
            rows.append({
                "id": t.id,
                "txn_type": t.txn_type,
                "amount": amt,
                "txn_date": t.txn_date.isoformat(),
                "note": t.note,
                "balance": capital,
            })
        return {
            "investor": summary(inv, sums(db, investor_id).get(investor_id)),
            "txns": rows,
        }

    @router.post("/investors/{investor_id}/txns")
    def add_txn(investor_id: int, body: TxnIn,
                db: Session = Depends(get_db), user=Depends(get_current_user)):
        need_admin(user)
        inv = db.query(Investor).filter(Investor.id == investor_id).first()
        if not inv:
            raise HTTPException(status_code=404, detail="ইনভেস্টর পাওয়া যায়নি")
        if body.txn_type not in ("deposit", "withdraw", "profit"):
            raise HTTPException(status_code=400, detail="লেনদেনের ধরন ঠিক নেই")
        if body.amount is None or body.amount <= 0:
            raise HTTPException(status_code=400, detail="টাকার পরিমাণ শূন্যের বেশি হতে হবে")
        if body.txn_type == "withdraw":
            s = sums(db, investor_id).get(investor_id, {"deposit": 0.0, "withdraw": 0.0})
            capital = s["deposit"] - s["withdraw"]
            if body.amount > capital + 0.001:
                raise HTTPException(
                    status_code=400,
                    detail=f"উত্তোলন বর্তমান মূলধনের ({capital:,.2f}) চেয়ে বেশি হতে পারে না",
                )
        t = InvestorTxn(
            investor_id=investor_id,
            txn_type=body.txn_type,
            amount=body.amount,
            txn_date=body.txn_date or date.today(),
            note=(body.note or "").strip() or None,
            created_by=getattr(user, "username", None),
        )
        db.add(t)
        db.commit()
        return {"ok": True, "id": t.id}

    @router.delete("/investor-txns/{txn_id}")
    def delete_txn(txn_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
        need_admin(user)
        t = db.query(InvestorTxn).filter(InvestorTxn.id == txn_id).first()
        if not t:
            raise HTTPException(status_code=404, detail="লেনদেন পাওয়া যায়নি")
        if t.txn_type == "deposit":
            s = sums(db, t.investor_id).get(t.investor_id, {"deposit": 0.0, "withdraw": 0.0})
            if (s["deposit"] - float(t.amount)) - s["withdraw"] < -0.001:
                raise HTTPException(
                    status_code=400,
                    detail="এই জমা মুছলে মূলধন ঋণাত্মক হয়ে যাবে। আগে উত্তোলনের এন্ট্রি দেখুন",
                )
        db.delete(t)
        db.commit()
        return {"ok": True}

    return router