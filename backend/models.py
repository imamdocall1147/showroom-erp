from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import declarative_base, relationship
from datetime import datetime

Base = declarative_base()


class Role(Base):
    __tablename__ = "roles"
    id = Column(Integer, primary_key=True)
    name = Column(String(50), unique=True, nullable=False)


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    username = Column(String(50), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    full_name = Column(String(100))
    role_id = Column(Integer, ForeignKey("roles.id"))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    # null = সব শোরুম দেখতে পারবে; মান থাকলে শুধু ওই শোরুম
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=True)

    role = relationship("Role")


class Company(Base):
    __tablename__ = "companies"
    id = Column(Integer, primary_key=True)
    name = Column(String(150), nullable=False)
    address = Column(String(255))
    phone = Column(String(30))
    created_at = Column(DateTime, default=datetime.utcnow)


class Branch(Base):
    __tablename__ = "branches"
    id = Column(Integer, primary_key=True)
    company_id = Column(Integer, ForeignKey("companies.id"), nullable=False)
    name = Column(String(150), nullable=False)
    address = Column(String(255))
    phone = Column(String(30))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    company = relationship("Company")


class Warehouse(Base):
    __tablename__ = "warehouses"
    id = Column(Integer, primary_key=True)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=False)
    name = Column(String(150), nullable=False)
    location = Column(String(255))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    branch = relationship("Branch")


class Brand(Base):
    __tablename__ = "brands"
    id = Column(Integer, primary_key=True)
    name = Column(String(100), unique=True, nullable=False)


class Product(Base):
    __tablename__ = "products"
    id = Column(Integer, primary_key=True)
    brand_id = Column(Integer, ForeignKey("brands.id"), nullable=False)
    model_name = Column(String(150), nullable=False)
    category = Column(String(50))
    unit_price = Column(Integer)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    brand = relationship("Brand")


class Area(Base):
    __tablename__ = "areas"
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)


class Party(Base):
    __tablename__ = "parties"
    id = Column(Integer, primary_key=True)
    name = Column(String(150), nullable=False)
    party_type = Column(String(20), nullable=False)
    phone = Column(String(30))
    address = Column(String(255))
    area_id = Column(Integer, ForeignKey("areas.id"))
    created_at = Column(DateTime, default=datetime.utcnow)

    area = relationship("Area")


class Unit(Base):
    __tablename__ = "units"
    id = Column(Integer, primary_key=True)
    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)
    warehouse_id = Column(Integer, ForeignKey("warehouses.id"), nullable=False)

    chassis_no = Column(String(50), unique=True, nullable=False)
    engine_no = Column(String(50), unique=True, nullable=False)
    color = Column(String(50))
    year = Column(String(10))

    purchase_price = Column(Integer, nullable=False)
    purchase_date = Column(DateTime, default=datetime.utcnow)
    supplier_id = Column(Integer, ForeignKey("parties.id"))

    status = Column(String(20), default="in_stock")

    # বিক্রয়: sold_price = শুধু বাইকের মূল্য। মোট = sold_price + decoration_cost + registration_cost
    sold_price = Column(Integer)
    decoration_cost = Column(Integer, default=0)
    registration_cost = Column(Integer, default=0)
    sold_date = Column(DateTime)
    customer_id = Column(Integer, ForeignKey("parties.id"))

    # কোন সাপ্লায়ার-অর্ডারের আওতায় এই বাইক এসেছে (থাকলে)
    supplier_order_id = Column(Integer, ForeignKey("supplier_orders.id"), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)

    product = relationship("Product")
    warehouse = relationship("Warehouse")
    supplier = relationship("Party", foreign_keys=[supplier_id])
    customer = relationship("Party", foreign_keys=[customer_id])

    brta_status = Column(String, default="not_started")  # not_started, submitted, in_process, completed
    brta_reg_no = Column(String, nullable=True)
    brta_submission_date = Column(DateTime, nullable=True)
    brta_completion_date = Column(DateTime, nullable=True)
    brta_notes = Column(String, nullable=True)

    # গেট পাস নম্বর (কোম্পানি থেকে গাড়ী ছাড়ানোর সময়ের নম্বর)
    gate_pass_no = Column(String(50), nullable=True)


class Account(Base):
    __tablename__ = "accounts"
    id = Column(Integer, primary_key=True)
    name = Column(String(150), nullable=False)
    account_type = Column(String(30), nullable=False)
    is_active = Column(Boolean, default=True)
    # প্রতিটি শোরুমের নিজস্ব Cash, Accounts Receivable ইত্যাদি একাউন্ট
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=True)


class Voucher(Base):
    __tablename__ = "vouchers"
    id = Column(Integer, primary_key=True)
    voucher_type = Column(String(20), nullable=False)
    voucher_date = Column(DateTime, default=datetime.utcnow)
    reference = Column(String(150))
    narration = Column(String(255))
    created_at = Column(DateTime, default=datetime.utcnow)


class VoucherEntry(Base):
    __tablename__ = "voucher_entries"
    id = Column(Integer, primary_key=True)
    voucher_id = Column(Integer, ForeignKey("vouchers.id"), nullable=False)
    account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False)
    party_id = Column(Integer, ForeignKey("parties.id"), nullable=True)
    debit = Column(Integer, default=0)
    credit = Column(Integer, default=0)

    voucher = relationship("Voucher")
    account = relationship("Account")
    party = relationship("Party")


class SparePart(Base):
    __tablename__ = "spare_parts"
    id = Column(Integer, primary_key=True)
    name = Column(String(150), nullable=False)
    unit = Column(String(20), default="pcs")
    stock_qty = Column(Integer, default=0)
    purchase_price = Column(Integer, default=0)
    sale_price = Column(Integer, default=0)
    warehouse_id = Column(Integer, ForeignKey("warehouses.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    warehouse = relationship("Warehouse")


# ---------------------------------------------------------------
# অগ্রিম অর্ডার ও অগ্রিম পেমেন্ট
# ---------------------------------------------------------------
from sqlalchemy import Date


class AdvanceOrder(Base):
    __tablename__ = "advance_orders"
    id = Column(Integer, primary_key=True)
    customer_id = Column(Integer, ForeignKey("parties.id"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)
    color = Column(String(50))
    agreed_price = Column(Integer, nullable=False)
    order_date = Column(DateTime, default=datetime.utcnow)
    expected_delivery_date = Column(Date, nullable=True)
    status = Column(String(20), default="open")  # open, delivered, cancelled
    notes = Column(String(255))
    unit_id = Column(Integer, ForeignKey("units.id"), nullable=True)
    # কোন শোরুমের অর্ডার
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class AdvancePayment(Base):
    __tablename__ = "advance_payments"
    id = Column(Integer, primary_key=True)
    order_id = Column(Integer, ForeignKey("advance_orders.id"), nullable=False)
    kind = Column(String(10), default="payment")  # payment, refund, forfeit, applied
    amount = Column(Integer, nullable=False)
    payment_mode = Column(String(10), default="cash")
    payment_date = Column(DateTime, default=datetime.utcnow)
    voucher_id = Column(Integer, ForeignKey("vouchers.id"), nullable=True)
    note = Column(String(255))


# ---------------------------------------------------------------
# সাপ্লায়ার/কোম্পানির কাছে গাড়ীর অর্ডার (কত ইউনিট, ইউনিট প্রতি কত দামে)
# ---------------------------------------------------------------
class SupplierOrder(Base):
    __tablename__ = "supplier_orders"
    id = Column(Integer, primary_key=True)
    branch_id = Column(Integer, ForeignKey("branches.id"), nullable=True)
    supplier_id = Column(Integer, ForeignKey("parties.id"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)
    qty = Column(Integer, nullable=False)
    unit_price = Column(Integer, nullable=False)
    order_date = Column(DateTime, default=datetime.utcnow)
    expected_date = Column(Date, nullable=True)
    status = Column(String(20), default="open")  # open, completed, cancelled
    notes = Column(String(255))
    created_at = Column(DateTime, default=datetime.utcnow)


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
AdvanceOrder.quantity = Column(Integer, default=1)          # কত ইউনিটের অর্ডার
AdvanceOrder.unit_price = Column(Integer, nullable=True)    # প্রতি ইউনিটের চুক্তির দাম
AdvanceOrder.delivered_qty = Column(Integer, default=0)     # কত ইউনিট ডেলিভারি হয়েছে
AdvanceOrder.delivered_value = Column(Integer, default=0)   # ডেলিভারি হওয়া ইউনিটের চুক্তি মূল্য
from sqlalchemy import LargeBinary
class ChallanFile(Base):
    __tablename__ = "challan_files"
    id = Column(Integer, primary_key=True)
    challan_no = Column(String(150))
    source_url = Column(String(500))
    pdf_data = Column(LargeBinary, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


    Unit.challan_id = Column(Integer, nullable=True)   # কোন চালান থেকে এসেছে
    
    