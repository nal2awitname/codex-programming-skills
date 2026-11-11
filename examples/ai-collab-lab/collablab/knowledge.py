"""Built-in knowledge base loaded from Markdown documents.

Each document starts with a ``# Title`` line followed by ``Key: value`` header
lines (Kind, Keywords, Module). Fenced blocks tagged ``python module`` and
``python tests`` hold the code of a recipe. Keywords are matched as
substrings so that languages written without spaces still match.
"""
from __future__ import annotations

import re
from pathlib import Path

KNOWLEDGE_DIR = Path(__file__).with_name("knowledge")
_FENCE = re.compile(r"^```([^\n]*)\n(.*?)^```\s*$", re.S | re.M)
_WORD = re.compile(r"[a-z0-9_]+")


def parse_document(doc_id: str, text: str) -> dict:
    lines = text.replace("\r\n", "\n").split("\n")
    title = doc_id
    headers: dict[str, str] = {}
    index = 0
    while index < len(lines) and not lines[index].strip():
        index += 1
    if index < len(lines) and lines[index].startswith("# "):
        title = lines[index][2:].strip()
        index += 1
    while index < len(lines):
        match = re.match(r"^([A-Za-z]+):\s*(.*)$", lines[index])
        if not match:
            break
        headers[match[1].lower()] = match[2].strip()
        index += 1
    body = "\n".join(lines[index:]).strip()
    code = {}
    for info, block in _FENCE.findall(body):
        parts = info.split()
        if len(parts) == 2 and parts[0] == "python" and parts[1] in {"module", "tests"}:
            code[parts[1]] = block
    keywords = [word.strip().lower() for word in headers.get("keywords", "").split(",") if word.strip()]
    return {
        "id": doc_id,
        "title": title,
        "kind": headers.get("kind", "article").lower(),
        "keywords": keywords,
        "module": headers.get("module", ""),
        "body": body,
        "code": code,
        "author": headers.get("author", "library"),
    }


def load_builtin() -> list[dict]:
    documents = []
    for path in sorted(KNOWLEDGE_DIR.glob("*.md")):
        documents.append(parse_document(path.stem, path.read_text(encoding="utf-8")))
    return documents


def score(document: dict, query: str) -> int:
    """Rank a document for a free-text query; zero means unrelated."""
    text = query.lower()
    words = set(_WORD.findall(text))
    total = 0
    for keyword in document["keywords"]:
        if keyword and keyword in text:
            total += 3
    title = document["title"].lower()
    for word in words:
        if len(word) < 3:
            continue
        if word in title:
            total += 2
        elif word in document["body"].lower():
            total += 1
    return total


def search(documents: list[dict], query: str, limit: int = 5, kind: str | None = None) -> list[dict]:
    ranked = []
    for document in documents:
        if kind and document["kind"] != kind:
            continue
        value = score(document, query)
        if value > 0:
            ranked.append((value, document["id"], document))
    ranked.sort(key=lambda item: (-item[0], item[1]))
    return [
        {"id": doc["id"], "title": doc["title"], "kind": doc["kind"], "score": value,
         "module": doc["module"], "snippet": snippet(doc["body"])}
        for value, _, doc in ranked[:limit]
    ]


def snippet(body: str, length: int = 220) -> str:
    prose = _FENCE.sub("", body).strip()
    prose = re.sub(r"\s+", " ", prose)
    return prose if len(prose) <= length else prose[: length - 1] + "…"
