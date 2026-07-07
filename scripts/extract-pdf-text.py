import sys

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
