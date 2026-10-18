"""
ফোনের অ্যাপ আপডেটের জন্য দুটো ছোট এন্ডপয়েন্ট।

  GET /app/version   -> {"build": 5, "name": "1.0.0"}  (সর্বশেষ প্রকাশিত অ্যাপের ভার্সন)
  GET /app/download  -> সর্বশেষ APK ফাইল

ফাইল থাকে backend/updates/ ফোল্ডারে (app.apk আর version.json)।
publish_update.bat চালালে এই ফাইলগুলো নিজে তৈরি হয়।
"""
import json
import os

from fastapi import APIRouter
from fastapi.responses import FileResponse, JSONResponse

UPDATE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "updates")


def build_update_router() -> APIRouter:
    router = APIRouter()

    @router.get("/app/version")
    def app_version():
        path = os.path.join(UPDATE_DIR, "version.json")
        if not os.path.exists(path):
            return {"build": 0, "name": ""}
        with open(path, encoding="utf-8") as f:
            return json.load(f)

    @router.get("/app/download")
    def app_download():
        path = os.path.join(UPDATE_DIR, "app.apk")
        if not os.path.exists(path):
            return JSONResponse({"detail": "আপডেট ফাইল পাওয়া যায়নি"}, status_code=404)
        return FileResponse(
            path,
            media_type="application/vnd.android.package-archive",
            filename="showroom-erp.apk",
        )

    return router