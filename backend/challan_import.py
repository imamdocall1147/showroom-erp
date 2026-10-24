"""NBR মূসক-৬.৩ চালান PDF থেকে গাড়ির তালিকা (ইঞ্জিন/চেসিস) বের করার মডিউল।

ব্যবহার:
    import challan_import
    result = challan_import.import_from_url(url)
"""
import io
import re
import urllib.request
import urllib.error
from datetime import datetime
from urllib.parse import urlparse

# সুরক্ষা: শুধু এই সার্ভারের চালান PDF নামানো যাবে (যেকোনো লিংক নয়)
ALLOWED_HOSTS = {"118.179.101.12"}
ALLOWED_PATH_PREFIX = "/files/SaleChallan_Report_PDF/"
MAX_BYTES = 5 * 1024 * 1024  # ৫ MB
TIMEOUT_SECONDS = 20

_ENG_CHA = re.compile(r"Eng:\s*([A-Z0-9]+)\s*,\s*Cha:\s*([A-Z0-9]+)", re.IGNORECASE)
_DATE = re.compile(r"(\d{1,2})[\s-]*([A-Za-z]{3})[\s-]*(\d{4})")
_MONEY = re.compile(r"\d[\d,]*\.\d{2}")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """রিডাইরেক্ট অনুসরণ বন্ধ, যাতে অনুমোদিত সার্ভার থেকে অন্য জায়গায় যাওয়া না যায়।"""

    def redirect_request(self, *args, **kwargs):
        return None


def validate_url(url: str) -> str:
    url = (url or "").strip()
    p = urlparse(url)
    if p.scheme not in ("http", "https"):
        raise ValueError("লিংক সঠিক নয়")
    if p.hostname not in ALLOWED_HOSTS:
        raise ValueError("এই সার্ভারের চালান অনুমোদিত নয়")
    if not p.path.startswith(ALLOWED_PATH_PREFIX) or not p.path.lower().endswith(".pdf"):
        raise ValueError("এটা চালান PDF-এর লিংক নয়")
    return url


def fetch_pdf(url: str) -> bytes:
    url = validate_url(url)
    opener = urllib.request.build_opener(_NoRedirect)
    req = urllib.request.Request(url, headers={"User-Agent": "showroom-erp"})
    with opener.open(req, timeout=TIMEOUT_SECONDS) as resp:
        data = resp.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("ফাইল অনেক বড়")
    if not data.startswith(b"%PDF"):
        raise ValueError("ফাইলটি PDF নয়")
    return data


def extract_text(pdf_bytes: bytes) -> str:
    from pypdf import PdfReader  # দেরিতে import, যাতে পার্সার আলাদা পরীক্ষা করা যায়

    reader = PdfReader(io.BytesIO(pdf_bytes))
    text = "\n".join((page.extract_text() or "") for page in reader.pages)
    return _normalize(text)


def _normalize(text: str) -> str:
    # PDF-এর হাইফেন আসলে অদৃশ্য soft-hyphen (\xad), আর স্পেস অনেক সময় \xa0
    return text.replace("\xad", "-").replace("\xa0", " ")


def _to_float(s: str) -> float:
    return float(s.replace(",", ""))


def parse_text(text: str, source_url: str = None) -> dict:
    warnings = []
    text = _normalize(text)

    # গাড়ির জোড়া (ইঞ্জিন, চেসিস), ক্রম ঠিক রেখে, ডুপ্লিকেট বাদ
    seen = set()
    units = []
    for eng, cha in _ENG_CHA.findall(text):
        eng, cha = eng.upper(), cha.upper()
        if (eng, cha) in seen:
            continue
        seen.add((eng, cha))
        units.append({"engine_no": eng, "chassis_no": cha})

    # মডেল: প্রথম "Eng:"-এর ঠিক আগের লাইন (হাইফেন হারিয়ে যায়, তাই যাচাই করতে হবে)
    model = ""
    idx = text.find("Eng:")
    if idx > 0:
        before = text[:idx].rstrip().splitlines()
        if before:
            model = before[-1].strip()

    # পরিমাণ ও মোট মূল্য: "PCS 3 581,395.35 ... 1,875,000.00" লাইন
    quantity = None
    total_with_tax = None
    for line in text.splitlines():
        m = re.search(r"PCS\s+(\d+)", line)
        if m:
            quantity = int(m.group(1))
            money = _MONEY.findall(line)
            if money:
                total_with_tax = _to_float(money[-1])
            break

    unit_price = None
    if quantity and total_with_tax:
        unit_price = round(total_with_tax / quantity, 2)

    # তারিখ
    date_iso = None
    m = _DATE.search(text)
    if m:
        try:
            date_iso = datetime.strptime(
                f"{m.group(1)}{m.group(2).title()}{m.group(3)}", "%d%b%Y"
            ).strftime("%Y-%m-%d")
        except ValueError:
            pass

    # চালান নম্বর: লিংকের ফাইলের নাম থেকে (লেখায় হাইফেন থাকে না)
    challan_no = None
    if source_url:
        name = urlparse(source_url).path.rsplit("/", 1)[-1]
        challan_no = re.sub(r"\.pdf$", "", name, flags=re.IGNORECASE)

    if not units:
        raise ValueError("চালানে কোনো ইঞ্জিন/চেসিস নম্বর পাওয়া যায়নি")
    if quantity is not None and quantity != len(units):
        warnings.append(
            f"চালানে পরিমাণ {quantity}, কিন্তু {len(units)}টি গাড়ির নম্বর পাওয়া গেছে। দেখে নিন।"
        )
    if unit_price is None:
        warnings.append("মূল্য পড়া যায়নি, হাতে দিন।")

    return {
        "challan_no": challan_no,
        "date": date_iso,
        "model_text": model,
        "quantity": quantity,
        "unit_price_with_tax": unit_price,
        "total_with_tax": total_with_tax,
        "units": units,
        "warnings": warnings,
    }


def parse_challan_pdf(pdf_bytes: bytes, source_url: str = None) -> dict:
    return parse_text(extract_text(pdf_bytes), source_url)


def import_from_url(url: str) -> dict:
    url = validate_url(url)
    return parse_challan_pdf(fetch_pdf(url), url)