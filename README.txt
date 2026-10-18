ফাইল কোথায় রাখবেন
===================
backend\          -> D:\apps\showroom-erp\backend\   (python স্ক্রিপ্ট ও data_cleaned.xlsx)
frontend_lib\     -> D:\apps\showroom-erp\frontend\lib\   (.dart ফাইল)
start-kit\        -> D:\apps\showroom-erp\   (এক ক্লিকে চালুর ফাইল, পরে লাগবে)

চালানোর ক্রম (backend ফোল্ডারে, venv চালু করে):
1) python apply_partners.py
2) ব্যাকএন্ড একবার চালু করে বন্ধ করুন
3) python import_data.py data_cleaned.xlsx            (মডেল/গোডাউনের তালিকা)
4) python import_data.py data_cleaned.xlsx --product-id ম --warehouse-id গ            (ট্রায়াল)
5) ঠিক লাগলে শেষে --commit যোগ করুন

আগের কাজের স্ক্রিপ্ট (না চালিয়ে থাকলে): apply_stock_transfer.py, apply_investors.py
