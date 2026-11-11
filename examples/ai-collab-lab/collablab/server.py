"""Local HTTP server: serves the web GUI and a small JSON API.

The server binds to the loopback interface by default. State-changing
requests must be JSON and carry the ``X-Collab-Lab`` header, which a foreign
web page cannot add without a CORS preflight this server never approves, and
the Host header must name this server, which blocks DNS-rebinding pages.
"""
from __future__ import annotations

import json
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from . import __version__, knowledge
from .brains.claude import SUGGESTED_MODELS
from .engine import Engine, list_scenarios, read_scenario
from .tools import CATEGORIES, catalog
from .world import BRAINS, EFFORTS, ROLES, TASK_STATUSES, USER_ID, WorldError

WEB_DIR = Path(__file__).with_name("web")
STATIC = {"/": ("index.html", "text/html; charset=utf-8"),
          "/static/app.js": ("app.js", "text/javascript; charset=utf-8"),
          "/static/style.css": ("style.css", "text/css; charset=utf-8"),
          "/static/icon.svg": ("icon.svg", "image/svg+xml")}
MAX_BODY = 4 * 1024 * 1024
CSRF_HEADER = "X-Collab-Lab"


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


class LabServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, engine: Engine):
        self.engine = engine
        super().__init__(address, Handler)
        host, port = self.server_address[:2]
        names = {"127.0.0.1", "localhost", "[::1]", str(host)}
        self.allowed_hosts = {f"{name}:{port}" for name in names} | names

    @property
    def url(self) -> str:
        host, port = self.server_address[:2]
        shown = "127.0.0.1" if host in ("0.0.0.0", "::") else host
        return f"http://{shown}:{port}/"


class Handler(BaseHTTPRequestHandler):
    server: LabServer
    server_version = f"AICollabLab/{__version__}"

    def log_message(self, format, *args):  # keep the console quiet; the GUI has its own log
        return

    # ------------------------------------------------------------ plumbing
    def _send(self, status: int, body: bytes, content_type: str, extra: dict | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; "
                         "connect-src 'self'; frame-ancestors 'none'")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, payload, status: int = 200, extra: dict | None = None) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send(status, body, "application/json; charset=utf-8", extra)

    def _check_host(self) -> None:
        if self.headers.get("Host", "") not in self.server.allowed_hosts:
            raise ApiError(HTTPStatus.FORBIDDEN, "bad_host", "Unexpected Host header")

    def _body(self) -> dict:
        if self.headers.get(CSRF_HEADER) != "1":
            raise ApiError(HTTPStatus.FORBIDDEN, "missing_header", f"Requests must send {CSRF_HEADER}: 1")
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            raise ApiError(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, "json_required", "Send application/json")
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            raise ApiError(HTTPStatus.BAD_REQUEST, "bad_length", "Invalid Content-Length") from None
        if not 0 <= length <= MAX_BODY:
            raise ApiError(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "too_large", "Request body is too large")
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        except (UnicodeDecodeError, ValueError):
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_json", "Body is not valid JSON") from None
        if not isinstance(data, dict):
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_json", "Body must be a JSON object")
        return data

    def _dispatch(self, routes: dict) -> None:
        url = urlparse(self.path)
        try:
            self._check_host()
            handler = routes.get(url.path)
            if handler is None:
                raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "No such endpoint")
            handler(self, url)
        except ApiError as error:
            self._json({"ok": False, "error": {"code": error.code, "message": error.message}}, error.status)
        except WorldError as error:
            self._json({"ok": False, "error": {"code": error.code, "message": error.message}},
                       HTTPStatus.BAD_REQUEST)
        except (KeyError, TypeError, ValueError) as error:
            self._json({"ok": False, "error": {"code": "invalid_request", "message": str(error)}},
                       HTTPStatus.BAD_REQUEST)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in STATIC:
            try:
                self._check_host()
            except ApiError as error:
                self._json({"ok": False, "error": {"code": error.code, "message": error.message}}, error.status)
                return
            name, kind = STATIC[path]
            self._send(200, (WEB_DIR / name).read_bytes(), kind)
            return
        self._dispatch(GET_ROUTES)

    do_HEAD = do_GET

    def do_POST(self):
        self._dispatch(POST_ROUTES)

    @property
    def engine(self) -> Engine:
        return self.server.engine

    # ------------------------------------------------------------- GET API
    def get_state(self, url):
        query = parse_qs(url.query)
        since = int(query.get("since", ["0"])[0] or 0)
        self._json(self.engine.snapshot(max(0, since)))

    def get_meta(self, url):
        self._json({"version": __version__, "roles": ROLES, "brains": BRAINS, "efforts": EFFORTS,
                    "task_statuses": TASK_STATUSES, "models": SUGGESTED_MODELS, "tools": catalog(),
                    "tool_categories": CATEGORIES, "scenarios": list_scenarios(), "user": USER_ID})

    def get_file(self, url):
        path = parse_qs(url.query).get("path", [""])[0]
        with self.engine.world.lock:
            record = dict(self.engine.world.read_file(path))
        self._json(record)

    def get_agent(self, url):
        agent_id = parse_qs(url.query).get("id", [""])[0]
        world = self.engine.world
        with world.lock:
            agent = world.get_agent(agent_id)
            data = agent.public()
            data["memory"] = json.loads(json.dumps(agent.memory, default=str))
            data["recent"] = [e for e in world.events if e["actor"] == agent_id][-80:]
            data["history_turns"] = len(self.engine.claude.histories.get(agent_id, []))
        self._json(data)

    def get_knowledge(self, url):
        query = parse_qs(url.query)
        world = self.engine.world
        with world.lock:
            if "id" in query:
                self._json(world.get_document(query["id"][0]))
                return
            text = query.get("q", [""])[0].strip()
            if text:
                results = knowledge.search(world.documents, text, 20)
            else:
                results = [{"id": d["id"], "title": d["title"], "kind": d["kind"], "score": 0,
                            "module": d["module"], "snippet": knowledge.snippet(d["body"])} for d in world.documents]
        self._json({"results": results})

    def get_export(self, url):
        body = json.dumps(self.engine.export_state(), ensure_ascii=False, indent=1).encode("utf-8")
        self._send(200, body, "application/json; charset=utf-8",
                   {"Content-Disposition": 'attachment; filename="ai-collab-lab-state.json"'})

    # ------------------------------------------------------------ POST API
    def post_message(self, url):
        data = self._body()
        outcome = self.engine.user_message(str(data.get("to", "")), str(data.get("text", "")))
        self._json(outcome, 200 if outcome["ok"] else 400)

    def post_control(self, url):
        action = self._body().get("action")
        engine = self.engine
        if action == "run":
            engine.start()
        elif action == "pause":
            threading.Thread(target=engine.pause, daemon=True).start()
        elif action == "step":
            if engine.running:
                raise ApiError(HTTPStatus.CONFLICT, "running", "Pause the simulation before stepping")
            threading.Thread(target=engine.step, daemon=True).start()
        elif action == "reset":
            engine.reset(team=True)
        elif action == "clear":
            engine.reset(team=False)
        else:
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_action", "action must be run, pause, step, reset or clear")
        self._json({"ok": True, "status": engine.status})

    def post_agents(self, url):
        data = self._body()
        action, agent_id = data.get("action"), data.get("id", "")
        if action == "add":
            agent = self.engine.add_agent(data.get("agent") or {})
            self._json({"ok": True, "agent": agent.public()})
            return
        if action == "update":
            agent = self.engine.update_agent(agent_id, data.get("changes") or {})
            self._json({"ok": True, "agent": agent.public()})
            return
        if action == "remove":
            self.engine.remove_agent(agent_id)
        elif action == "nudge":
            self.engine.nudge(agent_id)
            if self.engine.settings["auto_run"]:
                self.engine.start()
        else:
            raise ApiError(HTTPStatus.BAD_REQUEST, "invalid_action", "action must be add, update, remove or nudge")
        self._json({"ok": True})

    def post_settings(self, url):
        self._json({"ok": True, "settings": self.engine.update_settings(self._body())})

    def post_tool(self, url):
        data = self._body()
        outcome = self.engine.toolbox.call(USER_ID, str(data.get("name", "")), data.get("args") or {})
        if outcome["ok"] and self.engine.settings["auto_run"] and self.engine.has_work():
            self.engine.start()
        self._json(outcome, 200 if outcome["ok"] else 400)

    def post_scenario(self, url):
        self.engine.load_scenario(read_scenario(str(self._body().get("id", ""))))
        self._json({"ok": True})

    def post_import(self, url):
        self.engine.import_state(self._body().get("state"))
        self._json({"ok": True})


GET_ROUTES = {"/api/state": Handler.get_state, "/api/meta": Handler.get_meta, "/api/file": Handler.get_file,
              "/api/agent": Handler.get_agent, "/api/knowledge": Handler.get_knowledge,
              "/api/export": Handler.get_export}
POST_ROUTES = {"/api/message": Handler.post_message, "/api/control": Handler.post_control,
               "/api/agents": Handler.post_agents, "/api/settings": Handler.post_settings,
               "/api/tool": Handler.post_tool, "/api/scenario": Handler.post_scenario,
               "/api/import": Handler.post_import}


def make_server(engine: Engine, host: str = "127.0.0.1", port: int = 8765) -> LabServer:
    return LabServer((host, port), engine)
