import json
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.orm import Session
from pydantic import BaseModel
import bcrypt

from database import get_db
from models import (
    Base, User, Role, Branch, Warehouse, Brand, Product, Area, Party,
    Unit, SparePart, Account, Voucher, VoucherEntry, AdvanceOrder, SupplierOrder,
)


# ---------------------------------------------------------------
# অনুমোদনের অনুরোধ রাখার টেবিল (সার্ভার চালু হলে নিজে থেকে তৈরি হবে)
# ---------------------------------------------------------------
class ChangeRequest(Base):
    __tablename__ = "change_requests"
    id = Column(Integer, primary_key=True)
    entity = Column(String(30), nullable=False)
    action = Column(String(10), nullable=False)  # update, delete
    target_id = Column(Integer, nullable=False)
    summary = Column(String(255))
    payload = Column(Text)
    status = Column(String(12), default="pending")  # pending, approved, rejected
    requested_by = Column(Integer, nullable=False)
    requested_by_name = Column(String(100))
    requested_at = Column(DateTime, default=datetime.utcnow)
    decided_by_name = Column(String(100))
    decided_at = Column(DateTime)
    decision_note = Column(String(255))


def _changes(payload: BaseModel) -> dict:
    """শুধু যে ফিল্ডগুলো অ্যাপ থেকে পাঠানো হয়েছে সেগুলো ফেরত দেয়"""
    if hasattr(payload, "model_dump"):
        return payload.model_dump(exclude_unset=True)
    return payload.dict(exclude_unset=True)


def _clean_name(value, label: str) -> str:
    value = (value or "").strip()
    if not value:
        raise HTTPException(status_code=400, detail=f"{label} খালি রাখা যাবে না")
    return value


def _hash_password(password: str) -> str:
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে")
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _is_admin(user: User) -> bool:
    role = (user.role.name if user.role else "").strip().lower()
    return role == "admin"


def _require_admin(user: User):
    if not _is_admin(user):
        raise HTTPException(status_code=403, detail="এই কাজ শুধু অ্যাডমিন করতে পারবে")


def _branch_of_warehouse(db: Session, warehouse_id):
    w = db.query(Warehouse).filter(Warehouse.id == warehouse_id).first()
    return w.branch_id if w else None


# ---------------------------------------------------------------
# আপডেটের জন্য ডাটা মডেল (সব ফিল্ড ঐচ্ছিক)
# ---------------------------------------------------------------
class WarehouseUpdate(BaseModel):
    branch_id: int | None = None
    name: str | None = None
    location: str | None = None
    is_active: bool | None = None


class BranchUpdate(BaseModel):
    name: str | None = None
    address: str | None = None
    phone: str | None = None
    is_active: bool | None = None


class BrandUpdate(BaseModel):
    name: str | None = None


class ProductUpdate(BaseModel):
    brand_id: int | None = None
    model_name: str | None = None
    category: str | None = None
    unit_price: int | None = None
    is_active: bool | None = None


class AreaUpdate(BaseModel):
    name: str | None = None


class SparePartUpdate(BaseModel):
    name: str | None = None
    unit: str | None = None
    warehouse_id: int | None = None
    purchase_price: int | None = None
    sale_price: int | None = None


class UnitUpdate(BaseModel):
    chassis_no: str | None = None
    engine_no: str | None = None
    color: str | None = None
    year: str | None = None
    warehouse_id: int | None = None


class PartyUpdate(BaseModel):
    name: str | None = None
    phone: str | None = None
    address: str | None = None
    area_id: int | None = None
    nid_no: str | None = None


class UserUpdate(BaseModel):
    username: str | None = None
    full_name: str | None = None
    role_name: str | None = None
    is_active: bool | None = None
    branch_id: int | None = None  # null পাঠালে সব শোরুম দেখতে পারবে


class PasswordReset(BaseModel):
    new_password: str


class PasswordChange(BaseModel):
    old_password: str
    new_password: str


class DecisionNote(BaseModel):
    note: str | None = None


# ---------------------------------------------------------------
# প্রতিটি তথ্যের এডিট/ডিলিটের নিয়ম (ভুল হলে HTTPException দেয়)
# ---------------------------------------------------------------
def _upd_warehouse(db, w, ch):
    if "name" in ch:
        w.name = _clean_name(ch["name"], "গোডাউনের নাম")
    if "location" in ch:
        w.location = ch["location"]
    if ch.get("is_active") is not None:
        w.is_active = ch["is_active"]
    if ch.get("branch_id") is not None and ch["branch_id"] != w.branch_id:
        if not db.query(Branch).filter(Branch.id == ch["branch_id"]).first():
            raise HTTPException(status_code=404, detail="শাখা পাওয়া যায়নি")
        # মাল বা হিসাব থাকলে গোডাউন অন্য শোরুমে সরালে দুই শোরুমের হিসাব গুলিয়ে যাবে
        if (db.query(Unit).filter(Unit.warehouse_id == w.id).count() > 0
                or db.query(SparePart).filter(SparePart.warehouse_id == w.id).count() > 0):
            raise HTTPException(
                status_code=400,
                detail="এই গোডাউনে মাল/হিসাব আছে, তাই অন্য শোরুমে সরানো যাবে না (দুই শোরুমের হিসাব আলাদা)",
            )
        w.branch_id = ch["branch_id"]


def _del_warehouse(db, w):
    if db.query(Unit).filter(Unit.warehouse_id == w.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই গোডাউনে বাইকের হিসাব আছে, তাই মুছা যাবে না")
    if db.query(SparePart).filter(SparePart.warehouse_id == w.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই গোডাউনে স্পেয়ার পার্টস আছে, তাই মুছা যাবে না")


def _upd_branch(db, b, ch):
    if "name" in ch:
        b.name = _clean_name(ch["name"], "শাখার নাম")
    if "address" in ch:
        b.address = ch["address"]
    if "phone" in ch:
        b.phone = ch["phone"]
    if ch.get("is_active") is not None:
        b.is_active = ch["is_active"]


def _del_branch(db, b):
    if db.query(Warehouse).filter(Warehouse.branch_id == b.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই শাখার গোডাউন আছে, আগে গোডাউন সরান")
    if db.query(Account).filter(Account.branch_id == b.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই শাখার হিসাবের একাউন্ট আছে, তাই মুছা যাবে না")
    if db.query(User).filter(User.branch_id == b.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই শাখার ইউজার আছে, আগে ইউজারদের শাখা বদলান")


def _upd_brand(db, b, ch):
    if "name" in ch:
        name = _clean_name(ch["name"], "ব্র্যান্ডের নাম")
        if db.query(Brand).filter(Brand.name == name, Brand.id != b.id).first():
            raise HTTPException(status_code=400, detail="এই নামের ব্র্যান্ড আগে থেকেই আছে")
        b.name = name


def _del_brand(db, b):
    if db.query(Product).filter(Product.brand_id == b.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই ব্র্যান্ডের প্রোডাক্ট মডেল আছে, আগে সেগুলো সরান")


def _upd_product(db, p, ch):
    if "model_name" in ch:
        p.model_name = _clean_name(ch["model_name"], "মডেলের নাম")
    if "category" in ch:
        p.category = ch["category"]
    if "unit_price" in ch:
        p.unit_price = ch["unit_price"]
    if ch.get("is_active") is not None:
        p.is_active = ch["is_active"]
    if ch.get("brand_id") is not None:
        if not db.query(Brand).filter(Brand.id == ch["brand_id"]).first():
            raise HTTPException(status_code=404, detail="ব্র্যান্ড পাওয়া যায়নি")
        p.brand_id = ch["brand_id"]


def _del_product(db, p):
    if db.query(Unit).filter(Unit.product_id == p.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই মডেলের বাইক ক্রয়/বিক্রয়ের হিসাব আছে, তাই মুছা যাবে না")
    if db.query(AdvanceOrder).filter(AdvanceOrder.product_id == p.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই মডেলে অগ্রিম অর্ডার আছে, তাই মুছা যাবে না")


def _upd_area(db, a, ch):
    if "name" in ch:
        a.name = _clean_name(ch["name"], "এলাকার নাম")


def _del_area(db, a):
    if db.query(Party).filter(Party.area_id == a.id).count() > 0:
        raise HTTPException(status_code=400, detail="এই এলাকায় কাস্টমার/সাপ্লায়ার আছে, তাই মুছা যাবে না")


def _upd_party(db, p, ch):
    if "name" in ch:
        p.name = _clean_name(ch["name"], "নাম")
    if "phone" in ch:
        p.phone = ch["phone"]
    if "address" in ch:
        p.address = ch["address"]
    if "area_id" in ch:
        if ch["area_id"] is not None and not db.query(Area).filter(Area.id == ch["area_id"]).first():
            raise HTTPException(status_code=404, detail="এলাকা পাওয়া যায়নি")
        p.area_id = ch["area_id"]
    # NID কলাম মডেলে থাকলে তবেই সেভ হবে
    if "nid_no" in ch and hasattr(Party, "nid_no"):
        p.nid_no = ch["nid_no"]


def _del_party(db, p):
    used = (
        db.query(Unit).filter((Unit.customer_id == p.id) | (Unit.supplier_id == p.id)).count()
        + db.query(VoucherEntry).filter(VoucherEntry.party_id == p.id).count()
        + db.query(AdvanceOrder).filter(AdvanceOrder.customer_id == p.id).count()
    )
    if used > 0:
        raise HTTPException(status_code=400, detail="এর লেনদেনের হিসাব আছে, তাই মুছা যাবে না")


def _upd_part(db, s, ch):
    if "name" in ch:
        s.name = _clean_name(ch["name"], "পার্টসের নাম")
    if ch.get("unit"):
        s.unit = ch["unit"]
    if ch.get("purchase_price") is not None:
        s.purchase_price = ch["purchase_price"]
    if ch.get("sale_price") is not None:
        s.sale_price = ch["sale_price"]
    if ch.get("warehouse_id") is not None:
        new_branch = _branch_of_warehouse(db, ch["warehouse_id"])
        if new_branch is None:
            raise HTTPException(status_code=404, detail="গোডাউন পাওয়া যায়নি")
        if new_branch != _branch_of_warehouse(db, s.warehouse_id):
            raise HTTPException(
                status_code=400,
                detail="স্পেয়ার পার্টস অন্য শোরুমের গোডাউনে সরানো যাবে না (দুই শোরুমের হিসাব আলাদা)",
            )
        s.warehouse_id = ch["warehouse_id"]


def _del_part(db, s):
    if (s.stock_qty or 0) > 0:
        raise HTTPException(status_code=400, detail="স্টকে মাল আছে, তাই মুছা যাবে না")


def _upd_unit(db, u, ch):
    if "chassis_no" in ch:
        chassis = _clean_name(ch["chassis_no"], "চেসিস নম্বর")
        if db.query(Unit).filter(Unit.chassis_no == chassis, Unit.id != u.id).first():
            raise HTTPException(status_code=400, detail="এই চেসিস নম্বর আগে থেকেই আছে")
        u.chassis_no = chassis
    if "engine_no" in ch:
        engine = _clean_name(ch["engine_no"], "ইঞ্জিন নম্বর")
        if db.query(Unit).filter(Unit.engine_no == engine, Unit.id != u.id).first():
            raise HTTPException(status_code=400, detail="এই ইঞ্জিন নম্বর আগে থেকেই আছে")
        u.engine_no = engine
    if "color" in ch:
        u.color = ch["color"]
    if "year" in ch:
        u.year = ch["year"]
    if ch.get("warehouse_id") is not None:
        new_branch = _branch_of_warehouse(db, ch["warehouse_id"])
        if new_branch is None:
            raise HTTPException(status_code=404, detail="গোডাউন পাওয়া যায়নি")
        if new_branch != _branch_of_warehouse(db, u.warehouse_id):
            raise HTTPException(
                status_code=400,
                detail="বাইক অন্য শোরুমের গোডাউনে সরানো যাবে না (দুই শোরুমের হিসাব আলাদা)",
            )
        u.warehouse_id = ch["warehouse_id"]


def _del_unit(db, u):
    """স্টকে থাকা (অবিক্রীত) বাইকের ভুল ক্রয়-এন্ট্রি মোছে, সাথে ক্রয়ের ভাউচারও।"""
    if u.status != "in_stock" or u.customer_id is not None:
        raise HTTPException(
            status_code=400,
            detail="এই বাইক বিক্রি হয়ে গেছে, তাই মুছা যাবে না",
        )
    if db.query(AdvanceOrder).filter(AdvanceOrder.unit_id == u.id).count() > 0:
        raise HTTPException(
            status_code=400,
            detail="এই বাইক কোনো অগ্রিম অর্ডারের সাথে জড়িত, তাই মুছা যাবে না",
        )

    # সাপ্লায়ার-অর্ডারের শেষ ইউনিট মুছলে অর্ডারটা আবার চলমান হয়ে যায়
    if u.supplier_order_id:
        so = db.query(SupplierOrder).filter(SupplierOrder.id == u.supplier_order_id).first()
        if so and so.status == "completed":
            so.status = "open"

    # এই বাইকের ক্রয়ের ভাউচার (চেসিস পরে বদলালেও id দিয়ে খুঁজে পাবে)
    vouchers = (
        db.query(Voucher)
        .filter(
            Voucher.voucher_type == "purchase",
            Voucher.narration.like(f"Unit #{u.id} (%"),
        )
        .all()
    )
    ids = [v.id for v in vouchers]
    if not ids:
        return

    # বাকিতে কেনা হলে: সাপ্লায়ারকে টাকা দেওয়া হয়ে গেলে ভাউচার মুছা নিরাপদ নয়।
    # ভাউচারের নিজের "Accounts Payable" এন্ট্রি দেখে ঠিক ওই শোরুমের একাউন্ট ধরা হয়।
    entries = (
        db.query(VoucherEntry)
        .join(Account, Account.id == VoucherEntry.account_id)
        .filter(
            VoucherEntry.voucher_id.in_(ids),
            Account.name == "Accounts Payable",
            VoucherEntry.party_id.isnot(None),
        )
        .all()
    )
    for e in entries:
        rows = (
            db.query(VoucherEntry)
            .filter(
                VoucherEntry.account_id == e.account_id,
                VoucherEntry.party_id == e.party_id,
            )
            .all()
        )
        balance = sum(r.credit or 0 for r in rows) - sum(r.debit or 0 for r in rows)
        if balance - (e.credit or 0) < 0:
            raise HTTPException(
                status_code=400,
                detail="এই বাইকের বাকি টাকা সাপ্লায়ারকে আংশিক/পুরো পরিশোধ হয়ে গেছে, তাই মুছা যাবে না",
            )

    db.query(VoucherEntry).filter(VoucherEntry.voucher_id.in_(ids)).delete(
        synchronize_session=False
    )
    db.query(Voucher).filter(Voucher.id.in_(ids)).delete(synchronize_session=False)


ENTITIES = {
    "warehouse": dict(model=Warehouse, label="গোডাউন", name=lambda o: o.name,
                      update=_upd_warehouse, delete=_del_warehouse,
                      path="warehouses", schema=WarehouseUpdate),
    "branch": dict(model=Branch, label="শাখা", name=lambda o: o.name,
                   update=_upd_branch, delete=_del_branch,
                   path="branches", schema=BranchUpdate),
    "brand": dict(model=Brand, label="ব্র্যান্ড", name=lambda o: o.name,
                  update=_upd_brand, delete=_del_brand,
                  path="brands", schema=BrandUpdate),
    "product": dict(model=Product, label="প্রোডাক্ট মডেল", name=lambda o: o.model_name,
                    update=_upd_product, delete=_del_product,
                    path="products", schema=ProductUpdate),
    "area": dict(model=Area, label="এলাকা", name=lambda o: o.name,
                 update=_upd_area, delete=_del_area,
                 path="areas", schema=AreaUpdate),
    "party": dict(model=Party, label="কাস্টমার/সাপ্লায়ার", name=lambda o: o.name,
                  update=_upd_party, delete=_del_party,
                  path="parties", schema=PartyUpdate),
    "spare-part": dict(model=SparePart, label="স্পেয়ার পার্টস", name=lambda o: o.name,
                       update=_upd_part, delete=_del_part,
                       path="spare-parts", schema=SparePartUpdate),
    # বাইক ইউনিট: এডিট আছে; ডিলিট শুধু স্টকে থাকা (অবিক্রীত) বাইকের ভুল এন্ট্রির জন্য
    "unit": dict(model=Unit, label="বাইক", name=lambda o: o.chassis_no,
                 update=_upd_unit, delete=_del_unit,
                 path="units", schema=UnitUpdate),
}


def _perform(db: Session, entity: str, action: str, obj, changes: dict):
    """কাজটা আসলেই করে ফেলে (শুধু অ্যাডমিন বা অনুমোদনের পর)"""
    cfg = ENTITIES[entity]
    if action == "update":
        cfg["update"](db, obj, changes)
        db.commit()
        db.refresh(obj)
        return obj
    cfg["delete"](db, obj)
    db.delete(obj)
    db.commit()
    return {"message": f"{cfg['label']} মুছে ফেলা হয়েছে"}


def _request_change(db: Session, user: User, entity: str, action: str,
                    item_id: int, changes: dict):
    cfg = ENTITIES[entity]
    model = cfg["model"]
    obj = db.query(model).filter(model.id == item_id).first()
    if not obj:
        raise HTTPException(status_code=404, detail=f"{cfg['label']} পাওয়া যায়নি")

    # অ্যাডমিন হলে সরাসরি হয়ে যায়
    if _is_admin(user):
        return _perform(db, entity, action, obj, changes)

    # অন্য ইউজার: আগে যাচাই করে নেয় (যাতে হবেই না এমন অনুরোধ অ্যাডমিনের কাছে না যায়)
    try:
        if action == "update":
            cfg["update"](db, obj, changes)
        else:
            cfg["delete"](db, obj)
    finally:
        db.rollback()

    verb = "এডিট" if action == "update" else "মুছে ফেলা"
    summary = f"{cfg['label']} {verb}: {cfg['name'](obj)}"
    payload = json.dumps(changes, ensure_ascii=False, default=str)

    existing = (
        db.query(ChangeRequest)
        .filter(
            ChangeRequest.entity == entity,
            ChangeRequest.action == action,
            ChangeRequest.target_id == item_id,
            ChangeRequest.requested_by == user.id,
            ChangeRequest.status == "pending",
        )
        .first()
    )
    if existing:
        existing.payload = payload
        existing.summary = summary
    else:
        db.add(ChangeRequest(
            entity=entity,
            action=action,
            target_id=item_id,
            summary=summary,
            payload=payload,
            requested_by=user.id,
            requested_by_name=user.full_name or user.username,
        ))
    db.commit()
    return JSONResponse(
        status_code=202,
        content={
            "pending_approval": True,
            "message": "অ্যাডমিনের অনুমোদনের জন্য অনুরোধ পাঠানো হয়েছে",
        },
    )


def _make_patch(entity: str, schema):
    def endpoint(item_id: int, payload: schema,
                 db: Session = Depends(get_db),
                 current_user: User = Depends(_current_user_dep)):
        return _request_change(db, current_user, entity, "update", item_id, _changes(payload))
    return endpoint


def _make_delete(entity: str):
    def endpoint(item_id: int,
                 db: Session = Depends(get_db),
                 current_user: User = Depends(_current_user_dep)):
        return _request_change(db, current_user, entity, "delete", item_id, {})
    return endpoint


def _current_user_dep():
    # build_master_router() এটাকে আসল get_current_user দিয়ে বদলে দেয়
    raise RuntimeError("get_current_user সেট করা হয়নি")


def build_master_router(get_current_user):
    global _current_user_dep
    _current_user_dep = get_current_user

    router = APIRouter()

    # ------------------------------------------------------------
    # এডিট / ডিলিট রুট: অ্যাডমিনের জন্য সরাসরি, অন্যদের জন্য অনুমোদনের অনুরোধ
    # ------------------------------------------------------------
    for entity, cfg in ENTITIES.items():
        if cfg["update"] and cfg["schema"]:
            router.add_api_route(
                f"/{cfg['path']}/{{item_id}}",
                _make_patch(entity, cfg["schema"]),
                methods=["PATCH"],
                name=f"update_{entity}",
            )
        if cfg["delete"]:
            router.add_api_route(
                f"/{cfg['path']}/{{item_id}}",
                _make_delete(entity),
                methods=["DELETE"],
                name=f"delete_{entity}",
            )

    # ------------------------------------------------------------
    # অনুমোদনের অনুরোধ: তালিকা, অনুমোদন, বাতিল
    # ------------------------------------------------------------
    @router.get("/change-requests")
    def list_change_requests(status: str = "pending",
                             db: Session = Depends(get_db),
                             current_user: User = Depends(get_current_user)):
        q = db.query(ChangeRequest)
        if not _is_admin(current_user):
            q = q.filter(ChangeRequest.requested_by == current_user.id)
        if status != "all":
            q = q.filter(ChangeRequest.status == status)
        rows = q.order_by(ChangeRequest.id.desc()).limit(200).all()
        result = []
        for r in rows:
            try:
                changes = json.loads(r.payload or "{}")
            except Exception:
                changes = {}
            result.append({
                "id": r.id,
                "entity": r.entity,
                "action": r.action,
                "summary": r.summary,
                "changes": changes,
                "status": r.status,
                "requested_by_name": r.requested_by_name,
                "requested_at": r.requested_at.isoformat() if r.requested_at else None,
                "decided_by_name": r.decided_by_name,
                "decided_at": r.decided_at.isoformat() if r.decided_at else None,
                "decision_note": r.decision_note,
            })
        return result

    @router.post("/change-requests/{request_id}/approve")
    def approve_change_request(request_id: int,
                               db: Session = Depends(get_db),
                               current_user: User = Depends(get_current_user)):
        _require_admin(current_user)
        req = db.query(ChangeRequest).filter(ChangeRequest.id == request_id).first()
        if not req:
            raise HTTPException(status_code=404, detail="অনুরোধ পাওয়া যায়নি")
        if req.status != "pending":
            raise HTTPException(status_code=400, detail="এই অনুরোধের সিদ্ধান্ত আগেই হয়ে গেছে")
        cfg = ENTITIES.get(req.entity)
        if not cfg:
            raise HTTPException(status_code=400, detail="অনুরোধের ধরন অজানা")
        model = cfg["model"]
        obj = db.query(model).filter(model.id == req.target_id).first()
        if not obj:
            raise HTTPException(status_code=404, detail="যে তথ্যের জন্য অনুরোধ, সেটা আর নেই। অনুরোধটি বাতিল করুন")
        try:
            changes = json.loads(req.payload or "{}")
        except Exception:
            changes = {}
        try:
            _perform(db, req.entity, req.action, obj, changes)
        except HTTPException:
            db.rollback()
            raise
        req.status = "approved"
        req.decided_by_name = current_user.username
        req.decided_at = datetime.utcnow()
        db.commit()
        return {"message": "অনুমোদন করা হয়েছে এবং কাজটি সম্পন্ন হয়েছে"}

    @router.post("/change-requests/{request_id}/reject")
    def reject_change_request(request_id: int, payload: DecisionNote,
                              db: Session = Depends(get_db),
                              current_user: User = Depends(get_current_user)):
        _require_admin(current_user)
        req = db.query(ChangeRequest).filter(ChangeRequest.id == request_id).first()
        if not req:
            raise HTTPException(status_code=404, detail="অনুরোধ পাওয়া যায়নি")
        if req.status != "pending":
            raise HTTPException(status_code=400, detail="এই অনুরোধের সিদ্ধান্ত আগেই হয়ে গেছে")
        req.status = "rejected"
        req.decided_by_name = current_user.username
        req.decided_at = datetime.utcnow()
        req.decision_note = (payload.note or "").strip() or None
        db.commit()
        return {"message": "অনুরোধ বাতিল করা হয়েছে"}

    # ------------------------------------------------------------
    # ইউজার: শুধু অ্যাডমিন (ইউজার আইডি/নাম/রোল/শোরুম বদল, পাসওয়ার্ড রিসেট, ডিলিট)
    # ------------------------------------------------------------
    @router.patch("/users/{user_id}")
    def update_user(user_id: int, payload: UserUpdate,
                    db: Session = Depends(get_db),
                    current_user: User = Depends(get_current_user)):
        _require_admin(current_user)
        u = db.query(User).filter(User.id == user_id).first()
        if not u:
            raise HTTPException(status_code=404, detail="ইউজার পাওয়া যায়নি")
        ch = _changes(payload)
        relogin = False
        if "username" in ch:
            username = _clean_name(ch["username"], "ইউজার আইডি")
            if db.query(User).filter(User.username == username, User.id != user_id).first():
                raise HTTPException(status_code=400, detail="এই ইউজার আইডি আগে থেকেই আছে")
            if username != u.username and u.id == current_user.id:
                relogin = True
            u.username = username
        if "full_name" in ch:
            u.full_name = ch["full_name"]
        if "branch_id" in ch:
            if ch["branch_id"] is not None:
                if not db.query(Branch).filter(Branch.id == ch["branch_id"]).first():
                    raise HTTPException(status_code=404, detail="শোরুম পাওয়া যায়নি")
            if u.branch_id != ch["branch_id"] and u.id == current_user.id:
                relogin = True
            u.branch_id = ch["branch_id"]
        if ch.get("is_active") is not None:
            if u.id == current_user.id and ch["is_active"] is False:
                raise HTTPException(status_code=400, detail="নিজের একাউন্ট বন্ধ করা যাবে না")
            u.is_active = ch["is_active"]
        if ch.get("role_name"):
            role_name = ch["role_name"].strip()
            if u.id == current_user.id and role_name.lower() != "admin":
                raise HTTPException(status_code=400, detail="নিজের অ্যাডমিন রোল সরানো যাবে না")
            role = db.query(Role).filter(Role.name == role_name).first()
            if not role:
                role = Role(name=role_name)
                db.add(role)
                db.commit()
                db.refresh(role)
            u.role_id = role.id
        db.commit()
        db.refresh(u)
        return {
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "role": u.role.name if u.role else None,
            "is_active": u.is_active,
            "branch_id": u.branch_id,
            "relogin_required": relogin,
        }

    @router.post("/users/{user_id}/reset-password")
    def reset_user_password(user_id: int, payload: PasswordReset,
                            db: Session = Depends(get_db),
                            current_user: User = Depends(get_current_user)):
        _require_admin(current_user)
        u = db.query(User).filter(User.id == user_id).first()
        if not u:
            raise HTTPException(status_code=404, detail="ইউজার পাওয়া যায়নি")
        u.password_hash = _hash_password(payload.new_password)
        db.commit()
        return {"message": "পাসওয়ার্ড বদলানো হয়েছে"}

    @router.post("/users/me/change-password")
    def change_my_password(payload: PasswordChange,
                           db: Session = Depends(get_db),
                           current_user: User = Depends(get_current_user)):
        ok = bcrypt.checkpw(
            payload.old_password.encode("utf-8"),
            current_user.password_hash.encode("utf-8"),
        )
        if not ok:
            raise HTTPException(status_code=400, detail="বর্তমান পাসওয়ার্ড ভুল")
        current_user.password_hash = _hash_password(payload.new_password)
        db.commit()
        return {"message": "পাসওয়ার্ড সফলভাবে বদলানো হয়েছে"}

    @router.delete("/users/{user_id}")
    def delete_user(user_id: int, db: Session = Depends(get_db),
                    current_user: User = Depends(get_current_user)):
        _require_admin(current_user)
        if user_id == current_user.id:
            raise HTTPException(status_code=400, detail="নিজের একাউন্ট মুছা যাবে না")
        u = db.query(User).filter(User.id == user_id).first()
        if not u:
            raise HTTPException(status_code=404, detail="ইউজার পাওয়া যায়নি")
        db.delete(u)
        db.commit()
        return {"message": "ইউজার মুছে ফেলা হয়েছে"}

    return router