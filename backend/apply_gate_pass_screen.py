# -*- coding: utf-8 -*-
"""
"নতুন বাইক ক্রয় এন্ট্রি" ফর্মে "গেট পাস নম্বর" ঘর যোগ করে (trade_screens.dart)।

ব্যবহার (PowerShell-এ Flutter প্রজেক্টের lib ফোল্ডারে ঢুকে):
    python apply_gate_pass_screen.py
অথবা অন্য ফোল্ডার থেকে:
    python apply_gate_pass_screen.py D:\\apps\\showroom-erp\\frontend\\lib

কিছু বদলানোর আগে trade_screens.dart.gp.bak নামে ব্যাকআপ রাখে।
(ব্যাকএন্ডে আগে apply_gate_pass.py চালানো থাকতে হবে।)
"""
import os
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
    folder = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
    path = os.path.join(folder, "trade_screens.dart")
    if not os.path.isfile(path):
        print("[ত্রুটি] trade_screens.dart পাওয়া যায়নি:", path)
        print("Flutter প্রজেক্টের lib ফোল্ডারে ঢুকে চালান, অথবা ফোল্ডারের পথ দিন।")
        sys.exit(1)

    s, crlf = read(path)
    if "_gatePassController" in s:
        print("গেট পাস ঘর আগেই বসানো আছে, কিছু করার নেই।")
        return

    # 1) কন্ট্রোলার
    s = replace_once(
        s,
        "  final _engineController = TextEditingController();\n",
        "  final _engineController = TextEditingController();\n"
        "  final _gatePassController = TextEditingController();\n",
        "কন্ট্রোলার তৈরি",
    )

    # 2) dispose
    s = replace_once(
        s,
        "    _engineController.dispose();\n",
        "    _engineController.dispose();\n"
        "    _gatePassController.dispose();\n",
        "dispose",
    )

    # 3) ইঞ্জিন নম্বর ঘরের ঠিক পরে নতুন ঘর
    marker = '"ইঞ্জিন নম্বর দিন" : null,'
    if s.count(marker) != 1:
        fail("ইঞ্জিন নম্বর ঘরের অংশ পাওয়া যায়নি।")
    i = s.index(marker)
    gap = "const SizedBox(height: 16),"
    j = s.find(gap, i)
    if j == -1:
        fail("ইঞ্জিন নম্বর ঘরের পরের ফাঁকা অংশ পাওয়া যায়নি।")
    line_start = s.rfind("\n", 0, j) + 1
    ind = s[line_start:j]
    line_end = s.index("\n", j) + 1
    block = (
        f"{ind}TextFormField(\n"
        f"{ind}  controller: _gatePassController,\n"
        f"{ind}  decoration: const InputDecoration(\n"
        f'{ind}    labelText: "গেট পাস নম্বর (ঐচ্ছিক)",\n'
        f"{ind}    border: OutlineInputBorder(),\n"
        f"{ind}  ),\n"
        f"{ind}),\n"
        f"{ind}{gap}\n"
    )
    s = s[:line_end] + block + s[line_end:]

    # 4) সার্ভারে পাঠানোর ডাটায়
    s = replace_once(
        s,
        '"order_id": _selectedOrderId,',
        '"order_id": _selectedOrderId,\n'
        '      "gate_pass_no": _gatePassController.text.trim().isEmpty\n'
        "          ? null\n"
        "          : _gatePassController.text.trim(),",
        "সার্ভারে পাঠানোর ডাটা",
    )

    shutil.copyfile(path, path + ".gp.bak")
    write(path, s, crlf)
    print("সফল! trade_screens.dart-এ যা যা হলো:")
    print("  - গেট পাস নম্বর (ঐচ্ছিক) ঘর যোগ হলো (ইঞ্জিন নম্বরের পরে)")
    print("  - ক্রয়ের সাথে gate_pass_no সার্ভারে যাবে")
    print("ব্যাকআপ: trade_screens.dart.gp.bak")
    print("এখন অ্যাপ আবার চালান (hot restart বা নতুন করে run)।")


if __name__ == "__main__":
    main()