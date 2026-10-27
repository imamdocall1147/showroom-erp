import os

from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from sqlalchemy import text, func, or_
from pydantic import BaseModel
from datetime import datetime, timedelta, date
from jose import jwt, ExpiredSignatureError
from backend.sms_service import send_sms
from backend.advance_orders import build_advance_router
from backend.commission import build_commission_router
from backend.report_data import build_router
import os
import bcrypt
from dotenv import load_dotenv
from backend.master_data import build_master_router
from backend import challan_import

from backend.database import engine, get_db
from backend.models import (
    Base, User, Role, Company, Branch, Warehouse,
    Brand, Product, Area, Party, Unit,
    Account, Voucher, VoucherEntry, SparePart, SupplierOrder,
    StockTransfer,
    Partner,
    PartnerAdvance,
)
import logging
logging.basicConfig(level=logging.INFO)

load_dotenv()

Base.metadata.create_all(bind=engine)


def _ensure_new_columns():
    """আগের টেবিলে নতুন কলাম না থাকলে বসিয়ে নেয় (একবারই কাজ করে)"""
    from sqlalchemy import inspect as _inspect
    wanted = [
        ("parties", "father_name", "VARCHAR(150)"),
        ("parties", "reference", "VARCHAR(100)"),
        ("parties", "entry_date", "DATE"),
        ("units", "sold_by_partner_id", "INTEGER"),
        ("units", "sale_ref", "VARCHAR(100)"),
        ("advance_orders", "quantity", "INTEGER DEFAULT 1"),
        ("advance_orders", "unit_price", "INTEGER"),
        ("advance_orders", "delivered_qty", "INTEGER DEFAULT 0"),
        ("advance_orders", "delivered_value", "INTEGER DEFAULT 0"),
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

app = FastAPI(title="Showroom ERP")
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
from backend.app_update import build_update_router
app.include_router(build_update_router())
SECRET_KEY = os.getenv("SECRET_KEY")
security = HTTPBearer()


# ---------------------------------------------------------------
# শোরুম (Branch) সংক্রান্ত সহায়ক ফাংশন
# টোকেনে "branch_id" থাকে: মান থাকলে ওই শোরুম, 0 বা না থাকলে সব শোরুম।
# ---------------------------------------------------------------
def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
):
    token = credentials.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        username = payload.get("sub")
        if username is None:
            raise HTTPException(status_code=401, detail="টোকেন অবৈধ")
    except ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="লগইনের মেয়াদ শেষ, আবার লগইন করুন")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="টোকেন অবৈধ")

    user = db.query(User).filter(User.username == username).first()
    if not user:
        raise HTTPException(status_code=401, detail="ইউজার পাওয়া যায়নি")

    # এই অনুরোধের সক্রিয় শোরুম (None = সব শোরুম)
    user.active_branch_id = payload.get("branch_id") or None
    return user


def scope_branch(user):
    """সক্রিয় শোরুমের id। None মানে সব শোরুম।"""
    return getattr(user, "active_branch_id", None)


def require_branch(user) -> int:
    """যে কাজে নির্দিষ্ট শোরুম লাগে (খরচ, আদায়, পরিশোধ ইত্যাদি)।"""
    bid = scope_branch(user)
    if not bid:
        raise HTTPException(status_code=400, detail="এই কাজের জন্য আগে একটি নির্দিষ্ট শোরুম বেছে নিন")
    return bid


def allowed_branches(db: Session, user):
    q = db.query(Branch)
    if user.branch_id:
        q = q.filter(Branch.id == user.branch_id)
    return q.order_by(Branch.id).all()


def make_token(user, branch_id):
    token_data = {
        "sub": user.username,
        "role": user.role.name if user.role else None,
        "branch_id": branch_id or 0,
        "exp": datetime.utcnow() + timedelta(hours=12),
    }
    return jwt.encode(token_data, SECRET_KEY, algorithm="HS256")


def branches_payload(db: Session, user):
    return [{"id": b.id, "name": b.name} for b in allowed_branches(db, user)]


def units_query(db: Session, bid):
    q = db.query(Unit)
    if bid:
        q = q.join(Warehouse, Unit.warehouse_id == Warehouse.id).filter(Warehouse.branch_id == bid)
    return q


def spare_parts_query(db: Session, bid):
    q = db.query(SparePart)
    if bid:
        q = q.join(Warehouse, SparePart.warehouse_id == Warehouse.id).filter(Warehouse.branch_id == bid)
    return q


def accounts_in_scope(db: Session, name: str, bid):
    q = db.query(Account).filter(Account.name == name)
    if bid:
        q = q.filter(Account.branch_id == bid)
    return q.all()


def account_ids_in_scope(db: Session, name: str, bid):
    return [a.id for a in accounts_in_scope(db, name, bid)]


app.include_router(build_router(get_current_user))

app.include_router(build_advance_router(get_current_user))
app.include_router(build_commission_router(get_current_user, User))

app.include_router(build_master_router(get_current_user))
class ChallanUrlIn(BaseModel):
    url: str

@app.post("/challan/preview")
def challan_preview(body: ChallanUrlIn, current_user=Depends(get_current_user)):
    try:
        return challan_import.import_from_url(body.url)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="চালান নামানো বা পড়া যায়নি")


@app.head("/")
def head_root():
    return {}

@app.get("/")
def root():
    return {"message": "Showroom ERP API চলছে"}


@app.get("/health/db")
def db_check(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        return {"db": "connected"}
    except Exception as e:
        return {"db": "error", "detail": str(e)}


class UserCreate(BaseModel):
    username: str
    password: str
    full_name: str
    role_name: str
    branch_id: int | None = None  # খালি = সব শোরুম


class LoginRequest(BaseModel):
    username: str
    password: str


class SwitchBranchRequest(BaseModel):
    branch_id: int  # 0 = সব শোরুম (শুধু যার সব শোরুমের অধিকার আছে)


@app.get("/users")
def list_users(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    users = db.query(User).all()
    return [
        {
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "role": u.role.name if u.role else None,
            "branch_id": u.branch_id,
        }
        for u in users
    ]


@app.post("/users/register")
def register_user(payload: UserCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    existing = db.query(User).filter(User.username == payload.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="এই ইউজারনেম আগে থেকেই আছে")

    if payload.branch_id:
        if not db.query(Branch).filter(Branch.id == payload.branch_id).first():
            raise HTTPException(status_code=404, detail="শোরুম পাওয়া যায়নি")

    role = db.query(Role).filter(Role.name == payload.role_name).first()
    if not role:
        role = Role(name=payload.role_name)
        db.add(role)
        db.commit()
        db.refresh(role)

    password_hash = bcrypt.hashpw(payload.password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

    new_user = User(
        username=payload.username,
        password_hash=password_hash,
        full_name=payload.full_name,
        role_id=role.id,
        branch_id=payload.branch_id or None,
    )
    db.add(new_user)
    db.commit()
    return {"message": "ইউজার তৈরি হয়েছে", "username": new_user.username}


@app.post("/login")
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == payload.username).first()
    if not user or not bcrypt.checkpw(payload.password.encode("utf-8"), user.password_hash.encode("utf-8")):
        raise HTTPException(status_code=401, detail="ভুল ইউজারনেম বা পাসওয়ার্ড")

    branches = allowed_branches(db, user)
    if user.branch_id:
        active = user.branch_id
    else:
        active = branches[0].id if branches else 0

    return {
        "access_token": make_token(user, active),
        "token_type": "bearer",
        "role": user.role.name,
        "branch_id": active,
        "branches": [{"id": b.id, "name": b.name} for b in branches],
        "can_view_all": user.branch_id is None,
    }


@app.post("/auth/switch-branch")
def switch_branch(payload: SwitchBranchRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if payload.branch_id == 0:
        if current_user.branch_id:
            raise HTTPException(status_code=403, detail="আপনার সব শোরুম দেখার অনুমতি নেই")
        target = 0
    else:
        branch = db.query(Branch).filter(Branch.id == payload.branch_id).first()
        if not branch:
            raise HTTPException(status_code=404, detail="শোরুম পাওয়া যায়নি")
        if current_user.branch_id and current_user.branch_id != payload.branch_id:
            raise HTTPException(status_code=403, detail="এই শোরুমে আপনার প্রবেশাধিকার নেই")
        target = payload.branch_id

    return {
        "access_token": make_token(current_user, target),
        "token_type": "bearer",
        "role": current_user.role.name if current_user.role else None,
        "branch_id": target,
        "branches": branches_payload(db, current_user),
        "can_view_all": current_user.branch_id is None,
    }


class CompanyCreate(BaseModel):
    name: str
    address: str | None = None
    phone: str | None = None


class BranchCreate(BaseModel):
    company_id: int
    name: str
    address: str | None = None
    phone: str | None = None


class WarehouseCreate(BaseModel):
    branch_id: int
    name: str
    location: str | None = None


@app.post("/companies")
def create_company(payload: CompanyCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    company = Company(name=payload.name, address=payload.address, phone=payload.phone)
    db.add(company)
    db.commit()
    db.refresh(company)
    return company


@app.get("/companies")
def list_companies(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return db.query(Company).all()


@app.post("/branches")
def create_branch(payload: BranchCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    _branch_admin(current_user)
    company = db.query(Company).filter(Company.id == payload.company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="কোম্পানি পাওয়া যায়নি")
    branch = Branch(
        company_id=payload.company_id,
        name=payload.name,
        address=payload.address,
        phone=payload.phone,
    )
    db.add(branch)
    db.commit()
    db.refresh(branch)
    return branch


@app.get("/branches")
def list_branches(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return allowed_branches(db, current_user)


@app.post("/warehouses")
def create_warehouse(payload: WarehouseCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    branch = db.query(Branch).filter(Branch.id == payload.branch_id).first()
    if not branch:
        raise HTTPException(status_code=404, detail="শাখা পাওয়া যায়নি")
    warehouse = Warehouse(
        branch_id=payload.branch_id,
        name=payload.name,
        location=payload.location,
    )
    db.add(warehouse)
    db.commit()
    db.refresh(warehouse)
    return warehouse


@app.get("/warehouses")
def list_warehouses(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    q = db.query(Warehouse)
    if bid:
        q = q.filter(Warehouse.branch_id == bid)
    return q.all()


class BrandCreate(BaseModel):
    name: str


class ProductCreate(BaseModel):
    brand_id: int
    model_name: str
    category: str | None = None
    unit_price: int | None = None


class AreaCreate(BaseModel):
    name: str


class PartyCreate(BaseModel):
    name: str
    party_type: str
    phone: str | None = None
    address: str | None = None
    area_id: int | None = None


@app.post("/brands")
def create_brand(payload: BrandCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    brand = Brand(name=payload.name)
    db.add(brand)
    db.commit()
    db.refresh(brand)
    return brand


@app.get("/brands")
def list_brands(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return db.query(Brand).all()


@app.post("/products")
def create_product(payload: ProductCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    brand = db.query(Brand).filter(Brand.id == payload.brand_id).first()
    if not brand:
        raise HTTPException(status_code=404, detail="ব্র্যান্ড পাওয়া যায়নি")
    product = Product(
        brand_id=payload.brand_id,
        model_name=payload.model_name,
        category=payload.category,
        unit_price=payload.unit_price,
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


@app.get("/products")
def list_products(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return db.query(Product).all()


@app.post("/areas")
def create_area(payload: AreaCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    area = Area(name=payload.name)
    db.add(area)
    db.commit()
    db.refresh(area)
    return area


@app.get("/areas")
def list_areas(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return db.query(Area).all()


@app.post("/parties")
def create_party(payload: PartyCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    if payload.party_type not in ("customer", "supplier"):
        raise HTTPException(status_code=400, detail="party_type অবশ্যই 'customer' বা 'supplier' হতে হবে")
    party = Party(
        name=payload.name,
        party_type=payload.party_type,
        phone=payload.phone,
        address=payload.address,
        area_id=payload.area_id,
    )
    db.add(party)
    db.commit()
    db.refresh(party)
    return party


@app.get("/parties")
def list_parties(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    # কাস্টমার ও সাপ্লায়ারের তালিকা দুই শোরুমে এক
    return db.query(Party).all()


def parse_entry_date(value):
    """'YYYY-MM-DD' থেকে datetime; খালি হলে এখনকার সময়। ভবিষ্যৎ তারিখ বন্ধ।"""
    if not value:
        return datetime.utcnow()
    try:
        d = datetime.strptime(value[:10], "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail="তারিখের ফরম্যাট ভুল (YYYY-MM-DD)")
    now = datetime.utcnow()
    if d.date() > now.date():
        raise HTTPException(status_code=400, detail="ভবিষ্যতের তারিখ দেওয়া যাবে না")
    if d.date() == now.date():
        return now
    return d.replace(hour=12)


class UnitPurchaseCreate(BaseModel):
    gate_pass_no: str | None = None  # গেট পাস নম্বর (ঐচ্ছিক)
    product_id: int
    warehouse_id: int
    chassis_no: str
    engine_no: str
    color: str | None = None
    year: str | None = None
    purchase_price: int
    purchase_date: str | None = None
    supplier_id: int | None = None
    payment_mode: str = "cash"
    advance_used: int = 0  # এই সাপ্লায়ারকে আগে দেওয়া অগ্রিম থেকে যত টাকা কাটা হবে
    order_id: int | None = None  # সাপ্লায়ার-অর্ডারের আওতায় এলে অর্ডারের id


class UnitSellRequest(BaseModel):
    sold_price: int                 # শুধু বাইকের মূল্য
    customer_id: int
    payment_mode: str = "cash"
    decoration_cost: int = 0        # ডেকোরেশন খরচ
    registration_cost: int = 0      # রেজিস্ট্রেশন খরচ
    paid_amount: int | None = None  # বাকিতে বিক্রয়ে এখন যত টাকা জমা নেওয়া হচ্ছে
    partner_id: int | None = None   # কোন পার্টনারের বিক্রয় (তার হিসাব থেকে বাদ যাবে)
    sale_date: str | None = None


class BrtaUpdate(BaseModel):
    brta_status: str
    brta_reg_no: str | None = None
    brta_submission_date: datetime | None = None
    brta_completion_date: datetime | None = None
    brta_notes: str | None = None


@app.patch("/units/{unit_id}/brta")
def update_brta(unit_id: int, payload: BrtaUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    unit = db.query(Unit).filter(Unit.id == unit_id).first()
    if not unit:
        raise HTTPException(status_code=404, detail="ইউনিট পাওয়া যায়নি")

    valid_statuses = ("not_started", "submitted", "in_process", "completed")
    if payload.brta_status not in valid_statuses:
        raise HTTPException(status_code=400, detail="brta_status অবৈধ")

    unit.brta_status = payload.brta_status
    unit.brta_reg_no = payload.brta_reg_no
    unit.brta_submission_date = payload.brta_submission_date
    unit.brta_completion_date = payload.brta_completion_date
    unit.brta_notes = payload.brta_notes
    db.commit()
    db.refresh(unit)
    return unit


@app.get("/reports/brta-status")
def brta_status_report(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    units = units_query(db, bid).filter(Unit.status == "sold").all()
    result = []
    for u in units:
        customer = db.query(Party).filter(Party.id == u.customer_id).first() if u.customer_id else None
        result.append({
            "unit_id": u.id,
            "chassis_no": u.chassis_no,
            "engine_no": u.engine_no,
            "model": u.product.model_name if u.product else None,
            "brand": u.product.brand.name if u.product and u.product.brand else None,
            "customer_name": customer.name if customer else None,
            "customer_phone": customer.phone if customer else None,
            "customer_address": customer.address if customer else None,
            "customer_area": customer.area.name if customer and customer.area else None,
            "customer_father": customer.father_name if customer else None,
            "sold_price": u.sold_price,
            "color": u.color,
            "year": u.year,
            "sold_date": u.sold_date,
            "brta_status": u.brta_status,
            "brta_reg_no": u.brta_reg_no,
            "brta_submission_date": u.brta_submission_date,
            "brta_completion_date": u.brta_completion_date,
            "brta_notes": u.brta_notes,
        })
    return {"units": result}


def supplier_advance_balances(db: Session, bid):
    """সাপ্লায়ার অনুযায়ী অগ্রিমের ব্যালান্স (দেওয়া − ক্রয়ে কাটা), সক্রিয় শোরুমের একাউন্টে"""
    ids = account_ids_in_scope(db, "Supplier Advances", bid)
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
    return {pid: int(d) - int(c) for pid, d, c in rows}


def get_or_create_account(db: Session, name: str, account_type: str, branch_id: int | None = None) -> Account:
    """প্রতিটি শোরুমের নিজস্ব একাউন্ট। branch_id দিলে ওই শোরুমের একাউন্ট খোঁজে/বানায়।"""
    q = db.query(Account).filter(Account.name == name)
    if branch_id is not None:
        q = q.filter(Account.branch_id == branch_id)
    account = q.order_by(Account.id).first()
    if not account:
        account = Account(name=name, account_type=account_type, branch_id=branch_id)
        db.add(account)
        db.commit()
        db.refresh(account)
    return account


@app.post("/units/purchase")
def purchase_unit(payload: UnitPurchaseCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    existing = db.query(Unit).filter(
        (Unit.chassis_no == payload.chassis_no) | (Unit.engine_no == payload.engine_no)
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="এই চেসিস বা ইঞ্জিন নম্বর আগে থেকেই আছে")

    product = db.query(Product).filter(Product.id == payload.product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="প্রোডাক্ট পাওয়া যায়নি")

    warehouse = db.query(Warehouse).filter(Warehouse.id == payload.warehouse_id).first()
    if not warehouse:
        raise HTTPException(status_code=404, detail="গোডাউন পাওয়া যায়নি")

    bid = scope_branch(current_user)
    if bid and warehouse.branch_id != bid:
        raise HTTPException(status_code=400, detail="এই গোডাউন অন্য শোরুমের")
    branch_id = warehouse.branch_id

    if payload.payment_mode not in ("cash", "due"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'due' হতে হবে")
    if payload.payment_mode == "due" and not payload.supplier_id:
        raise HTTPException(status_code=400, detail="বাকিতে ক্রয় করতে সাপ্লায়ার আবশ্যক")

    advance_used = payload.advance_used or 0
    if advance_used < 0:
        raise HTTPException(status_code=400, detail="অগ্রিমের পরিমাণ ঋণাত্মক হতে পারবে না")
    if advance_used > 0:
        if not payload.supplier_id:
            raise HTTPException(status_code=400, detail="অগ্রিম কাটতে সাপ্লায়ার বেছে নিন")
        available = supplier_advance_balances(db, branch_id).get(payload.supplier_id, 0)
        if advance_used > available:
            raise HTTPException(status_code=400, detail=f"এই সাপ্লায়ারের অগ্রিম আছে মাত্র ৳{available}")
        if advance_used > payload.purchase_price:
            raise HTTPException(status_code=400, detail="অগ্রিম ক্রয় মূল্যের বেশি কাটা যাবে না")
    remainder = payload.purchase_price - advance_used

    order = None
    received_before = 0
    if payload.order_id:
        order = db.query(SupplierOrder).filter(SupplierOrder.id == payload.order_id).first()
        if not order:
            raise HTTPException(status_code=404, detail="অর্ডার পাওয়া যায়নি")
        if order.status != "open":
            raise HTTPException(status_code=400, detail="এই অর্ডার আর চলমান নেই")
        if order.branch_id != branch_id:
            raise HTTPException(status_code=400, detail="এই অর্ডার অন্য শোরুমের")
        if order.supplier_id != payload.supplier_id:
            raise HTTPException(status_code=400, detail="অর্ডারের সাপ্লায়ারের সঙ্গে মেলেনি")
        if order.product_id != payload.product_id:
            raise HTTPException(status_code=400, detail="অর্ডারের মডেলের সঙ্গে মেলেনি")
        received_before = db.query(Unit).filter(Unit.supplier_order_id == order.id).count()
        if received_before >= order.qty:
            raise HTTPException(status_code=400, detail="এই অর্ডারের সব ইউনিট আগেই এসে গেছে")

    entry_dt = parse_entry_date(payload.purchase_date)
    unit = Unit(
        product_id=payload.product_id,
        warehouse_id=payload.warehouse_id,
        chassis_no=payload.chassis_no,
        engine_no=payload.engine_no,
        color=payload.color,
        year=payload.year,
        purchase_price=payload.purchase_price,
        supplier_id=payload.supplier_id,
        supplier_order_id=order.id if order else None,
        gate_pass_no=(payload.gate_pass_no or "").strip() or None,
        purchase_date=entry_dt,
        status="in_stock",
    )
    db.add(unit)
    if order and received_before + 1 >= order.qty:
        order.status = "completed"
    db.commit()
    db.refresh(unit)

    purchase_expense_account = get_or_create_account(db, "Inventory Purchase", "expense", branch_id)
    credit_account_name = "Cash" if payload.payment_mode == "cash" else "Accounts Payable"
    credit_account_type = "cash" if payload.payment_mode == "cash" else "payable"
    credit_account = get_or_create_account(db, credit_account_name, credit_account_type, branch_id)

    # নারেশনের "Unit #<id> (" অংশ বাইক মোছার সময় ভাউচার খুঁজতে কাজে লাগে — বদলাবেন না
    voucher = Voucher(
        voucher_type="purchase",
        narration=f"Unit #{unit.id} ({unit.chassis_no}) ক্রয়",
        reference=unit.chassis_no,
        voucher_date=entry_dt,
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    db.add(VoucherEntry(voucher_id=voucher.id, account_id=purchase_expense_account.id, debit=payload.purchase_price, credit=0))
    if advance_used > 0:
        adv_account = get_or_create_account(db, "Supplier Advances", "advance_paid", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=adv_account.id, party_id=payload.supplier_id, debit=0, credit=advance_used))
    if remainder > 0:
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=credit_account.id, party_id=payload.supplier_id, debit=0, credit=remainder))
    db.commit()
    db.refresh(unit)
    return unit


@app.get("/units/search")
def search_units(q: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """ইঞ্জিন বা চেসিস নম্বর (অংশ লিখলেও চলবে) দিয়ে বাইক খোঁজা: কোন শোরুমে, কার কাছে, কবে বিক্রি সহ।
    সব শোরুমেই খোঁজে (শুধু যার একটা নির্দিষ্ট শোরুমের অধিকার, সে নিজের শোরুমেরটা দেখে)।"""
    term = (q or "").strip()
    if len(term) < 3:
        raise HTTPException(status_code=400, detail="অন্তত ৩টা অক্ষর বা সংখ্যা লিখুন")

    # স্পেস ও হাইফেন বাদ দিয়েও মেলানো হয় (যেমন "ME4-JC" লিখলে "ME4JC..."-ও পাওয়া যায়)
    clean = term.replace(" ", "").replace("-", "")
    like = f"%{term}%"
    clean_like = f"%{clean}%"

    def stripped(col):
        return func.replace(func.replace(col, "-", ""), " ", "")

    query = db.query(Unit).filter(or_(
        Unit.chassis_no.ilike(like),
        Unit.engine_no.ilike(like),
        stripped(Unit.chassis_no).ilike(clean_like),
        stripped(Unit.engine_no).ilike(clean_like),
    ))
    if current_user.branch_id:
        query = query.join(Warehouse, Unit.warehouse_id == Warehouse.id).filter(
            Warehouse.branch_id == current_user.branch_id
        )
    units = query.order_by(Unit.id.desc()).limit(30).all()

    branch_names = {b.id: b.name for b in db.query(Branch).all()}
    local = timedelta(hours=6)  # ডাটাবেসে সময় UTC, বাংলাদেশ = UTC+6

    def fmt(dt, with_time=False):
        if not dt:
            return None
        return (dt + local).strftime("%Y-%m-%d %H:%M" if with_time else "%Y-%m-%d")

    result = []
    for u in units:
        customer = db.query(Party).filter(Party.id == u.customer_id).first() if u.customer_id else None
        supplier = db.query(Party).filter(Party.id == u.supplier_id).first() if u.supplier_id else None
        branch_id = u.warehouse.branch_id if u.warehouse else None

        sale_voucher_id = None
        paid_at_sale = None
        due_at_sale = None
        total_price = None
        if u.status == "sold":
            total_price = (u.sold_price or 0) + (u.decoration_cost or 0) + (u.registration_cost or 0)
            v = (
                db.query(Voucher)
                .filter(Voucher.voucher_type == "sale", Voucher.reference == u.chassis_no)
                .order_by(Voucher.id)
                .first()
            )
            if v:
                sale_voucher_id = v.id
                due_at_sale = (
                    db.query(func.coalesce(func.sum(VoucherEntry.debit), 0))
                    .join(Account, Account.id == VoucherEntry.account_id)
                    .filter(VoucherEntry.voucher_id == v.id, Account.name == "Accounts Receivable")
                    .scalar()
                )
                due_at_sale = int(due_at_sale or 0)
                paid_at_sale = max(total_price - due_at_sale, 0)

        result.append({
            "unit_id": u.id,
            "chassis_no": u.chassis_no,
            "engine_no": u.engine_no,
            "brand": u.product.brand.name if u.product and u.product.brand else None,
            "model": u.product.model_name if u.product else None,
            "color": u.color,
            "year": u.year,
            "gate_pass_no": u.gate_pass_no,
            "status": u.status,
            "showroom": branch_names.get(branch_id),
            "warehouse": u.warehouse.name if u.warehouse else None,
            "purchase_date": fmt(u.purchase_date),
            "purchase_price": u.purchase_price,
            "supplier_name": supplier.name if supplier else None,
            "sold_date": fmt(u.sold_date, with_time=True),
            "sold_price": u.sold_price,
            "decoration_cost": u.decoration_cost or 0,
            "registration_cost": u.registration_cost or 0,
            "total_price": total_price,
            "customer_name": customer.name if customer else None,
            "customer_phone": customer.phone if customer else None,
            "customer_address": customer.address if customer else None,
            "customer_area": customer.area.name if customer and customer.area else None,
            "invoice_no": sale_voucher_id,
            "paid_at_sale": paid_at_sale,
            "due_at_sale": due_at_sale,
            "brta_status": u.brta_status,
            "brta_reg_no": u.brta_reg_no,
        })
    return result


@app.get("/units")
def list_units(status: str | None = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    query = units_query(db, bid)
    if status:
        query = query.filter(Unit.status == status)
    return query.all()


@app.get("/units/{unit_id}")
def get_unit(unit_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    unit = db.query(Unit).filter(Unit.id == unit_id).first()
    if not unit:
        raise HTTPException(status_code=404, detail="ইউনিট পাওয়া যায়নি")
    return unit


@app.post("/units/{unit_id}/sell")
def sell_unit(unit_id: int, payload: UnitSellRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    unit = db.query(Unit).filter(Unit.id == unit_id).first()
    if not unit:
        raise HTTPException(status_code=404, detail="ইউনিট পাওয়া যায়নি")
    if unit.status == "sold":
        raise HTTPException(status_code=400, detail="এই ইউনিট আগেই বিক্রি হয়ে গেছে")
    if payload.payment_mode not in ("cash", "due"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'due' হতে হবে")
    if payload.decoration_cost < 0 or payload.registration_cost < 0:
        raise HTTPException(status_code=400, detail="খরচের পরিমাণ ঋণাত্মক হতে পারবে না")

    # বাইকের গোডাউন যে শোরুমের, বিক্রয়ের হিসাবও সেই শোরুমে যাবে
    branch_id = unit.warehouse.branch_id if unit.warehouse else None
    bid = scope_branch(current_user)
    if bid and branch_id != bid:
        raise HTTPException(status_code=400, detail="এই ইউনিট অন্য শোরুমের")

    bike_price = payload.sold_price
    decoration = payload.decoration_cost
    registration = payload.registration_cost
    total_price = bike_price + decoration + registration

    # জমা: নগদে পুরো টাকা। বাকিতে যতটুকু এখন নেওয়া হচ্ছে সেটা জমা, বাকিটা Accounts Receivable-এ।
    if payload.payment_mode == "cash":
        paid_now = total_price
    else:
        paid_now = payload.paid_amount or 0
        if paid_now < 0:
            raise HTTPException(status_code=400, detail="জমার পরিমাণ ঋণাত্মক হতে পারবে না")
        if paid_now >= total_price:
            raise HTTPException(status_code=400, detail="জমা মোট মূল্যের কম হতে হবে। পুরো টাকা নিলে 'নগদ' বেছে নিন")
    due_amount = total_price - paid_now

    entry_dt = parse_entry_date(payload.sale_date)
    unit.status = "sold"
    unit.sold_price = bike_price
    unit.decoration_cost = decoration
    unit.registration_cost = registration
    unit.sold_date = entry_dt
    unit.customer_id = payload.customer_id
    unit.sold_by_partner_id = payload.partner_id

    income_account = get_or_create_account(db, "Sales Income", "income", branch_id)

    voucher = Voucher(
        voucher_type="sale",
        narration=f"Unit #{unit.id} ({unit.chassis_no}) বিক্রয়",
        reference=unit.chassis_no,
        voucher_date=entry_dt,
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    # ডেবিট: মোট টাকা (বাইক + ডেকোরেশন + রেজিস্ট্রেশন) = এখন জমা (ক্যাশ) + বাকি (Accounts Receivable)
    if paid_now > 0:
        cash_account = get_or_create_account(db, "Cash", "cash", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=cash_account.id, party_id=payload.customer_id, debit=paid_now, credit=0))
    if due_amount > 0:
        receivable_account = get_or_create_account(db, "Accounts Receivable", "receivable", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=receivable_account.id, party_id=payload.customer_id, debit=due_amount, credit=0))
    # ক্রেডিট: প্রতিটি অংশ আলাদা আয়ের একাউন্টে
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=income_account.id, debit=0, credit=bike_price))
    if decoration > 0:
        deco_account = get_or_create_account(db, "Decoration Income", "income", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=deco_account.id, debit=0, credit=decoration))
    if registration > 0:
        reg_account = get_or_create_account(db, "Registration Income", "income", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=reg_account.id, debit=0, credit=registration))
    db.commit()

    customer = db.query(Party).filter(Party.id == payload.customer_id).first()
    if customer:
        if due_amount > 0:
            sms_text = (f"প্রিয় {customer.name}, আপনার বাইক ক্রয় সম্পন্ন হয়েছে। মোট মূল্য: ৳{total_price}, "
                        f"জমা: ৳{paid_now}, বাকি: ৳{due_amount}। ধন্যবাদ — Showroom ERP")
        else:
            sms_text = f"প্রিয় {customer.name}, আপনার বাইক ক্রয় সম্পন্ন হয়েছে। মোট মূল্য: ৳{total_price}। ধন্যবাদ — Showroom ERP"
        send_sms(customer.phone, sms_text)

    db.refresh(unit)
    return {
        "unit": unit,
        "voucher_id": voucher.id,
        "bike_price": bike_price,
        "decoration_cost": decoration,
        "registration_cost": registration,
        "total_price": total_price,
        "paid_amount": paid_now,
        "due_amount": due_amount,
    }


class DecorationIncomeRequest(BaseModel):
    amount: int
    customer_id: int | None = None
    payment_mode: str = "cash"
    note: str | None = None


@app.post("/decoration-income")
def add_decoration_income(payload: DecorationIncomeRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    branch_id = require_branch(current_user)

    if payload.amount <= 0:
        raise HTTPException(status_code=400, detail="টাকার পরিমাণ ০-এর বেশি হতে হবে")
    if payload.payment_mode not in ("cash", "due"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'due' হতে হবে")
    if payload.payment_mode == "due" and not payload.customer_id:
        raise HTTPException(status_code=400, detail="বাকিতে হলে কাস্টমার দিতে হবে")

    customer = None
    if payload.customer_id:
        customer = db.query(Party).filter(Party.id == payload.customer_id).first()
        if not customer:
            raise HTTPException(status_code=404, detail="কাস্টমার পাওয়া যায়নি")

    debit_name = "Cash" if payload.payment_mode == "cash" else "Accounts Receivable"
    debit_type = "cash" if payload.payment_mode == "cash" else "receivable"
    debit_account = get_or_create_account(db, debit_name, debit_type, branch_id)
    deco_account = get_or_create_account(db, "Decoration Income", "income", branch_id)

    narration = "ডেকোরেশন আয়"
    if payload.note:
        narration += f" - {payload.note}"

    voucher = Voucher(voucher_type="sale", narration=narration, reference="decoration")
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    db.add(VoucherEntry(voucher_id=voucher.id, account_id=debit_account.id,
                        party_id=payload.customer_id, debit=payload.amount, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=deco_account.id,
                        debit=0, credit=payload.amount))
    db.commit()

    if customer:
        send_sms(
            customer.phone,
            f"প্রিয় {customer.name}, ডেকোরেশন বাবদ ৳{payload.amount} গ্রহণ করা হয়েছে। ধন্যবাদ — Showroom ERP",
        )

    return {"voucher_id": voucher.id, "amount": payload.amount}


@app.get("/accounts")
def list_accounts(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    q = db.query(Account)
    if bid:
        q = q.filter(Account.branch_id == bid)
    accounts = q.order_by(Account.id).all()

    branch_names = {b.id: b.name for b in db.query(Branch).all()}
    result = []
    for a in accounts:
        name = a.name
        # সব শোরুম দেখার সময় কোন শোরুমের একাউন্ট তা নামের সাথে দেখায়
        if not bid and a.branch_id in branch_names:
            name = f"{a.name} — {branch_names[a.branch_id]}"
        result.append({
            "id": a.id,
            "name": name,
            "account_type": a.account_type,
            "is_active": a.is_active,
            "branch_id": a.branch_id,
        })
    return result


@app.get("/accounts/{account_id}/balance")
def get_account_balance(account_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="অ্যাকাউন্ট পাওয়া যায়নি")

    entries = db.query(VoucherEntry).filter(VoucherEntry.account_id == account_id).all()
    total_debit = sum(e.debit for e in entries)
    total_credit = sum(e.credit for e in entries)
    return {
        "account": account.name,
        "account_type": account.account_type,
        "total_debit": total_debit,
        "total_credit": total_credit,
        "balance": total_debit - total_credit,
    }


class PaymentRequest(BaseModel):
    amount: int
    expense_account_name: str
    payment_mode: str = "cash"
    narration: str | None = None


class ReceiptRequest(BaseModel):
    amount: int
    customer_id: int
    payment_mode: str = "cash"
    narration: str | None = None


@app.post("/payments")
def make_payment(payload: PaymentRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    branch_id = require_branch(current_user)
    if payload.payment_mode not in ("cash", "bank"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'bank' হতে হবে")

    expense_account = get_or_create_account(db, payload.expense_account_name, "expense", branch_id)
    credit_account_name = "Cash" if payload.payment_mode == "cash" else "Bank"
    credit_account = get_or_create_account(db, credit_account_name, payload.payment_mode, branch_id)

    voucher = Voucher(
        voucher_type="payment",
        narration=payload.narration or payload.expense_account_name,
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    db.add(VoucherEntry(voucher_id=voucher.id, account_id=expense_account.id, debit=payload.amount, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=credit_account.id, debit=0, credit=payload.amount))
    db.commit()

    return {"message": "পেমেন্ট সফল হয়েছে", "voucher_id": voucher.id}


@app.post("/receipts")
def make_receipt(payload: ReceiptRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    branch_id = require_branch(current_user)
    if payload.payment_mode not in ("cash", "bank"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'bank' হতে হবে")

    customer = db.query(Party).filter(Party.id == payload.customer_id).first()
    if not customer:
        raise HTTPException(status_code=404, detail="কাস্টমার পাওয়া যায়নি")

    debit_account_name = "Cash" if payload.payment_mode == "cash" else "Bank"
    debit_account = get_or_create_account(db, debit_account_name, payload.payment_mode, branch_id)
    receivable_account = get_or_create_account(db, "Accounts Receivable", "receivable", branch_id)

    voucher = Voucher(
        voucher_type="receipt",
        narration=payload.narration or f"{customer.name} থেকে বাকি আদায়",
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    db.add(VoucherEntry(voucher_id=voucher.id, account_id=debit_account.id, debit=payload.amount, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=receivable_account.id, party_id=payload.customer_id, debit=0, credit=payload.amount))
    db.commit()

    return {"message": "রিসিভ সফল হয়েছে", "voucher_id": voucher.id}


@app.post("/parties/{customer_id}/send-due-reminder")
def send_due_reminder(customer_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    customer = db.query(Party).filter(Party.id == customer_id).first()
    if not customer:
        raise HTTPException(status_code=404, detail="কাস্টমার পাওয়া যায়নি")

    bid = scope_branch(current_user)
    receivable_ids = account_ids_in_scope(db, "Accounts Receivable", bid)
    due = 0
    if receivable_ids:
        entries = db.query(VoucherEntry).filter(
            VoucherEntry.account_id.in_(receivable_ids),
            VoucherEntry.party_id == customer_id,
        ).all()
        due = sum(e.debit for e in entries) - sum(e.credit for e in entries)

    if due <= 0:
        raise HTTPException(status_code=400, detail="এই কাস্টমারের কোনো বাকি নেই")

    result = send_sms(
        customer.phone,
        f"প্রিয় {customer.name}, আপনার কাছে ৳{due} বাকি আছে। দয়া করে পরিশোধ করুন। ধন্যবাদ — Showroom ERP",
    )
    return {"message": "রিমাইন্ডার পাঠানো হয়েছে (গেটওয়ে কনফিগার না থাকলে শুধু লগ হবে)", "due_amount": due, "sms_result": result}


@app.get("/reports/stock")
def stock_report(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    units = units_query(db, bid).filter(Unit.status == "in_stock").all()
    result = []
    for u in units:
        result.append({
            "unit_id": u.id,
            "chassis_no": u.chassis_no,
            "engine_no": u.engine_no,
            "model": u.product.model_name if u.product else None,
            "brand": u.product.brand.name if u.product and u.product.brand else None,
            "color": u.color,
            "gate_pass_no": u.gate_pass_no,
            "warehouse": u.warehouse.name if u.warehouse else None,
            "purchase_price": u.purchase_price,
            "purchase_date": u.purchase_date,
        })
    return {"total_units_in_stock": len(result), "units": result}


@app.get("/reports/receivables")
def receivables_report(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    customers = db.query(Party).filter(Party.party_type == "customer").all()
    result = []
    for c in customers:
        units_sold = units_query(db, bid).filter(Unit.customer_id == c.id).all()
        # মোট বিক্রয় = বাইকের মূল্য + ডেকোরেশন + রেজিস্ট্রেশন
        total_sold = sum(
            (u.sold_price or 0) + (u.decoration_cost or 0) + (u.registration_cost or 0)
            for u in units_sold
        )
        if total_sold > 0:
            result.append({
                "customer_id": c.id,
                "customer_name": c.name,
                "area": c.area.name if c.area else None,
                "total_units_purchased": len(units_sold),
                "total_sale_value": total_sold,
            })
    return {"note": "এটি মোট বিক্রয়ের হিসাব দেখাচ্ছে, কাস্টমার-ভিত্তিক নিখুঁত বাকি হিসাব পরে যোগ হবে", "customers": result}


@app.get("/reports/receivables-by-party")
def receivables_by_party(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    receivable_ids = account_ids_in_scope(db, "Accounts Receivable", bid)
    if not receivable_ids:
        return {"customers": []}

    customers = db.query(Party).filter(Party.party_type == "customer").all()
    result = []
    for c in customers:
        entries = db.query(VoucherEntry).filter(
            VoucherEntry.account_id.in_(receivable_ids),
            VoucherEntry.party_id == c.id,
        ).all()
        total_debit = sum(e.debit for e in entries)
        total_credit = sum(e.credit for e in entries)
        due = total_debit - total_credit
        if due != 0:
            result.append({
                "customer_id": c.id,
                "customer_name": c.name,
                "area": c.area.name if c.area else None,
                "phone": c.phone,
                "due_amount": due,
            })
    return {"customers": result}


class SparePartCreate(BaseModel):
    name: str
    unit: str = "pcs"
    warehouse_id: int
    purchase_price: int = 0
    sale_price: int = 0


class SparePartRestock(BaseModel):
    qty: int
    purchase_price: int | None = None
    supplier_id: int | None = None
    payment_mode: str = "cash"


class SparePartSell(BaseModel):
    qty: int
    sale_price: int | None = None
    customer_id: int | None = None
    payment_mode: str = "cash"


@app.post("/spare-parts")
def create_spare_part(payload: SparePartCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    warehouse = db.query(Warehouse).filter(Warehouse.id == payload.warehouse_id).first()
    if not warehouse:
        raise HTTPException(status_code=404, detail="গোডাউন পাওয়া যায়নি")

    bid = scope_branch(current_user)
    if bid and warehouse.branch_id != bid:
        raise HTTPException(status_code=400, detail="এই গোডাউন অন্য শোরুমের")

    part = SparePart(
        name=payload.name,
        unit=payload.unit,
        warehouse_id=payload.warehouse_id,
        purchase_price=payload.purchase_price,
        sale_price=payload.sale_price,
        stock_qty=0,
    )
    db.add(part)
    db.commit()
    db.refresh(part)
    return part


@app.get("/spare-parts")
def list_spare_parts(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    return spare_parts_query(db, bid).all()


@app.post("/spare-parts/{part_id}/restock")
def restock_spare_part(part_id: int, payload: SparePartRestock, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    part = db.query(SparePart).filter(SparePart.id == part_id).first()
    if not part:
        raise HTTPException(status_code=404, detail="পার্টস পাওয়া যায়নি")
    if payload.qty <= 0:
        raise HTTPException(status_code=400, detail="পরিমাণ শূন্যের বেশি হতে হবে")
    if payload.payment_mode not in ("cash", "due"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'due' হতে হবে")
    if payload.payment_mode == "due" and not payload.supplier_id:
        raise HTTPException(status_code=400, detail="বাকিতে ক্রয় করতে সাপ্লায়ার আবশ্যক")

    branch_id = part.warehouse.branch_id if part.warehouse else None
    bid = scope_branch(current_user)
    if bid and branch_id != bid:
        raise HTTPException(status_code=400, detail="এই পার্টস অন্য শোরুমের")

    unit_price = payload.purchase_price if payload.purchase_price is not None else part.purchase_price
    total_cost = unit_price * payload.qty

    part.stock_qty += payload.qty
    if payload.purchase_price is not None:
        part.purchase_price = payload.purchase_price
    db.commit()
    db.refresh(part)

    purchase_expense_account = get_or_create_account(db, "Inventory Purchase", "expense", branch_id)
    credit_account_name = "Cash" if payload.payment_mode == "cash" else "Accounts Payable"
    credit_account_type = "cash" if payload.payment_mode == "cash" else "payable"
    credit_account = get_or_create_account(db, credit_account_name, credit_account_type, branch_id)

    voucher = Voucher(
        voucher_type="purchase",
        narration=f"স্পেয়ার পার্টস ক্রয়: {part.name} x{payload.qty}",
        reference=f"part-{part.id}",
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    db.add(VoucherEntry(voucher_id=voucher.id, account_id=purchase_expense_account.id, debit=total_cost, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=credit_account.id, party_id=payload.supplier_id, debit=0, credit=total_cost))
    db.commit()

    return part


@app.post("/spare-parts/{part_id}/sell")
def sell_spare_part(part_id: int, payload: SparePartSell, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    part = db.query(SparePart).filter(SparePart.id == part_id).first()
    if not part:
        raise HTTPException(status_code=404, detail="পার্টস পাওয়া যায়নি")
    if payload.qty <= 0:
        raise HTTPException(status_code=400, detail="পরিমাণ শূন্যের বেশি হতে হবে")
    if payload.payment_mode not in ("cash", "due"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'due' হতে হবে")
    if payload.payment_mode == "due" and not payload.customer_id:
        raise HTTPException(status_code=400, detail="বাকিতে বিক্রি করতে কাস্টমার আবশ্যক")
    if part.stock_qty < payload.qty:
        raise HTTPException(status_code=400, detail="পর্যাপ্ত স্টক নেই")

    branch_id = part.warehouse.branch_id if part.warehouse else None
    bid = scope_branch(current_user)
    if bid and branch_id != bid:
        raise HTTPException(status_code=400, detail="এই পার্টস অন্য শোরুমের")

    unit_sale_price = payload.sale_price if payload.sale_price is not None else part.sale_price
    total_sale = unit_sale_price * payload.qty

    part.stock_qty -= payload.qty

    debit_account_name = "Cash" if payload.payment_mode == "cash" else "Accounts Receivable"
    debit_account_type = "cash" if payload.payment_mode == "cash" else "receivable"
    debit_account = get_or_create_account(db, debit_account_name, debit_account_type, branch_id)
    income_account = get_or_create_account(db, "Spare Parts Income", "income", branch_id)

    voucher = Voucher(
        voucher_type="sale",
        narration=f"স্পেয়ার পার্টস বিক্রয়: {part.name} x{payload.qty}",
        reference=f"part-{part.id}",
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    db.add(VoucherEntry(voucher_id=voucher.id, account_id=debit_account.id, party_id=payload.customer_id, debit=total_sale, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=income_account.id, debit=0, credit=total_sale))
    db.commit()
    if payload.customer_id:
        customer = db.query(Party).filter(Party.id == payload.customer_id).first()
        if customer:
            send_sms(
                customer.phone,
                f"প্রিয় {customer.name}, আপনার স্পেয়ার পার্টস ক্রয় সম্পন্ন হয়েছে। মূল্য: ৳{total_sale}। ধন্যবাদ — Showroom ERP",
            )

    db.refresh(part)
    return {"spare_part": part, "total_sale": total_sale, "voucher_id": voucher.id}


class SupplierPaymentRequest(BaseModel):
    amount: int
    supplier_id: int
    payment_mode: str = "cash"
    narration: str | None = None


@app.post("/supplier-payments")
def pay_supplier(payload: SupplierPaymentRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    branch_id = require_branch(current_user)
    if payload.payment_mode not in ("cash", "bank"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'bank' হতে হবে")

    supplier = db.query(Party).filter(Party.id == payload.supplier_id).first()
    if not supplier:
        raise HTTPException(status_code=404, detail="সাপ্লায়ার পাওয়া যায়নি")

    payable_account = get_or_create_account(db, "Accounts Payable", "payable", branch_id)
    credit_account_name = "Cash" if payload.payment_mode == "cash" else "Bank"
    credit_account = get_or_create_account(db, credit_account_name, payload.payment_mode, branch_id)

    voucher = Voucher(
        voucher_type="payment",
        narration=payload.narration or f"{supplier.name}-কে পরিশোধ",
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    db.add(VoucherEntry(voucher_id=voucher.id, account_id=payable_account.id, party_id=payload.supplier_id, debit=payload.amount, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=credit_account.id, debit=0, credit=payload.amount))
    db.commit()

    return {"message": "পরিশোধ সফল হয়েছে", "voucher_id": voucher.id}


class SupplierOrderCreate(BaseModel):
    supplier_id: int
    product_id: int
    qty: int
    unit_price: int
    expected_date: date | None = None
    notes: str | None = None


def supplier_order_dicts(db: Session, orders):
    received = dict(
        db.query(Unit.supplier_order_id, func.count(Unit.id))
        .filter(Unit.supplier_order_id.isnot(None))
        .group_by(Unit.supplier_order_id)
        .all()
    )
    parties = {p.id: p for p in db.query(Party).all()}
    products = {p.id: p for p in db.query(Product).all()}
    advances = {}
    result = []
    for o in orders:
        if o.branch_id not in advances:
            advances[o.branch_id] = supplier_advance_balances(db, o.branch_id)
        got = int(received.get(o.id, 0))
        sup = parties.get(o.supplier_id)
        prod = products.get(o.product_id)
        result.append({
            "id": o.id,
            "supplier_id": o.supplier_id,
            "supplier_name": sup.name if sup else None,
            "product_id": o.product_id,
            "model": prod.model_name if prod else None,
            "qty": o.qty,
            "unit_price": o.unit_price,
            "total_value": o.qty * o.unit_price,
            "received": got,
            "remaining": max(o.qty - got, 0),
            "status": o.status,
            "order_date": o.order_date.strftime("%Y-%m-%d") if o.order_date else None,
            "expected_date": o.expected_date.isoformat() if o.expected_date else None,
            "notes": o.notes,
            "advance_balance": advances[o.branch_id].get(o.supplier_id, 0),
        })
    return result


@app.post("/supplier-orders")
def create_supplier_order(payload: SupplierOrderCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """কোম্পানিকে গাড়ীর অর্ডার: কত ইউনিট, ইউনিট প্রতি কত দামে"""
    branch_id = require_branch(current_user)
    supplier = db.query(Party).filter(Party.id == payload.supplier_id).first()
    if not supplier or supplier.party_type != "supplier":
        raise HTTPException(status_code=404, detail="সাপ্লায়ার পাওয়া যায়নি")
    if not db.query(Product).filter(Product.id == payload.product_id).first():
        raise HTTPException(status_code=404, detail="প্রোডাক্ট পাওয়া যায়নি")
    if payload.qty <= 0 or payload.unit_price <= 0:
        raise HTTPException(status_code=400, detail="ইউনিট সংখ্যা ও ইউনিট প্রতি মূল্য ০-এর বেশি হতে হবে")

    order = SupplierOrder(
        branch_id=branch_id,
        supplier_id=payload.supplier_id,
        product_id=payload.product_id,
        qty=payload.qty,
        unit_price=payload.unit_price,
        expected_date=payload.expected_date,
        notes=(payload.notes or "").strip() or None,
        status="open",
    )
    db.add(order)
    db.commit()
    db.refresh(order)
    return supplier_order_dicts(db, [order])[0]


@app.get("/supplier-orders")
def list_supplier_orders(status: str | None = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    q = db.query(SupplierOrder)
    if bid:
        q = q.filter(SupplierOrder.branch_id == bid)
    if status:
        q = q.filter(SupplierOrder.status == status)
    return supplier_order_dicts(db, q.order_by(SupplierOrder.id.desc()).all())


@app.post("/supplier-orders/{order_id}/cancel")
def cancel_supplier_order(order_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    order = db.query(SupplierOrder).filter(SupplierOrder.id == order_id).first()
    bid = scope_branch(current_user)
    if not order or (bid and order.branch_id != bid):
        raise HTTPException(status_code=404, detail="অর্ডার পাওয়া যায়নি")
    if order.status != "open":
        raise HTTPException(status_code=400, detail="শুধু চলমান অর্ডার বাতিল করা যায়")
    order.status = "cancelled"
    db.commit()
    return supplier_order_dicts(db, [order])[0]


class SupplierAdvanceRequest(BaseModel):
    supplier_id: int
    amount: int
    payment_mode: str = "cash"
    narration: str | None = None


@app.post("/supplier-advances")
def pay_supplier_advance(payload: SupplierAdvanceRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """কোম্পানি/সাপ্লায়ারকে গাড়ী ক্রয়ের অগ্রিম টাকা দেওয়া। পরে ইউনিটের ক্রয়ে এখান থেকে কাটা যায়।"""
    branch_id = require_branch(current_user)
    if payload.amount <= 0:
        raise HTTPException(status_code=400, detail="টাকার পরিমাণ ০-এর বেশি হতে হবে")
    if payload.payment_mode not in ("cash", "bank"):
        raise HTTPException(status_code=400, detail="payment_mode অবশ্যই 'cash' বা 'bank' হতে হবে")

    supplier = db.query(Party).filter(Party.id == payload.supplier_id).first()
    if not supplier or supplier.party_type != "supplier":
        raise HTTPException(status_code=404, detail="সাপ্লায়ার পাওয়া যায়নি")

    adv_account = get_or_create_account(db, "Supplier Advances", "advance_paid", branch_id)
    money_name = "Cash" if payload.payment_mode == "cash" else "Bank"
    money_account = get_or_create_account(db, money_name, payload.payment_mode, branch_id)

    voucher = Voucher(
        voucher_type="advance",
        narration=payload.narration or f"{supplier.name}-কে গাড়ী ক্রয়ের অগ্রিম",
        reference=f"sadv-{supplier.id}",
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)

    db.add(VoucherEntry(voucher_id=voucher.id, account_id=adv_account.id, party_id=supplier.id, debit=payload.amount, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=money_account.id, debit=0, credit=payload.amount))
    db.commit()

    balance = supplier_advance_balances(db, branch_id).get(supplier.id, 0)
    return {"message": "অগ্রিম দেওয়া হয়েছে", "voucher_id": voucher.id, "advance_balance": balance}


@app.get("/supplier-advances")
def list_supplier_advances(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """কোন সাপ্লায়ারের কাছে এখনো কত অগ্রিম জমা আছে (ক্রয়ে কাটা বাদে)"""
    bid = scope_branch(current_user)
    balances = supplier_advance_balances(db, bid)
    result = []
    for pid, bal in balances.items():
        if bal == 0:
            continue
        p = db.query(Party).filter(Party.id == pid).first()
        result.append({
            "supplier_id": pid,
            "supplier_name": p.name if p else None,
            "phone": p.phone if p else None,
            "advance_balance": bal,
        })
    result.sort(key=lambda r: -r["advance_balance"])
    return result


@app.get("/reports/payables-by-party")
def payables_by_party(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    payable_ids = account_ids_in_scope(db, "Accounts Payable", bid)
    if not payable_ids:
        return {"suppliers": []}

    suppliers = db.query(Party).filter(Party.party_type == "supplier").all()
    result = []
    for s in suppliers:
        entries = db.query(VoucherEntry).filter(
            VoucherEntry.account_id.in_(payable_ids),
            VoucherEntry.party_id == s.id,
        ).all()
        total_debit = sum(e.debit for e in entries)
        total_credit = sum(e.credit for e in entries)
        due = total_credit - total_debit
        if due != 0:
            result.append({
                "supplier_id": s.id,
                "supplier_name": s.name,
                "area": s.area.name if s.area else None,
                "phone": s.phone,
                "payable_amount": due,
            })
    return {"suppliers": result}


@app.get("/reports/dashboard")
def dashboard_report(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)

    income_account_names = ["Sales Income", "Spare Parts Income", "Decoration Income", "Registration Income"]
    income_account_ids = []
    for n in income_account_names:
        income_account_ids += account_ids_in_scope(db, n, bid)

    daily_sales_map = {}
    if income_account_ids:
        entries = (
            db.query(
                func.date(Voucher.voucher_date).label("day"),
                func.sum(VoucherEntry.credit - VoucherEntry.debit).label("amount"),
            )
            .join(Voucher, Voucher.id == VoucherEntry.voucher_id)
            .filter(VoucherEntry.account_id.in_(income_account_ids))
            .group_by(func.date(Voucher.voucher_date))
            .order_by(func.date(Voucher.voucher_date))
            .all()
        )
        for day, amount in entries:
            daily_sales_map[str(day)] = int(amount or 0)

    total_revenue = sum(daily_sales_map.values())
    total_units_sold = units_query(db, bid).filter(Unit.status == "sold").count()

    receivable_ids = account_ids_in_scope(db, "Accounts Receivable", bid)
    total_receivables = 0
    if receivable_ids:
        r_entries = db.query(VoucherEntry).filter(VoucherEntry.account_id.in_(receivable_ids)).all()
        total_receivables = sum(e.debit for e in r_entries) - sum(e.credit for e in r_entries)

    payable_ids = account_ids_in_scope(db, "Accounts Payable", bid)
    total_payables = 0
    if payable_ids:
        p_entries = db.query(VoucherEntry).filter(VoucherEntry.account_id.in_(payable_ids)).all()
        total_payables = sum(e.credit for e in p_entries) - sum(e.debit for e in p_entries)

    stock_units = units_query(db, bid).filter(Unit.status == "in_stock").all()
    stock_value = sum(u.purchase_price for u in stock_units)
    spare_parts = spare_parts_query(db, bid).all()
    stock_value += sum(p.stock_qty * p.purchase_price for p in spare_parts)

    daily_sales = [{"date": d, "amount": a} for d, a in sorted(daily_sales_map.items())]

    return {
        "total_revenue": total_revenue,
        "total_units_sold": total_units_sold,
        "total_receivables": total_receivables,
        "total_payables": total_payables,
        "stock_value": stock_value,
        "daily_sales": daily_sales,
    }



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
from backend.investors import build_investor_router
app.include_router(build_investor_router(get_db, get_current_user, engine))



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



# ---------------------------------------------------------------
# কাস্টমারের বাড়তি ঘর: পিতার নাম, রেফারেন্স, তারিখ
# ---------------------------------------------------------------
class PartyExtra(BaseModel):
    father_name: str | None = None
    reference: str | None = None
    entry_date: date | None = None


def _party_extra_dict(p):
    return {
        "id": p.id,
        "father_name": p.father_name,
        "reference": p.reference,
        "entry_date": p.entry_date.isoformat() if p.entry_date else None,
    }


@app.get("/parties-extra")
def parties_extra_all(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return [_party_extra_dict(p) for p in db.query(Party).all()]


@app.get("/parties/{party_id}/extra")
def party_extra_get(party_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    p = db.query(Party).filter(Party.id == party_id).first()
    if not p:
        raise HTTPException(status_code=404, detail="পার্টি পাওয়া যায়নি")
    return _party_extra_dict(p)


@app.put("/parties/{party_id}/extra")
def party_extra_put(party_id: int, payload: PartyExtra, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    p = db.query(Party).filter(Party.id == party_id).first()
    if not p:
        raise HTTPException(status_code=404, detail="পার্টি পাওয়া যায়নি")
    p.father_name = (payload.father_name or "").strip() or None
    p.reference = (payload.reference or "").strip() or None
    p.entry_date = payload.entry_date
    db.commit()
    return _party_extra_dict(p)



# ---------------------------------------------------------------
# রানার (সাপ্লায়ার) থেকে ডেলিভারির রিপোর্ট
# ---------------------------------------------------------------
@app.get("/reports/supplier-deliveries")
def supplier_deliveries(month: str | None = None, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """মাসের অর্ডার, দৈনিক গাড়ী পাওয়া, আর সব চলমান অর্ডারে এখনো মোট কত গাড়ী আসা বাকি।
    month = YYYY-MM (না দিলে চলতি মাস)।"""
    bid = scope_branch(current_user)
    local = timedelta(hours=6)  # ডাটাবেসে সময় UTC, বাংলাদেশ = UTC+6

    if month:
        try:
            y, m = [int(x) for x in month.split("-")]
            start = datetime(y, m, 1)
        except Exception:
            raise HTTPException(status_code=400, detail="month অবশ্যই YYYY-MM আকারে দিন (যেমন 2026-10)")
    else:
        now_local = datetime.utcnow() + local
        y, m = now_local.year, now_local.month
        start = datetime(y, m, 1)
    end = datetime(y + (m // 12), (m % 12) + 1, 1)
    start_utc, end_utc = start - local, end - local

    oq = db.query(SupplierOrder)
    if bid:
        oq = oq.filter(SupplierOrder.branch_id == bid)
    month_orders = (
        oq.filter(SupplierOrder.order_date >= start_utc, SupplierOrder.order_date < end_utc)
        .order_by(SupplierOrder.id)
        .all()
    )
    open_orders = oq.filter(SupplierOrder.status == "open").order_by(SupplierOrder.id).all()
    month_rows = supplier_order_dicts(db, month_orders)
    open_rows = supplier_order_dicts(db, open_orders)

    uq = units_query(db, bid).filter(
        Unit.supplier_id.isnot(None),
        Unit.purchase_date >= start_utc,
        Unit.purchase_date < end_utc,
    )
    daily = {}
    for u in uq.all():
        day = (u.purchase_date + local).strftime("%Y-%m-%d")
        daily[day] = daily.get(day, 0) + 1

    return {
        "month": f"{y:04d}-{m:02d}",
        "month_ordered": sum(r["qty"] for r in month_rows if r["status"] != "cancelled"),
        "month_received": sum(r["received"] for r in month_rows),
        "month_orders": month_rows,
        "delivered_in_month": sum(daily.values()),
        "daily_deliveries": [{"date": d, "count": c} for d, c in sorted(daily.items())],
        "open_orders_remaining": sum(r["remaining"] for r in open_rows),
        "open_orders": open_rows,
    }


# ---------------------------------------------------------------
# শোরুম যোগ ও সম্পাদনা (শুধু অ্যাডমিন)
# ---------------------------------------------------------------
class BranchUpdate(BaseModel):
    name: str
    address: str | None = None
    phone: str | None = None


def _branch_admin(user):
    role_name = (user.role.name if getattr(user, "role", None) else "") or ""
    if role_name.strip().lower() != "admin":
        raise HTTPException(status_code=403, detail="শুধু অ্যাডমিন শোরুম যোগ বা সম্পাদনা করতে পারবেন")


@app.put("/branches/{branch_id}")
def update_branch(branch_id: int, payload: BranchUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    _branch_admin(current_user)
    branch = db.query(Branch).filter(Branch.id == branch_id).first()
    if not branch:
        raise HTTPException(status_code=404, detail="শোরুম পাওয়া যায়নি")
    name = (payload.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="শোরুমের নাম লিখুন")
    dup = db.query(Branch).filter(Branch.name == name, Branch.id != branch_id).first()
    if dup:
        raise HTTPException(status_code=400, detail="এই নামে আরেকটি শোরুম আছে")
    branch.name = name
    branch.address = (payload.address or "").strip() or None
    branch.phone = (payload.phone or "").strip() or None
    db.commit()
    db.refresh(branch)
    return branch


@app.delete("/branches/{branch_id}")
def delete_branch(branch_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    _branch_admin(current_user)
    branch = db.query(Branch).filter(Branch.id == branch_id).first()
    if not branch:
        raise HTTPException(status_code=404, detail="শোরুম পাওয়া যায়নি")
    if db.query(Branch).count() <= 1:
        raise HTTPException(status_code=400, detail="শেষ শোরুম মোছা যাবে না")
    used = []
    for table in Base.metadata.sorted_tables:
        if table.name == "branches":
            continue
        for col in table.columns:
            if col.name in ("branch_id", "from_branch_id", "to_branch_id"):
                n = db.query(func.count()).select_from(table).filter(col == branch_id).scalar()
                if n:
                    used.append(table.name)
                    break
    if used:
        raise HTTPException(
            status_code=400,
            detail="এই শোরুমে ডাটা আছে, তাই মোছা যাবে না (" + ", ".join(used) + ")",
        )
    db.delete(branch)
    db.commit()
    return {"ok": True}
# ---------------------------------------------------------------
# কাস্টমারের পূর্বের বকেয়া (হিসাব শুরুর আগের পাওনা)
# ---------------------------------------------------------------
class OpeningBalanceRequest(BaseModel):
    amount: int
    balance_date: str | None = None


def _find_opening_voucher(db: Session, party_id: int, rec_account_id: int):
    return (
        db.query(Voucher)
        .join(VoucherEntry, VoucherEntry.voucher_id == Voucher.id)
        .filter(
            Voucher.voucher_type == "opening",
            Voucher.reference == f"opening-{party_id}",
            VoucherEntry.account_id == rec_account_id,
        )
        .first()
    )


@app.get("/parties/{party_id}/opening-balance")
def get_opening_balance(party_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    ids = account_ids_in_scope(db, "Accounts Receivable", bid)
    total = 0
    if ids:
        v_ids = [
            v.id for v in db.query(Voucher).filter(
                Voucher.voucher_type == "opening",
                Voucher.reference == f"opening-{party_id}",
            ).all()
        ]
        if v_ids:
            total = int(
                db.query(func.coalesce(func.sum(VoucherEntry.debit), 0))
                .filter(
                    VoucherEntry.voucher_id.in_(v_ids),
                    VoucherEntry.account_id.in_(ids),
                    VoucherEntry.party_id == party_id,
                )
                .scalar() or 0
            )
    return {"amount": total}


@app.put("/parties/{party_id}/opening-balance")
def set_opening_balance(party_id: int, payload: OpeningBalanceRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """পূর্বের বকেয়া বসায়। আগে দেওয়া থাকলে অঙ্ক বদলে দেয়। ০ দিলে মুছে যায়।"""
    branch_id = require_branch(current_user)
    party = db.query(Party).filter(Party.id == party_id).first()
    if not party or party.party_type != "customer":
        raise HTTPException(status_code=404, detail="কাস্টমার পাওয়া যায়নি")
    if payload.amount < 0:
        raise HTTPException(status_code=400, detail="অঙ্ক ঋণাত্মক হতে পারবে না")

    rec = get_or_create_account(db, "Accounts Receivable", "receivable", branch_id)
    existing = _find_opening_voucher(db, party_id, rec.id)

    if payload.amount == 0:
        if existing:
            db.query(VoucherEntry).filter(VoucherEntry.voucher_id == existing.id).delete()
            db.delete(existing)
            db.commit()
        return {"amount": 0}

    equity = get_or_create_account(db, "Opening Balance", "equity", branch_id)

    if existing:
        for e in db.query(VoucherEntry).filter(VoucherEntry.voucher_id == existing.id).all():
            if e.account_id == rec.id:
                e.debit, e.credit = payload.amount, 0
            elif e.account_id == equity.id:
                e.debit, e.credit = 0, payload.amount
        if payload.balance_date:
            existing.voucher_date = parse_entry_date(payload.balance_date)
        db.commit()
        return {"amount": payload.amount, "voucher_id": existing.id}

    voucher = Voucher(
        voucher_type="opening",
        narration=f"{party.name} — পূর্বের বকেয়া",
        reference=f"opening-{party_id}",
        voucher_date=parse_entry_date(payload.balance_date),
    )
    db.add(voucher)
    db.commit()
    db.refresh(voucher)
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=rec.id, party_id=party_id, debit=payload.amount, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=equity.id, party_id=party_id, debit=0, credit=payload.amount))
    db.commit()
    return {"amount": payload.amount, "voucher_id": voucher.id}
# ---------------------------------------------------------------
# বিক্রয় ইনভয়েস এডিট (শুধু অ্যাডমিন)
# ---------------------------------------------------------------
def _sale_admin(user):
    role_name = (user.role.name if getattr(user, "role", None) else "") or ""
    if role_name.strip().lower() != "admin":
        raise HTTPException(status_code=403, detail="শুধু অ্যাডমিন বিক্রয় ইনভয়েস এডিট করতে পারবেন")


class SaleEditRequest(BaseModel):
    customer_id: int
    sold_price: int
    decoration_cost: int = 0
    registration_cost: int = 0
    paid_amount: int | None = None  # খালি = পুরো টাকা জমা (নগদ)
    sale_date: str | None = None
    partner_id: int | None = None


def _sale_voucher_of(db: Session, unit):
    return (
        db.query(Voucher)
        .filter(Voucher.voucher_type == "sale", Voucher.reference == unit.chassis_no)
        .order_by(Voucher.id)
        .first()
    )


def _sale_dict(db: Session, u):
    local = timedelta(hours=6)
    total = (u.sold_price or 0) + (u.decoration_cost or 0) + (u.registration_cost or 0)
    v = _sale_voucher_of(db, u)
    due = 0
    if v:
        due = int(
            db.query(func.coalesce(func.sum(VoucherEntry.debit), 0))
            .join(Account, Account.id == VoucherEntry.account_id)
            .filter(VoucherEntry.voucher_id == v.id, Account.name == "Accounts Receivable")
            .scalar() or 0
        )
    cust = db.query(Party).filter(Party.id == u.customer_id).first() if u.customer_id else None
    return {
        "unit_id": u.id,
        "chassis_no": u.chassis_no,
        "engine_no": u.engine_no,
        "brand": u.product.brand.name if u.product and u.product.brand else None,
        "model": u.product.model_name if u.product else None,
        "customer_id": u.customer_id,
        "customer_name": cust.name if cust else None,
        "sold_price": u.sold_price or 0,
        "decoration_cost": u.decoration_cost or 0,
        "registration_cost": u.registration_cost or 0,
        "total": total,
        "paid": max(total - due, 0),
        "due": due,
        "sale_date": (u.sold_date + local).strftime("%Y-%m-%d") if u.sold_date else None,
        "partner_id": u.sold_by_partner_id,
        "invoice_no": v.id if v else None,
    }


@app.get("/sales")
def list_sales(q: str = "", db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    bid = scope_branch(current_user)
    query = units_query(db, bid).filter(Unit.status == "sold")
    term = (q or "").strip()
    if term:
        like = f"%{term}%"
        query = query.filter(or_(
            Unit.chassis_no.ilike(like),
            Unit.engine_no.ilike(like),
            Unit.customer_id.in_(db.query(Party.id).filter(Party.name.ilike(like))),
        ))
    units = query.order_by(Unit.sold_date.desc()).limit(60).all()
    return [_sale_dict(db, u) for u in units]


@app.put("/units/{unit_id}/sale")
def edit_sale(unit_id: int, payload: SaleEditRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    _sale_admin(current_user)
    unit = db.query(Unit).filter(Unit.id == unit_id).first()
    if not unit or unit.status != "sold":
        raise HTTPException(status_code=404, detail="বিক্রি হওয়া গাড়ী পাওয়া যায়নি")

    branch_id = unit.warehouse.branch_id if unit.warehouse else None
    bid = scope_branch(current_user)
    if bid and branch_id != bid:
        raise HTTPException(status_code=400, detail="এই গাড়ী অন্য শোরুমের")

    if not db.query(Party).filter(Party.id == payload.customer_id).first():
        raise HTTPException(status_code=404, detail="কাস্টমার পাওয়া যায়নি")
    if payload.sold_price <= 0:
        raise HTTPException(status_code=400, detail="বাইকের মূল্য ০-এর বেশি হতে হবে")
    if payload.decoration_cost < 0 or payload.registration_cost < 0:
        raise HTTPException(status_code=400, detail="খরচের পরিমাণ ঋণাত্মক হতে পারবে না")

    bike = payload.sold_price
    deco = payload.decoration_cost
    reg = payload.registration_cost
    total = bike + deco + reg
    paid = total if payload.paid_amount is None else payload.paid_amount
    if paid < 0:
        raise HTTPException(status_code=400, detail="জমা ঋণাত্মক হতে পারবে না")
    if paid > total:
        raise HTTPException(status_code=400, detail="জমা মোট মূল্যের বেশি হতে পারবে না")
    due = total - paid

    # তারিখ একই থাকলে আগের সময়ই থাকবে
    local = timedelta(hours=6)
    old_day = (unit.sold_date + local).strftime("%Y-%m-%d") if unit.sold_date else None
    if payload.sale_date and payload.sale_date[:10] != old_day:
        unit.sold_date = parse_entry_date(payload.sale_date)

    unit.sold_price = bike
    unit.decoration_cost = deco
    unit.registration_cost = reg
    unit.customer_id = payload.customer_id
    unit.sold_by_partner_id = payload.partner_id

    voucher = _sale_voucher_of(db, unit)
    if voucher:
        db.query(VoucherEntry).filter(VoucherEntry.voucher_id == voucher.id).delete()
        voucher.voucher_date = unit.sold_date
    else:
        voucher = Voucher(
            voucher_type="sale",
            narration=f"Unit #{unit.id} ({unit.chassis_no}) বিক্রয়",
            reference=unit.chassis_no,
            voucher_date=unit.sold_date,
        )
        db.add(voucher)
        db.flush()

    income = get_or_create_account(db, "Sales Income", "income", branch_id)
    if paid > 0:
        cash = get_or_create_account(db, "Cash", "cash", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=cash.id, party_id=payload.customer_id, debit=paid, credit=0))
    if due > 0:
        rec = get_or_create_account(db, "Accounts Receivable", "receivable", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=rec.id, party_id=payload.customer_id, debit=due, credit=0))
    db.add(VoucherEntry(voucher_id=voucher.id, account_id=income.id, debit=0, credit=bike))
    if deco > 0:
        da = get_or_create_account(db, "Decoration Income", "income", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=da.id, debit=0, credit=deco))
    if reg > 0:
        ra = get_or_create_account(db, "Registration Income", "income", branch_id)
        db.add(VoucherEntry(voucher_id=voucher.id, account_id=ra.id, debit=0, credit=reg))
    db.commit()
    db.refresh(unit)
    return _sale_dict(db, unit)

@app.delete("/units/{unit_id}/sale")
def cancel_sale(unit_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    role_name = (current_user.role.name if getattr(current_user, "role", None) else "") or ""
    if role_name.strip().lower() != "admin":
        raise HTTPException(status_code=403, detail="শুধু অ্যাডমিন বিক্রয় বাতিল করতে পারবেন")

    unit = db.query(Unit).filter(Unit.id == unit_id).first()
    if not unit or unit.status != "sold":
        raise HTTPException(status_code=404, detail="বিক্রি হওয়া গাড়ী পাওয়া যায়নি")

    branch_id = unit.warehouse.branch_id if unit.warehouse else None
    bid = scope_branch(current_user)
    if bid and branch_id != bid:
        raise HTTPException(status_code=400, detail="এই গাড়ী অন্য শোরুমের")

    # গ্রহণ করা কমিশন থাকলে আটকাবে
    from backend.commission import UnitCommission
    received = db.query(UnitCommission).filter(
        UnitCommission.unit_id == unit.id, UnitCommission.status == "received").first()
    if received:
        raise HTTPException(status_code=400, detail="এই গাড়ির কমিশন গ্রহণ করা হয়েছে, আগে তা মিলিয়ে নিন")

    # বিক্রয়ের ভাউচার ও এন্ট্রি মুছুন
    vouchers = db.query(Voucher).filter(
        Voucher.voucher_type == "sale", Voucher.reference == unit.chassis_no).all()
    for v in vouchers:
        db.query(VoucherEntry).filter(VoucherEntry.voucher_id == v.id).delete()
        db.delete(v)

    # গাড়ি আবার স্টকে
    unit.status = "in_stock"
    unit.sold_price = None
    unit.decoration_cost = 0
    unit.registration_cost = 0
    unit.sold_date = None
    unit.customer_id = None
    unit.sold_by_partner_id = None
    db.commit()
    return {"ok": True, "unit_id": unit.id}

# ---------------------------------------------------------------
# বিক্রয় ফেরত: ভুলে বিক্রি হওয়া গাড়ী স্টকে ফিরিয়ে আনা (ইতিহাস থাকে)
# ---------------------------------------------------------------
class SaleReturnRequest(BaseModel):
    reason: str | None = None
    keep_as_advance: bool = False  # true = জমা টাকা ফেরত না দিয়ে কাস্টমারের নামে অগ্রিম রাখা


@app.post("/units/{unit_id}/return-sale")
def return_sale(unit_id: int, payload: SaleReturnRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    _sale_admin(current_user)

    unit = db.query(Unit).filter(Unit.id == unit_id).first()
    if not unit or unit.status != "sold":
        raise HTTPException(status_code=404, detail="বিক্রি হওয়া গাড়ী পাওয়া যায়নি")

    branch_id = unit.warehouse.branch_id if unit.warehouse else None
    bid = scope_branch(current_user)
    if bid and branch_id != bid:
        raise HTTPException(status_code=400, detail="এই গাড়ী অন্য শোরুমের")

    from backend.commission import UnitCommission
    received = db.query(UnitCommission).filter(
        UnitCommission.unit_id == unit.id, UnitCommission.status == "received").first()
    if received:
        raise HTTPException(status_code=400, detail="এই গাড়ির কমিশন গ্রহণ করা হয়েছে, আগে তা মিলিয়ে নিন")

    old_vouchers = (
        db.query(Voucher)
        .filter(Voucher.voucher_type == "sale", Voucher.reference == unit.chassis_no)
        .order_by(Voucher.id)
        .all()
    )
    if not old_vouchers:
        raise HTTPException(status_code=400, detail="এই বিক্রয়ের ভাউচার পাওয়া যায়নি")

    reason = (payload.reason or "").strip()[:120] or "বিক্রয় ফেরত"
    ret = Voucher(
        voucher_type="sale_return",
        narration=f"Unit #{unit.id} ({unit.chassis_no}) বিক্রয় ফেরত — {reason}",
        reference=f"return-{unit.chassis_no}",
        voucher_date=datetime.utcnow(),
    )
    db.add(ret)
    db.flush()

    rec = get_or_create_account(db, "Accounts Receivable", "receivable", branch_id)
    refunded_cash = 0
    kept_advance = 0

    for v in old_vouchers:
        for e in db.query(VoucherEntry).filter(VoucherEntry.voucher_id == v.id).all():
            account_id = e.account_id
            party_id = e.party_id
            # জমা নেওয়া নগদ টাকা: ফেরত দেওয়া (Cash কমবে) অথবা কাস্টমারের অগ্রিম হিসেবে রাখা
            if e.account and e.account.name == "Cash" and (e.debit or 0) > 0:
                if payload.keep_as_advance:
                    account_id = rec.id
                    party_id = e.party_id or unit.customer_id
                    kept_advance += e.debit
                else:
                    refunded_cash += e.debit
            db.add(VoucherEntry(
                voucher_id=ret.id,
                account_id=account_id,
                party_id=party_id,
                debit=e.credit or 0,   # উল্টো এন্ট্রি
                credit=e.debit or 0,
            ))
        # পুরোনো ভাউচারের রেফারেন্স বদলে দিই, যাতে আবার বিক্রয়ে নতুন ভাউচারটাই খুঁজে পায়
        v.reference = f"{unit.chassis_no}~r{v.id}"

    unit.status = "in_stock"
    unit.sold_price = None
    unit.decoration_cost = 0
    unit.registration_cost = 0
    unit.sold_date = None
    unit.customer_id = None
    unit.sold_by_partner_id = None
    db.commit()

    return {
        "ok": True,
        "unit_id": unit.id,
        "return_voucher_id": ret.id,
        "cash_refunded": refunded_cash,
        "kept_as_advance": kept_advance,
    }