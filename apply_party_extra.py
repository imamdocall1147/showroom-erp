# -*- coding: utf-8 -*-
"""
কাস্টমারের নতুন ঘর (পিতার নাম, রেফারেন্স, তারিখ) সংরক্ষণ ও পড়ার ব্যাকএন্ড এন্ডপয়েন্ট বসায়।
আগে apply_partners.py চালানো থাকতে হবে (ওটাই ডাটাবেসে ঘরগুলো তৈরি করে)।

ব্যবহার (PowerShell-এ, backend ফোল্ডারে ঢুকে, venv চালু করে):
    python apply_party_extra.py
"""
import os
import shutil
import sys
import py_compile

MAIN_CODE = '''


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
            sys.exit(1)

    if "Party.father_name" not in read(models_p):
        print("[ত্রুটি] models.py-তে Party.father_name নেই। আগে python apply_partners.py চালান, তারপর এটা।")
        sys.exit(1)

    original = read(main_p)
    main_s = original.replace("\r\n", "\n")
    if "def party_extra_put" in main_s:
        print("কিছু করার নেই, আগেই বসানো আছে।")
        return
    head = main_s.split("app = FastAPI")[0]
    for needed in ("date", "Party", "BaseModel"):
        if needed not in head:
            print(f"[ত্রুটি] main.py-তে '{needed}' ইম্পোর্ট পাওয়া যায়নি। কিছু বদলানো হয়নি।")
            sys.exit(1)

    new_main = main_s.rstrip() + "\n" + MAIN_CODE
    if "\r\n" in original:
        new_main = new_main.replace("\n", "\r\n")
    shutil.copyfile(main_p, main_p + ".bak2")
    write(main_p, new_main)
    try:
        py_compile.compile(main_p, doraise=True)
    except py_compile.PyCompileError as e:
        shutil.copyfile(main_p + ".bak2", main_p)
        print("[ত্রুটি] সিনট্যাক্স এরর, আগের অবস্থায় ফিরিয়ে দিয়েছি:")
        print(e)
        sys.exit(1)
    print("সফল! কাস্টমারের বাড়তি ঘরের এন্ডপয়েন্ট বসানো হলো। ব্যাকআপ: main.py.bak2")
    print("এখন ব্যাকএন্ড আবার চালু করুন।")


if __name__ == "__main__":
    main()
