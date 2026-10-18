"""
অগ্রিম অর্ডার চালু করার স্বয়ংক্রিয় প্যাচ।

কীভাবে চালাবেন:
  1. FastAPI সার্ভার বন্ধ করুন (Ctrl+C)।
  2. advance_orders.py ও এই ফাইলটা main.py-র পাশের ফোল্ডারে রাখুন।
  3. ওই ফোল্ডারে টার্মিনাল খুলে চালান:   python apply_advance_patch.py
  4. FastAPI সার্ভার আবার চালু করুন (নতুন টেবিল নিজে থেকেই তৈরি হবে)।

এটা যা করে:
  - main.py ও models.py-র ব্যাকআপ রাখে (main.py.bak2, models.py.bak2)
  - models.py-র শেষে AdvanceOrder ও AdvancePayment টেবিল যোগ করে
  - main.py-তে অগ্রিম অর্ডারের রুট যোগ করে
দুইবার চালালেও ক্ষতি নেই।
"""
import os
import shutil
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

MODELS_ADD = '''

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
'''


def patch_models(s):
    if "class AdvanceOrder" in s:
        return s, "models.py: অগ্রিম টেবিল আগেই আছে, বাদ দিলাম"
    if not s.endswith("\n"):
        s += "\n"
    return s + MODELS_ADD, "models.py: AdvanceOrder ও AdvancePayment যোগ হয়েছে"


def patch_main(s):
    notes = []
    imp = "from advance_orders import build_advance_router\n"
    if imp in s:
        notes.append("main.py: import আগেই আছে, বাদ দিলাম")
    else:
        anchor = "from sms_service import send_sms\n"
        if s.count(anchor) != 1:
            raise RuntimeError("main.py-তে 'from sms_service import send_sms' লাইন মেলেনি")
        s = s.replace(anchor, anchor + imp)
        notes.append("main.py: import যোগ হয়েছে")

    inc = "app.include_router(build_advance_router(get_current_user))\n"
    if inc in s:
        notes.append("main.py: রুট আগেই যোগ করা আছে, বাদ দিলাম")
    else:
        anchor = '@app.get("/")\ndef root'
        if s.count(anchor) != 1:
            raise RuntimeError('main.py-তে @app.get("/") def root মেলেনি')
        s = s.replace(anchor, inc + "\n\n" + anchor)
        notes.append("main.py: অগ্রিম অর্ডারের রুট যোগ হয়েছে")
    return s, notes


def main():
    for name in ("models.py", "main.py", "advance_orders.py"):
        if not os.path.exists(name):
            print(f"{name} পাওয়া যায়নি। সব ফাইল main.py-র পাশের ফোল্ডারে রেখে চালান।")
            return

    models = open("models.py", encoding="utf-8").read()
    main_py = open("main.py", encoding="utf-8").read()
    try:
        new_models, m1 = patch_models(models)
        new_main, m2 = patch_main(main_py)
    except RuntimeError as e:
        print("থামলাম, কোনো ফাইল বদলাইনি:", e)
        return

    shutil.copy("models.py", "models.py.bak2")
    shutil.copy("main.py", "main.py.bak2")
    open("models.py", "w", encoding="utf-8").write(new_models)
    open("main.py", "w", encoding="utf-8").write(new_main)

    print(m1)
    for line in m2:
        print(line)
    print("\nশেষ। এবার FastAPI সার্ভার আবার চালু করুন।")


if __name__ == "__main__":
    main()