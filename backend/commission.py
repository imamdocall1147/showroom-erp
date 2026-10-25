from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import Session

from backend.database import Base, get_db
from backend.models import Unit, Voucher, VoucherEntry, Account

router = APIRouter()


class UnitCommission(Base):
    __tablename__ = "unit_commissions"
    id = Column(Integer, primary_key=True)
    unit_id = Column(Integer, ForeignKey("units.id"), nullable=False)
    company_id = Column(Integer, ForeignKey("parties.id"), nullable=True)
    amount = Column(Integer, nullable=False)
    status = Column(String(20), default="pending")  # pending / received
    receipt_id = Column(Integer, ForeignKey("commission_receipts.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class CommissionReceipt(Base):
    __tablename__ = "commission_receipts"
    id = Column(Integer, primary_key=True)
    company_id = Column(Integer, ForeignKey("parties.id"), nullable=True)
    received_date = Column(DateTime, default=datetime.utcnow)
    total_amount = Column(Integer, nullable=False)
    note = Column(String(255))
    voucher_id = Column(Integer, ForeignKey("vouchers.id"), nullable=True)


class CommissionIn(BaseModel):
    unit_id: int
    company_id: int | None = None
    amount: int


class ReceiptIn(BaseModel):
    company_id: int | None = None
    commission_ids: list[int]
    total_amount: int
    received_date: str | None = None
    note: str | None = None


def _get_or_create_account(db: Session, name: str, account_type: str, branch_id):
    q = db.query(Account).filter(Account.name == name)
    if branch_id is not None:
        q = q.filter(Account.branch_id == branch_id)
    account = q.first()
    if not account:
        account = Account(name=name, account_type=account_type, branch_id=branch_id)
        db.add(account)
        db.flush()
    return account


def build_commission_router(get_current_user, User):
    @router.post("/commissions")
    def add_commission(payload: CommissionIn, db: Session = Depends(get_db),
                       current_user: User = Depends(get_current_user)):
        if payload.amount <= 0:
            raise HTTPException(status_code=400, detail="কমিশনের পরিমাণ ০-এর বেশি হতে হবে")
        unit = db.query(Unit).filter(Unit.id == payload.unit_id).first()
        if not unit:
            raise HTTPException(status_code=404, detail="গাড়ি পাওয়া যায়নি")
        existing = db.query(UnitCommission).filter(
            UnitCommission.unit_id == payload.unit_id,
            UnitCommission.status == "pending").first()
        if existing:
            existing.amount = payload.amount
            existing.company_id = payload.company_id
            c = existing
        else:
            c = UnitCommission(unit_id=payload.unit_id,
                               company_id=payload.company_id,
                               amount=payload.amount)
            db.add(c)
        db.commit()
        db.refresh(c)
        return c

    @router.get("/commissions")
    def list_commissions(status: str | None = None, db: Session = Depends(get_db),
                         current_user: User = Depends(get_current_user)):
        q = db.query(UnitCommission, Unit).join(Unit, Unit.id == UnitCommission.unit_id)
        if status:
            q = q.filter(UnitCommission.status == status)
        rows = q.order_by(UnitCommission.id.desc()).all()
        return [{
            "id": c.id, "unit_id": c.unit_id, "chassis_no": u.chassis_no,
            "company_id": c.company_id, "amount": c.amount, "status": c.status,
            "receipt_id": c.receipt_id,
        } for c, u in rows]

    @router.post("/commission-receipts")
    def receive_commission(payload: ReceiptIn, db: Session = Depends(get_db),
                           current_user: User = Depends(get_current_user)):
        if payload.total_amount <= 0:
            raise HTTPException(status_code=400, detail="প্রাপ্ত টাকা ০-এর বেশি হতে হবে")
        items = db.query(UnitCommission).filter(
            UnitCommission.id.in_(payload.commission_ids),
            UnitCommission.status == "pending").all()
        if not items or len(items) != len(set(payload.commission_ids)):
            raise HTTPException(status_code=400, detail="কিছু কমিশন পাওয়া যায়নি বা আগেই গ্রহণ করা হয়েছে")

        branch_id = getattr(current_user, "branch_id", None)
        when = datetime.fromisoformat(payload.received_date) if payload.received_date else datetime.utcnow()

        voucher = Voucher(voucher_type="receipt", voucher_date=when,
                          reference="commission",
                          narration=payload.note or "কোম্পানি থেকে কমিশন প্রাপ্তি")
        db.add(voucher)
        db.flush()
        cash = _get_or_create_account(db, "Cash", "cash", branch_id)
        income = _get_or_create_account(db, "Commission Income", "income", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=cash.id,
                            party_id=payload.company_id, debit=payload.total_amount, credit=0))
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=income.id,
                            debit=0, credit=payload.total_amount))

        receipt = CommissionReceipt(company_id=payload.company_id, received_date=when,
                                    total_amount=payload.total_amount, note=payload.note,
                                    voucher_id=voucher.id)
        db.add(receipt)
        db.flush()
        for c in items:
            c.status = "received"
            c.receipt_id = receipt.id
        db.commit()
        return {"receipt_id": receipt.id, "total_amount": receipt.total_amount,
                "commissions": len(items)}

    @router.get("/commissions/report")
    def commission_report(date_from: str | None = None, date_to: str | None = None,
                          db: Session = Depends(get_db),
                          current_user: User = Depends(get_current_user)):
        q = db.query(CommissionReceipt)
        if date_from:
            q = q.filter(CommissionReceipt.received_date >= datetime.fromisoformat(date_from))
        if date_to:
            q = q.filter(CommissionReceipt.received_date <= datetime.fromisoformat(date_to + "T23:59:59"))
        received = sum(r.total_amount for r in q.all())
        pending_rows = db.query(UnitCommission).filter(UnitCommission.status == "pending").all()
        return {
            "received_in_period": received,
            "pending_total": sum(c.amount for c in pending_rows),
            "pending_count": len(pending_rows),
        }

    return router