"""
SMS পাঠানোর জন্য একটা সাধারণ ইন্টারফেস।
এখনো কোনো SMS গেটওয়ে কনফিগার করা হয়নি — send_sms() শুধু লগ করবে।
পরে গেটওয়ে ঠিক হলে এই ফাংশনের ভেতরের কোড বদলে দিন
(নিচে bulksmsbd.net-এর উদাহরণ কমেন্ট করে দেওয়া আছে, প্রয়োজনে uncomment করুন)।
"""
import logging

logger = logging.getLogger("sms")


def send_sms(phone: str | None, message: str) -> dict:
    if not phone:
        return {"status": "skipped", "reason": "ফোন নম্বর নেই"}

    # ---- এখনো কোনো গেটওয়ে কনফিগার করা হয়নি — শুধু লগ করা হচ্ছে ----
    logger.info(f"[SMS STUB] To: {phone} | Message: {message}")
    return {"status": "stub", "message": "SMS গেটওয়ে এখনো কনফিগার করা হয়নি — শুধু লগ করা হলো"}

    # ---- উদাহরণ: bulksmsbd.net ব্যবহার করলে (গেটওয়ে ঠিক হলে উপরের return বাদ দিয়ে এটা uncomment করুন) ----
    # import requests
    # import os
    # api_key = os.getenv("SMS_API_KEY")
    # sender_id = os.getenv("SMS_SENDER_ID")
    # response = requests.get(
    #     "http://bulksmsbd.net/api/smsapi",
    #     params={
    #         "api_key": api_key,
    #         "type": "text",
    #         "number": phone,
    #         "senderid": sender_id,
    #         "message": message,
    #     },
    # )
    # return {"status": "sent", "response": response.text}