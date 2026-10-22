import os
import sys

print("--- PYTHON PATH DEBUGGER ---")
print("Current Working Directory:", os.getcwd())

# backend ফোল্ডারের ভেতর ফাইলটি আছে কিনা চেক করা
backend_path = os.path.join(os.getcwd(), 'backend', 'sms_service.py')
root_path = os.path.join(os.getcwd(), 'sms_service.py')

if os.path.exists(root_path):
    print("✅ Found sms_service.py in ROOT directory!")
elif os.path.exists(backend_path):
    print("✅ Found sms_service.py inside 'backend' folder!")
else:
    print("❌ sms_service.py NOT FOUND in root or backend!")
    
    # পুরো প্রোজেক্টে ফাইলটি খোঁজা
    for root, dirs, files in os.walk('.'):
        if 'sms_service.py' in files:
            print(f"🔍 Found it here: {os.path.join(root, 'sms_service.py')}")
