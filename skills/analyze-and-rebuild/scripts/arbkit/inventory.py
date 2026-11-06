"""Read-only discovery. Results contain metadata, never source snippets."""

import ast
import hashlib
import os
import re
import shutil
import subprocess
from pathlib import Path

from .common import digest, is_link, source_text

IGNORED = {".git", ".venv", "venv", "node_modules", "__pycache__", "vendor", "dist", "build"}
HINTS = {".py": "Python", ".pyw": "Python", ".js": "JavaScript", ".jsx": "JavaScript",
         ".ts": "TypeScript", ".tsx": "TypeScript", ".ps1": "PowerShell", ".psm1": "PowerShell",
         ".cs": "C#", ".java": "Java", ".kt": "Kotlin", ".c": "C", ".h": "C/C++",
         ".cpp": "C++", ".rs": "Rust", ".go": "Go", ".html": "HTML", ".css": "CSS",
         ".json": "JSON", ".xml": "XML", ".yaml": "YAML", ".toml": "TOML"}


class PythonIndex(ast.NodeVisitor):
    def __init__(self):
        self.symbols, self.imports, self.stack = [], [], []

    def definition(self, node, kind, name):
        qualified = ".".join([x["name"] for x in self.stack] + [name])
        item = {"name": name, "qualified_name": qualified, "kind": kind,
                "line": node.lineno, "end_line": node.end_lineno,
                "column": node.col_offset, "calls": [], "discovery": "ast"}
        self.symbols.append(item)
        self.stack.append(item)
        self.generic_visit(node)
        self.stack.pop()

    def visit_FunctionDef(self, node):
        self.definition(node, "function", node.name)

    def visit_AsyncFunctionDef(self, node):
        self.definition(node, "async_function", node.name)

    def visit_ClassDef(self, node):
        self.definition(node, "class", node.name)

    def visit_Lambda(self, node):
        self.definition(node, "lambda", "lambda@%s:%s" % (node.lineno, node.col_offset))

    def visit_Import(self, node):
        self.imports.extend(x.name for x in node.names)

    def visit_ImportFrom(self, node):
        self.imports.append("." * node.level + (node.module or ""))

    def visit_Call(self, node):
        parts, target = [], node.func
        while isinstance(target, ast.Attribute):
            parts.append(target.attr)
            target = target.value
        if isinstance(target, ast.Name):
            parts.append(target.id)
            if self.stack:
                self.stack[-1]["calls"].append(".".join(reversed(parts)))
        self.generic_visit(node)


def _powershell(path):
    executable = shutil.which("pwsh") or (shutil.which("powershell") if os.name == "nt" else None)
    if not executable:
        return None
    script = Path(__file__).parents[1] / "powershell-index.ps1"
    from .common import _pairs
    import json
    result = subprocess.run([executable, "-NoLogo", "-NoProfile", "-NonInteractive",
                             "-File", str(script), "-SourceFile", str(path)],
                            capture_output=True, timeout=15, check=True)
    return json.loads(result.stdout.decode("utf-8-sig"), object_pairs_hook=_pairs)


def _inspect(path, raw):
    hint = HINTS.get(path.suffix.lower(), "unknown")
    result = {"language_hint": hint, "confirmed_language": None, "parser": "manual_required",
              "symbols": [], "imports": [], "notes": []}
    for magic, kind in [(b"MZ", "PE candidate"), (b"\x7fELF", "ELF"),
                        (b"\x00asm", "WebAssembly"), (b"PK\x03\x04", "ZIP/package")]:
        if raw.startswith(magic):
            result["artifact_kind"] = kind
            result["notes"].append("Binary/package internals and runtime functions are not enumerated.")
            return result
    if b"\0" in raw[:4096] and not raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        result["artifact_kind"] = "binary"
        return result
    text = source_text(raw)
    result["line_count"] = len(text.splitlines())
    if hint == "Python":
        try:
            index = PythonIndex()
            index.visit(ast.parse(raw, filename=path.name))
            result.update(parser="python_ast", confirmed_language="Python",
                          symbols=index.symbols, imports=sorted(set(index.imports)))
            result["notes"].append("Syntactic inventory only; dynamic code and runtime dispatch need review.")
        except (SyntaxError, ValueError, RecursionError) as error:
            result["notes"].append("Python parse failed: " + type(error).__name__)
        return result
    if hint == "PowerShell":
        try:
            native = _powershell(path)
            if native is not None:
                result.update(native)
                return result
        except (OSError, ValueError, subprocess.SubprocessError):
            result["notes"].append("Native PowerShell parser unavailable or failed.")
    patterns = []
    if hint == "PowerShell":
        patterns = [r"(?im)^\s*(?:function|filter|workflow)\s+([\w:-]+)"]
    elif hint in {"JavaScript", "TypeScript"}:
        patterns = [r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(",
                    r"\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:\([^;{}]*\)|[\w$]+)\s*=>"]
    for pattern in patterns:
        for match in re.finditer(pattern, text):
            line = text.count("\n", 0, match.start()) + 1
            result["symbols"].append({"name": match.group(1), "qualified_name": match.group(1),
                                      "kind": "candidate", "line": line, "end_line": line,
                                      "column": 0, "calls": [], "discovery": "heuristic"})
    result["notes"].append("Extension and regex hints are incomplete; require manual/tool-assisted discovery.")
    return result


def scan(root, max_files=5000, max_bytes=2 * 1024 * 1024):
    root = Path(root).resolve()
    if not root.is_dir() or max_files < 1 or max_bytes < 1:
        raise ValueError("source must be a directory; scan limits must be positive")
    files, skipped, policy = [], [], []
    count = 0
    def walk_error(error):
        raise ValueError("cannot enumerate source directory: " + type(error).__name__)
    for directory, dirs, names in os.walk(root, followlinks=False, onerror=walk_error):
        dirs.sort()
        names.sort()
        for name in list(dirs):
            p = Path(directory) / name
            if name in IGNORED or is_link(p):
                dirs.remove(name)
                policy.append({"path": p.relative_to(root).as_posix(),
                               "reason": "symlink_or_reparse_point" if is_link(p) else "default_dependency_or_build_exclusion"})
        for name in names:
            count += 1
            p = Path(directory) / name
            relative = p.relative_to(root).as_posix()
            if count > max_files:
                raise ValueError("file limit exceeded; narrow scope or increase --max-files")
            if is_link(p) or not p.is_file():
                skipped.append({"path": relative, "reason": "symlink_or_special_file"})
                continue
            stat = p.stat()
            if name.startswith(".env") or p.suffix.lower() in {".key", ".pem", ".pfx"}:
                policy.append({"path": relative, "reason": "credential_material_not_inspected"})
                continue
            if stat.st_size > max_bytes:
                skipped.append({"path": relative, "reason": "size_limit", "size": stat.st_size,
                                "mtime_ns": stat.st_mtime_ns})
                continue
            try:
                with p.open("rb") as stream:
                    raw = stream.read(max_bytes + 1)
                if len(raw) > max_bytes:
                    raise ValueError("source file grew beyond scan limit; retry discovery")
                info = _inspect(p, raw)
            except OSError as error:
                skipped.append({"path": relative, "reason": type(error).__name__})
                continue
            for symbol in info["symbols"]:
                key = [relative, symbol["qualified_name"], symbol["line"], symbol["column"]]
                symbol["id"] = "F-" + digest(key)[:16]
            files.append({"path": relative, "sha256": hashlib.sha256(raw).hexdigest(),
                          "bytes": len(raw), **info})
    fingerprint = digest({"files": [(f["path"], f["sha256"]) for f in files],
                          "skipped": skipped, "policy_exclusions": policy})
    return {"schema_version": 2, "files": files, "skipped": skipped,
            "policy_exclusions": policy, "fingerprint": fingerprint,
            "limits": {"max_files": max_files, "max_bytes": max_bytes},
            "global_completeness": "not_proven"}
