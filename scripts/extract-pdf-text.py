import sys

# Force UTF-8 output so non-ASCII characters (e.g. †, →, μ) in PDFs
# don't crash on Windows where the default console encoding is gbk.
sys.stdout.reconfigure(encoding="utf-8")

path = sys.argv[1]

try:
    from pypdf import PdfReader
except Exception:
    try:
        from PyPDF2 import PdfReader
    except Exception as exc:
        raise SystemExit(f"No PDF text extraction library available: {exc}")

reader = PdfReader(path)
parts = []
for page in reader.pages[:8]:
    parts.append(page.extract_text() or "")

print("\n".join(parts))
