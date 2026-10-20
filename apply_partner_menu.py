# -*- coding: utf-8 -*-
"""
আগে থেকে বানানো PartnerScreen (partner_screen.dart) অ্যাপের মেনুতে যোগ করে:
"পার্টনার হিসাব" (শুধু অ্যাডমিন)।  নতুন কোনো স্ক্রিন বানায় না, আপনার আগের স্ক্রিনই খোলে।

ব্যবহার (PowerShell-এ Flutter প্রজেক্টের lib ফোল্ডারে ঢুকে):
    python C:\\Users\\user\\Downloads\\apply_partner_menu.py
অথবা পথ দিয়ে:
    python C:\\Users\\user\\Downloads\\apply_partner_menu.py D:\\apps\\showroom-erp\\showroom-erp\\frontend\\lib

কিছু বদলানোর আগে main.dart.pm.bak নামে ব্যাকআপ রাখে।
"""
import os
import re
import shutil
import sys


def read(path):
    with open(path, "rb") as f:
        raw = f.read()
    crlf = b"\r\n" in raw
    return raw.decode("utf-8-sig").replace("\r\n", "\n"), crlf


def write(path, text, crlf):
    if crlf:
        text = text.replace("\n", "\r\n")
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))


def fail(msg):
    print("[ত্রুটি]", msg, "কিছু বদলানো হয়নি।")
    print("এই মেসেজটা সহ আমাকে জানান।")
    sys.exit(1)


def replace_once(text, anchor, new, label):
    n = text.count(anchor)
    if n != 1:
        fail(f"'{label}' জায়গাটা ঠিকমতো পাওয়া যায়নি (পাওয়া গেছে {n} বার)।")
    return text.replace(anchor, new)


def main():
    lib = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
    main_p = os.path.join(lib, "main.dart")
    screen_p = os.path.join(lib, "partner_screen.dart")
    for p in (main_p, screen_p):
        if not os.path.isfile(p):
            print("[ত্রুটি] ফাইল পাওয়া যায়নি:", p)
            print("Flutter প্রজেক্টের lib ফোল্ডারে ঢুকে চালান, অথবা lib ফোল্ডারের পথ দিন।")
            sys.exit(1)

    main_s, crlf = read(main_p)
    screen_s, _ = read(screen_p)

    if "PartnerScreen(" in main_s:
        print("main.dart-এ পার্টনার মেনু আগেই আছে, কিছু করার নেই।")
        return

    # PartnerScreen-এর কনস্ট্রাক্টরে কী কী লাগে দেখে নেওয়া
    i = screen_s.find("class PartnerScreen extends")
    if i == -1:
        fail("partner_screen.dart-এ PartnerScreen ক্লাস পাওয়া যায়নি।")
    m = re.search(r"PartnerScreen\(\s*\{(.*?)\}\s*\)", screen_s[i:], re.S)
    if not m:
        fail("PartnerScreen-এর কনস্ট্রাক্টর বোঝা যায়নি।")
    required = re.findall(r"required\s+this\.(\w+)", m.group(1))
    args = []
    for name in required:
        if name == "token":
            args.append("token: t")
        elif name == "role":
            args.append("role: widget.role")
        else:
            fail(f"PartnerScreen-এ আমার অজানা একটা আবশ্যক প্যারামিটার আছে: '{name}'।")
    if "token: t" not in args:
        args.insert(0, "token: t")  # বাকি সব স্ক্রিনের মতোই টোকেন পাঠানো হবে
    call = f"PartnerScreen({', '.join(args)})"

    new_main = main_s
    if "import 'partner_screen.dart';" not in new_main:
        new_main = replace_once(
            new_main,
            "import 'investor_screen.dart';\n",
            "import 'investor_screen.dart';\nimport 'partner_screen.dart';\n",
            "ইম্পোর্ট",
        )

    item = (
        '    _MenuItem(Icons.groups, "পার্টনার হিসাব",\n'
        f"        (t) => {call},\n"
        "        roles: {'admin'}),\n"
    )
    anchor = '    _MenuItem(Icons.search, "গাড়ী খুঁজুন",\n'
    new_main = replace_once(new_main, anchor, item + anchor, 'মেনুর "গাড়ী খুঁজুন" আইটেম')

    shutil.copyfile(main_p, main_p + ".pm.bak")
    write(main_p, new_main, crlf)
    print("সফল! main.dart-এ মেনুতে 'পার্টনার হিসাব' (শুধু অ্যাডমিন) যোগ হলো।")
    print(f"স্ক্রিন খুলবে: {call}")
    print("ব্যাকআপ: main.dart.pm.bak")
    print("এখন অ্যাপ নতুন করে run করুন (অ্যাডমিন দিয়ে লগইন করে দেখুন)।")


if __name__ == "__main__":
    main()