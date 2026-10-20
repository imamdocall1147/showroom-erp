from sqlalchemy import text
from database import engine

with engine.begin() as conn:
    wh = conn.execute(text("SELECT id FROM warehouses WHERE branch_id=2")).fetchall()
    acc = conn.execute(text("SELECT COUNT(*) FROM accounts WHERE branch_id=2")).scalar()
    usr = conn.execute(text("SELECT COUNT(*) FROM users WHERE branch_id=2")).scalar()
    print("শোরুম 2-তে গোডাউন:", [r[0] for r in wh], "| একাউন্ট:", acc, "| ইউজার:", usr)

    if [r[0] for r in wh] != [1] or acc != 0 or usr != 0:
        print("শর্ত মেলেনি, কিছু বদলানো হয়নি। এই আউটপুট আমাকে পাঠান।")
    else:
        conn.execute(text("UPDATE warehouses SET branch_id=1 WHERE id=1"))
        # শোরুম 2 এখন ফাঁকা কিনা দেখে তবেই মোছা হবে
        left = conn.execute(text("SELECT COUNT(*) FROM warehouses WHERE branch_id=2")).scalar()
        if left == 0:
            conn.execute(text("DELETE FROM branches WHERE id=2"))
            print("গোডাউন 1 শোরুম 1-এ সরানো হয়েছে, ফাঁকা শোরুম 2 মুছে ফেলা হয়েছে।")
        else:
            print("গোডাউন সরানো হয়েছে, শোরুম 2 মোছা হয়নি।")

    print("\nএখনকার শোরুম:")
    for r in conn.execute(text("SELECT id, name FROM branches ORDER BY id")):
        print("  ", r[0], r[1])
    print("এখনকার গোডাউন:")
    for r in conn.execute(text("SELECT id, name, branch_id FROM warehouses ORDER BY id")):
        print("  ", r[0], r[1], "(শোরুম id:", r[2], ")")