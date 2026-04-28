#!/usr/bin/env python3
"""
extract_docs.py — Extract text from project documentation files.
Supports .txt and .md; PDF/DOCX extraction requires optional dependencies.
"""

import os
import sys
import argparse


def extract_txt(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def extract_md(path: str) -> str:
    return extract_txt(path)


def extract_pdf(path: str) -> str:
    try:
        import pdfplumber
        text_parts = []
        with pdfplumber.open(path) as pdf:
            for page in pdf.pages:
                t = page.extract_text()
                if t:
                    text_parts.append(t)
        return "\n".join(text_parts)
    except ImportError:
        return f"[PDF extraction unavailable: install pdfplumber]\nFile: {path}"


def extract_docx(path: str) -> str:
    try:
        from docx import Document
        doc = Document(path)
        return "\n".join(p.text for p in doc.paragraphs)
    except ImportError:
        return f"[DOCX extraction unavailable: install python-docx]\nFile: {path}"


EXTRACTORS = {
    ".txt":  extract_txt,
    ".md":   extract_md,
    ".pdf":  extract_pdf,
    ".docx": extract_docx,
}


def extract(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    fn = EXTRACTORS.get(ext)
    if fn is None:
        return f"[Unsupported format: {ext}]"
    return fn(path)


def main():
    parser = argparse.ArgumentParser(description="Extract text from documentation files.")
    parser.add_argument("files", nargs="+", help="Input files to extract")
    parser.add_argument("-o", "--output", default=None,
                        help="Output file (default: stdout)")
    args = parser.parse_args()

    results = []
    for fpath in args.files:
        if not os.path.exists(fpath):
            print(f"[WARN] File not found: {fpath}", file=sys.stderr)
            continue
        content = extract(fpath)
        results.append(f"=== {fpath} ===\n{content}\n")

    output = "\n".join(results)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output)
        print(f"Written to {args.output}")
    else:
        print(output)


if __name__ == "__main__":
    main()
