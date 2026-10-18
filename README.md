# Showroom ERP

বাইক/গাড়ির শোরুমের জন্য ম্যানেজমেন্ট সফটওয়্যার: স্টক, ক্রয়-বিক্রয়, বাকি আদায়, সাপ্লায়ারের অগ্রিম ও অর্ডার,
অগ্রিম অর্ডার, দোকান খরচ, হিসাব, BRTA কাগজপত্র, রিপোর্ট। একাধিক শোরুম (সেল সেন্টার) সাপোর্ট করে।

## গঠন

```
backend/    FastAPI + SQLAlchemy + PostgreSQL (API সার্ভার)
frontend/   Flutter অ্যাপ (Windows, Android, ওয়েব)
```

## backend চালানো

প্রয়োজন: Python 3.10+, PostgreSQL।

```powershell
cd backend
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r requirements.txt
```

`.env.example` কপি করে `backend/.env` বানান এবং `DATABASE_URL` ও `SECRET_KEY`-এ আসল মান দিন।
ডাটাবেস (যেমন `showroom_erp`) আগে PostgreSQL-এ তৈরি করে নিন। টেবিল সার্ভার চালু হলে নিজে তৈরি হয়।

```powershell
.\venv\Scripts\python.exe -m uvicorn main:app --reload
```

সার্ভার চলবে `http://127.0.0.1:8000`। প্রথম ইউজার (অ্যাডমিন) তৈরির নিয়ম আপনার সেটআপ অনুযায়ী যোগ করুন।

## frontend চালানো

প্রয়োজন: Flutter SDK।

```powershell
cd frontend
flutter pub get
flutter run -d windows
```

ব্যাকএন্ডের ঠিকানা `frontend/lib/main.dart`-এর `apiBaseUrl`-এ আছে। অন্য কম্পিউটার বা মোবাইল থেকে চালাতে
সেটা সার্ভারের ঠিকানায় বদলান।

## নিরাপত্তা

- `.env`, ডাটাবেসের ব্যাকআপ (`*.sql`) ও কাস্টমারের ডেটা (`*.csv`, `*.xlsx`) রিপোজিটরিতে রাখবেন না।
  `.gitignore` এগুলো আটকায়, তবু `git status` দেখে নিশ্চিত হয়ে তারপর `git push` দিন।
- অনলাইনে চালানোর আগে `SECRET_KEY` নতুন করে বানান এবং HTTPS ব্যবহার করুন।
